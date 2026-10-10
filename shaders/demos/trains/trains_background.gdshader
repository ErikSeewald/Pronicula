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
uniform bool show_jitter = false; // Draw a checker pattern across the screen to highlight the distinct jitter groups

// Generates circuits of connected joints and draws them if the current fragment intersects them.
// - jt_group_id: The ID of the jitter group that the fragment that is being drawn falls into
// - coords_in_jt_group: The coordinates of the current fragment within the jitter group ((x,y) for x,y in [0, JITTER_BOUNDS])
// - joint_pos_in_jt_group: The coordinates of the jittered joint within the jitter group ((x,y) for x,y in [0, JITTER_BOUNDS])
// - circuit_neighbors: 
float draw_circuit(vec2 jt_group_id, vec2 coords_in_jt_group, vec2 joint_pos_in_jt_group, out vec2[2] circuit_neighbors)
{
	float alpha = 0.0;
	float jt_bounds_f = float(JITTER_BOUNDS);
	vec2 jt_center_vec2 = vec2(float(JITTER_CENTER));
	
	ivec2 circuit_id = get_circuit_id(ivec2(jt_group_id));
	ivec2 coords_in_circuit = get_coords_in_circuit(jt_group_id);
	int circuit_variant = get_circuit_variant(circuit_id);
	
	// NEXT IN THE CIRCUIT
	ivec2 next = get_next_from_cicuit(coords_in_circuit, circuit_variant);
	if (next != ivec2(-1))
	{
		ivec2 next_jt_group = circuit_coords_to_jt_group(next, circuit_id);
		vec2 joint_pos_pre_jitter = jt_group_id_to_joint_pos(vec2(next_jt_group));
		vec2 joint_pos = jitter_joint(joint_pos_pre_jitter);
		vec2 p_next = joint_pos - jt_group_id * jt_bounds_f;
		
		circuit_neighbors[0] = p_next;
		alpha = -sd_oriented_box(coords_in_jt_group, joint_pos_in_jt_group, p_next, tracks_thickness);
	}
	
	// PREV IN THE CIRCUIT
	ivec2 prev = get_prev_from_cicuit(coords_in_circuit, circuit_variant);
	if (prev != ivec2(-1))
	{
		ivec2 prev_jt_group = circuit_coords_to_jt_group(prev, circuit_id);
		vec2 joint_pos_pre_jitter = jt_group_id_to_joint_pos(vec2(prev_jt_group));
		vec2 joint_pos = jitter_joint(joint_pos_pre_jitter);
		vec2 p_prev = joint_pos - jt_group_id * jt_bounds_f;
		
		circuit_neighbors[1] = p_prev;
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, joint_pos_in_jt_group, p_prev, tracks_thickness)));
	}
	
	return alpha;
}

// Generates random bridges between neighboring joints and draws them if the current fragment intersects them.
// - jt_group_id: The ID of the jitter group that the fragment that is being drawn falls into
// - coords_in_jt_group: The coordinates of the current fragment within the jitter group ((x,y) for x,y in [0, JITTER_BOUNDS])
// - joint_pos_in_jt_group: The coordinates of the jittered joint within the jitter group ((x,y) for x,y in [0, JITTER_BOUNDS])
// - circuit_neighbors: 
float draw_bridges(vec2 jt_group_id, vec2 coords_in_jt_group, vec2 joint_pos_in_jt_group, in vec2[2] circuit_neighbors)
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
		vec2 joint_pos_pre_jitter = jt_group_id_to_joint_pos((jt_group_id + in_offsets[i]));
		vec2 joint_pos = jitter_joint(joint_pos_pre_jitter);
		vec2 p_left = joint_pos - jt_group_id * jt_bounds_f;
		
		if (p_left == circuit_neighbors[0] || p_left == circuit_neighbors[1]) { continue; }
		
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, joint_pos_in_jt_group, p_left, tracks_thickness)));	
	}
	
	// OUT
	int out_offset_idx = int(hash_vec2_float(jt_group_id, global_seed) * 10.0) % NUM_NEIGHBOR_JOINTS;
	vec2 out_offset = NEIGHBOR_JOINTS_OFFSETS[out_offset_idx];
	
	vec2 joint_pos_pre_jitter = jt_group_id_to_joint_pos((jt_group_id + out_offset));
	vec2 joint_pos = jitter_joint(joint_pos_pre_jitter);
	vec2 p_right = joint_pos - jt_group_id * jt_bounds_f;
	
	if (p_right != circuit_neighbors[0] && p_right != circuit_neighbors[1] )
	{
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, joint_pos_in_jt_group, p_right, tracks_thickness)));
		
		// Draw another track offset by the normal to give that chemistry-formula-like look	
		vec2 direction = normalize(joint_pos_in_jt_group - p_right);
		vec2 normal = vec2(-direction.y, direction.x);
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group - normal, joint_pos_in_jt_group, p_right, tracks_thickness)));	
	}
	
	return alpha;
}

