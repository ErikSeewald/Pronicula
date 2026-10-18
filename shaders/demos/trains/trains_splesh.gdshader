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

// Generates a spawnpoint (joint) for the current train based on the given
// life cicle that it is in and the joint bounds (side length of the background in number of joints)
vec2 generate_spawnpoint(uint num_life_cicle, float joint_bounds)
{
	vec2 hash = hash_vec2_vec2(vec2(float(num_life_cicle), train_id), global_seed);
	return floor(hash * joint_bounds);
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
	float joint_bounds = global_size / float(JITTER_BOUNDS); // Screen has joint_bounds x joint_bounds joints
	vec2 spawnPoint = generate_spawnpoint(num_life_cicle, joint_bounds);
	
	// Loop over the train's lifetime
	vec2 prevPrevJoint = spawnPoint;
	vec2 prevJoint = spawnPoint;
	vec2 nextJoint = spawnPoint;
	for (uint i = 0u; i < lifestep; i++)
	{
		prevPrevJoint = prevJoint;
		prevJoint = nextJoint;
		
		// Get the next position in the circuit
		vec2 jt_group_id = floor(nextJoint);
		ivec2 circuit_id = get_circuit_id(ivec2(nextJoint));
		ivec2 coords_in_circuit = get_coords_in_circuit(nextJoint);
		int circuit_variant = get_circuit_variant(circuit_id);
		
		const bool GET_NEXT = true;
		ivec2 next = get_from_circuit(coords_in_circuit, circuit_variant, GET_NEXT);	
		nextJoint = vec2(circuit_coords_to_jt_group(next, circuit_id));
		
		// Also get the next position if the train where to take a bridge
		vec2 out_offset = get_random_neighbor_offset(jt_group_id);
		vec2 bridge_next = prevJoint + out_offset;
		
		// INPUTS
		for (int i = 0; i < NUM_NEIGHBOR_JOINTS; i++)
		{
			// Check all the offsets of the neighbors to see if any land on current jitter group
			vec2 neighbor_id = jt_group_id - NEIGHBOR_JOINTS_OFFSETS[i];
			vec2 neighbor_offset = get_random_neighbor_offset(neighbor_id);
			if (neighbor_id + neighbor_offset == jt_group_id)
			{	
				if (bridge_next == prevPrevJoint || bridge_next == nextJoint)
				{
					bridge_next = prevJoint + neighbor_offset;
				}
			}
		}
		
		// Take the bridge either if the train has left a circuit and therefore can only take bridges
		// or by random chance (if the bridge would not mean backtracking)
		bool forceIfLeftCircuit = next == ivec2(-1);
		if (forceIfLeftCircuit || (bridge_next != prevPrevJoint && bridge_next != nextJoint))
		{
			// offset hash by train_id to make sure trains decide differently and by num_life_cicle to make sure they take different
			// paths each respawn
			if (forceIfLeftCircuit || (hash(float(i) + train_id + float(num_life_cicle), global_seed) > 0.5)) { nextJoint = bridge_next;}
		}
		
		// Force the quad back if it has left the screen
		if (nextJoint.x < 0.0 || nextJoint.y < 0.0 || nextJoint.x > joint_bounds || nextJoint.y > joint_bounds)
		{
			nextJoint = prevPrevJoint;
		}
	}
	
	// Apply the uniform jitter to the coordinates
	nextJoint = jitter_grouped(nextJoint, 1.0, global_jitter_intensity / float(JITTER_BOUNDS), global_seed);
	prevJoint = jitter_grouped(prevJoint, 1.0, global_jitter_intensity / float(JITTER_BOUNDS), global_seed);
	
	// Finally, interpolate between the previous and next track joint to get the position.
	return mix(prevJoint, nextJoint, mod(quad_time, 1.0));
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

uniform int train_id_check = 0;
void fragment() 
{	
	// Color each segment of the same train with the same color
	vec3 foreground = train_colors[int(train_id) % 3];
	COLOR.rgb = mix(foreground, GREY, train_greyness);
	
	// Draw train segment
	float circle = -sd_circle(UV - vec2(0.5), 0.5);
	COLOR.a = mask_aa(0.0, 1.0, circle);
}
