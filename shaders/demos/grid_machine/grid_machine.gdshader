shader_type canvas_item;
#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"
#include "res://shaders/util/debug.gdshaderinc"

group_uniforms general;
uniform float time = 0.0;
uniform int seed = 1;

group_uniforms grid;
uniform float grid_size = 12.0;
uniform float grid_padding: hint_range(-1.0, 0.0, 0.01) = -0.05;
uniform int num_square_genes = 5;

group_uniforms debug;
uniform int debug_square_id: hint_enum("OFF:0", "X:1", "Y:2") = 0;

group_uniforms grid_lines;
uniform vec3 grid_line_color: source_color = vec3(0.0);
uniform float grid_line_thickness: hint_range(0.0, 0.1, 0.001) = 0.02;

const int NUM_GRID_NEIGHBORS = 4;
const vec2[NUM_GRID_NEIGHBORS] GRID_NEIGHBOR_OFFSETS = { vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0) };

// coords_in_square are between 0.0 and 1.0
vec3 draw_grid_lines(vec2 coords_in_square, vec3 cur_col)
{	
	// Recenter the square around 0.0 for the sdf box and
	// set the scale to be 1x1 within the square
	vec2 centered_coords = coords_in_square - vec2(0.5);
	const vec2 half_size = vec2(0.5);
	
	// First generate a filled box via sd_box and then
	// AND-combine two step functions to only leave the outline
	float filled_box = sd_box(centered_coords, half_size);
	float outline_alpha = step(-grid_line_thickness, filled_box) * step(filled_box, 0.0);
	

	//if (coords_in_square.x > 0.5) { return vec3(1.0, 0.0, 0.0); }
	return mask_aa(cur_col, grid_line_color, outline_alpha);
}

int get_gene(vec2 square_id)
{
	return int(hash_vec2_float(square_id, seed) * float(num_square_genes)) % num_square_genes;
}

vec3 remove_gene_pair_grid_lines(vec2 coords_in_square, vec2 square_id, vec3 cur_col)
{
	int gene = get_gene(square_id);
	
	bool is_edge_of_gene_pair = false;
	for (int i = 0; i < NUM_GRID_NEIGHBORS; i++)
	{
		vec2 offset = GRID_NEIGHBOR_OFFSETS[i];
		vec2 neighbor_id = square_id + offset;
		
		if (neighbor_id.x < 0.0 || neighbor_id.x > grid_size - 1.0|| neighbor_id.y < 0.0 || neighbor_id.y > grid_size - 1.0) { continue; }
		
		int neighbor_gene = get_gene(neighbor_id);
		
		if (neighbor_gene == gene)
		{
			if (offset.x > 0.0)
			{
				if (coords_in_square.x > 0.5 && coords_in_square.y > grid_line_thickness && coords_in_square.y < 1.0 - grid_line_thickness)
				{
					cur_col = vec3(1.0);
				}
			}
			
			else if (offset.x < 0.0)
			{
				if (coords_in_square.x < 0.5  && coords_in_square.y > grid_line_thickness && coords_in_square.y < 1.0 - grid_line_thickness)
				{
					cur_col = vec3(1.0);
				}
			}
			
			else if (offset.y > 0.0)
			{
				if (coords_in_square.y > 0.5  && coords_in_square.x > grid_line_thickness && coords_in_square.x < 1.0 - grid_line_thickness)
				{
					cur_col = vec3(1.0);
				}
			}
			
			else if (offset.y < 0.0)
			{
				if (coords_in_square.y < 0.5  && coords_in_square.x > grid_line_thickness && coords_in_square.x < 1.0 - grid_line_thickness)
				{
					cur_col = vec3(1.0);
				}
			}
			
		}
	}
	
	return cur_col;
}

vec3 draw_square_genes(vec2 coords_in_square, vec2 square_id, vec3 cur_col)
{
	int gene = get_gene(square_id);
	vec3 gene_col = vec3(0.0, hash_vec2_vec2(vec2(float(gene)), seed));
	
	float circle = -sd_circle(coords_in_square - vec2(0.5), 0.2);
	return mask_aa(cur_col, gene_col, circle);
}

void fragment()
{
	COLOR.rgb = vec3(1.0);

	// Scale coords and scale them down with some padding to the edge of the screen space
	vec2 coords = UV * grid_size;
	coords = (coords * (1.0 - 2.0 * grid_padding)) + grid_padding * grid_size;
	
	if (coords.x > 0.0 && coords.y > 0.0 && coords.x <= grid_size && coords.y <= grid_size) 
	{
		vec2 square_id = floor(coords);
		vec2 coords_in_square = fract(coords);
		
		COLOR.rgb = draw_grid_lines(coords_in_square, COLOR.rgb);
		COLOR.rgb = remove_gene_pair_grid_lines(coords_in_square, square_id, COLOR.rgb);
		COLOR.rgb = draw_square_genes(coords_in_square, square_id, COLOR.rgb);
		
		switch (debug_square_id)
		{
			case 1: COLOR.rgb = debug_draw_int_5_digits(int(square_id.x), coords_in_square); break;
			case 2: COLOR.rgb = debug_draw_int_5_digits(int(square_id.y), coords_in_square); break;
		}
	}
}