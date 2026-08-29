#include "res://shaders/util/sdf.gdshaderinc"
#include "res://shaders/util/random.gdshaderinc"

/*
* Shared code (and uniforms) for the representation of the train tracks of this demo.
* The background shader uses it for drawing the tracks, the train shader uses it to
* calculate the path of the trains.
*
* Note: Global uniforms were used because the background and the trains are different shaders
* and would otherwise go out of sync if one of their shared uniforms was adjusted in the GUI.
*/

// A single "cell" in this shader has the width/height: 1/global_size of uv space
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

// Gets the (next/prev) circuit coordinate from the circuit defined by circuit_num and the 
// given current coordinate the series.
// Returns (-1,-1) if the current coordinate is not part of the circuit.
ivec2 _get_from_circuit(ivec2 current, int circuit_num, bool get_next)
{
	// Indexed access to const arrays should be faster than a loop solution, even if it requires
	// two arrays.
	int circuit_index = (current.x + current.y * CIRCUIT_SIZE);
	int index = circuit_index + circuit_num * NUM_JOINTS_IN_CIRCUIT;
	return get_next ? NEXT_IN_CIRCUIT[index] : PREV_IN_CIRCUIT[index];
}

ivec2 get_next_from_cicuit(ivec2 current, int circuit_num)
{
	const bool GET_NEXT = true;
	return _get_from_circuit(current, circuit_num, GET_NEXT);
}

ivec2 get_prev_from_cicuit(ivec2 current, int circuit_num)
{
	const bool GET_NEXT = false;
	return _get_from_circuit(current, circuit_num, GET_NEXT);
}