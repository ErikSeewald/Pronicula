@tool
extends EditorPlugin

var floating_container_script := preload("floating_container.gd")

func _enter_tree() -> void:
	add_custom_type("FloatingContainer", "Node2D", floating_container_script, null)

func _exit_tree() -> void:
	remove_custom_type("FloatingContainer")
