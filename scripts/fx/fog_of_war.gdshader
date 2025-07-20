shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled, unshaded;

uniform sampler2D visibility_texture : source_color, hint_default_black;
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 0.8);
uniform vec2 map_world_size = vec2(120.0, 120.0);
uniform vec2 map_world_origin = vec2(-60.0, -60.0);
uniform float fog_height : hint_range(0.0, 10.0) = 0.5;
uniform float visibility_threshold : hint_range(0.0, 1.0) = 0.4;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.15;
uniform float fade_distance : hint_range(0.0, 10.0) = 3.0;
uniform bool debug_mode = false;

varying vec3 world_position;

void vertex() {
    // Transform the vertex position to world space
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float sample_visibility_smooth(vec2 uv) {
    // Sample the visibility texture with smooth filtering
    return texture(visibility_texture, uv).r;
}

float calculate_fog_fade(vec2 map_uv) {
    // Sample visibility at current position
    float center_visibility = sample_visibility_smooth(map_uv);
    
    // If we're in a visible area, check distance to fog boundary
    if (center_visibility > visibility_threshold) {
        return 0.0; // No fog in visible areas
    }
    
    // Calculate texture space step size based on world fade distance
    vec2 texture_size = vec2(textureSize(visibility_texture, 0));
    vec2 world_to_texture = texture_size / map_world_size;
    float fade_step = fade_distance * length(world_to_texture) / texture_size.x;
    
    // Sample in multiple directions to find distance to visible areas
    float min_distance_to_visible = fade_distance;
    
    // Sample in 8 directions around the current position
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * 3.14159 * 2.0 / 8.0;
        vec2 direction = vec2(cos(angle), sin(angle));
        
        // Sample at multiple distances in this direction
        for (int j = 1; j <= 8; j++) {
            float distance = float(j) * fade_step / 8.0;
            vec2 sample_uv = map_uv + direction * distance;
            
            // Clamp to texture bounds
            sample_uv = clamp(sample_uv, vec2(0.0), vec2(1.0));
            
            float sample_visibility = sample_visibility_smooth(sample_uv);
            
            // If we found a visible area, record the distance
            if (sample_visibility > visibility_threshold) {
                min_distance_to_visible = min(min_distance_to_visible, distance * fade_distance / fade_step);
                break;
            }
        }
    }
    
    // Create smooth fade based on distance to visible areas
    float fade_factor = smoothstep(0.0, fade_distance, min_distance_to_visible);
    
    // Combine with original visibility-based fog
    float base_fog = 1.0 - smoothstep(visibility_threshold - edge_softness, visibility_threshold + edge_softness, center_visibility);
    
    // Apply fade factor to create softer edges
    return base_fog * fade_factor;
}

void fragment() {
    // Convert world position to map UV coordinates
    vec2 map_uv = (world_position.xz - map_world_origin) / map_world_size;
    map_uv = clamp(map_uv, vec2(0.0), vec2(1.0));
    
    // Sample visibility texture
    float visibility_raw = texture(visibility_texture, map_uv).r;
    
    // Debug mode: show raw visibility data with high contrast
    if (debug_mode) {
        if (visibility_raw > 0.5) {
            ALBEDO = vec3(0.0, 1.0, 0.0); // Bright green for visible
            ALPHA = 1.0;
        } else {
            ALBEDO = vec3(1.0, 0.0, 0.0); // Bright red for fogged
            ALPHA = 1.0;
        }
    } else {
        // Calculate fog with smooth edge fading
        float fog_alpha_factor = calculate_fog_fade(map_uv);
        float fog_alpha = fog_color.a * fog_alpha_factor;
        
        ALBEDO = fog_color.rgb;
        ALPHA = fog_alpha;
    }
}