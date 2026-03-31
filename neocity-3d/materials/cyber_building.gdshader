shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.02, 0.02, 0.04, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.0, 0.8, 1.0); // Neon Pink
uniform float grid_size = 2.0;
uniform float edge_thickness = 0.08;
uniform float emission_str = 8.0;

void fragment() {
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 abs_norm = abs(NORMAL);
    vec2 grid_uv = vec2(0.0);
    
    if (abs_norm.x > 0.5) grid_uv = world_pos.zy;
    else if (abs_norm.z > 0.5) grid_uv = world_pos.xy;
    else grid_uv = world_pos.xz;
    
    vec2 local_uv = fract(grid_uv / grid_size);
    
    // Wireframe edge detection
    float edge_x = step(local_uv.x, edge_thickness) + step(1.0 - edge_thickness, local_uv.x);
    float edge_y = step(local_uv.y, edge_thickness) + step(1.0 - edge_thickness, local_uv.y);
    float edge = clamp(edge_x + edge_y, 0.0, 1.0);
    
    ALBEDO = mix(base_color.rgb, edge_color.rgb, edge);
    METALLIC = 0.8;
    ROUGHNESS = 0.2;
    EMISSION = edge_color.rgb * edge * emission_str;
}
