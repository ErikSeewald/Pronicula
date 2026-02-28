shader_type canvas_item;
#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"

// Colors are kept constant because I use color distances for masking sometimes
const vec3 BACKGROUND_COL = vec3(0.475, 0.78, 0.459);
const vec3 WHEEL_COL_A = vec3(0.988, 0.0, 0.298);
const vec3 WHEEL_COL_B = vec3(0.0, 0.647, 0.518);
const vec3 HAMSTER_COL_BASE = vec3(1.0, 0.45, 0.2);
const vec3 HAMSTER_SKIN_COL = vec3(1.0, 0.8, 0.8);
const vec3 HAMSTER_NOSE_COL = vec3(1.0, 0.6, 0.6);
const vec4 TRANSPARENT = vec4(1.0, 1.0, 1.0, 0.0);

group_uniforms general;
uniform float time = 0.0;
uniform float size = 12.0;
uniform int seed = 1;

group_uniforms wheels;
// Define jitter groups within which all tiles are jittered identically
uniform float jitter_intensity: hint_range(0.0, 2.0) = 2.0;
const int jitter_bounds = 3;
const int jitter_center = 1;

const float WHEEL_INNER_RADIUS = 0.3;
const float WHEEL_OUTER_RADIUS = 0.45;
const vec2 wheel_center_to_bottom = vec2(0.5, 0.5 + WHEEL_INNER_RADIUS);

group_uniforms hamsters;
const float HAMSTER_SIZE = 0.13;
uniform uint hamster_count = 30;
uniform float bobbing_speed = 50.0;
uniform float wheel_desire: hint_range(0.0, 1.0) = 0.75; // Chance to choose a wheel as the next goal

// Jitters the given coordinates with a jitter seed derived from
// the jitter group they fall into.
// As a result, all coordinates within the same group are jittered the same.
vec2 jitter_grouped(vec2 coords)
{
	vec2 jitter_seed = floor(coords  / float(jitter_bounds));
	return jitter(coords, jitter_seed, seed, jitter_intensity);
}

// Samples the procedural SDF wheel texture based on the given uv as well
// as the rotated uv for the non-static parts. Uses the difference
// between cur_col and BACKGROUND_COL to mask out the hamsters that were
// drawn prior, drawing them inbetween wheel background and foreground.
//
// Returns vec4(wheel_rgb, alpha)
vec4 sample_wheel(vec2 uv, vec2 rotated_uv, vec3 cur_col)
{
	uv -= vec2(0.5);
	rotated_uv -= vec2(0.5);
	float alpha = 0.0;
	
	float main_wheel = -sd_wheel(uv, WHEEL_OUTER_RADIUS, WHEEL_INNER_RADIUS);
	float is_main_wheel = ceil(main_wheel);
	
	const float AXLE_RADIUS = WHEEL_OUTER_RADIUS * 0.2;
	float axle = -sd_circle(uv, AXLE_RADIUS);
	
	alpha = max(main_wheel, axle);
	
	const float LEG_WIDTH = WHEEL_OUTER_RADIUS * 0.28;
	const float LEG_LENGTH = 0.42;
	float leg_left = -sd_oriented_box(uv, vec2(0.0), vec2(-LEG_LENGTH, LEG_LENGTH), LEG_WIDTH);
	float leg_right = -sd_oriented_box(uv, vec2(0.0), vec2(LEG_LENGTH, LEG_LENGTH), LEG_WIDTH);
	
	alpha = max(max(alpha, leg_left), leg_right);
	
	const float BAR_WIDTH = LEG_WIDTH * 0.65;
	const float BAR_LENGTH = WHEEL_OUTER_RADIUS * 0.9;
	float axis_bar_h = -sd_oriented_box(rotated_uv, vec2(BAR_LENGTH, 0.0), vec2(-BAR_LENGTH, 0.0), BAR_WIDTH);
	float axis_bar_v = -sd_oriented_box(rotated_uv, vec2(0.0, BAR_LENGTH), vec2(0.0, -BAR_LENGTH), BAR_WIDTH);
	
	alpha = max(max(alpha, axis_bar_h), axis_bar_v);
	
	// Hamster in front of legs, axle, bars but behind main wheel
	float hamster_mask = mask_aa(length(BACKGROUND_COL - cur_col), 0.0, is_main_wheel);
	alpha = mask_aa(alpha, 0.0, hamster_mask);

	vec3 color = mask_aa(WHEEL_COL_A, WHEEL_COL_B, max(rotated_uv.x, 0.0) * is_main_wheel);
	return vec4(color, alpha); // mask_aa is applied later
}

