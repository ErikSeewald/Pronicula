shader_type canvas_item;

#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"

const vec3 BACKGROUND_COL = vec3(0.2, 0.2, 0.2);
const vec3 RED = vec3(1.0, 0.2, 0.2);
const vec3 GREEN = vec3(0.2, 1.0, 0.2);
const vec3 BLUE = vec3(0.2, 0.2, 1.0);
const vec3 YELLOW = vec3(1.0, 1.0, 0.2);
const vec3[4] colors = {RED, GREEN, BLUE, YELLOW};

uniform float time = 0.0;
uniform int seed = 1u;
uniform uint num_quads;

varying float quad_id;

void vertex()
{
	quad_id = floor(float(VERTEX_ID) / 4.0);
	
	float side = floor(sqrt(float(num_quads)));
	float y = floor(quad_id / side);
	float x = quad_id - y * side;
	VERTEX.x += x * 0.3;
	VERTEX.y += y * 0.3;
	
	float modid = mod(quad_id, 10000);
	VERTEX += (hash_vec2_vec2(vec2(modid), seed) - vec2(0.5)) * time;
}

void fragment()
{
	COLOR.rgb = BACKGROUND_COL;
	
	vec3 foreground = colors[int(quad_id) % 4];
	float circle = -sd_circle(UV - vec2(0.5), 0.2);
	COLOR.rgb = mask_aa(COLOR.rgb, foreground, circle);
	COLOR.a = mask_aa(0.0, 1.0, circle);
}