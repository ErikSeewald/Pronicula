extends MeshInstance2D

@onready var mat: ShaderMaterial = self.material
@export var background_rect: ColorRect

var quad_count: int = 2000
var time: float = 0.0
var time_speed := 1.0

func _ready() -> void:
	time = material.get_shader_parameter("time")
	on_quad_count_change(quad_count)

func _process(delta: float) -> void: 
	time += delta * time_speed
	material.set_shader_parameter("time", time)

# Use an on_change signal with an additional binding parameter for 'param_name'
func on_change_shader_param(param_value, param_name) -> void:
	material.set_shader_parameter(param_name, param_value)
	
# Use an on_change signal with an additional binding parameter for 'param_name'
func on_change_global_shader_param(param_value, param_name) -> void:
	RenderingServer.global_shader_parameter_set_override(param_name, param_value)

# Splesh needs to be reinitialized with the given amount of quads
func on_quad_count_change(count: int) -> void:
	self.mesh = null # Drop old reference. Not sure if this actually speeds up garbage collection.
	
	quad_count = count
	var splesh: ArrayMesh = SpleshGenerator.generate_splesh(quad_count)
	self.mesh = splesh

# Separate function because its a shader param on the background_rect
func set_show_jitter(value: bool) -> void:
	background_rect.material.set_shader_parameter("show_jitter", value)
	
func on_set_time_speed(value: float) -> void:
	time_speed = value
	
func return_to_menu():
	get_tree().change_scene_to_file("res://scenes/menu/menu.tscn")
