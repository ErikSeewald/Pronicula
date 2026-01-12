extends ColorRect

var time := 0.0

func _process(delta: float) -> void:
	time += delta
	material.set_shader_parameter("time", time)
