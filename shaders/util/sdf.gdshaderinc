// Returns the signed distance of p to a wheel defined by the outer and
// inner radius.
float sd_wheel(vec2 p, float outer_r, float inner_r)
{
	float outer = length(p) - outer_r;
	float inner = length(p) - inner_r;
	return max(outer, -inner);
}

// Returns the signed distance of p to a circle defined by the given radius.
float sd_circle(vec2 p, float r)
{
	return length(p) - r;
}

// Returns the signed distance of p to an oriented box.
// The box is defined by the edge a-b and the height h.
// https://iquilezles.org/articles/distfunctions2d/
float sd_oriented_box(vec2 p, vec2 a, vec2 b, float h)
{
	float l = length(b - a);
	vec2 d = (b - a) / l;
	vec2 q = (p - (a + b) * 0.5);
	q = mat2(vec2(d.x, -d.y), vec2(d.y,  d.x)) * q;
	q = abs(q) - vec2(l, h)*0.5;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Returns the union of the SDFs in the rows of the given vector.
float sdf_union(vec2 sdfs)
{
	return max(sdfs.x, sdfs.y);
}

// Returns the union of the SDFs in the rows of the given vector.
float sdf_union(vec3 sdfs)
{
	return max(sdfs.x, max(sdfs.y, sdfs.z));
}

// Returns the union of the SDFs in the rows of the given vector.
float sdf_union(vec4 sdfs)
{
	return max(sdfs.x, max(max(sdfs.y, sdfs.z), sdfs.w));
}