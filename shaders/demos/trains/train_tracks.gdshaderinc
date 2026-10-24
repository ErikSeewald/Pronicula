#include "res://shaders/util/sdf.gdshaderinc"
#include "res://shaders/util/resource.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"

/*
* Shared code (and uniforms) for the representation of the train tracks of this demo.
* The background shader uses it for drawing the tracks, the train shader uses it to
* calculate the path of the trains.
*
* Note: Global uniforms were used because the background and the trains are different shaders
* and would otherwise go out of sync if one of their shared uniforms was adjusted in the GUI.
*/

// A single "cell" in this shader has the width and height: 1/global_size of uv space
global uniform float global_size;
global uniform int global_seed;

// --- JITTER ---
global uniform float global_jitter_intensity;
const int JITTER_BOUNDS = 9; // All cells within this group (width/height defined as number of cells) jitter identically
const int JITTER_CENTER = 4; // The in-jitter-group index of the cell that acts as a track joint
// --> A single jitter group for a single joint

const int NUM_NEIGHBOR_JOINTS = 4; // Only jitter-groups that share an edge are considered neighbors
const vec2[NUM_NEIGHBOR_JOINTS] NEIGHBOR_JOINTS_OFFSETS = { vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0) };

// --- CIRCUITS ---
// Pre-defined circuits are used within subsections of the total area to ensure high connectivity
const int CIRCUIT_SIZE = 3; // The grid (of jitter groups) defined by this width/height is guaranteed to have a full circuit of tracks
const int NUM_JOINTS_IN_CIRCUIT = CIRCUIT_SIZE*CIRCUIT_SIZE;
const int NUM_DEFINED_CIRCUITS = 5; // Different circuits made up of the same number of points to give variety in patterns

// Structured in such a way that each "row" of NUM_JOINTS_IN_CIRCUIT values can be indexed:
// [x+y*CIRCUIT_SIZE] -> next value (or (-1,-1) if the point is not part of the circuit)
const ivec2[NUM_DEFINED_CIRCUITS * NUM_JOINTS_IN_CIRCUIT] NEXT_IN_CIRCUIT = 
{
	ivec2(1, 0), ivec2(2, 0), ivec2(2, 1), ivec2(0, 0), ivec2(-1, -1), ivec2(2, 2), ivec2(0, 1), ivec2(0, 2), ivec2(1, 2), // Full circle
	ivec2(1, 0), ivec2(2, 0), ivec2(2, 1), ivec2(0, 0), ivec2(1, 2), ivec2(1, 1), ivec2(0, 1), ivec2(0, 2), ivec2(-1, -1), // Top left corner
	ivec2(-1, -1), ivec2(2, 0), ivec2(2, 1), ivec2(1, 1), ivec2(1, 0), ivec2(2, 2), ivec2(0, 1), ivec2(0, 2), ivec2(1, 2), // Bottom right corner
	ivec2(1, 0), ivec2(1, 1), ivec2(-1, -1), ivec2(0, 0), ivec2(2, 1), ivec2(2, 2), ivec2(0, 1), ivec2(0, 2), ivec2(1, 2), // Bottom left corner
	ivec2(1, 0), ivec2(2, 0), ivec2(2, 1), ivec2(0, 0), ivec2(0, 1), ivec2(2, 2), ivec2(-1, -1), ivec2(1, 1), ivec2(1, 2) // Top right corner
};

// Structured in such a way that each "row" of NUM_JOINTS_IN_CIRCUIT values can be indexed:
// [x+y*CIRCUIT_SIZE] -> previous value (or (-1,-1) if the point is not part of the circuit)
const ivec2[NUM_DEFINED_CIRCUITS * NUM_JOINTS_IN_CIRCUIT] PREV_IN_CIRCUIT = 
{
	ivec2(0, 1), ivec2(0, 0), ivec2(1, 0), ivec2(0, 2), ivec2(-1, -1), ivec2(2, 0), ivec2(1, 2), ivec2(2, 2), ivec2(2, 1), // Full circle
	ivec2(0, 1), ivec2(0, 0), ivec2(1, 0), ivec2(0, 2), ivec2(2, 1), ivec2(2, 0), ivec2(1, 2), ivec2(1, 1), ivec2(-1, -1), // Top left corner
	ivec2(-1, -1), ivec2(1, 1), ivec2(1, 0), ivec2(0, 2), ivec2(0, 1), ivec2(2, 0), ivec2(1, 2), ivec2(2, 2), ivec2(2, 1), // Bottom right corner
	ivec2(0, 1), ivec2(0, 0), ivec2(-1, -1), ivec2(0, 2), ivec2(1, 0), ivec2(1, 1), ivec2(1, 2), ivec2(2, 2), ivec2(2, 1), // Bottom left corner
	ivec2(0, 1), ivec2(0, 0), ivec2(1, 0), ivec2(1, 1), ivec2(1, 2), ivec2(2, 0), ivec2(-1, -1), ivec2(2, 2), ivec2(2, 1)  // Top right corner
};

