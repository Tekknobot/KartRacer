shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

/* ---------- Look controls (all procedural) ---------- */
uniform vec3 asphalt_color = vec3(0.12, 0.12, 0.13);
uniform vec3 shoulder_color = vec3(0.55, 0.56, 0.58);
uniform vec3 grass_color = vec3(0.11, 0.35, 0.12);
uniform vec3 line_color = vec3(0.95, 0.95, 0.92); // center + edge lines

/* Road geometry in UV space (U = left/right, V = along the track) */
uniform float road_width = 0.52;      // 0..1 (fraction of the plane width)
uniform float shoulder_width = 0.04;  // extra width outside the asphalt, each side
uniform float edge_line_width = 0.010;
uniform float center_line_width = 0.012;

/* Dashes along V */
uniform float dash_length = 0.08;  // length of a dash (in V UV units after scaling)
uniform float dash_gap = 0.06;     // gap between dashes
uniform float v_scroll = 0.0;      // animate forward movement (add to UV.y)

/* Scale UVs so V runs "longer" down the plane (helps dash frequency on big meshes) */
uniform vec2 uv_scale = vec2(1.0, 3.0);

/* Soft antialiasing at edges (world-size independent) */
uniform float edge_softness = 0.002;

/* ---------- helpers ---------- */
float band_smooth(float d, float half_w, float aa) {
    // 1 inside a band centered at 0 with half-width half_w, AA width aa
    return 1.0 - smoothstep(half_w, half_w + aa, abs(d));
}

void fragment() {
    // scale UVs; put road centered at U = 0.5, running along +V
    vec2 uv = vec2(UV.x, UV.y) * uv_scale + vec2(0.0, v_scroll);
    float u = uv.x - 0.5; // center road at 0.5

    // AA amounts for crisp lines regardless of resolution/scale
    float aa_u = fwidth(u) + edge_softness;
    float aa_v = fwidth(uv.y) + edge_softness;

    float half_road = clamp(road_width * 0.5, 0.0, 0.5);
    float half_asphalt = half_road;
    float half_shoulder = half_road + shoulder_width;

    // Masks (0..1)
    float in_asphalt  = band_smooth(u, half_asphalt, aa_u);
    float in_shoulder = clamp(band_smooth(u, half_shoulder, aa_u) - in_asphalt, 0.0, 1.0);

    // Base color blend: grass -> shoulder -> asphalt
    vec3 col = grass_color;
    col = mix(col, shoulder_color, in_shoulder);
    col = mix(col, asphalt_color, in_asphalt);

    // Edge lines (one near each asphalt edge, inside the road)
    float edge_pos = half_asphalt - max(0.0, edge_line_width * 1.2);
    float edge_mask = band_smooth(u - edge_pos, edge_line_width * 0.5, aa_u)
                    + band_smooth(u + edge_pos, edge_line_width * 0.5, aa_u);
    edge_mask = clamp(edge_mask, 0.0, 1.0);
    col = mix(col, line_color, edge_mask * in_asphalt);

    // Center dashed line
    float center_mask = band_smooth(u, center_line_width * 0.5, aa_u);

    float period = max(1e-4, dash_length + dash_gap);
    float t = fract(uv.y / period);
    float dash = 1.0 - smoothstep(dash_length / period, (dash_length / period) + aa_v, t);
    float center_dashed = center_mask * dash * in_asphalt;

    col = mix(col, line_color, center_dashed);

    ALBEDO = col;
    ALPHA = 1.0;
}
