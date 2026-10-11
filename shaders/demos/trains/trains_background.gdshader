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
// ("Drawing them" means returning an alpha value > 0)
// - coords: The coordinates of the current fragment (in the [UV * global_size] coordinate system)
// - joint_pos: The jittered coordinates of the joint (in the [UV * global_size] coordinate system)
// - jt_group_id: The ID of the jitter group that the fragment that is being drawn falls into
float draw_circuit(vec2 coords, vec2 joint_pos, vec2 jt_group_id)
{
	float alpha = 0.0;
	
	// Get information about the circuit
	ivec2 circuit_id = get_circuit_id(ivec2(jt_group_id));
	ivec2 coords_in_circuit = get_coords_in_circuit(jt_group_id);
	int circuit_variant = get_circuit_variant(circuit_id);
	
	// Loop over the previous and next element of the circuit and add them to alpha
	for (int i = 0; i < 2; ++i)
	{
		bool get_next_or_prev = i == 0;
		ivec2 circuit_neighbor = get_from_circuit(coords_in_circuit, circuit_variant, get_next_or_prev);
		if (circuit_neighbor == ivec2(-1)) { break; } // This joint is not part of the circuit
		
		ivec2 neighbor_jt_group = circuit_coords_to_jt_group(circuit_neighbor, circuit_id);
		vec2 neighbor_joint_pos_pre_jitter = jt_group_id_to_joint_pos(vec2(neighbor_jt_group));
		vec2 neighbor_joint_pos = jitter_joint(neighbor_joint_pos_pre_jitter);
		
		float dist_to_track = sd_oriented_box(coords, joint_pos, neighbor_joint_pos, tracks_thickness);
		alpha = sdf_union(vec2(alpha, -dist_to_track));
	}
	
	return alpha;
}

// Generates random bridges between neighboring joints and draws them if the current fragment intersects them.
// ("Drawing them" means returning an alpha value > 0)
// - coords: The coordinates of the current fragment (in the [UV * global_size] coordinate system)
// - joint_pos: The jittered coordinates of the joint (in the [UV * global_size] coordinate system)
// - jt_group_id: The ID of the jitter group that the fragment that is being drawn falls into
float draw_bridges(vec2 coords, vec2 joint_pos, vec2 jt_group_id)
{
	float alpha = 0.0;
	
	// --- OUTGOING BRIDGE (to another jitter group) ---
	vec2 out_offset = get_random_neighbor_offset(jt_group_id);
	vec2 out_joint_pos_pre_jitter = jt_group_id_to_joint_pos((jt_group_id + out_offset));
	vec2 out_joint_pos = jitter_joint(out_joint_pos_pre_jitter);
	
	float dist_to_bridge = sd_oriented_box(coords, joint_pos, out_joint_pos, tracks_thickness);
	alpha = sdf_union(vec2(alpha, -dist_to_bridge));
	
	// Draw another track offset by the normal to give that chemistry-formula-like look	
	vec2 direction = normalize(joint_pos - out_joint_pos);
	vec2 normal = vec2(-direction.y, direction.x);
	
	dist_to_bridge = sd_oriented_box(coords - normal, joint_pos, out_joint_pos, tracks_thickness * 2.0);
	alpha = sdf_union(vec2(alpha, -dist_to_bridge));	
	
	
	// --- INCOMING BRIDGES (from other jitter groups) ---
	// This needs to be drawn because the outgoing bridges of the other groups will only
	// render to the edge of their own jitter group.
	for (int i = 0; i < NUM_NEIGHBOR_JOINTS; i++)
	{
		// Check all the offset of the neighbors and draw the bridge if any of them land on the current jitter group
		vec2 neighbor_id = jt_group_id - NEIGHBOR_JOINTS_OFFSETS[i];
		vec2 neighbor_offset = get_random_neighbor_offset(neighbor_id);
		if (neighbor_id + neighbor_offset == jt_group_id)
		{
			vec2 in_joint_pos_pre_jitter = jt_group_id_to_joint_pos(neighbor_id);
			vec2 in_joint_pos = jitter_joint(in_joint_pos_pre_jitter);
			
			dist_to_bridge = sd_oriented_box(coords, joint_pos, in_joint_pos, tracks_thickness);
			alpha = sdf_union(vec2(alpha, -dist_to_bridge));	
		}
	}

	return alpha;
}

// Draws the tracks between joints.
// - cur_col: The current fragment color to mask onto
// - coords: The coordinates of the current fragment (in the [UV * global_size] coordinate system)
// - joint_pos: The jittered coordinates of the joint of the fragment's jitter group
// - jt_group_id: The ID of the jitter group that the fragment that is being drawn falls into
vec3 draw_tracks(vec3 cur_col, vec2 coords, vec2 joint_pos, vec2 jt_group_id)
{	
	// 1. Draw a circuit between joints (one out of a selection of predefined circuits) 
	// to make sure the tracks have high connectivity
	float circuit_alpha = draw_circuit(coords, joint_pos, jt_group_id);

	// 2. Draw bridges between other joints at random to connect the circuits together
	float bridge_alpha = draw_bridges(coords, joint_pos, jt_group_id);
	
	float alpha = sdf_union(vec2(circuit_alpha, bridge_alpha));
	return mask_aa(cur_col, tracks_color, alpha);
}

// Draws the joints of the train tracks as little circles.
// - cur_col: The current fragment color to mask onto
// - coords: The coordinates of the current fragment (in the [UV * global_size] coordinate system)
// - joint_pos: The jittered coordinates of the joint of the fragment's jitter group
// - jt_group_id: The ID of the jitter group that the fragment that is being drawn falls into
vec3 draw_joints(vec3 cur_col, vec2 coords, vec2 joint_pos, vec2 jt_group_id)
{	
	if (show_jitter)
	{
	 	// Checker pattern to visualize the different jitter groups
		float checker_factor = max(0.4, mod(jt_group_id.x + jt_group_id.y, 2)) * 10.0;
		
		// Divide jitter groups into smaller squares
		// (Offset by joint_pos because coords on its own is not jittered)
		vec2 square = vec2(floor(joint_pos - coords));
		
		cur_col *= hash_vec2_float(square, global_seed) * checker_factor;
	}
	
	float alpha = -sd_circle(coords - joint_pos, tracks_thickness * 2.0);
	return mask_aa(cur_col, tracks_color, alpha);
}

void fragment() 
{
	// Map UV space to main coordinate space
	vec2 coords = UV * global_size;
	
	// ID/Coordinates of the jitter group that the coords fall into
	vec2 jt_group_id = floor(coords / float(JITTER_BOUNDS));
	
	// Get the track joint of this jitter group and jitter its position
	vec2 joint_pos_pre_jitter = jt_group_id_to_joint_pos(jt_group_id);
	vec2 joint_pos = jitter_joint(joint_pos_pre_jitter);
	
	// Draw through masking
	COLOR.rgb = background_color;
	COLOR.rgb = draw_joints(COLOR.rgb, coords, joint_pos, jt_group_id);
	COLOR.rgb = draw_tracks(COLOR.rgb, coords, joint_pos, jt_group_id);
}