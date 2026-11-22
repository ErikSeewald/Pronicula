shader_type canvas_item;
#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"
#include "res://shaders/util/sdf.gdshaderinc"
#include "res://shaders/util/debug.gdshaderinc"


// ---------------------
// ----- UNIFORMS ------
// ---------------------

group_uniforms general;
uniform float time = 0.0;
uniform int seed = 1;

group_uniforms grid;
uniform float grid_size = 16.0;
uniform float gene_falloff = 0.1;
uniform float stretch_distribution = 0.5;

group_uniforms debug;
uniform int debug_square_id: hint_enum("OFF:0", "X:1", "Y:2") = 0;
uniform int debug_show_grid_stage = -1;

group_uniforms grid_lines;
uniform vec3 grid_line_color: source_color = vec3(0.1);
uniform float grid_line_thickness: hint_range(0.0, 0.1, 0.001) = 0.03;


// ---------------------
// ------- GENES -------
// ---------------------

// Defines a gene for a single grid square.
// Depending on the gene, the square might merge with other squares to
// create a 2x2 square, etc.
struct Gene
{
	// The dimensions that the square takes when combining with its
	// neighbors that share the same gene.
	vec2 dimensions;
	
	int id; // Identifier for switch statements
	vec3 color; // Unique color for debugging.
};
 
// These gene dimensions were specifically chosen to be (mostly) squares with
// side lengths of powers of 2 so that squares with a smaller dimension
// are always fully inside squares with a bigger dimension.
// For example, a 3x3 could not guarantee non-overlapping alignment with a 2x2.
// See draw_grid() for how the special cases of 1x2 and 2x1 are handled.
const int NUM_GENES = 5;
const Gene GENE_1x1 = Gene(vec2(1.0, 1.0), 0, vec3(1.0, 0.0, 0.0));
const Gene GENE_1x2 = Gene(vec2(1.0, 2.0), 1, vec3(0.0, 1.0, 0.0));
const Gene GENE_2x1 = Gene(vec2(2.0, 1.0), 2, vec3(0.0, 0.0, 1.0));
const Gene GENE_2x2 = Gene(vec2(2.0, 2.0), 3, vec3(1.0, 1.0, 0.0));
const Gene GENE_4x4 = Gene(vec2(4.0, 4.0), 4, vec3(1.0, 0.0, 1.0));
const Gene GENE_UNKNOWN = Gene(vec2(1.0, 1.0), -1, vec3(1.0));

// Draws the color of the given gene and returns the new fragment color.
// Uses the given current color to only draw behind the grid lines.
vec3 debug_draw_gene_color(Gene gene, vec3 cur_col)
{
	// Comparison with a little epsilon because == is not great for vec3 uniforms
	bool is_grid_line = length(cur_col - grid_line_color) < 0.0001;
	return is_grid_line ? grid_line_color : gene.color;
}

// Draws the outline of a square and returns the new fragment color.
// - coords_in_square: The fragment's coordinates inside the square. Should be in [0.0, 1.0]
// - line_thickness: Defines the thickness of x: the horizontal lines, and y: the vertical lines.
//					This thickness is relative to the [0.0, 1.0] coords in square.
// -	cur_col: The current color of the fragment. This function blends the outline on top.
vec3 draw_square_outline(vec2 coords_in_square, vec2 line_thickness, vec3 cur_col)
{		
	// Get the distance to both edges and then use a step function for the 
	// line thickness. Combine both with AND.
	vec2 edge_dist = min(coords_in_square, vec2(1.0) - coords_in_square);
	float outline_x = step(line_thickness.x, edge_dist.x);
	float outline_y = step(line_thickness.y, edge_dist.y);
	float outline_alpha = 1.0 - outline_x * outline_y; 
	
	return mask_aa(cur_col, grid_line_color, outline_alpha);
}

