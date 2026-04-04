shader_type canvas_item;

#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"

#include "res://shaders/util/debug.gdshaderinc"

group_uniforms general;
uniform float time = 0.0;
uniform float size = 100.0;
uniform int seed = 1;

group_uniforms colors;
uniform vec3 background_color: source_color = vec3(0.45, 0.4, 0.8);
uniform vec3 tracks_color: source_color = vec3(0.1, 0.1, 0.2);

group_uniforms tracks;
uniform float jitter_intensity: hint_range(0.0, 6.0) = 6.0;
const int jitter_bounds = 9;
const int jitter_center = 5;

group_uniforms debug;
uniform bool show_jitter = false;

vec3 draw_joints(vec2 coords, vec3 cur_col)
{	
	vec2 jittered = jitter_grouped(coords, float(jitter_bounds), jitter_intensity, seed);
	ivec2 idx = ivec2(jittered);
	
	if (show_jitter)
	{
		ivec2 group_id = ivec2(coords / float(jitter_bounds));
		cur_col.gb = hash_vec2_vec2(vec2(idx), seed) * max(0.4, float((group_id.x + group_id.y) % 2));
	}
	
	if (idx.x % jitter_bounds == jitter_center && idx.y % jitter_bounds == jitter_center)
	{		
		vec2 uv = fract(jittered);
		uv -= vec2(0.5);
		float alpha = -sd_circle(uv, 0.25);
		
		return mask_aa(cur_col, tracks_color, alpha);
	}

	return cur_col;
}

const int num_offsets = 4;
const vec2[num_offsets] offsets = { vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0) };

const int num_points_in_base_circuit = 8;
const ivec2[num_points_in_base_circuit] circuit_series = 
{
	ivec2(0, 0), ivec2(1, 0), ivec2(2, 0),
	ivec2(2, 1), ivec2(2, 2), ivec2(1, 2),
	ivec2(0, 2), ivec2(0, 1)
};

ivec2 circuit_next(ivec2 current)
{
	for (int i = 0; i < num_points_in_base_circuit; i++)
	{
		if (current == circuit_series[i]) { return circuit_series[(i+1) % num_points_in_base_circuit]; }
	}
}

ivec2 circuit_prev(ivec2 current)
{
	if (current == ivec2(0, 0)) { return circuit_series[num_points_in_base_circuit - 1]; }
	for (int i = 0; i < num_points_in_base_circuit; i++)
	{
		if (current == circuit_series[i]) { return circuit_series[(i-1) % num_points_in_base_circuit]; }
	}
}

vec3 draw_tracks(vec2 coords, vec3 cur_col)
{	
	float bounds = float(jitter_bounds);
	vec2 group_id = floor(coords / bounds);
	vec2 group_uv = mod(coords, bounds);
	
	vec2 center = (group_id * bounds + vec2(float(jitter_center))) + vec2(0.5);
	vec2 jittered_center = jitter_grouped(center, float(jitter_bounds), -jitter_intensity, seed);
	vec2 p0 = mod(jittered_center, bounds);
	
	float alpha;
	
	// IN
	vec2[num_offsets] in_offsets;
	int inputs_found = 0;
	for (int i = 0; i < num_offsets; i++)
	{
		vec2 neighbor_id = group_id - offsets[i];
		int neighbor_offset_idx = int(hash_vec2_float(neighbor_id, seed) * 10.0) % num_offsets;
		vec2 neighbor_offset = offsets[neighbor_offset_idx];
		if (neighbor_id + neighbor_offset == group_id)
		{
			in_offsets[inputs_found] = -neighbor_offset;
			inputs_found++;
		}
	}	
	for (int i = 0; i < inputs_found; i++)
	{
		center = ((group_id + in_offsets[i]) * bounds + vec2(float(jitter_center))) + vec2(0.5);
		jittered_center = jitter_grouped(center, float(jitter_bounds), -jitter_intensity, seed);
		vec2 p_left = jittered_center - group_id * bounds;
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(group_uv, p0, p_left, 0.2)));	
	}
	
	// OUT
	int out_offset_idx = int(hash_vec2_float(group_id, seed) * 10.0) % num_offsets;
	vec2 out_offset = offsets[out_offset_idx];
	
	center = ((group_id + out_offset) * bounds + vec2(float(jitter_center))) + vec2(0.5);
	jittered_center = jitter_grouped(center, float(jitter_bounds), -jitter_intensity, seed);
	vec2 p_right = jittered_center - group_id * bounds;
	
	alpha = sdf_union(vec2(alpha, -sd_oriented_box(group_uv, p0, p_right, 0.2)));
	
	// BASE CIRCUIT
	int circuits_bounds = 3;
	ivec2 circuit_id = ivec2(coords / float(circuits_bounds * jitter_bounds));
	ivec2 circuit_idx = ivec2(mod(group_id, float(circuits_bounds)));
	
	if (circuit_idx != ivec2(1, 1))
	{
		ivec2 next = circuit_next(circuit_idx) + circuit_id * circuits_bounds;
		
		center = (vec2(next) * bounds + vec2(float(jitter_center))) + vec2(0.5);
		jittered_center = jitter_grouped(center, float(jitter_bounds), -jitter_intensity, seed);
		vec2 p_next = jittered_center - group_id * bounds;
		
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(group_uv, p0, p_next, 0.2)));
		
		// PREV
		ivec2 prev = circuit_prev(circuit_idx) + circuit_id * circuits_bounds;
		
		center = (vec2(prev) * bounds + vec2(float(jitter_center))) + vec2(0.5);
		jittered_center = jitter_grouped(center, float(jitter_bounds), -jitter_intensity, seed);
		vec2 p_prev = jittered_center - group_id * bounds;
		
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(group_uv, p0, p_prev, 0.2)));
	}


	return mask_aa(cur_col, tracks_color, alpha);
}

void fragment() 
{
	vec2 coords = UV * size;
	
	COLOR.rgb = background_color;
	COLOR.rgb = draw_joints(coords, COLOR.rgb);
	COLOR.rgb = draw_tracks(coords, COLOR.rgb);
}