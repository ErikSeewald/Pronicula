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

varying float quad_id;

uniform float time = 0.0;
uniform uint num_quads;

void vertex()
{
	quad_id = floor(float(VERTEX_ID) / 4.0);
	
	float side = floor(sqrt(float(num_quads)));

	float y = floor(quad_id / side);
	float x = quad_id - y*side;

	VERTEX.x += x * 0.4;
	VERTEX.y += y * 0.4;
	
	
	float modid = mod(quad_id, 50000);
	VERTEX += (hash_vec2_vec2(vec2(modid, 1.0 - modid), 1) - vec2(0.5))  * time;
}

void fragment()
{
	COLOR.rgb = BACKGROUND_COL;
	
	int i = int(quad_id);
	vec3 foreground = colors[i % 4];
	COLOR.rgb = mask_aa(COLOR.rgb, foreground, -sd_circle(UV - vec2(0.5), 0.2));
	COLOR.a = mask_aa(0.0, 1.0, -sd_circle(UV - vec2(0.5), 0.2));
}