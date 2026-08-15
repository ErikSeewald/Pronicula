shader_type canvas_item;

#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/demos/trains/train_tracks.gdshaderinc"

group_uniforms colors;
uniform vec3 background_color: source_color = vec3(0.45, 0.4, 0.8);
uniform vec3 tracks_color: source_color = vec3(0.1, 0.1, 0.2);

group_uniforms debug;
uniform bool show_jitter = false;

// Draws the joints/jitter centers of the train tracks as little circles based on the
// given coordinates of the fragment. Uses the given current color to mask them on top.
vec3 draw_joints(vec2 coords, vec3 cur_col)
{	
	vec2 jittered = jitter_grouped(coords, float(jitter_bounds), global_jitter_intensity, global_seed);
	ivec2 cell_idx = ivec2(jittered);
	
	if (show_jitter)
	{
	 	// Checker pattern to show the jitter groups
		ivec2 jt_group_id = ivec2(coords / float(jitter_bounds));
		float checker_factor = max(0.4, float((jt_group_id.x + jt_group_id.y) % 2));
		
		// And a random color for each cell within the group
		cur_col.gb = hash_vec2_vec2(vec2(cell_idx), global_seed) * checker_factor;
	}
	
	if (cell_idx.x % jitter_bounds == jitter_center && cell_idx.y % jitter_bounds == jitter_center)
	{		
		vec2 uv = fract(jittered);
		uv -= vec2(0.5);
		float alpha = -sd_circle(uv, tracks_thickness * 1.5);
		return mask_aa(cur_col, tracks_color, alpha);
	}

	return cur_col;
}


// Draws tracks between the joints at the center of jitter-groups based on the given fragment
// coordinates and masks them on top of the given current color.
vec3 draw_tracks(vec2 coords, vec3 cur_col)
{	
	// Jitter-group
	float jt_bounds_f = float(jitter_bounds); // I just do not want to keep doing "float(jitter_bounds)"
	vec2 jt_group_id = floor(coords / jt_bounds_f);
	vec2 coords_in_jt_group = mod(coords, jt_bounds_f);
	
	// Joint
	vec2 jt_center_vec2 = vec2(float(jitter_center));
	vec2 joint_pos_pre_jitter = (jt_group_id * jt_bounds_f + jt_center_vec2) + vec2(0.5);
	vec2 joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -global_jitter_intensity, global_seed);
	vec2 p0 = mod(joint_pos, jt_bounds_f);
	
	// BASE CIRCUIT
	vec2[2] circuit_neighbors;
	float circuit_alpha = sd_circuit(coords, jt_group_id, joint_pos_pre_jitter, joint_pos, coords_in_jt_group, p0, circuit_neighbors);
	
	float bridge_alpha = sd_bridge(jt_group_id, joint_pos_pre_jitter, joint_pos, coords_in_jt_group, p0, circuit_neighbors);
	float alpha = sdf_union(vec2(circuit_alpha, bridge_alpha));

	return mask_aa(cur_col, tracks_color, alpha);
}

void fragment() 
{
	vec2 coords = UV * global_size;
	
	COLOR.rgb = background_color;
	COLOR.rgb = draw_joints(coords, COLOR.rgb);
	COLOR.rgb = draw_tracks(coords, COLOR.rgb);
}