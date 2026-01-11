## A 2D node container that allows dragging and scaling of its contents
## uniformly with mouse and touch controls.

extends Node2D
class_name FloatingContainer

var touches := {} # Currently active input touches
var last_pinch_distance := 0.0

var dragging := false
var last_drag_pos = Vector2.ZERO

func _input(event):
	_mouse_input(event)
	_touch_input(event)

## Checks for and handles mouse input in the given event.
func _mouse_input(event) -> void:
	const scale_speed := 0.05
	var mouse_pos = get_global_mouse_position()
	
	if Input.is_action_just_pressed("zoom_in"):
		zoom_to_center(mouse_pos, 1 + scale_speed)
	elif Input.is_action_just_pressed("zoom_out"):
		zoom_to_center(mouse_pos, 1 - scale_speed)
		
	if event.is_action_pressed("move_around"):
		dragging = true
		last_drag_pos = mouse_pos

	elif event.is_action_released("move_around"):
		dragging = false

	if event is InputEventMouseMotion:
		# Touch drag may cause this event too, only handle mouse drag here
		if dragging and touches.size() == 0:
			global_position += mouse_pos - last_drag_pos
			last_drag_pos = mouse_pos

## Checks for and handles touch input in the given event.
func _touch_input(event) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position

			if touches.size() == 2:
				var p = touches.values()
				last_drag_pos = (p[0] + p[1]) * 0.5

			if not _is_touch_over_ui():
				dragging = true
		else:
			touches.erase(event.index)

			# Ensure smooth dragging transition to a single finger
			if touches.size() == 1:
				last_drag_pos = touches.values()[0]
				last_pinch_distance = 0.0

			# Stop dragging entirely
			if touches.size() == 0:
				dragging = false
				last_drag_pos = Vector2.ZERO
				last_pinch_distance = 0.0

	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if dragging:
			match touches.size():
				1: _one_finger_drag()
				2: _two_finger_drag()

## Handles dragging with one finger.
func _one_finger_drag() -> void:
	var p = touches.values()[0]
	if last_drag_pos != Vector2.ZERO:
		global_position += p - last_drag_pos	
	last_drag_pos = p

## Handles zooming and dragging with two fingers
func _two_finger_drag() -> void:
	# Zoom
	var points = touches.values()
	var p1 = points[0]
	var p2 = points[1]

	var current_distance = p1.distance_to(p2)
	if last_pinch_distance == 0.0:
		last_pinch_distance = current_distance
		return

	var factor = current_distance / last_pinch_distance
	last_pinch_distance = current_distance
		
	var pinch_center = (p1 + p2) * 0.5
	zoom_to_center(pinch_center, factor)
	
	# Move
	if last_drag_pos != Vector2.ZERO:
		global_position += pinch_center - last_drag_pos	
	last_drag_pos = pinch_center

## Returns whether the current touch is over UI elements that should not
## allow dragging/zooming. Prevents stuff like slider interactions causing
## the container to move.
func _is_touch_over_ui() -> bool:
	var ui := get_viewport().gui_get_hovered_control()
	if ui == null:
		return false
	
	return ui.has_signal("pressed") \
		or ui.has_signal("text_changed") \
		or ui.has_signal("value_changed")

## Zooms toward the given center by the given factor
func zoom_to_center(center: Vector2, factor: float) -> void:
	var d = center - global_position
	global_position += d - d * factor
	scale *= factor
