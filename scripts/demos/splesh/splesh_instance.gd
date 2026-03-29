extends MeshInstance2D

@onready var mat: ShaderMaterial = self.material

@export var num_quads: int = 500000
var time: float = 0.0

func _ready() -> void:
	var splesh: ArrayMesh = SpleshGenerator.generate_splesh(num_quads, SpleshGenerator.CullMode.NEVER_CULL)
	self.mesh = splesh
	mat.set_shader_parameter("num_quads", num_quads)
	
func _process(delta: float): 
	time += delta
	mat.set_shader_parameter("time", time)
	
	# To compare a mouse pos to a vertex pos in the shader, send this to it
	# self.to_local(get_global_mouse_position())
