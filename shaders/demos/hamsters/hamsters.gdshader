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
const float HAMSTER_LEAVES_WHEEL_T = 0.5; // What fraction of their walk interval do hamsters spend on the wheel
const float HAMSTER_SIZE = 0.13;
const float HAMSTER_DRAW_RADIUS = HAMSTER_SIZE * 1.5;
const int HAMSTER_CYCLES_COUNT = 7; // Number of possible cycle lengths for a hamster (walk from one goal to the next)
const float MAX_HAMSTER_CYCLE = 60.0; // The other cycles are divisors => Know time when all hamsters are starting new cycle
const float HAMSTER_CYCLE_LENGTHS[HAMSTER_CYCLES_COUNT] = {6.0, 10.0, 12.0, 15.0, 20.0, 30.0, 60.0};
uniform uint hamster_count = 30;
uniform float bobbing_speed = 20.0;
uniform float bobbing_strength = 0.1;
uniform float walk_noisiness = 10.0;
uniform float wheel_desire: hint_range(0.0, 1.0) = 0.75; // Chance to choose a wheel as the next goal

// Struct defining attributes of a hamster to more easily pass between functions.
struct hamster
{
	float idx;
	float cycle_length; // Just the current cycle
	float phase; // Phase in the current goal cycle
	float wheel_rotation; // How much has this specific hamster rotated its wheel
	vec2 coords;
	bool on_wheel;
	
	// The third row of the goal vec3 indicates whether the goal is a wheel
	vec3 last_goal;
	vec3 cur_goal;
};

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
	alpha = mask_aa(alpha, 0.0, round(hamster_mask));

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
	coords = jitter_grouped(coords, float(jitter_bounds), jitter_intensity, seed);
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

// Returns the current cycle length of the hamster defined by the given idx.
// The point of having different cycle lengths is so that it does not look like all
// hamsters are starting to run or getting off their wheels at the same time.
float get_cycle_length(float hamster_idx)
{
	// Hamsters keep their cycle lengths for one MAX_HAMSTER_CYCLE. This is because,
	// to generate a consistent hash that indexes into the cycle lengths array, a specific interval would need
	// to be chosen. By the end of this interval, all hamsters would need to have completed their current cycle
	// to avoid snapping to new positions. Since all cycle lengths divide MAX_HAMSTER_CYCLE, it fits that role.
	float last_switch = floor(time / MAX_HAMSTER_CYCLE);
	return HAMSTER_CYCLE_LENGTHS[int(hash(hamster_idx + last_switch, seed) * float(HAMSTER_CYCLES_COUNT))];
}

// Returns a smoothed noise offset for the hamster's walk.
// X and Y coordinate should use different noise seeds for more organic noise.
float walk_noise(float noise_seed)
{
	float t = time * hash(noise_seed, seed);
	float t_int = floor(t);
	float t_fract = fract(t);
	float a = hash(t_int, seed);
	float b = hash(t_int+1.0, seed);
	return mix(a, b, smoothstep(0.0, 1.0, t_fract));
}

// Returns the shift to apply to the walk of the hamster belonging to the given idx
// based on the given cycle phase.
vec2 get_walk_shift(float hamster_idx, float phase)
{
	vec2 noise = vec2(walk_noise(hamster_idx) - 0.5, walk_noise(hamster_idx+17.0) - 0.5);
	float phase_scale = (1.0 - abs(0.5 - phase) * 2.0); // Scale intensity so that at beginning and end it is at goal pos
	return noise * walk_noisiness * phase_scale; 
}

// Returns how far the wheel of the given idx is rotated by a single hamster for a time t.
// Uses a function that speeds up from 0.0 and slows down until HAMSTER_LEAVES_WHEEL_T in a way that ensures 
// t=HAMSTER_LEAVES_WHEEL_T returns a multiple of 2PI so that the wheel is back in its default position when the hamster
// leaves it.
float get_wheel_rotation(float t, vec2 wheel_idx)
{
	float f = 1.0 / (1.0 + exp(-(t*30.0 - 7.5))) * 6.29; // 6.29 to ensure HAMSTER_LEAVES_WHEEL_T returns 2PI
	float individualizer = floor((hash_vec2_float(wheel_idx, seed) + 0.1) * 10.0); // Whole number to ensure multiple of 2PI
	return f * individualizer; // This is why 0.1 is always added to the individualizer hash. Do not want wheels to get stuck.
}

