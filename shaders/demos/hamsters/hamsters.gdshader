shader_type canvas_item;
#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"

group_uniforms general;
uniform float time = 0.0;
uniform float size = 12.0;
uniform int seed = 1;

group_uniforms wheels;
uniform float jitter_intensity: hint_range(0.0, 2.0) = 2.0;
uniform float inner_wheel_size = 0.3;
uniform float outer_wheel_size = 0.45;

group_uniforms hamsters;
uniform uint hamster_count = 1;
uniform float hamster_size = 0.2;

group_uniforms colors;
uniform vec3 background_col: source_color = vec3(0.4, 0.8, 0.4);

// Define jitter groups within which all tiles are jittered identically
const int jitter_bounds = 3;
const int center_idx = 1;

// Samples the procedural SDF wheel texture based on the given UV.
vec4 sample_wheel(vec2 uv)
{
	uv -= vec2(0.5);
	vec4 value = vec4(1.0, 1.0, 1.0, 0.0);

	float outer = length(uv) - outer_wheel_size;
	float inner = length(uv) - inner_wheel_size;
	float alpha = -max(outer, -inner);

	float aa = fwidth(alpha);
	vec4 circ = vec4(1.0);
	circ.rgb = mix(circ.rgb, vec3(1.0, 0.0, 0.0), smoothstep(0.0, aa, max(uv.x, 0.0)));

	value = mix(value, circ, smoothstep(0.0, aa, alpha));
	return value;
}

vec2 get_jittered_wheel_coords(vec2 coords)
{
	//float sin_jitter = 1.7 + sin(time) * 0.3;
	vec2 jitter_seed = floor(coords  / float(jitter_bounds));
	return jitter(coords, jitter_seed, seed, jitter_intensity);
}

// Draws wheels onto the current color at the given pre-jittered grid coordinates.
vec3 draw_wheels(vec2 coords, vec3 cur_color)
{
	// Only draw wheel if the tile is the center of the jitter group
	coords = get_jittered_wheel_coords(coords);
	ivec2 idx = ivec2(coords);
	if (idx.x % jitter_bounds == center_idx && idx.y % jitter_bounds == center_idx)
	{
		vec2 uv = fract(coords);
		uv = rotate_around_center(uv, hash_vec2_float(vec2(idx), seed) * time);
		vec4 wheel = sample_wheel(uv);
		return mix(cur_color, wheel.rgb, wheel.a);
	}

	return cur_color;
}

// Samples the procedural SDF hamster texture based on the given UV.
vec4 sample_hamster(vec2 uv, vec3 color)
{
	// Origin already at hamster center
	vec4 value = vec4(1.0, 1.0, 1.0, 0.0);

	float alpha = -(length(uv) - hamster_size);

	float aa = fwidth(alpha);
	vec4 circ = vec4(color, 1.0);

	value = mix(value, circ, smoothstep(0.0, aa, alpha));
	return value;
}

vec2 get_goal(vec2 cur_hamster, float t)
{
	vec2 hash = hash_vec2_vec2(cur_hamster * t, seed) * size;

	// 50% chance for the goal to be a wheel
	if (fract(hash.x) < 0.5)
	{
		vec2 jitter_seed = floor(hash / float(jitter_bounds));
		vec2 goal = floor(hash / float(jitter_bounds)) * float(jitter_bounds) + vec2(1.0);
		goal = jitter(goal, jitter_seed, seed, -jitter_intensity); // Inverse jitter
		return goal;
	}

	return hash;
}

// Draws hamsters onto the current color at the given grid coordinates.
vec3 draw_hamsters(vec2 coords, vec3 cur_color)
{
	const int cycles = 6;
	const float cycle_lengths[cycles] = {1.0, 2.0, 3.0, 4.0, 6.0, 12.0};

	//vec2 shift = vec2(sin(time * 5.0), cos(time * 2.5));
	vec2 shift = vec2(sin(time * 7.0), cos(time * 5.0)) * 0.2;

	for (uint i = 0u; i < hamster_count; i++)
	{
		float idx = float(i);

		// Every 12 seconds, the cycle lengths of all of them change
		// This is because 12 has 6 divisors, allowing for these cycle lengths
		float last_switch = floor(time / 12.0);
		float tt = cycle_lengths[int(hash_vec2_float(vec2(idx + last_switch), seed) * 100.0) % cycles];
		float phase = fract(time / tt);
		float t0 = floor(time / tt) * tt;
		float t1 = t0 + tt;

		vec2 cur_hamster = hash_vec2_vec2(vec2(idx), seed);
		vec2 last_goal = get_goal(cur_hamster, t0);
		vec2 cur_goal = get_goal(cur_hamster, t1);
		cur_hamster = last_goal - (last_goal - cur_goal) * phase + shift;

		bool b = false;

		vec2 jit = get_jittered_wheel_coords(last_goal);
		ivec2 wheel_idx = ivec2(jit);
		if (wheel_idx.x % jitter_bounds == center_idx && wheel_idx.y % jitter_bounds == center_idx)
		{
			if (phase < 0.5) {cur_hamster = last_goal; b = true;}
			else {cur_hamster = last_goal - (last_goal - cur_goal) * (phase-0.5)*2.0 + shift;}
		}

		float d = length(coords - cur_hamster);
		if (d < hamster_size + 0.1)
		{
			vec3 hamster_col;
			switch (int(tt))
				{
					case 1: hamster_col = vec3(1.0, 0.0, 0.0); break;
					case 2: hamster_col = vec3(0.0, 1.0, 0.0); break;
					case 3: hamster_col = vec3(0.0, 0.0, 1.0); break;
					case 4: hamster_col = vec3(1.0, 0.0, 1.0); break;
					case 6: hamster_col = vec3(0.0, 1.0, 1.0); break;
					case 8: hamster_col = vec3(1.0, 1.0, 0.0); break;
					case 12: hamster_col = vec3(1.0, 1.0, 1.0); break;

				}
			if (b) {hamster_col = vec3(0.0, 0.0, 0.0);}

			vec4 hamster = sample_hamster(coords - cur_hamster, hamster_col);
			cur_color = mix(cur_color, hamster.rgb, hamster.a);
			// Do not return early, overlap is possible
		}
	}
	return cur_color;
}

void fragment()
{
	vec2 grid_coords = UV * size;

	COLOR.rgb = background_col;
	COLOR.rgb = draw_wheels(grid_coords, COLOR.rgb);
	COLOR.rgb = draw_hamsters(grid_coords, COLOR.rgb);
}