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

// Returns the signed distance of p to a bezier curve defined by
// A(from), B(control), and C(to).
// https://iquilezles.org/articles/distfunctions2d/
float sd_bezier( in vec2 pos, in vec2 A, in vec2 B, in vec2 C )
{    
    vec2 a = B - A;
    vec2 b = A - 2.0*B + C;
    vec2 c = a * 2.0;
    vec2 d = A - pos;
    float kk = 1.0 / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0*dot(a, a)+dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);      
    float res = 0.0;
    float p = ky - kx*kx;
    float p3 = p*p*p;
    float q = kx*(2.0*kx*kx-3.0*ky) + kz;
    float h = q*q + 4.0*p3;
    if( h >= 0.0) 
    { 
        h = sqrt(h);
        vec2 x = (vec2(h, -h)-q)/2.0;
        vec2 uv = sign(x)*pow(abs(x), vec2(1.0 / 3.0));
        float t = clamp( uv.x+uv.y-kx, 0.0, 1.0 );
		vec2 v = d + (c + b*t)*t;
        res = dot(v, v);
    }
    else
    {
        float z = sqrt(-p);
        float v = acos( q/(p*z*2.0) ) / 3.0;
        float m = cos(v);
        float n = sin(v)*1.732050808;
        vec3  t = clamp(vec3(m+m, -n-m, n-m)*z-kx, 0.0, 1.0);
		vec2 v1 = d+(c+b*t.x)*t.x;
		vec2 v2 = d+(c+b*t.y)*t.y;
        res = min( dot(v1, v1),
                   dot(v2, v2) );
    }
    return sqrt( res );
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