// Updates the given hamster struct to be animated as running on a wheel.
// Therefore, it assumes on_wheel and the corresponding attributes are set
// so it can deduce the wheel coordinate and state properly.
void animate_hamster_on_wheel(inout hamster h, float cumulative_wheel_rotation)
{
	h.coords = h.last_goal.xy; // Snap to the wheel
	ivec2 wheel_idx = ivec2(jitter_grouped(h.coords, float(jitter_bounds), jitter_intensity, seed));
	h.wheel_rotation = get_wheel_rotation(h.phase, vec2(wheel_idx));
	float rotation = cumulative_wheel_rotation + h.wheel_rotation; // Real accumulation done in draw_hamsters()
	
	// Move the hamster up onto the inner radius of the wheel
	vec2 floor_offset = -vec2(0.0, 0.7) * HAMSTER_SIZE; 
	h.coords += floor_offset;
	
	// Temporarily recenter for wheel rotation
	vec2 center = h.last_goal.xy - wheel_center_to_bottom; // Bottom of wheel is goal -> remove offset to get center
	h.coords -= center;
	
	// Random chance to eventually start tumbling around the wheel, but only if the wheel is spun far enough
	if (rotation > 4.0*PI && round(hash(h.idx, seed)) * h.phase > 0.2)
	{
		// These ones tumble around / get flung around the wheel
		h.coords = rotate_around_center(h.coords, -rotation);
	}
	else
	{
		// These rotate around a bit while still running along with the wheel
		// (Use wheel rotation here to make the hamster bob faster when it is "running faster")
		vec2 bobbing_offset = vec2(0.0, sin(time * h.wheel_rotation * bobbing_speed * 0.001) * HAMSTER_SIZE * bobbing_strength);
		h.coords = rotate_around_center(h.coords + bobbing_offset, sin(time * rotation * 0.001 * 5.0/(h.idx+1.0)));
	}
	
	h.coords += center; // Move back after rotation around center is done
}

// Constructs the base attributes of the hamster defined by the given index
// based on the current uniform values.
hamster construct_hamster(uint index)
{
	hamster h;
	h.idx = float(index);
	h.coords = hash_vec2_vec2(vec2(h.idx), seed);
	h.on_wheel = false;
	h.wheel_rotation = 0.0;
	
	h.cycle_length = get_cycle_length(h.idx);
	float t_div_l = time / h.cycle_length; 
	h.phase = fract(t_div_l);
	float t0 = floor(t_div_l) * h.cycle_length;
	float t1 = t0 + h.cycle_length;
	h.last_goal = get_goal(h.coords, t0);
	h.cur_goal = get_goal(h.coords, t1);
	
	return h;
}

// Draws hamsters onto the current color at the given grid coordinates.
// Writes to the given wheel_rotation variable to define how far hamsters
// have moved a wheel on the given coordinates (if such a wheel exists).
vec3 draw_hamsters(vec2 coords, vec3 cur_col, inout float wheel_rotation)
{
	for (uint i = 0u; i < hamster_count; i++)
	{
		hamster h = construct_hamster(i);
		vec2 shift = get_walk_shift(h.idx, h.phase);
		vec2 path_vector = ((h.last_goal.xy - h.cur_goal.xy) + shift);
		h.coords = h.last_goal.xy - path_vector * h.phase;
		
		// The hamster can be on a wheel only if it arrived at one at its last goal.
		// Only count goals if they were explicitly forced to be wheel coords (i.e. z == 1.0).
		// Otherwise position assumptions may be off.
		if (h.last_goal.z == 1.0)
		{
			// Half of the phase is used to animate the hamster on the wheel.
			// Then it will run off to the next goal at double speed => Allows for "staying"
			// at a wheel while still following the analytic/stateless goal cycle method.
			h.on_wheel = h.phase < 0.5;
			if (h.on_wheel) 
			{
				animate_hamster_on_wheel(h, wheel_rotation);
				if (ivec2(coords / float(jitter_bounds)) == ivec2(h.last_goal.xy / float(jitter_bounds)))
				{
					// Only update the cumulative wheel rotation if this hamster is actually on the same
					// wheel as this fragment.
					wheel_rotation += h.wheel_rotation;	
				}
			}
			else { h.coords = h.last_goal.xy - path_vector * (h.phase - 0.5) * 2.0; }
		}

		// Roaming hamsters bob up and down while walking corresponding to their speed
		// and a random offset so that multiple hamsters do not appear synced.
		if (!h.on_wheel) 
		{ 
			float speed = bobbing_speed * MAX_HAMSTER_CYCLE/h.cycle_length;
			float desync_offset = 1.0/(h.idx+1.0);
			h.coords += vec2(0.0, sin(time * speed + desync_offset) * HAMSTER_SIZE * bobbing_strength); 
		}
		
		// Recenter coordinates around hamster to see wether this fragment lies on it
		// and to apply transformations like local rotation that cannot be performed on the hamster
		// struct alone.
		vec2 hamster_centered = coords - h.coords;
		if (length(coords - h.coords) < HAMSTER_DRAW_RADIUS)
		{
			if (h.on_wheel) 
			{ 
				float local_rotation = -sin(h.phase * wheel_rotation) * 0.3;
				hamster_centered = rotate_around_origin(hamster_centered, local_rotation); 
			}
			vec3 hamster_col_offset = vec3(0.7, 0.7, 0.0) * (hash(h.idx, seed) - 0.5);
			vec4 hamster = sample_hamster(hamster_centered, hamster_col_offset);
			cur_col = mix(cur_col, hamster.rgb, hamster.a); // No early return here, hamsters may overlap
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
	COLOR.rgb = draw_hamsters(coords, COLOR.rgb, wheel_rotation); // Writes to wheel_rotation
	COLOR.rgb = draw_wheels(coords, COLOR.rgb, wheel_rotation);	
}