// Draws wheels onto the current color at the given coordinate.
// This coordinate is used to determine wether the fragment falls onto the UV bounds of a jittered
// wheel. Should that be the case, sample_wheel() makes sure to mask the pre-drawn hamsters between
// the various parts of the wheel correctly.
// If the hamster drawing step determined that there are hamsters on the wheel at this fragment,
// the given wheel_rotation determines how far they have rotated it and how it should therefore be drawn.
vec3 draw_wheels(vec2 coords, vec3 cur_col, float wheel_rotation)
{	
	// Only draw wheel if the tile is the center of the jitter group
	coords = jitter_grouped(coords);
	ivec2 idx = ivec2(coords);
	if (idx.x % jitter_bounds == jitter_center && idx.y % jitter_bounds == jitter_center)
	{		
		vec2 uv = fract(coords);
		
		// Main rotation induced by the hamsters
		vec2 rotated_uv = rotate_around_center(uv, wheel_rotation);
		
		// Still give all wheels a small global rotation to make them look more random
		uv = rotate_around_center(uv, (hash_vec2_float(vec2(idx), seed) - 0.5) * 0.25);
		
		vec4 wheel = sample_wheel(uv, rotated_uv, cur_col);
		return mask_aa(cur_col, wheel.rgb, wheel.a);
	}

	return cur_col;
}

// Samples the procedural SDF hamster texture based on the given position 
// around the hamster center (0,0).
// The given color_offset is used to add variety to the appearances of different hamsters.
vec4 sample_hamster(vec2 pos, vec3 color_offset)
{
	vec4 value = TRANSPARENT;
	float alpha = 0.0;
	vec3 hamster_col = HAMSTER_COL_BASE + color_offset;
	
	// EARS
	float ear_size = HAMSTER_SIZE * 0.4;
	vec2 ear_A_offset = vec2(0.6, 0.9) * HAMSTER_SIZE;
	vec2 ear_B_offset = vec2(-0.6, 0.9) * HAMSTER_SIZE;
	float ear_A = -sd_circle(pos + ear_A_offset, ear_size);
	float ear_B = -sd_circle(pos + ear_B_offset, ear_size);
	
	alpha = sdf_union(vec2(ear_A, ear_B));
	value = mask_aa(value, vec4(hamster_col, 1.0), alpha);
	
	float inner_ear_size = HAMSTER_SIZE * 0.25;
	float inner_ear_A = -sd_circle(pos + ear_A_offset, inner_ear_size);
	float inner_ear_B = -sd_circle(pos + ear_B_offset, inner_ear_size);
	
	alpha = sdf_union(vec2(inner_ear_A, inner_ear_B));
	value = mask_aa(value, vec4(HAMSTER_SKIN_COL, 1.0), alpha);
	
	// BODY
	float head = -sd_circle(pos, HAMSTER_SIZE);
	float head_white = -sd_circle(pos + vec2(0.0, -0.5) * HAMSTER_SIZE, HAMSTER_SIZE * 0.7);
	
	alpha = head;
	value = mask_aa(value, vec4(hamster_col, 1.0), alpha);
	
	alpha = min(head_white, head);
	value = mask_aa(value, vec4(1.0), alpha);
	
	// FACE
	float eye_size = HAMSTER_SIZE * 0.22;
	float eye_A = -sd_circle(pos + vec2(0.4, 0.2) * HAMSTER_SIZE, eye_size);
	float eye_B = -sd_circle(pos + vec2(-0.4, 0.2) * HAMSTER_SIZE, eye_size);
	float mouth = -sd_circle(pos + vec2(0.0, -0.5) * HAMSTER_SIZE, HAMSTER_SIZE * 0.1);
	
	alpha = sdf_union(vec3(mouth, eye_A, eye_B));
	value = mask_aa(value, vec4(vec3(0.0), 1.0), alpha);
	
	float sparkle_size = HAMSTER_SIZE * 0.075;
	float eye_sparkle_A = -sd_circle(pos + vec2(0.32, 0.28) * HAMSTER_SIZE, sparkle_size);
	float eye_sparkle_B = -sd_circle(pos + vec2(-0.32, 0.28) * HAMSTER_SIZE, sparkle_size);
	
	alpha = sdf_union(vec2(eye_sparkle_A, eye_sparkle_B));
	value = mask_aa(value, vec4(1.0), alpha);
	
	float nose = -sd_circle(pos, HAMSTER_SIZE * 0.25);
	
	alpha = nose;
	value = mask_aa(value, vec4(HAMSTER_NOSE_COL, 1.0), alpha);
	
	return value;
}

