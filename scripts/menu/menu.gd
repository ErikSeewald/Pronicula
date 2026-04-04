extends Control

func launch_hamsters():
	get_tree().change_scene_to_file("res://scenes/demos/Hamsters.tscn")

func launch_trains():
	get_tree().change_scene_to_file("res://scenes/demos/Trains.tscn")

func launch_splesh_demo():
	get_tree().change_scene_to_file("res://scenes/demos/splesh.tscn")

func launch_switching_tiles():
	get_tree().change_scene_to_file("res://scenes/demos/SwitchingTiles.tscn")