// Returns wether the current fragment has the given gene.
// Uses the fragment's id on the "level" of the grid with the gene's dimensions
// for the random chance to ensure all fragments of a rectangle in that grid behave the same.
// (Also uses the gene's id to offset the chances so that larger dimensions are less likely,
// which leads to a prettier distribution)
bool gene_chance(vec2 cur_level_id, Gene gene)
{
	float chance_offset = float(gene.id) * gene_falloff;
	return hash_vec2_float(cur_level_id, seed) > 0.5 + chance_offset;
}

// Takes the given square and returns the identifier of the rectangle it falls
// onto in the grid defined by the given gene's width and height.
vec2 get_id_on_gene_level(vec2 square_id, Gene gene)
{
	return floor(square_id / gene.dimensions);
}

// Returns the gene of the square with the given id.
// The gene is deterministic at every coordinate.
Gene get_gene(vec2 square_id)
{
	// Note: I chose againt using a loop here for clarity in the GENE_2x1 and GENE_1x2 case.
	
	// Start at largest gene level and return if the square took that gene.
	// If not, move one level lower and repeat. This way, the larger gene
	// grids block out the smaller ones to ensure that, if one square takes
	// gene AxB, all other squares within that larger AxB square also have that gene.
	Gene gene = GENE_4x4;
	vec2 cur_level_id = get_id_on_gene_level(square_id, gene);
	if (gene_chance(cur_level_id, gene)) { return gene; }
	
	gene = GENE_2x2;
	cur_level_id = get_id_on_gene_level(square_id, gene);
	if (gene_chance(cur_level_id, gene)) { return gene; }
	
	// Special case for 1x2 and 2x1: Since they cannot occupy the same 2x2, 
	// use the 2x2 id to force a chance for either one or the other gene.
	// The same type can both occupy the same 2x2 without issue.
	gene = hash_vec2_float(cur_level_id, seed) > stretch_distribution ? GENE_1x2 : GENE_2x1;
	cur_level_id = get_id_on_gene_level(square_id, gene);
	if (gene_chance(cur_level_id, gene)) { return gene; }
	
	return GENE_1x1;
}

vec3 draw_grid(vec2 coords, vec3 cur_col)
{
	if (coords.x > 0.0 && coords.y > 0.0 && coords.x <= grid_size && coords.y <= grid_size) 
	{
		vec2 square_id = floor(coords);
		vec2 coords_in_square = fract(coords);
		
		Gene gene = get_gene(square_id);
		if (debug_show_grid_stage >= 0)
		{
			if (gene.id < NUM_GENES - debug_show_grid_stage) { gene = GENE_UNKNOWN; }
		}
		
		
		vec2 coords_in_gene = coords_in_square;
		vec2 line_thickness = vec2(grid_line_thickness);
		
		switch (gene.id)
		{
			case 4:
				coords_in_gene = fract(coords / 4.0);
				line_thickness /= 4.0;
				break;
			case 3:
				coords_in_gene = fract(coords / 2.0);
				line_thickness /= 2.0;
				break;
			case 2:
				coords_in_gene = fract(vec2(coords.x / 2.0, coords.y));
				line_thickness /= vec2(2.0, 1.0);
				break;
			case 1:
				coords_in_gene = fract(vec2(coords.x, coords.y  / 2.0));
				line_thickness /= vec2(1.0, 2.0);
				break;
		}
		
		cur_col = draw_square_outline(coords_in_gene, line_thickness, cur_col);
		cur_col = debug_draw_gene_color(gene, cur_col);
		
		switch (debug_square_id)
		{
			case 1: cur_col = debug_draw_int_5_digits(int(square_id.x), coords_in_square); break;
			case 2: cur_col = debug_draw_int_5_digits(int(square_id.y), coords_in_square); break;
		}
	}
	
	return cur_col;
}


void fragment()
{
	COLOR.rgb = vec3(1.0);

	vec2 coords = UV * grid_size;
	
	COLOR.rgb = draw_grid(coords, COLOR.rgb);
}