// Chooses a pseudo-random wandering goal based on the given hamster position
// and the point in time t.
// Has a chance of choosing a specific wheel instead of a random coordinate
// as the goal.
// Returns: vec3(goal.x, goal.y, is_wheel)
vec3 get_goal(vec2 hamster_pos, float t)
{
	t = t == 0.0 ? 0.1 : t; // If t were allowed to be 0, all hamsters would start with the same goal	
	vec2 hash = hash_vec2_vec2(hamster_pos * t, seed) * size;

	if (fract(hash.x) < wheel_desire)
	{
		// Inverse jitter_grouped() to get the coordinate of the wheel in the jitter group
		// that the hash falls into
		vec2 jitter_seed = floor(hash / float(jitter_bounds));
		vec2 center = jitter_seed * float(jitter_bounds) + vec2(1.0);
		vec2 goal = jitter(center, jitter_seed, seed, -jitter_intensity); // Inverse jitter
		return vec3(goal + wheel_center_to_bottom, 1.0);
	}
	
	return vec3(hash, 0.0);
}

float walkNoise(float t)
{
	float t_int = floor(t);
	float t_fract = fract(t);
	float a = hash_seedless(t_int);
	float b = hash_seedless(t_int+1.0);
	return mix(a, b, smoothstep(0.0, 1.0, t_fract));
}

// Speeds up until 0.25 then slows down again
float get_wheel_rotation(float t, vec2 idx)
{
	float individualizer = floor((hash_vec2_float(idx, seed) + 0.1) * 10.0); // Whole number to ensure multiple of 2PI
	return 1.0 / (1.0 + exp(-(t*20.0 - 5.0))) * individualizer * 6.325; // 6.325to ensure integral from 0.0 to 0.5 is 2PI
}

