extends MeshInstance2D

@onready var mat: ShaderMaterial = self.material

@export var num_quads: int = 100
var t: float = 0.0

func _ready() -> void:
	var splesh: ArrayMesh = SpleshGenerator.generate_splesh(num_quads, SpleshGenerator.CullMode.NEVER_CULL)
	var err = ResourceSaver.save(splesh, "res://splesh_100.tres")
	self.mesh = splesh
	self.scale = Vector2(20, 20)
	mat.set_shader_parameter("num_quads", num_quads)
	
func set_time(time: float):
	mat.set_shader_parameter("time", time)
	
func _process(delta: float): 
	t += delta
	set_time(t)
