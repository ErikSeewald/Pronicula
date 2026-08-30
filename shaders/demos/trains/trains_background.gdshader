shader_type canvas_item;

#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/demos/trains/train_tracks.gdshaderinc"

group_uniforms tracks;
uniform float tracks_thickness = 0.3;

group_uniforms colors;
uniform vec3 background_color: source_color = vec3(0.45, 0.4, 0.8);
uniform vec3 tracks_color: source_color = vec3(0.1, 0.1, 0.2);

group_uniforms debug;
uniform bool show_jitter = false;

float sd_circuit(vec2 coords, vec2 jt_group_id, vec2 joint_pos_pre_jitter, vec2 joint_pos, vec2 coords_in_jt_group, vec2 p0, out vec2[2] circuit_neighbors)
{
	float alpha = 0.0;
	
	float jt_bounds_f = float(JITTER_BOUNDS);
	vec2 jt_center_vec2 = vec2(float(JITTER_CENTER));
	
	int circuits_bounds = 3;
	ivec2 circuit_id = ivec2(coords / float(circuits_bounds * JITTER_BOUNDS));
	ivec2 circuit_idx = ivec2(mod(jt_group_id, float(circuits_bounds)));
	
	int circuit_num = int(hash_vec2_float(vec2(circuit_id), global_seed) * 10.0) % NUM_DEFINED_CIRCUITS;
	
	ivec2 next = get_next_from_cicuit(circuit_idx, circuit_num);
	if (next != ivec2(-1))
	{
		next += circuit_id * circuits_bounds;
		joint_pos_pre_jitter = (vec2(next) * jt_bounds_f + jt_center_vec2) + vec2(0.5);
		joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -global_jitter_intensity, global_seed);
		vec2 p_next = joint_pos - jt_group_id * jt_bounds_f;
		
		circuit_neighbors[0] = p_next;
		
		alpha = -sd_oriented_box(coords_in_jt_group, p0, p_next, tracks_thickness);
	}
	
	// PREV
	ivec2 prev = get_prev_from_cicuit(circuit_idx, circuit_num);
	if (prev != ivec2(-1))
	{
		prev += circuit_id * circuits_bounds;
		joint_pos_pre_jitter = (vec2(prev) * jt_bounds_f + jt_center_vec2) + vec2(0.5);
		joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -global_jitter_intensity, global_seed);
		vec2 p_prev = joint_pos - jt_group_id * jt_bounds_f;
		
		circuit_neighbors[1] = p_prev;
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, p0, p_prev, tracks_thickness)));
	}
	
	return alpha;
}


float sd_bridge(vec2 jt_group_id, vec2 joint_pos_pre_jitter, vec2 joint_pos, vec2 coords_in_jt_group, vec2 p0, in vec2[2] circuit_neighbors)
{
	float alpha = 0.0;
	
	float jt_bounds_f = float(JITTER_BOUNDS);
	vec2 jt_center_vec2 = vec2(float(JITTER_CENTER));
	
	// IN

	vec2[NUM_NEIGHBOR_JOINTS] in_offsets;
	int inputs_found = 0;
	for (int i = 0; i < NUM_NEIGHBOR_JOINTS; i++)
	{
		vec2 neighbor_id = jt_group_id - NEIGHBOR_JOINTS_OFFSETS[i];
		int neighbor_offset_idx = int(hash_vec2_float(neighbor_id, global_seed) * 10.0) % NUM_NEIGHBOR_JOINTS;
		vec2 neighbor_offset = NEIGHBOR_JOINTS_OFFSETS[neighbor_offset_idx];
		if (neighbor_id + neighbor_offset == jt_group_id)
		{
			in_offsets[inputs_found] = -neighbor_offset;
			inputs_found++;
		}
	}	
	for (int i = 0; i < inputs_found; i++)
	{
		joint_pos_pre_jitter = ((jt_group_id + in_offsets[i]) * jt_bounds_f + jt_center_vec2) + vec2(0.5);
		joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -global_jitter_intensity, global_seed);
		vec2 p_left = joint_pos - jt_group_id * jt_bounds_f;
		
		if (p_left == circuit_neighbors[0] || p_left == circuit_neighbors[1]) { continue; }
		
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, p0, p_left, tracks_thickness)));	
	}
	
	// OUT
	int out_offset_idx = int(hash_vec2_float(jt_group_id, global_seed) * 10.0) % NUM_NEIGHBOR_JOINTS;
	vec2 out_offset = NEIGHBOR_JOINTS_OFFSETS[out_offset_idx];
	
	joint_pos_pre_jitter = ((jt_group_id + out_offset) * jt_bounds_f + jt_center_vec2) + vec2(0.5);
	joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -global_jitter_intensity, global_seed);
	vec2 p_right = joint_pos - jt_group_id * jt_bounds_f;
	
	if (p_right != circuit_neighbors[0] && p_right != circuit_neighbors[1] )
	{
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, p0, p_right, tracks_thickness)));
		
		// Draw another track offset by the normal to give that chemistry-formula-like look	
		vec2 direction = normalize(p0 - p_right);
		vec2 normal = vec2(-direction.y, direction.x);
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group - normal, p0, p_right, tracks_thickness)));	
	}
	
	return alpha;
}

// Draws the joints/jitter centers of the train tracks as little circles based on the
// given coordinates of the fragment. Uses the given current color to mask them on top.
vec3 draw_joints(vec2 coords, vec3 cur_col)
{	
	vec2 jittered = jitter_grouped(coords, float(JITTER_BOUNDS), global_jitter_intensity, global_seed);
	ivec2 cell_idx = ivec2(jittered);
	
	if (show_jitter)
	{
	 	// Checker pattern to show the jitter groups
		ivec2 jt_group_id = ivec2(coords / float(JITTER_BOUNDS));
		float checker_factor = max(0.4, float((jt_group_id.x + jt_group_id.y) % 2));
		
		// And a random color for each cell within the group
		cur_col.gb = hash_vec2_vec2(vec2(cell_idx), global_seed) * checker_factor;
	}
	
	if (cell_idx.x % JITTER_BOUNDS == JITTER_CENTER && cell_idx.y % JITTER_BOUNDS == JITTER_CENTER)
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
	float jt_bounds_f = float(JITTER_BOUNDS); // I just do not want to keep doing "float(JITTER_BOUNDS)"
	vec2 jt_group_id = floor(coords / jt_bounds_f);
	vec2 coords_in_jt_group = mod(coords, jt_bounds_f);
	
	// Joint
	vec2 jt_center_vec2 = vec2(float(JITTER_CENTER));
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