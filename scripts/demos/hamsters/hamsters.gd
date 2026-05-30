extends ColorRect

var time := 0.0
var time_speed := 1.0

func _ready() -> void:
	time = material.get_shader_parameter("time")

func _process(delta: float) -> void:
	time += delta * time_speed
	material.set_shader_parameter("time", time)
	
func on_change(param_value, param_name) -> void:
	material.set_shader_parameter(param_name, param_value)
	
func on_set_time_speed(value: float) -> void:
	time_speed = value
