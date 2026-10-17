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

vec2 get_jitter_group_coordinates()
{
		// Trains hava a lifetime beyond which they respawn. This is done because
	// some stateful loop over all steps in their lifetime is necessary.
	// - Each train receives an offset in their life cicle to make it seem more natural
	// - Each segment/quad of one train also receives an offset to make them follow each other
	float life_cicle_offset = hash(train_id, global_seed) * float(train_lifetime);
	float train_time_offset = mod(float(quad_id - train_id) * 0.2, float(train_length));
	float t = time - train_time_offset + life_cicle_offset;
	
	// Use the life cicle number to make each train behave differently on new cicles
	uint num_life_cicle = uint(t / float(train_lifetime));
	
	// Start the lifesteps at 1u to make sure trains immediately move after spawning
	uint lifestep = uint(t) % (train_lifetime);
	lifestep += 1u;
	
	// Get tracks joint position relative to BACKGROUND space
	float side = global_size / float(JITTER_BOUNDS);
	vec2 bg_offset = floor(hash_vec2_vec2(vec2(float(num_life_cicle), train_id), global_seed) * side);

	// Loop over the train's lifetime
	vec2 prevPrevPos = bg_offset;
	vec2 prevPos = bg_offset;
	vec2 nextPos = bg_offset;
	for (uint i = 0u; i < lifestep; i++)
	{
		prevPrevPos = prevPos;
		prevPos = nextPos;
		
		// Get the next position in the circuit
		vec2 jt_group_id = floor(nextPos);
		ivec2 circuit_id = get_circuit_id(ivec2(nextPos));
		ivec2 coords_in_circuit = get_coords_in_circuit(nextPos);
		int circuit_variant = get_circuit_variant(circuit_id);
		
		const bool GET_NEXT = true;
		ivec2 next = get_from_circuit(coords_in_circuit, circuit_variant, GET_NEXT);	
		nextPos = vec2(circuit_coords_to_jt_group(next, circuit_id));
		
		// Also get the next position if the train where to take a bridge
		vec2 out_offset = get_random_neighbor_offset(jt_group_id);
		vec2 bridge_next = prevPos + out_offset;
		
		// INPUTS
		vec2[NUM_NEIGHBOR_JOINTS] in_offsets;
		int inputs_found = 0;
		for (int i = 0; i < NUM_NEIGHBOR_JOINTS; i++)
		{
			vec2 neighbor_id = jt_group_id - NEIGHBOR_JOINTS_OFFSETS[i];
			vec2 neighbor_offset = get_random_neighbor_offset(neighbor_id);
			if (neighbor_id + neighbor_offset == jt_group_id)
			{
				in_offsets[inputs_found] = -neighbor_offset;
				inputs_found++;
			}
		}
		
		if (inputs_found > 0)
		{
			int i = 0;
			while (i < inputs_found && (bridge_next == prevPrevPos || bridge_next == nextPos))
			{
				bridge_next = prevPos + in_offsets[i];
				i++;
			}
		}
		
;
		
		// Take the bridge either if the train has left a circuit and therefore can only take bridges
		// or by random chance (if the bridge would not mean backtracking)
		bool forceIfLeftCircuit = next == ivec2(-1);
		if (forceIfLeftCircuit || (bridge_next != prevPrevPos && bridge_next != nextPos))
		{
			// offset hash by train_id to make sure trains decide differently and by num_life_cicle to make sure they take different
			// paths each respawn
			if (forceIfLeftCircuit || (hash(float(i) + train_id + float(num_life_cicle), global_seed) > 0.5)) { nextPos = bridge_next;}
		}
		
		bool forceBackIfLeftScreen = nextPos.x < 0.0 || nextPos.y < 0.0 || nextPos.x > side || nextPos.y > side;
		if (forceBackIfLeftScreen)
		{
			nextPos = prevPrevPos;
		}
	}
	
	// Finally, the coordinates can be jittered and interpolated.
	nextPos = jitter_grouped(nextPos, 1.0, global_jitter_intensity / float(JITTER_BOUNDS), global_seed);
	prevPos = jitter_grouped(prevPos, 1.0, global_jitter_intensity / float(JITTER_BOUNDS), global_seed);
	bg_offset = mix(prevPos, nextPos, mod(t, 1.0));
	return bg_offset;
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
