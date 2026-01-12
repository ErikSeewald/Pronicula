shader_type canvas_item;
#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"

group_uniforms general;
uniform float time = 0.0;
uniform float size = 12.0;
uniform int seed = 1;

group_uniforms wheels;
uniform float jitter_intensity: hint_range(0.0, 2.0) = 2.0;
uniform float inner_wheel_size = 0.3;
uniform float outer_wheel_size = 0.45;

group_uniforms colors;
uniform vec3 background_col: source_color = vec3(0.4, 0.8, 0.4);

// Samples the procedural SDF wheel texture based on the given UV.
vec4 sample_wheel(vec2 uv)
{
	uv -= vec2(0.5);
	vec4 value = vec4(1.0, 1.0, 1.0, 0.0);
	
	float outer = length(uv) - outer_wheel_size;
	float inner = length(uv) - inner_wheel_size;
	float alpha = -max(outer, -inner);
	
	float aa = fwidth(alpha);	
	vec4 circ = vec4(1.0);
	circ.rgb = mix(circ.rgb, vec3(1.0, 0.0, 0.0), smoothstep(0.0, aa, max(uv.x, 0.0)));
	
	value = mix(value, circ, smoothstep(0.0, aa, alpha));
	return value;
}

// Draws wheels onto the current color at the given grid coordinates.
vec3 draw_wheels(vec2 coords, vec3 cur_color)
{
	//float sin_jitter = 1.7 + sin(time) * 0.3;
	
	// Define jitter groups within which all tiles are jittered identically
	const int jitter_bounds = 3;
	const int center_idx = 1;
	vec2 jitter_seed = floor(coords  / float(jitter_bounds));
	coords = jitter(coords, jitter_seed, seed, jitter_intensity);
	
	// Only draw wheel if the tile is the center of the jitter group
	ivec2 idx = ivec2(coords);
	if (idx.x % jitter_bounds == center_idx && idx.y % jitter_bounds == center_idx) 
	{
		vec2 uv = fract(coords);
		uv = rotate_around_center(uv, hash_vec2_float(vec2(idx), seed) * time);
		vec4 wheel = sample_wheel(uv);
		return mix(cur_color, wheel.rgb, wheel.a);
	}
	
	return cur_color;
}

void fragment() 
{	
	vec2 grid_coords = UV * size;
	COLOR.rgb = background_col;
	COLOR.rgb = draw_wheels(grid_coords, COLOR.rgb);
}