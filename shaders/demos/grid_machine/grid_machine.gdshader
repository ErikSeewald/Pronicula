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
uniform float gene_falloff = 0.06;
uniform float stretch_distribution = 0.5;

group_uniforms debug;
uniform int debug_square_id: hint_enum("OFF:0", "X:1", "Y:2") = 0;
uniform bool debug_show_genes = false;

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
	
	// Unique color for debugging.
	vec3 color; 
};
 
// These gene dimensions were specifically chosen to be (mostly) squares with
// side lengths of powers of 2 so that squares with a smaller dimension
// are always fully inside squares with a bigger dimension.
// For example, a 3x3 could not guarantee non-overlapping alignment with a 2x2.
// See get_gene() for how the special cases of 1x2 and 2x1 are handled.
const Gene GENE_1x1 = Gene(vec2(1.0, 1.0),vec3(1.0, 0.0, 0.0));
const Gene GENE_1x2 = Gene(vec2(1.0, 2.0), vec3(0.0, 1.0, 0.0));
const Gene GENE_2x1 = Gene(vec2(2.0, 1.0), vec3(0.0, 0.0, 1.0));
const Gene GENE_2x2 = Gene(vec2(2.0, 2.0), vec3(1.0, 1.0, 0.0));
const Gene GENE_4x4 = Gene(vec2(4.0, 4.0), vec3(1.0, 0.0, 1.0));

// Returns wether the current fragment has the given gene.
// Uses the fragment's id on the "level" of the grid with the gene's dimensions
// for the random chance to ensure all fragments of a rectangle in that grid behave the same.
// (Also uses the gene's id to offset the chances so that larger dimensions are less likely,
// which leads to a prettier distribution)
bool gene_chance(vec2 cur_level_id, Gene gene)
{
	float chance_offset = length(gene.dimensions) * gene_falloff;
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

// Draws the outline of a square and returns the new fragment color.
// - coords_in_square: The fragment's coordinates inside the square. Should be in [0.0, 1.0]
// - line_thickness: Defines the thickness of x: the horizontal lines, and y: the vertical lines.
//					This thickness is relative to the [0.0, 1.0] coords in square.
// - cur_col: The current color of the fragment. This function blends the outline on top.
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

// Draws the grid lines on top of the given current color and returns the new color.
// Optionally draws grid-related debug information.
// - gene: The fragment's grid gene
// - square_id: The 1x1 square that the fragment falls onto
// - coords_in_square: The [0.0, 1.0] coordinates within the 1x1 that the fragment falls onto
// - coords_in_gene: The [0.0, 1.0] coordinates within the gene.dimensions square that the fragment falls onto
// - cur_col: The fragments current color
vec3 draw_grid(Gene gene, vec2 square_id, vec2 coords_in_square, vec2 coords_in_gene, vec3 cur_col)
{	
	if (debug_show_genes) { cur_col = gene.color; }
	
	// Since coords_in_gene may be stretched compared to a 1x1 square, the line thickness
	// needs to be adjusted to the gene's dimensions
	vec2 line_thickness = vec2(grid_line_thickness) / gene.dimensions;
	cur_col = draw_square_outline(coords_in_gene, line_thickness, cur_col);
	
	// Debug: Show the coordinates of the square id
	switch (debug_square_id)
	{
		case 1: cur_col = debug_draw_int_5_digits(int(square_id.x), coords_in_square); break;
		case 2: cur_col = debug_draw_int_5_digits(int(square_id.y), coords_in_square); break;
	}
	
	return cur_col;
}

void fragment()
{
	// Scale the UV coordinates into grid coordinates and then
	// get the 1x1 square that the fragment falls onto
	vec2 coords = UV * grid_size;
	vec2 square_id = floor(coords);
	vec2 coords_in_square = fract(coords);
	
	// Get the gene for the square and the fragment's scaled coordinates
	// within the rectangle defined by the gene dimensions
	Gene gene = get_gene(square_id);
	vec2 coords_in_gene = fract(coords / gene.dimensions);
	
	COLOR.rgb = vec3(1.0);
	COLOR.rgb = draw_grid(gene, square_id, coords_in_square, coords_in_gene, COLOR.rgb);
}