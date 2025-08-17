shader_type spatial;
render_mode unshaded, cull_back;

// ====== Track shape ======
uniform vec2  track_half_extents = vec2(0.65, 0.35); // half size of the OUTER rounded rectangle in [-1..1] space
uniform float corner_radius      = 0.20;             // outer corner radius
uniform float track_width        = 0.12;             // thickness of the asphalt band

// ====== Lines (classic white edge lines) ======
uniform bool  use_white_lines    = true;
uniform float line_thickness     = 0.01;             // inner/outer white line thickness

// ====== Colors ======
uniform vec4  grass_color   : source_color = vec4(0.12, 0.50, 0.20, 1.0);
uniform vec4  asphalt_color : source_color = vec4(0.12, 0.12, 0.12, 1.0);
uniform vec4  line_color    : source_color = vec4(0.95, 0.95, 0.95, 1.0);

// ====== Start/finish line (checkered band) ======
uniform float start_line_x   = 0.0;  // position across X in [-1..1] space
uniform float start_line_w   = 0.06; // band width
uniform float checker_size   = 0.08; // checker square size (in the same space as p)

// ====== Retro pixel snap (0 = off) ======
uniform float pixel_grid     = 0.0; // Try 128.0 or 256.0

// ====== UV transform (if your plane UVs aren't 0..1) ======
uniform vec2  uv_scale  = vec2(1.0, 1.0);
uniform vec2  uv_offset = vec2(0.0, 0.0);

// ====== Warning track (red/white kerbs) ======
uniform bool  use_warning_track = true;
uniform float warning_size      = 0.04; // kerb thickness (each side)
uniform float warning_freq      = 12.0; // stripes around the loop (higher = more stripes)
uniform vec4  warning_red   : source_color = vec4(0.85, 0.05, 0.05, 1.0);
uniform vec4  warning_white : source_color = vec4(0.95, 0.95, 0.95, 1.0);

// Optional: offset kerbs a bit further onto/away from asphalt edges (signed, in "distance" units)
uniform float warning_outer_offset = 0.0; // positive pulls inward (onto track)
uniform float warning_inner_offset = 0.0; // positive pushes outward (into track)

// -------- SDF helpers --------
float sdRoundRect(vec2 p, vec2 half_extents, float r) {
    // Signed distance to a rounded rectangle centered at (0,0)
    vec2 q = abs(p) - (half_extents - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float band_smooth(float d, float d0, float d1, float aa) {
    // 1.0 when d is between (d1 .. d0), with smooth edges ~ aa wide
    return smoothstep(d0, d0 - aa, d) - smoothstep(d1, d1 - aa, d);
}

void fragment() {
    // Base UV → normalized coordinates p in [-1..1] (plane center = 0)
    vec2 uv = UV * uv_scale + uv_offset;
    if (pixel_grid > 0.0) {
        uv = (floor(uv * pixel_grid) + 0.5) / pixel_grid;
    }
    vec2 p = (uv - 0.5) * 2.0;

    // Outer & inner rounded rectangles (inner is “shrunk” by track_width)
    vec2  inner_extents = max(track_half_extents - vec2(track_width), vec2(0.001));
    float inner_radius  = max(corner_radius - track_width, 0.0);

    float d_outer = sdRoundRect(p, track_half_extents, corner_radius);
    float d_inner = sdRoundRect(p, inner_extents,    inner_radius);

    // Screen-space AA width from derivatives
    float aa = max(0.001, fwidth(d_outer) * 1.5);

    // Masks
    float inside_outer   = 1.0 - smoothstep(0.0, aa, d_outer); // inside outer shape
    float outside_inner  =      smoothstep(0.0, aa, d_inner);  // outside inner shape
    float track_mask     = inside_outer * outside_inner;       // asphalt band

    // Base color: grass vs asphalt
    vec3 col = mix(grass_color.rgb, asphalt_color.rgb, track_mask);

    // ====== Warning track (kerbs) ======
    if (use_warning_track) {
        // Bands hugging outer & inner edges (with optional offsets)
        float kerb_outer = band_smooth(d_outer + warning_outer_offset, 0.0, -warning_size, aa) * outside_inner;
        float kerb_inner = band_smooth(d_inner + warning_inner_offset,  warning_size, 0.0, aa) * inside_outer;

        // Alternate red/white stripes by angle around center
        float angle = atan(p.y, p.x); // radians -pi..pi
        // Map angle to 0..1 stripe pattern by frequency
        float stripes = fract(angle / (3.14159265 / warning_freq)); // repeats around
        float stripe_step = step(0.5, stripes); // 0 or 1
        vec3 kerb_col = mix(warning_red.rgb, warning_white.rgb, stripe_step);

        float kerb_mask = clamp(kerb_outer + kerb_inner, 0.0, 1.0);
        col = mix(col, kerb_col, kerb_mask);
    }

    // ====== White border lines (if enabled) ======
    if (use_white_lines) {
        float outer_line = band_smooth(d_outer, 0.0, -line_thickness, aa) * outside_inner;
        float inner_line = band_smooth(d_inner,  line_thickness, 0.0, aa) * inside_outer;
        float line_mask = clamp(outer_line + inner_line, 0.0, 1.0);
        col = mix(col, line_color.rgb, line_mask);
    }

    // ====== Checkered start/finish band ======
    float band_x = 1.0 - smoothstep(start_line_w * 0.5, start_line_w * 0.5 + aa, abs(p.x - start_line_x));
    float on_track_band = band_x * track_mask;

    // Checker pattern (alternating white/asphalt)
    vec2  c = p / checker_size;
    float checker = mod(floor(c.x) + floor(c.y), 2.0); // 0 or 1
    float white_sq = 1.0 - checker; // white on even
    col = mix(col, line_color.rgb, on_track_band * white_sq);

    ALBEDO = col;
    ALPHA  = 1.0;
}
