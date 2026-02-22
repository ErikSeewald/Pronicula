shader_type canvas_item;
#include "res://shaders/util/resource.gdshaderinc"

group_uniforms set_by_script;
uniform float grid_size = 1.0;
uniform float time : hint_range(0.0, 1.0) = 0.0; // Used to animate the moving of the square
uniform ivec2 move_to = ivec2(-1, -1); // The final position of the moving square
uniform ivec2 move_from = ivec2(-1, -1); // The pre-switch position of the moving square

uniform int move_dir : hint_enum("DOWN", "RIGHT", "UP", "LEFT") = 0; // Direction from 'move_from'
const vec2 DIRECTIONS[4] = {vec2(0, 1), vec2(1, 0), vec2(0, -1), vec2(-1, 0)};

/// The number of different classes into which a grid square can fall.
const int NUM_CLASSES = 4;

/// Each pixel stores information about its corresponding grid square
/// in its color channels.
uniform sampler2D grid_tex : filter_nearest;

/// Stores information about a single square on the grid.
/// Its class specifies the procedural texture with which to render it.
struct grid_square
{
	int cur_class;
	int prev_class;	
	ivec2 grid_position;
};

/// Creates a grid_square struct containing information about the square
/// that the given uv falls into on the 'grid_tex' uniform.
grid_square get_grid_square(vec2 uv)
{	
	// The script only assigns values between 0 and 1 that the shader
	// can then divide into as many classes as it wants.
	vec4 values = padded_texture(grid_tex, uv, grid_size) * float(NUM_CLASSES);
	grid_square square;
	square.cur_class = int(values.r);
	square.prev_class = int(values.g);
	square.grid_position = ivec2(uv*grid_size);
	return square;
}

/// Square (background) with a polygon (foreground) in its center
/// Uses a regular polygon SDF (derived from Inigo Quilez)
vec3 sample_polygon_square(vec2 uv, float sides, vec3 background, vec3 foreground)
{
	vec2 p = uv - vec2(0.5);
	const float radius = 0.25;
	
	float angle = 2.0*PI / sides;
	float half_angle = angle * 0.5;
	float polar_angle = atan(p.y, p.x);
	
	// Fold space into one wedge to use symmetry to check for distance to just that edge
	polar_angle = mod(polar_angle + half_angle, angle) - half_angle;
	vec2 q = length(p) * vec2(cos(polar_angle), abs(sin(polar_angle)));
	float dist_to_edge = q.x - radius * cos(half_angle);
	
	return mask_aa(background, foreground, -dist_to_edge);
}

/// Samples the procedural square texture specified by the given class.
/// 'is_moving' specifies whether the square that is being sampled is being animated.
vec3 sample_square(int class, vec2 internal_uv, bool is_moving)
{
	switch (class)
	{
		case 1: if (is_moving) { internal_uv = rotate_around_center(internal_uv, time*PI); }
				return sample_polygon_square(internal_uv, 4.0, vec3(0.15, 0.15, 0.15), vec3(1.0, 0.0, 0.0));
				
		case 2: if (is_moving) { internal_uv = rotate_around_center(internal_uv, time*2.0*PI); }
				return sample_polygon_square(internal_uv, 3.0, vec3(0.1, 0.1, 0.1), vec3(0.0, 1.0, 0.0));
				
		case 3: if (is_moving) { internal_uv = rotate_around_center(internal_uv, time*2.0*PI); }
				return sample_polygon_square(internal_uv, 5.0, vec3(0.05, 0.05, 0.05), vec3(1.0, 1.0, 0.0));
				
		default: if (is_moving) { internal_uv = rotate_around_center(internal_uv, time*PI); }
				return sample_polygon_square(internal_uv, 6.0, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0));
	}
}

void fragment() 
{
	grid_square square = get_grid_square(UV);
	vec2 internal_uv = fract(UV * grid_size);
	bool is_moving = false; // Property of the rendered square of this fragment, not the grid square
	
	// If the square is being animated to move into its position, display the previous value below
	// while the square it moves out from immediately takes the new value.
	int class = square.grid_position == move_to ? square.prev_class : square.cur_class;
	COLOR.rgb = sample_square(class, internal_uv, is_moving);
	
	// Then overlay the animated square above
	vec2 pos = UV*grid_size;
	vec2 change = DIRECTIONS[move_dir] * time;
	vec2 moved = vec2(move_from) + change;
	
	is_moving =	pos.x >= moved.x && pos.x <= moved.x + 1.0 &&
				pos.y >= moved.y && pos.y <= moved.y + 1.0;
	if (is_moving)
	{
		vec2 adjusted_pos = vec2(move_to) + vec2(0.5, 0.5); // hits correct square on all rounding systems
		square = get_grid_square(adjusted_pos / grid_size);
		internal_uv = mod(internal_uv - change, vec2(1.0)); 
		COLOR.rgb = sample_square(square.cur_class, internal_uv, is_moving);
	}
}