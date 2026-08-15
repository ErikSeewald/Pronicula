shader_type canvas_item;

#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"
#include "res://shaders/util/debug.gdshaderinc"
#include "res://shaders/demos/trains/train_tracks.gdshaderinc"

const vec3 BACKGROUND_COL = vec3(0.2, 0.2, 0.2);
const vec3 RED = vec3(1.0, 0.2, 0.2);
const vec3 GREEN = vec3(0.2, 1.0, 0.2);
const vec3 BLUE = vec3(0.2, 0.2, 1.0);
const vec3 YELLOW = vec3(1.0, 1.0, 0.2);
const vec3[4] colors = {RED, GREEN, BLUE, YELLOW};

group_uniforms splesh;
uniform uint num_quads;
uniform uint train_lifetime = 16;
uniform uint train_length = 4;

uniform float circ_size = 0.02;

uniform float max_id : hint_range(0.0, 10.0, 1.0) = 1;
uniform int x_offset = 0;
uniform int y_offset = 0;

varying flat float quad_id;
varying vec2 v;

vec2 tr_background(vec2 input) { return input / 11.111111 * (100.0/global_size); }

void vertex()
{
	// Scale quad
	VERTEX = (VERTEX - vec2(0.5)) * circ_size + vec2(0.5);
	
	// Assign to train_ids to make them represent segments of the train
	quad_id = floor(float(VERTEX_ID) / 4.0);
	float train_id = floor(quad_id / float(train_length));
	
	// Spawn the segments along an initial distribution
	float side = floor(sqrt(float(num_quads) / float(train_length)));
	float y = floor(train_id / side);
	float x = (train_id - y * side) * 2.0 ;
	
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
	vec2 bg_offset = vec2(x + float(x_offset), y + float(y_offset));
	

	// Loop over the trains lifetime
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
		int circuit_num = int(hash_vec2_float(vec2(circuit_id), global_seed) * 10.0) % num_circuits;
		ivec2 next = get_from_circuit(circuit_idx, circuit_num, CIRCUIT_NEXT);	
		nextPos = vec2(next) + vec2(circuit_id) * float(circuits_bounds);
		
		// Also get the next position if the train where to take a bridge
		// OUT (TODO: ALSO ALLOW THEM TO MOVE ALONG "IN" BRIDGES, OTHERWISE THE CAN GET STUCK)
		int out_offset_idx = int(hash_vec2_float(jt_group_id, global_seed) * 10.0) % num_neighbors;
		vec2 out_offset = neighbor_offsets[out_offset_idx];
		vec2 bridge_next = prevPos + out_offset;
		
		// Take the bridge either if the train has left a circuit and therefore can only take bridges
		// or by random chance (if the bridge would not mean backtracking)
		bool forceIfLeftCircuit = next == ivec2(-1);
		if (forceIfLeftCircuit || (bridge_next != prevPrevPos && bridge_next != nextPos))
		{
			// offset hash by train_id to make sure trains decide differently and by num_life_cicle to make sure they take different
			// paths each respawn
			if (forceIfLeftCircuit || (hash(float(i) + train_id + float(num_life_cicle), global_seed) > 0.5)) { nextPos = bridge_next;}
		}
	}
	
	// Finally, the coordinates can be jittered and interpolated.
	nextPos = jitter_grouped(nextPos, 1.0, -global_jitter_intensity / float(jitter_bounds), global_seed);
	prevPos = jitter_grouped(prevPos, 1.0, -global_jitter_intensity / float(jitter_bounds), global_seed);
	bg_offset = mix(prevPos, nextPos, mod(t, 1.0));
	
	// DEBUG: Visualize the stored positions using the vertices
	/*
	if (VERTEX_ID == 0) { bg_offset = prevPrevPos; }
	else if (VERTEX_ID == 1) { bg_offset = prevPos; }
	else if (VERTEX_ID == 2) { bg_offset = nextPos; }*/
	
	// Convert to VERTEX space
	vec2 pos = VERTEX;
	pos += tr_background(vec2(0.5, 0.5)); // Now aligned with the (unjittered) top left joint
	pos += tr_background(bg_offset); // Now at the (jittered) bg_offset joint position	
	
	// Finally, offset the VERTEX by 0.5 so that the center of UV space is
	// at (0,0).
	VERTEX = pos - vec2(0.5);
}

void fragment() 
{
	COLOR.rgb = BACKGROUND_COL;
	
	// Color each train segment with the same color
	float train_id = floor(quad_id / float(train_length));
	vec3 foreground = colors[int(train_id) % 4];
	
	// Draw train segment
	float circle = -sd_circle(UV - vec2(0.5), 0.5);
	COLOR.rgb = mask_aa(COLOR.rgb, foreground, circle);
	COLOR.a = mask_aa(0.0, 1.0, circle);
	
	//if (quad_id > max_id) { COLOR.a = 0.0; }
}
