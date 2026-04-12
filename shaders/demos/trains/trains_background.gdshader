shader_type canvas_item;

#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"

group_uniforms general;
uniform float time = 0.0;
uniform float size = 100.0; // A single "cell" in this shader has the width/height: 1/size of uv space
uniform int seed = 1;

group_uniforms colors;
uniform vec3 background_color: source_color = vec3(0.45, 0.4, 0.8);
uniform vec3 tracks_color: source_color = vec3(0.1, 0.1, 0.2);

group_uniforms tracks;
uniform float tracks_thickness = 0.3;
uniform float jitter_intensity: hint_range(0.0, 6.0) = 6.0; // Anything beyond that range clips jitter bounds
const int jitter_bounds = 9; // All cells within this group (width/height defined as number of cells) jitter identically
const int jitter_center = 5; // The in-jitter-group index of the cell that acts as a track joint

const int num_neighbors = 4; // Only jitter-groups that share an edge are considered neighbors
const vec2[num_neighbors] neighbor_offsets = { vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0) };

// Pre-defined circuits are used within subsections of the total area to ensure high connectivity
const int circuit_size = 3; // The grid defined by this width/height is guaranteed to have a full circuit of tracks
const int num_points_in_circuit = circuit_size*circuit_size;
const int num_circuits = 5; // Different circuits made up of the same number of points to give variety in patterns

// Structured in such a way that each "row" of num_points_in_circuit values can be indexed:
// [x+y*circuit_size] -> next value (or (-1,-1) if the point is not part of the circuit)
const ivec2[num_circuits * num_points_in_circuit] circuit_next = 
{
	ivec2(1, 0), ivec2(2, 0), ivec2(2, 1), ivec2(0, 0), ivec2(-1, -1), ivec2(2, 2), ivec2(0, 1), ivec2(0, 2), ivec2(1, 2), // Full circle
	ivec2(1, 0), ivec2(2, 0), ivec2(2, 1), ivec2(0, 0), ivec2(1, 2), ivec2(1, 1), ivec2(0, 1), ivec2(0, 2), ivec2(-1, -1), // Top left corner
	ivec2(-1, -1), ivec2(2, 0), ivec2(2, 1), ivec2(1, 1), ivec2(1, 0), ivec2(2, 2), ivec2(0, 1), ivec2(0, 2), ivec2(1, 2), // Bottom right corner
	ivec2(1, 0), ivec2(1, 1), ivec2(-1, -1), ivec2(0, 0), ivec2(2, 1), ivec2(2, 2), ivec2(0, 1), ivec2(0, 2), ivec2(1, 2), // Bottom left corner
	ivec2(1, 0), ivec2(2, 0), ivec2(2, 1), ivec2(0, 0), ivec2(0, 1), ivec2(2, 2), ivec2(-1, -1), ivec2(1, 1), ivec2(1, 2) // Top right corner
};

// Structured in such a way that each "row" of num_points_in_circuit values can be indexed:
// [x+y*circuit_size] -> previous value (or (-1,-1) if the point is not part of the circuit)
const ivec2[num_circuits * num_points_in_circuit] circuit_prev = 
{
	ivec2(0, 1), ivec2(0, 0), ivec2(1, 0), ivec2(0, 2), ivec2(-1, -1), ivec2(2, 0), ivec2(1, 2), ivec2(2, 2), ivec2(2, 1), // Full circle
	ivec2(0, 1), ivec2(0, 0), ivec2(1, 0), ivec2(0, 2), ivec2(2, 1), ivec2(2, 0), ivec2(1, 2), ivec2(1, 1), ivec2(-1, -1), // Top left corner
	ivec2(-1, -1), ivec2(1, 1), ivec2(1, 0), ivec2(0, 2), ivec2(0, 1), ivec2(2, 0), ivec2(1, 2), ivec2(2, 2), ivec2(2, 1), // Bottom right corner
	ivec2(0, 1), ivec2(0, 0), ivec2(-1, -1), ivec2(0, 2), ivec2(1, 0), ivec2(1, 1), ivec2(1, 2), ivec2(2, 2), ivec2(2, 1), // Bottom left corner
	ivec2(0, 1), ivec2(0, 0), ivec2(1, 0), ivec2(1, 1), ivec2(1, 2), ivec2(2, 0), ivec2(-1, -1), ivec2(2, 2), ivec2(2, 1)  // Top right corner
};

