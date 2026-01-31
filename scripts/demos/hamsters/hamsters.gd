extends ColorRect

var time := 0.0

func _process(delta: float) -> void:
	time += delta * 3.0
	material.set_shader_parameter("time", time)
