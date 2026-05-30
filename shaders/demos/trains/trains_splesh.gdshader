shader_type canvas_item;

#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"
#include "res://shaders/util/debug.gdshaderinc"

const vec3 BACKGROUND_COL = vec3(0.2, 0.2, 0.2);
const vec3 RED = vec3(1.0, 0.2, 0.2);
const vec3 GREEN = vec3(0.2, 1.0, 0.2);
const vec3 BLUE = vec3(0.2, 0.2, 1.0);
const vec3 YELLOW = vec3(1.0, 1.0, 0.2);
const vec3[4] colors = {RED, GREEN, BLUE, YELLOW};

uniform float time = 0.0;
uniform int seed = 1u;
uniform uint num_quads;

uniform float max_id : hint_range(0.0, 10.0, 1.0) = 1;
uniform int x = 0;
uniform int y = 0;

varying flat float quad_id;
varying vec2 v;

vec2 tr_background(vec2 input) { return input / 11.1; }

void vertex()
{
	quad_id = floor(float(VERTEX_ID) / 4.0);
	
	VERTEX -= vec2(0.5);
	VERTEX += tr_background(vec2(0.5, 0.5)); // Now aligned with top left joint
	
	VERTEX += tr_background(vec2(float(x), float(y)));

}

void fragment() 
{
	COLOR.rgb = BACKGROUND_COL;
	
	vec3 foreground = colors[int(quad_id) % 4];
	float circle = -sd_circle(UV - vec2(0.5), 0.01);
	COLOR.rgb = mask_aa(COLOR.rgb, foreground, circle);
	COLOR.a = mask_aa(0.0, 1.0, circle);
	
	if (quad_id > max_id) { COLOR.a = 0.0; }
}
