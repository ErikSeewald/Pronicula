// Some arbitrary seeding offsets and numbers.
const float ARBITRARY_FACTOR = 43758.5453123;
const float ARBITRARY_OFFSET = 19.17;
const vec2 ARBITRARY_VEC2_A = vec2(123.4, 567.8);
const vec2 ARBITRARY_VEC2_B = vec2(987.6, 543.2);

// Basic seedless hash function that is mostly used to transform seed_int
// into seed_float. By Patricio Gonzalez Vivo (Public Domain).
float hash_seedless(float n)
{
    return fract(sin(n) * ARBITRARY_FACTOR);
}

// Hashes the given float based on the given seed.
float hash(float n, int seed)
{
	return fract(sin(n) * ARBITRARY_FACTOR * hash_seedless(float(seed)));
}

// Hash function (vec2 to float) derived from Inigo Quilez's hash functions.
// Uses the given seed for pseudo-randomness.
float hash_vec2_float(vec2 p, int seed)
{
	// Apply seed
	float seed_float = hash_seedless(float(seed));
    vec2 seed_vec = vec2(seed_float, seed_float + ARBITRARY_OFFSET);
    p += seed_vec;

    float projection1 = dot(p, ARBITRARY_VEC2_A);
    float projection2 = dot(p, ARBITRARY_VEC2_B);
    float h = sin(projection1) + sin(projection2);
	
    return fract(h * ARBITRARY_FACTOR);
}

// Hashes the given vec2 to another vec2 based on the given seed.
// Both values of the hashed vector are in the range [0.0, 1.0)
vec2 hash_vec2_vec2(vec2 p, int seed)
{
    return vec2(hash_vec2_float(p, seed), hash_vec2_float(p + ARBITRARY_OFFSET, seed));
}

// Jitters the given vector randomly based on the given
// - seed_vec: Used to hash vec2 -> vec2
// - base_seed: Base seed to use for pseudo-randomness
// - intensity: Strength of the jitter
vec2 jitter(vec2 to_jitter, vec2 seed_vec, int base_seed, float intensity)
{
	const vec2 middle_shift = vec2(0.5, 0.5);
	vec2 offset = hash_vec2_vec2(seed_vec, base_seed) - middle_shift;
	return to_jitter + offset * intensity;
}

// Jitters the given coordinates with a jitter seed derived from
// the jitter group they fall into.
// - jitter_bounds defines the size of a single group
// - jitter_intensity affects how strongly the coordinates are jittered within the group
// - base_seed is used as the basis of rng and combined with the jitter seed
// As a result, all coordinates within the same group are jittered the same.
vec2 jitter_grouped(vec2 coords, float jitter_bounds, float jitter_intensity, int base_seed)
{
	vec2 jitter_seed = floor(coords  / float(jitter_bounds));
	return jitter(coords, jitter_seed, base_seed, jitter_intensity);
}
