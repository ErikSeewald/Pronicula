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
global uniform int global_seed;
uniform uint num_quads;

global uniform float global_size;
uniform float circ_size = 0.01;

global uniform float global_jitter_intensity; // Anything beyond that range clips jitter bounds
const int jitter_bounds = 9; // All cells within this group (width/height defined as number of cells) jitter identically
const int jitter_center = 4; // The in-jitter-group index of the cell that acts as a track joint

uniform float max_id : hint_range(0.0, 10.0, 1.0) = 1;
uniform int x_offset = 0;
uniform int y_offset = 0;

varying flat float quad_id;
varying vec2 v;

vec2 tr_background(vec2 input) { return input / 11.111111 * (100.0/global_size); }

void vertex()
{
	quad_id = floor(float(VERTEX_ID) / 4.0);
	
	float side = 11.0;
	float y = floor(quad_id / side);
	float x = (quad_id - y * side);
	
	// Get joint position relative to BACKGROUND space
	vec2 bg_offset = vec2(x + float(x_offset), y + float(y_offset));
	bg_offset = jitter_grouped(bg_offset, 1.0, -global_jitter_intensity / float(jitter_bounds), global_seed);
	
	// Get joint position relative to VERTEX space
	vec2 pos = VERTEX;
	pos += tr_background(vec2(0.5, 0.5)); // Now aligned with the (unjittered) top left joint
	pos += tr_background(bg_offset); // Now at the (jittered) bg_offset joint position
	
	// Finally, offset the VERTEX by 0.5 so that the center of UV space is
	// at (0,0).
	VERTEX = pos - vec2(0.5);
}

void fragment() 
{
	COLOR.rgb = BACKGROUND_COL;
	
	vec3 foreground = colors[int(quad_id) % 4];
	float circle = -sd_circle(UV - vec2(0.5), circ_size);
	COLOR.rgb = mask_aa(COLOR.rgb, foreground, circle);
	COLOR.a = mask_aa(0.0, 1.0, circle);
	
	//if (quad_id > max_id) { COLOR.a = 0.0; }
}
