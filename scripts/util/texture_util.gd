extends Object
class_name TextureUtil

## Creates an image padded to the nearest pow2 >= real_size.
## Shaders work better with pow2 square textures so this padding is preferable.
## Uses the given format and disables mipmaps.
static func create_padded_img(real_size: int, format: Image.Format) -> Image:
	const use_mipmaps = false
	var s := nearest_po2(real_size)
	return Image.create(s, s, use_mipmaps, format)
