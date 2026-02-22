// Masks b over a based on alpha with anti-aliasing.
// alpha > ~0.0 => Overwrites a with b
float mask_aa(float a, float b, float alpha)
{
	float aa = fwidth(alpha);
	return mix(a, b, smoothstep(0.0, aa, alpha));
}

// Masks b over a based on alpha with anti-aliasing.
// alpha > ~0.0 => Overwrites a with b
vec2 mask_aa(vec2 a, vec2 b, float alpha)
{
	float aa = fwidth(alpha);
	return mix(a, b, smoothstep(0.0, aa, alpha));
}

// Masks b over a based on alpha with anti-aliasing.
// alpha > ~0.0 => Overwrites a with b
vec3 mask_aa(vec3 a, vec3 b, float alpha)
{
	float aa = fwidth(alpha);
	return mix(a, b, smoothstep(0.0, aa, alpha));
}

// Masks b over a based on alpha with anti-aliasing.
// alpha > ~0.0 => Overwrites a with b
vec4 mask_aa(vec4 a, vec4 b, float alpha)
{
	float aa = fwidth(alpha);
	return mix(a, b, smoothstep(0.0, aa, alpha));
}

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

/// Rotates the given vec around the origin based on the given radians
vec2 rotate_around_origin(vec2 v, float rad)
{
	float s = sin(rad);
	float c = cos(rad);
	mat2 rot = mat2(vec2(c, s), vec2(-s, c));

	v = rot * v;
	return v;
}

/// Rotates the given UV around its center based on the given radians
vec2 rotate_around_center(vec2 uv, float rad)
{
	uv -= 0.5;	
	uv = rotate_around_origin(uv, rad);
	uv += 0.5;
	return uv;
}