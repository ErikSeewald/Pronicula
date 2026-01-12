// Samples a given texture (usually padded to maintain pow2 dimensions)
// as if only the non-padded regions (real_size) exist.
vec4 padded_texture(sampler2D tex, vec2 uv, float real_size)
{
	vec2 real_uv = uv * real_size / float(textureSize(tex, 0).x);
	return texture(tex, real_uv);
}

// Returns the pixel coordinate of the given UV on the given texture.
// Assumes width and height of the texture are the same.
ivec2 pixel_coord(sampler2D tex, vec2 uv)
{
	return ivec2((uv * float(textureSize(tex, 0).x)));
}

/// Rotates the given UV around its center based on the given radians
vec2 rotate_around_center(vec2 uv, float rad)
{
	float s = sin(rad);
	float c = cos(rad);
	mat2 rot = mat2(vec2(c, s), vec2(-s, c));

	uv -= 0.5;	
	uv = rot * uv;
	uv += 0.5;
	return uv;
}
