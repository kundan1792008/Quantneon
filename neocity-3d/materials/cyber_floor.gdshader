shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_albedo : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform vec4 grid_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform float grid_spacing = 4.0;
uniform float grid_thickness = 0.05;
uniform float emission_energy = 5.0;

uniform float puddle_scale = 0.1;
uniform float puddle_threshold = 0.5;

// Hash function for noise
vec2 random2(vec2 st){
    st = vec2( dot(st,vec2(127.1,311.7)),
              dot(st,vec2(269.5,183.3)) );
    return -1.0 + 2.0*fract(sin(st)*43758.5453123);
}

// Gradient Noise
float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);

    vec2 u = f*f*(3.0-2.0*f);

    return mix( mix( dot( random2(i + vec2(0.0,0.0) ), f - vec2(0.0,0.0) ),
                     dot( random2(i + vec2(1.0,0.0) ), f - vec2(1.0,0.0) ), u.x),
                mix( dot( random2(i + vec2(0.0,1.0) ), f - vec2(0.0,1.0) ),
                     dot( random2(i + vec2(1.0,1.0) ), f - vec2(1.0,1.0) ), u.x), u.y);
}

void fragment() {
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 uv = world_pos.xz;
    
    // Grid Logic
    vec2 grid_uv = fract(uv / grid_spacing);
    float grid_line = step(grid_uv.x, grid_thickness) + step(grid_uv.y, grid_thickness);
    grid_line = clamp(grid_line, 0.0, 1.0);
    
    // Puddle Logic (Perlin Noise)
    float n = noise(uv * puddle_scale) * 0.5 + 0.5;
    float puddle = smoothstep(puddle_threshold - 0.1, puddle_threshold + 0.1, n);
    
    // Mixing Albedo
    ALBEDO = mix(base_albedo.rgb, grid_color.rgb, grid_line);
    
    // Wet floor reflects heavily
    METALLIC = mix(0.2, 0.95, puddle);
    ROUGHNESS = mix(0.9, 0.05, puddle);
    
    // Grid glow
    EMISSION = grid_color.rgb * grid_line * emission_energy;
}
