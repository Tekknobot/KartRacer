shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

/* palette */
uniform vec3 asphalt_color = vec3(0.12, 0.12, 0.13);
uniform vec3 shoulder_color = vec3(0.55, 0.56, 0.58);
uniform vec3 grass_color = vec3(0.11, 0.35, 0.12);
uniform vec3 line_color = vec3(0.95, 0.95, 0.92);

/* widths (match straight) */
uniform float road_width = 0.52;
uniform float shoulder_width = 0.04;
uniform float edge_line_width = 0.010;
uniform float center_line_width = 0.012;
/* NEW: how far to inset the edge lines from the asphalt edge */
uniform float edge_line_inset_factor = 1.2; // 1.2 * edge_line_width like your straight

/* dashes */
uniform float dash_length = 0.08;
uniform float dash_gap    = 0.06;
uniform float v_scroll    = 0.0;

/* keep square UVs */
uniform vec2 uv_scale = vec2(1.0, 1.0);

/* orientation (bottom→right) */
uniform vec2  arc_center_uv = vec2(1.0, 0.0);
uniform float turn_radius_uv = 0.5;
uniform float start_angle_deg = 180.0;
uniform float sweep_deg = -90.0;

/* AA */
uniform float edge_softness = 0.002;

/* helpers */
float band_smooth(float d, float half_w, float aa) { return 1.0 - smoothstep(half_w, half_w + aa, abs(d)); }
float cross2(vec2 a, vec2 b) { return a.x*b.y - a.y*b.x; }
float angle_radians(float deg) { return deg * (PI / 180.0); }

float sector_mask(vec2 v, float a0, float a1, float aa) {
    vec2 b0 = vec2(cos(a0), sin(a0));
    vec2 b1 = vec2(cos(a1), sin(a1));
    float c0 = cross2(b0, v);
    float c1 = cross2(v, b1);
    float m0 = smoothstep(-aa, aa, c0);
    float m1 = smoothstep(-aa, aa, c1);
    return m0 * m1;
}

void fragment() {
    vec2 uv = UV * uv_scale;
    vec2 p = uv - arc_center_uv;

    float a0 = angle_radians(start_angle_deg);
    float a1 = a0 + angle_radians(sweep_deg);
    if (sweep_deg < 0.0) { float t = a0; a0 = a1; a1 = t; } // enforce CCW for mask

    float r = length(p);
    float aa_r = fwidth(r) + edge_softness;
    float aa_s = (fwidth(p.x) + fwidth(p.y)) * 0.5 + edge_softness;

    float half_road = max(1e-5, road_width * 0.5);
    float r_mid     = turn_radius_uv;
    float r_in      = r_mid - half_road;
    float r_out     = r_mid + half_road;

    float in_sector = sector_mask(p, a0, a1, aa_s);

    float in_asphalt  = band_smooth(r - r_mid, half_road, aa_r) * in_sector;
    float in_shoulder = clamp(band_smooth(r - r_mid, half_road + shoulder_width, aa_r) - in_asphalt, 0.0, 1.0) * in_sector;

    vec3 col = grass_color;
    col = mix(col, shoulder_color, in_shoulder);
    col = mix(col, asphalt_color, in_asphalt);

    /* --- edge lines with inset (creates small dark gap next to shoulder) --- */
    float inset = max(0.0, edge_line_width * edge_line_inset_factor);
    float edge_mask =
          band_smooth(r - (r_in  + inset), edge_line_width * 0.5, aa_r)
        + band_smooth(r - (r_out - inset), edge_line_width * 0.5, aa_r);
    edge_mask = clamp(edge_mask, 0.0, 1.0) * in_sector * in_asphalt;
    col = mix(col, line_color, edge_mask);

    /* center dashed line */
    float theta = atan(p.y, p.x);
    float rel = mod(theta - angle_radians(start_angle_deg) + TAU, TAU);
    float sweep = abs(angle_radians(sweep_deg));
    float s = clamp(rel, 0.0, sweep);
    float arc_u = r_mid * s + v_scroll;
    float period = max(1e-4, dash_length + dash_gap);
    float aa_arc = (fwidth(theta) * r_mid) + edge_softness;
    float t = fract(arc_u / period);
    float dash = 1.0 - smoothstep(dash_length / period, (dash_length / period) + aa_arc / max(period, 1e-4), t);
    float center_mask = band_smooth(r - r_mid, center_line_width * 0.5, aa_r) * in_sector * in_asphalt;

    col = mix(col, line_color, center_mask * dash);

    ALBEDO = col;
    ALPHA = 1.0;
}
