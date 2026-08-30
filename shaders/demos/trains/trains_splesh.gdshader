shader_type canvas_item;

#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"
#include "res://shaders/util/debug.gdshaderinc"
#include "res://shaders/demos/trains/train_tracks.gdshaderinc"

const vec3 BACKGROUND_COL = vec3(0.5, 0.5, 0.8);
const vec3 RED = vec3(1.0, 0.2, 0.4);
const vec3 GREEN = vec3(0.2, 1.0, 0.4);
const vec3 BLUE = vec3(0.3, 0.3, 1.0);
const vec3[3] colors = {RED, GREEN, BLUE};

group_uniforms general;
uniform float time = 0.0;

group_uniforms splesh;
uniform float greyness : hint_range(0.0, 1.0)= 0.0;
uniform uint num_quads;
uniform uint train_lifetime = 16;
uniform uint train_length = 4;

uniform float circ_size = 0.02;

varying flat float quad_id;

vec2 background_to_vertex_space(vec2 background_coord) 
{ 
	float converter = 9.0 / global_size;
	return background_coord * converter; 
}

void vertex()
{
	
	// Assign to train_ids to make them represent segments of the train
	quad_id = floor(float(VERTEX_ID) / 4.0);
	float train_id = floor(quad_id / float(train_length));
	
	// Scale quad (cars smaller than engine)
	float size = mod(quad_id, float(train_length)) == 0.0 ? circ_size * 1.5 : circ_size;
	VERTEX = (VERTEX - vec2(0.5)) * size + vec2(0.5);
	
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
	int circuits_bounds = 3;
	for (uint i = 0u; i < lifestep; i++)
	{
		prevPrevPos = prevPos;
		prevPos = nextPos;
		
		// Get the next position in the circuit
		vec2 jt_group_id = floor(nextPos);
		ivec2 circuit_id = ivec2(nextPos / float(circuits_bounds));
		ivec2 circuit_idx = ivec2(mod(jt_group_id, float(circuits_bounds)));
		int circuit_num = int(hash_vec2_float(vec2(circuit_id), global_seed) * 10.0) % NUM_DEFINED_CIRCUITS;
		ivec2 next = get_next_from_cicuit(circuit_idx, circuit_num);	
		nextPos = vec2(next) + vec2(circuit_id) * float(circuits_bounds);
		
		// Also get the next position if the train where to take a bridge
		int out_offset_idx = int(hash_vec2_float(jt_group_id, global_seed) * 10.0) % NUM_NEIGHBOR_JOINTS;
		vec2 out_offset = NEIGHBOR_JOINTS_OFFSETS[out_offset_idx];
		vec2 bridge_next = prevPos + out_offset;
		
		// INPUTS
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
	nextPos = jitter_grouped(nextPos, 1.0, -global_jitter_intensity / float(JITTER_BOUNDS), global_seed);
	prevPos = jitter_grouped(prevPos, 1.0, -global_jitter_intensity / float(JITTER_BOUNDS), global_seed);
	bg_offset = mix(prevPos, nextPos, mod(t, 1.0));
	
	// Convert to VERTEX space
	vec2 pos = VERTEX;
	pos += background_to_vertex_space(vec2(0.5, 0.5)); // Now aligned with the (unjittered) top left joint
	pos += background_to_vertex_space(bg_offset); // Now at the (jittered) bg_offset joint position	
	
	// Finally, offset the VERTEX by 0.5 so that the center of UV space is
	// at (0,0).
	VERTEX = pos - vec2(0.5);
}

void fragment() 
{
	COLOR.rgb = BACKGROUND_COL;
	
	// Color each train segment with the same color
	float train_id = floor(quad_id / float(train_length));
	vec3 foreground = colors[int(train_id) % 3];
	foreground = mix(foreground, BACKGROUND_COL, greyness);
	
	// Draw train segment
	float circle = -sd_circle(UV - vec2(0.5), 0.5);
	COLOR.rgb = mask_aa(COLOR.rgb, foreground, circle);
	COLOR.a = mask_aa(0.0, 1.0, circle);
}
