extends Node
class_name SpleshGenerator

const QUAD_VERTICES: PackedVector3Array = [
	Vector3(0, 0, 0),
	Vector3(0 + 1, 0, 0),
	Vector3(0 + 1, 1, 0),
	Vector3(0, 1, 0),
]

const QUAD_UVS: PackedVector2Array = [
	Vector2(0, 0),
	Vector2(1, 0),
	Vector2(1, 1),
	Vector2(0, 1),
]

## By default, Godot culls the splesh by its AABB even if the vertex shader
## has theoretically modified it. NEVER_CULL instructs the SpleshGenerator
## to set the AABB to an infinite size.
enum CullMode {
	NEVER_CULL,
	DEFAULT_CULL,
}

## Creates a splesh (2D Split-Mesh) and returns it.
## - A splesh is made up of a varying amount of disjoint quads.
## - All quads have the same vertex position (i.e., overlap by default).
static func generate_splesh(num_quads: int, cull_mode: CullMode = CullMode.NEVER_CULL) -> ArrayMesh:
	var splesh: ArrayMesh = ArrayMesh.new()
	var vertex_count: int = num_quads * 4
	var index_count: int = num_quads * 6
	
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.resize(vertex_count)
	var uvs: PackedVector2Array = PackedVector2Array()
	uvs.resize(vertex_count)
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(index_count)
	
	# Index based because it is much faster than append & concatenate
	for i in range(num_quads):
		var v: int = i * 4
		var j: int = i * 6
		
		vertices[v + 0] = QUAD_VERTICES[0]
		vertices[v + 1] = QUAD_VERTICES[1]
		vertices[v + 2] = QUAD_VERTICES[2]
		vertices[v + 3] = QUAD_VERTICES[3]
		
		uvs[v + 0] = QUAD_UVS[0]
		uvs[v + 1] = QUAD_UVS[1]
		uvs[v + 2] = QUAD_UVS[2]
		uvs[v + 3] = QUAD_UVS[3]
		
		# Two triangles per quad
		indices[j + 0] = v + 0
		indices[j + 1] = v + 1
		indices[j + 2] = v + 2
		
		indices[j + 3] = v + 2
		indices[j + 4] = v + 3
		indices[j + 5] = v + 0
		
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	splesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	if (cull_mode == CullMode.NEVER_CULL):
		splesh.custom_aabb = AABB(Vector3(-INF, -INF, -INF), Vector3(INF, INF, INF))
	
	return splesh
