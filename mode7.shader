shader_type canvas_item;

uniform sampler2D track_tex : source_color, repeat_enable, filter_nearest;
uniform vec2 track_size = vec2(2048.0, 2048.0);
uniform vec2 cam_pos = vec2(1024.0, 1024.0);
uniform float cam_rot = 0.0;
uniform float horizon = 0.42;   // 0..1
uniform float zoom = 180.0;     // perspective strength

void fragment() {
    vec2 uv = UV; // 0..1
    if (uv.y < horizon) {
        // simple sky color
        COLOR = vec4(0.45, 0.7, 1.0, 1.0);
        return;
    }

    float row = (uv.y - horizon);
    float dist = zoom / max(row, 0.0001);
    float sx = (uv.x - 0.5) * dist;

    float c = cos(-cam_rot);
    float s = sin(-cam_rot);
    vec2 sample = vec2(c * sx - s * dist, s * sx + c * dist);

    vec2 texcoord = cam_pos + sample;
    vec2 t = texcoord / track_size;
    // Fallback: if track texture is not assigned, draw a checker so it's obvious
    if (textureSize(track_tex, 0).x <= 1.0) {
        float check = step(0.5, fract((texcoord.x + texcoord.y) * 0.05));
        COLOR = vec4(vec3(0.2 + 0.6 * check), 1.0);
        return;
    }

    COLOR = texture(track_tex, fract(t));
}