// Draws tracks between the joints based on the given fragment
// coordinates and masks them on top of the given current color.
vec3 draw_tracks(vec2 coords, vec3 cur_col)
{	
	// Jitter group
	float jt_bounds_f = float(JITTER_BOUNDS); // I just do not want to keep doing "float(JITTER_BOUNDS)"
	vec2 jt_group_id = floor(coords / jt_bounds_f);
	vec2 coords_in_jt_group = mod(coords, jt_bounds_f);
	
	// Joint
	vec2 jt_center_vec2 = vec2(float(JITTER_CENTER));
	vec2 joint_pos_pre_jitter = jt_group_id_to_joint_pos(jt_group_id);
	vec2 joint_pos = jitter_joint(joint_pos_pre_jitter);
	vec2 joint_pos_in_jt_group = mod(joint_pos, jt_bounds_f);
	
	// 1. Draw one of a selection of possible complete circuits with predefined bounds to make sure the tracks have high connectivity
	vec2[2] circuit_neighbors; // draw_circuit writes the coordinates of the neighbor joints in the circuit to this array
	float circuit_alpha = draw_circuit(jt_group_id, coords_in_jt_group, joint_pos_in_jt_group, circuit_neighbors);

	// 2. Draw bridges between other joints at random to connect the circuits together
	// (draw_bridges Uses the circuit_neighbors array to avoid adding bridges between joints that were already bridged by the circuit)
	float bridge_alpha = draw_bridges(jt_group_id, coords_in_jt_group, joint_pos_in_jt_group, circuit_neighbors);
	
	float alpha = sdf_union(vec2(circuit_alpha, bridge_alpha));
	return mask_aa(cur_col, tracks_color, alpha);
}

// Draws the joints of the train tracks as little circles based on the
// given coordinates of the fragment. Masks them on top of the given current color.
vec3 draw_joints(vec2 coords, vec3 cur_col)
{
	// Since joints are jittered with jitter_joint(coords), to see if this fragment
	// lands on a jittered joint, we need to use the inverse function and check if the resulting
	// coordinate was the center of a jitter group.
	vec2 inverse_jitter_coords = inverse_jitter_joint(coords);
	ivec2 cell_idx = ivec2(inverse_jitter_coords);
	
	if (show_jitter)
	{
	 	// Checker pattern to show the jitter groups
		ivec2 jt_group_id = ivec2(coords / float(JITTER_BOUNDS));
		float checker_factor = max(0.4, float((jt_group_id.x + jt_group_id.y) % 2));
		cur_col *= hash_vec2_float(vec2(cell_idx), global_seed) * checker_factor * 10.0;
	}
	
	// When undoing the jitter, the given coords land on a jitter center -> Current coords match a jittered joint
	if (cell_idx.x % JITTER_BOUNDS == JITTER_CENTER && cell_idx.y % JITTER_BOUNDS == JITTER_CENTER)
	{		
		vec2 uv = fract(inverse_jitter_coords);
		uv -= vec2(0.5);
		float alpha = -sd_circle(uv, tracks_thickness * 1.5);
		return mask_aa(cur_col, tracks_color, alpha);
	}

	return cur_col;
}

void fragment() 
{
	vec2 coords = UV * global_size;
	
	COLOR.rgb = background_color;
	COLOR.rgb = draw_joints(coords, COLOR.rgb);
	COLOR.rgb = draw_tracks(coords, COLOR.rgb);
}