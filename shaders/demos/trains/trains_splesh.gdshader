shader_type canvas_item;

#include "res://shaders/demos/trains/train_tracks.gdshaderinc"

const vec3 GREY = vec3(0.5, 0.5, 0.8);
const vec3 RED = vec3(1.0, 0.2, 0.4);
const vec3 GREEN = vec3(0.2, 1.0, 0.4);
const vec3 BLUE = vec3(0.3, 0.3, 1.0);
const vec3[3] train_colors = {RED, GREEN, BLUE};

uniform float time = 0.0;
uniform uint train_length = 4; // Segments per train
uniform uint train_lifetime = 128; // How many moves between track joints until "respawn"
uniform float train_size_factor = 1.0;
uniform float train_greyness : hint_range(0.0, 1.0) = 0.0;

varying flat float quad_id; // Which quad of the splesh is being rendered?
varying flat float train_id; // Which train does the quad belong to?

// Max. options for the next joint at any time
// (Next in circuit, prev in circuit, outgoing bridge, incoming bridges from neighbor joints)
const int NUM_NEXT_OPTIONS = NUM_NEIGHBOR_JOINTS + 3;

// Offsets the given vertex so that the quad is centered around (0.0)
// and scales it based on scaling uniforms.
// Quads that represent the engine of a train are scaled larger than those that represent cars.
vec2 centerAndScale(vec2 v)
{
	v = v - vec2(0.5);
	
	bool isEngine = mod(quad_id, float(train_length)) == 0.0;
	float train_size = 1.75 / global_size * train_size_factor;
	float size = isEngine ? train_size * 1.5 : train_size;
	return v * size;
}

// Converts a coordinate relative to the jitter groups of the background shader
// into a coordinate in vertex space of this splesh shader.
vec2 jitter_group_to_vertex_space(vec2 background_coord) 
{ 
	float converter = float(JITTER_BOUNDS) / global_size;
	return background_coord * converter; 
}

// Returns a float t that represents the uniform time with a quad-specific offset
// to control its position in space over time.
//
// Trains hava a lifetime beyond which they respawn. This is done because
// a stateful loop over all steps in their lifetime is necessary.
// - Each train receives an offset in their life cicle to make their respawns not happen at the same time
// - Each segment/quad of one train also receives an offset to make them follow each other
float get_quad_time()
{
	float life_cicle_offset = hash(train_id, global_seed) * float(train_lifetime);
	float quad_time_offset = mod(quad_id, float(train_length)) * 0.2;
	return time - quad_time_offset + life_cicle_offset;
}

// Generates a spawnpoint (on a track joint) for the current train based on the given
// life cicle. Ensures that it is in and the joint bounds (side length of the background in number of joints)
vec2 generate_spawnpoint(uint num_life_cicle, float joint_bounds)
{
	vec2 hash = hash_vec2_vec2(vec2(float(num_life_cicle), train_id), global_seed);
	return floor(hash * joint_bounds);
}

// Returns true if the given vec2 is not equal to the given previous joint or
// any other candidate for the next joint.
bool is_next_joint_candidate(vec2 joint, vec2 prev_joint, vec2[NUM_NEXT_OPTIONS] next_options)
{
	bool is_candidate = joint != prev_joint;
	for (int i = 0; i < NUM_NEXT_OPTIONS && is_candidate; i++)
	{
		is_candidate = is_candidate && joint != next_options[i];
	}
	return is_candidate;
}

