extends ColorRect

var time := 0.0

func _ready() -> void:
	time = material.get_shader_parameter("time")

func _process(delta: float) -> void:
	time += delta
	material.set_shader_parameter("time", time)
	
func on_change(param_value, param_name):
	material.set_shader_parameter(param_name, param_value)