// Named parameters for configuring which of the two arrays to use
const bool CIRCUIT_NEXT = true;
const bool CIRCUIT_PREV = false;

group_uniforms debug;
uniform bool show_jitter = false;

// Draws the joints/jitter centers of the train tracks as little circles based on the
// given coordinates of the fragment. Uses the given current color to mask them on top.
vec3 draw_joints(vec2 coords, vec3 cur_col)
{	
	vec2 jittered = jitter_grouped(coords, float(jitter_bounds), jitter_intensity, seed);
	ivec2 cell_idx = ivec2(jittered);
	
	if (show_jitter)
	{
	 	// Checker pattern to show the jitter groups
		ivec2 jt_group_id = ivec2(coords / float(jitter_bounds));
		float checker_factor = max(0.4, float((jt_group_id.x + jt_group_id.y) % 2));
		
		// And a random color for each cell within the group
		cur_col.gb = hash_vec2_vec2(vec2(cell_idx), seed) * checker_factor;
	}
	
	if (cell_idx.x % jitter_bounds == jitter_center && cell_idx.y % jitter_bounds == jitter_center)
	{		
		vec2 uv = fract(jittered);
		uv -= vec2(0.5);
		float alpha = -sd_circle(uv, tracks_thickness * 1.5);
		return mask_aa(cur_col, tracks_color, alpha);
	}

	return cur_col;
}

// Gets the (next/prev) ivec2 from the circuit defined by circuit_num and the current ivec2 in
// the series. The constants CIRCUIT_NEXT and CIRCUIT_PREV are passed to the get_next bool.
ivec2 get_from_circuit(ivec2 current, int circuit_num, bool get_next)
{
	// Indexed access to const arrays should be faster than a loop solution, even if it requires
	// two arrays.
	int index = (current.x + current.y * circuit_size) + circuit_num * num_points_in_circuit;
	return get_next ? circuit_next[index] : circuit_prev[index];
}

uniform float bezier_offset = 3.0;
float fixed_bezier(vec2 coords, vec2 a, vec2 b, bool is_right)
{
	float offset = is_right ? bezier_offset : -bezier_offset;
	
	vec2 middle = 0.5 * (a + b);
	vec2 dir = normalize(a - b);
	vec2 perpendicular = vec2(-dir.y, dir.x);
	vec2 control = middle + perpendicular * offset;
	
	float q = sd_bezier(coords, a, control, b);
	return q < tracks_thickness * 0.5 ? 1.0 : 0.0;
}

float sd_circuit(vec2 coords, vec2 jt_group_id, vec2 joint_pos_pre_jitter, vec2 joint_pos, vec2 coords_in_jt_group, vec2 p0, out vec2[2] circuit_neighbors)
{
	float alpha = 0.0;
	
	float jt_bounds_f = float(jitter_bounds);
	vec2 jt_center_vec2 = vec2(float(jitter_center));
	
	int circuits_bounds = 3;
	ivec2 circuit_id = ivec2(coords / float(circuits_bounds * jitter_bounds));
	ivec2 circuit_idx = ivec2(mod(jt_group_id, float(circuits_bounds)));
	
	int circuit_num = int(hash_vec2_float(vec2(circuit_id), seed) * 10.0) % num_circuits;
	
	ivec2 next = get_from_circuit(circuit_idx, circuit_num, CIRCUIT_NEXT);
	if (next != ivec2(-1))
	{
		next += circuit_id * circuits_bounds;
		joint_pos_pre_jitter = (vec2(next) * jt_bounds_f + jt_center_vec2) + vec2(0.5);
		joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -jitter_intensity, seed);
		vec2 p_next = joint_pos - jt_group_id * jt_bounds_f;
		
		circuit_neighbors[0] = p_next;
		
		alpha = -sd_oriented_box(coords_in_jt_group, p0, p_next, tracks_thickness);
	}
	
	// PREV
	ivec2 prev = get_from_circuit(circuit_idx, circuit_num, CIRCUIT_PREV);
	if (prev != ivec2(-1))
	{
		prev += circuit_id * circuits_bounds;
		joint_pos_pre_jitter = (vec2(prev) * jt_bounds_f + jt_center_vec2) + vec2(0.5);
		joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -jitter_intensity, seed);
		vec2 p_prev = joint_pos - jt_group_id * jt_bounds_f;
		
		circuit_neighbors[1] = p_prev;
		alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, p0, p_prev, tracks_thickness)));	
	}
	
	return alpha;
}