// Gets the coordinates of the quad that is being rendered in jitter group space.
// Since there is one track joint per jitter group and the trains only move between joints,
// it is easier to calculate the train's position in this coordinate system and then later
// convert it back into VERTEX space.
//
// For this, it loops over the train's lifetime, calculates the joints it would have moved
// along during that time and finally interpolates between the previous and next joint with
// an offset by quad_id to place the quad on the tracks.
vec2 get_jitter_group_coordinates()
{
	// Offset the global time uniform for this specific quad
	float quad_time = get_quad_time();

	// Get the lifestep of the quad during the current life cicle
	// (moves between two joints in a single lifestep)
	uint lifestep = uint(quad_time) % (train_lifetime);
	
	// Use a life cicle number to make trains behave differently on new cicles
	uint num_life_cicle = uint(quad_time / float(train_lifetime));
	
	// Spawn the train somewhere on the map
	// (Offset joint_bounds by -0.5 because the joints are at the jitter group center)
	float joint_bounds = floor(global_size / float(JITTER_BOUNDS) - 0.5);
	vec2 spawn_point = generate_spawnpoint(num_life_cicle, joint_bounds);
	
	// Loop over the train's lifetime
	vec2 prev_joint = spawn_point;
	vec2 cur_joint = spawn_point;
	vec2 next_joint = spawn_point;
	for (uint i = 0u; i < lifestep; i++)
	{
		prev_joint = cur_joint;
		cur_joint = next_joint;
		
		// Initialize all options for the next joint to vec2(-1).
		// Options in order are: Next in circuit, outgoing bridge, incoming bridges
		vec2[NUM_NEXT_OPTIONS] next_options = {vec2(-1), vec2(-1), vec2(-1), vec2(-1), vec2(-1), vec2(-1), vec2(-1)};
		
		// Get current circuit
		ivec2 cur_circuit_id = get_circuit_id(ivec2(cur_joint));
		ivec2 cur_coords_in_circuit = get_coords_in_circuit(cur_joint);
		int cur_circuit_variant = get_circuit_variant(cur_circuit_id);
		
		// Get the next and previous position in the circuit
		// (previous is an option too because we might have entered via bridge -> prev might be a new path)
		ivec2 next_coords_in_circuit = get_from_circuit(cur_coords_in_circuit, cur_circuit_variant, true);
		ivec2 prev_coords_in_circuit = get_from_circuit(cur_coords_in_circuit, cur_circuit_variant, false);	
		if (next_coords_in_circuit != ivec2(-1)) // Skip if not part of a circuit at all
		{
			next_options[0] = vec2(circuit_coords_to_jt_group(next_coords_in_circuit, cur_circuit_id));
			next_options[1] = vec2(circuit_coords_to_jt_group(prev_coords_in_circuit, cur_circuit_id));
		}
		
		// Also get the next position if the train were to take the outgoing bridge
		next_options[2] = cur_joint + get_neighbor_offset(cur_joint);
		
		// And check for incoming bridges from neighbor joints
		for (int i = 0; i < NUM_NEIGHBOR_JOINTS; i++)
		{	
			vec2 neighbor_joint = cur_joint - NEIGHBOR_JOINTS_OFFSETS[i];
			vec2 neighbor_bridge_offset = get_neighbor_offset(neighbor_joint);
			if (neighbor_joint + neighbor_bridge_offset == cur_joint)
			{	
				next_options[3 + i] = neighbor_joint;
			}
		}
		
		// Randomly choose one of the options for the next joint
		float rand_hash = hash(float(i + num_life_cicle) + train_id, global_seed);
		int random_idx = int(rand_hash * float(NUM_NEXT_OPTIONS));
		
		// If the chosen joint is out of bounds (includes invalid indicator vec2(-1)), 
		// or if it would lead to backtracking, use the next valid one.
		// If we have run out of non-backtracking options, just backtrack.
		for (int j = 0; j < NUM_NEXT_OPTIONS; j++)
		{
			vec2 chosen_next = next_options[(random_idx + j) % NUM_NEXT_OPTIONS];
			
			// Skip if out of bounds
			if (chosen_next.x < 0.0 || chosen_next.y < 0.0 || chosen_next.x > joint_bounds || chosen_next.y > joint_bounds)
			{ continue; }
			
			next_joint = chosen_next; // Save it for now, even if it might backtrack
			if (next_joint != prev_joint) { break; } // Not backtracking -> Perfect. Exit early.
		}
	}
	
	// Apply jitter to the coordinates based on the global shader uniforms
	const float _jt_group_size = 1.0; // 1.0 because the coordinates are already relative to jitter groups
	float _jitter_intensity = global_jitter_intensity / float(JITTER_BOUNDS); // Need to scale this down for the same reason
	cur_joint = jitter_grouped(cur_joint, _jt_group_size, _jitter_intensity, global_seed);
	next_joint = jitter_grouped(next_joint, _jt_group_size, _jitter_intensity, global_seed);
	
	// Finally, interpolate between the current and next track joint to get the position.
	return mix(cur_joint, next_joint, mod(quad_time, 1.0));
}

void vertex()
{
	// Get the quad id of the vertex and 
	// assign splesh quads to train_ids to make them represent segments of the train
	quad_id = floor(float(VERTEX_ID) / 4.0);	
	train_id = floor(quad_id / float(train_length));
	
	// Scale the quad and center it around (0,0)
	VERTEX = centerAndScale(VERTEX);
	
	// Get the position of the train segment in jitter group space
	vec2 jt_group_coords = get_jitter_group_coordinates();
	
	// Convert it to VERTEX space by
	// 1. Aligning it with the center of the top left jitter group
	// (Trains spawn on track joints, which sit at the center of jitter groups -> Therefore this first alignment is needed)
	VERTEX += jitter_group_to_vertex_space(vec2(0.5, 0.5));
	
	// 2. Offsetting it by the jitter group coordinates to align it with the final position relative to the background
	VERTEX += jitter_group_to_vertex_space(jt_group_coords);
}

void fragment() 
{	
	// Color each segment of the same train with the same color
	vec3 foreground = train_colors[int(train_id) % 3];
	COLOR.rgb = mix(foreground, GREY, train_greyness);
	
	// Draw train segment
	float circle = -sd_circle(UV - vec2(0.5), 0.5);
	COLOR.a = mask_aa(0.0, 1.0, circle);
}
