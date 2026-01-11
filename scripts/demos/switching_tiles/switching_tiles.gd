extends ColorRect

@export var grid_size := 5:
	set(value):
		grid_size = value
		_on_set_grid_size()

@export var speed := 0.5

const DIRECTIONS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

var time := 0.0
var _img: Image
var _tex: ImageTexture

func set_grid_size(s) -> void:
	set("grid_size", s)
	
func set_speed(s) -> void:
	speed = s
	
func _ready() -> void:
	_on_set_grid_size()

func _process(delta: float) -> void:
	time += delta
	
	# Switch two squares
	if time > speed:
		time = 0.0
		var from = Vector2i(int(randf()*grid_size), int(randf()*grid_size))
		var direction = int(randf() * len(DIRECTIONS))
		var to = from+DIRECTIONS[direction]
		while to.x < 0 or to.x >= grid_size or to.y < 0 or to.y >= grid_size:
			direction = (direction + 1) % len(DIRECTIONS)
			to = from+DIRECTIONS[direction]
		
		var from_col: Color = _img.get_pixel(from.x, from.y)
		var to_col: Color = _img.get_pixel(to.x, to.y)
		
		# Prev state of 'to' in green channel so the shader can animate
		# the new state replacing it.
		_img.set_pixel(from.x, from.y, to_col)
		_img.set_pixel(to.x, to.y, Color(from_col.r, to_col.r, 0.0))
		_tex.update(_img)
		
		material.set_shader_parameter("move_to", Vector2i(to))
		material.set_shader_parameter("move_from", Vector2i(from))
		material.set_shader_parameter("move_dir", direction)
		
	# Shader only expects time to be 0.0 (start moving) to 1.0 (move finished)
	material.set_shader_parameter("time", time / speed)

## Resets the grid texture to the new dimensions and sends it to the shader
func _on_set_grid_size() -> void:
	_img = TextureUtil.create_padded_img(grid_size, Image.FORMAT_RGB8)
	for x in range(grid_size):
		for y in range(grid_size):
			_img.set_pixel(x, y, Color(randf(), 0.0, 0.0))
	_tex = ImageTexture.create_from_image(_img)
	
	material.set_shader_parameter("grid_tex", _tex)
	material.set_shader_parameter("grid_size", grid_size)	