// Gets the coordinate of the next/prev element in the circuit.
// - coords_in_circuit: The current coordinate
// - circuit_variant: Which of the predefined circuits is used here?
// - get_next: If true, then the next element is fetched. Otherwise its the previous element
// Returns (-1,-1) if the current coordinate is not part of the circuit.
ivec2 get_from_circuit(ivec2 current, int circuit_variant, bool get_next)
{
	// Get the index in the circuit series of the current coordinate
	// and use it to look up the next/prev coordinate.
	// Indexed access to const arrays should be faster than a loop solution,
	// even if it requires two arrays.
	
	int index_in_circuit = (current.x + current.y * CIRCUIT_SIZE);
	int circuit_variant_offset = circuit_variant * NUM_JOINTS_IN_CIRCUIT;
	int lookup_index = index_in_circuit + circuit_variant_offset;
	return get_next ? NEXT_IN_CIRCUIT[lookup_index] : PREV_IN_CIRCUIT[lookup_index];
}

// Each circuit is made up of CIRCUIT_SIZE x CIRCUIT_SIZE jitter groups.
// This function returns the id/idx of the circuit that the given
// jitter group falls into.
ivec2 get_circuit_id(ivec2 jt_group_id)
{
	return jt_group_id / CIRCUIT_SIZE;
}

// Each circuit is made up of CIRCUIT_SIZE x CIRCUIT_SIZE jitter groups.
// This function returns the coordinates of the given
// jitter group within the circuit.
ivec2 get_coords_in_circuit(vec2 jt_group_id)
{
	return ivec2(mod(jt_group_id, float(CIRCUIT_SIZE)));
}

// Each circuit is made up of CIRCUIT_SIZE x CIRCUIT_SIZE jitter groups.
// This function converts the given coordinates within the given circuit into
// the jt_group_id of the jitter group that this element in the circuit represents.
ivec2 circuit_coords_to_jt_group(ivec2 coords_in_circuit, ivec2 circuit_id)
{
	return coords_in_circuit + circuit_id * CIRCUIT_SIZE;
}

// Before jittering, each joint is at the center of each jitter group.
// This function converts the id of the jitter group to the absolute
// coordinates of its joint.
vec2 jt_group_id_to_joint_pos(vec2 jt_group_id)
{
	return jt_group_id * float(JITTER_BOUNDS) + float(JITTER_CENTER) + vec2(0.5);
}

// Jitters the given joint position based on the jitter bounds, global jitter intensity and global seed.
vec2 jitter_joint(vec2 joint_pos_pre_jitter)
{
	return jitter_grouped(joint_pos_pre_jitter, float(JITTER_BOUNDS), global_jitter_intensity, global_seed);
}

// There is NUM_DEFINED_CIRCUITS distinct possible circuits.
// This function returns the id of the circuit variant that
//  the circuit of  the given circuit id belongs to.
int get_circuit_variant(ivec2 circuit_id)
{
	return int(hash_vec2_float(vec2(circuit_id), global_seed) * float(NUM_DEFINED_CIRCUITS));
}

// Returns a random (seed + input deterministic) element from NEIGHBOR_JOINTS_OFFSETS
// based on the jitter group id.
vec2 get_neighbor_offset(vec2 jt_group_id)
{
	int index = int(hash_vec2_float(jt_group_id, global_seed) * float(NUM_NEIGHBOR_JOINTS));
	return NEIGHBOR_JOINTS_OFFSETS[index];
}