// Draws hamsters onto the current color at the given grid coordinates.
vec3 draw_hamsters(vec2 coords, vec3 cur_col, inout float wheel_rotation)
{
	const int cycles = 7;
	const float full_cycle = 60.0;
	const float cycle_lengths[cycles] = {/*1.0, 2.0, 3.0, 4.0, 5.0,*/ 6.0, 10.0, 12.0, 15.0, 20.0, 30.0, 60.0};

	for (uint i = 0u; i < hamster_count; i++)
	{
		float idx = float(i);

		// Every 60 t, the cycle lengths of all of them change
		// This is because 60 has 12 divisors, allowing for these cycle lengths
		float last_switch = floor(time / full_cycle);
		float tt = cycle_lengths[int(hash_vec2_float(vec2(idx + last_switch), seed) * 100.0) % cycles];
		float phase = fract(time / tt);
		float t0 = floor(time / tt) * tt;
		float t1 = t0 + tt;
		
		float st = time + 10.0 * hash_seedless(idx);
		vec2 shift = vec2(walkNoise(st), walkNoise(st+17.0)) * (1.0 - abs(0.5 - phase) * 2.0) * 10.0; // Scale intensity so that at beginning and end it is at goal pos
		vec2 cur_hamster = hash_vec2_vec2(vec2(idx), seed);
		vec3 last_goal = get_goal(cur_hamster, t0);
		vec3 cur_goal = get_goal(cur_hamster, t1);
		cur_hamster = last_goal.xy - (last_goal.xy - cur_goal.xy) * phase + shift;

		bool b = false;

		vec2 jit = jitter_grouped(last_goal.xy);
		ivec2 wheel_idx = ivec2(jit);
		
		float cur_wheel_rotation;
		
		vec2 bobbing_offset = vec2(0.0, sin(time * bobbing_speed * 20.0/tt + 1.0/(idx+1.0)) * HAMSTER_SIZE * 0.1);
				// Only goals that were explicitly forced to be the wheel should be counted, otherwise position assumptions may be off
		if (last_goal.z == 1.0)
		{
			vec2 floor_offset = -vec2(0.0, 0.7) * HAMSTER_SIZE;
			vec2 center = last_goal.xy - wheel_center_to_bottom;
			if (phase < 0.5) 
			{
				cur_hamster = last_goal.xy; b = true;
	
				
				float t = (time - t0) / tt; // Start rotation at bottom of the wheel
				cur_wheel_rotation = get_wheel_rotation(t, vec2(wheel_idx));
				
				bobbing_offset = vec2(0.0, sin(time * cur_wheel_rotation * bobbing_speed * 0.005) * HAMSTER_SIZE * 0.2);
				
				
				if (ivec2(coords/float(jitter_bounds)) == ivec2(last_goal.xy / float(jitter_bounds)))
				{
					wheel_rotation += cur_wheel_rotation;	
				}
				
				if (round(hash_seedless(idx)) * phase > 0.25)
				{
					// These ones tumble around instead
					cur_hamster = rotate_around_center(cur_hamster - center + floor_offset, - max(wheel_rotation, cur_wheel_rotation)) + center;
				}
				else
				{
					cur_hamster = rotate_around_center(cur_hamster - center + floor_offset + bobbing_offset, sin(time * cur_wheel_rotation * 0.001 + 5.0/(idx+1.0))) + center;
				}
			}
			else 
			{

				cur_hamster = last_goal.xy - ((last_goal.xy - cur_goal.xy) + shift) * (phase-0.5)*2.0 ;
			}
		}

		if (!b) { cur_hamster += bobbing_offset; }
		vec2 dif = coords - cur_hamster;
		float d = length(dif);
		if (d < HAMSTER_SIZE * 1.5)
		{
			vec3 hamster_col_offset = vec3(0.7, 0.7, 0.0) * (hash_seedless(idx) - 0.5);

			vec2 hamster_centered = coords - cur_hamster;
			if (b) { hamster_centered = rotate_around_origin(hamster_centered, -sin(time * cur_wheel_rotation * 0.001) * 0.5); }
			vec4 hamster = sample_hamster(hamster_centered, hamster_col_offset);
			cur_col = mix(cur_col, hamster.rgb, hamster.a);
			// Do not return early, overlap is possible
		}
	}
	return cur_col;
}

void fragment()
{
	vec2 coords = UV * size;
	float wheel_rotation = 0.0; // How far the wheel at this frag has been rotated by hamsters
	
	// First, the background is drawn. Then the hamsters are drawn and the cumulative wheel rotation
	// at the wheel of the current fragment (if it contains a wheel at all) is set.
	// Finally, the wheels are drawn based on this information, part of them behind and part of them
	// in front of the hamsters (using the current color compared to the background color as a mask).
	COLOR.rgb = BACKGROUND_COL;
	COLOR.rgb = draw_hamsters(coords, COLOR.rgb, wheel_rotation);
	COLOR.rgb = draw_wheels(coords, COLOR.rgb, wheel_rotation);	
}