float sd_bridge(vec2 jt_group_id, vec2 joint_pos_pre_jitter, vec2 joint_pos, vec2 coords_in_jt_group, vec2 p0, in vec2[2] circuit_neighbors)
{
	float alpha = 0.0;
	
	float jt_bounds_f = float(jitter_bounds);
	vec2 jt_center_vec2 = vec2(float(jitter_center));
	
	// IN
	vec2[num_neighbors] in_offsets;
	int inputs_found = 0;
	for (int i = 0; i < num_neighbors; i++)
	{
		vec2 neighbor_id = jt_group_id - neighbor_offsets[i];
		int neighbor_offset_idx = int(hash_vec2_float(neighbor_id, seed) * 10.0) % num_neighbors;
		vec2 neighbor_offset = neighbor_offsets[neighbor_offset_idx];
		if (neighbor_id + neighbor_offset == jt_group_id)
		{
			in_offsets[inputs_found] = -neighbor_offset;
			inputs_found++;
		}
	}	
	for (int i = 0; i < inputs_found; i++)
	{
		joint_pos_pre_jitter = ((jt_group_id + in_offsets[i]) * jt_bounds_f + jt_center_vec2) + vec2(0.5);
		joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -jitter_intensity, seed);
		vec2 p_left = joint_pos - jt_group_id * jt_bounds_f;
		
		if (p_left == circuit_neighbors[0] || p_left == circuit_neighbors[1] ) { continue; }
		//alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, p0, p_left, tracks_thickness)));	
		alpha = sdf_union(vec2(alpha, fixed_bezier(coords_in_jt_group, p0, p_left, false)));
	}
	
	// OUT
	int out_offset_idx = int(hash_vec2_float(jt_group_id, seed) * 10.0) % num_neighbors;
	vec2 out_offset = neighbor_offsets[out_offset_idx];
	
	joint_pos_pre_jitter = ((jt_group_id + out_offset) * jt_bounds_f + jt_center_vec2) + vec2(0.5);
	joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -jitter_intensity, seed);
	vec2 p_right = joint_pos - jt_group_id * jt_bounds_f;
	
	if (p_right != circuit_neighbors[0] && p_right != circuit_neighbors[1] )
	{
		//alpha = sdf_union(vec2(alpha, -sd_oriented_box(coords_in_jt_group, p0, p_right, tracks_thickness)));
		alpha = sdf_union(vec2(alpha, fixed_bezier(coords_in_jt_group, p0, p_right, true)));
	}
	
	return alpha;
}

// Draws tracks between the joints at the center of jitter-groups based on the given fragment
// coordinates and masks them on top of the given current color.
vec3 draw_tracks(vec2 coords, vec3 cur_col)
{	
	// Jitter-group
	float jt_bounds_f = float(jitter_bounds); // I just do not want to keep doing "float(jitter_bounds)"
	vec2 jt_group_id = floor(coords / jt_bounds_f);
	vec2 coords_in_jt_group = mod(coords, jt_bounds_f);
	
	// Joint
	vec2 jt_center_vec2 = vec2(float(jitter_center));
	vec2 joint_pos_pre_jitter = (jt_group_id * jt_bounds_f + jt_center_vec2) + vec2(0.5);
	vec2 joint_pos = jitter_grouped(joint_pos_pre_jitter, jt_bounds_f, -jitter_intensity, seed);
	vec2 p0 = mod(joint_pos, jt_bounds_f);
	
	// BASE CIRCUIT
	vec2[2] circuit_neighbors;
	float circuit_alpha = sd_circuit(coords, jt_group_id, joint_pos_pre_jitter, joint_pos, coords_in_jt_group, p0, circuit_neighbors);
	
	float bridge_alpha = sd_bridge(jt_group_id, joint_pos_pre_jitter, joint_pos, coords_in_jt_group, p0, circuit_neighbors);
	float alpha = sdf_union(vec2(circuit_alpha, bridge_alpha));

	return mask_aa(cur_col, tracks_color, alpha);
}

void fragment() 
{
	vec2 coords = UV * size;
	
	COLOR.rgb = background_color;
	COLOR.rgb = draw_joints(coords, COLOR.rgb);
	COLOR.rgb = draw_tracks(coords, COLOR.rgb);
}