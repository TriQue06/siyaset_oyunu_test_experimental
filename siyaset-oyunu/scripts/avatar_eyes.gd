class_name AvatarEyes
extends RefCounted
## Small, cached eye patches: every painted iris pixel is clipped by the source
## face's eye-white coverage. Eyelids and skin are always the original face art.
static var _cache: Dictionary = {}

static func layers(face: String, iris: String) -> Array:
	var key := face + ":" + iris
	if _cache.has(key):
		return _cache[key]
	var info: Dictionary = AvatarCatalog.data().faces[face]
	var span := int(info.get("iris_span", 92))
	var source := AvatarCatalog.texture(iris).get_image()
	if source.is_compressed():
		source.decompress()
	source.resize(span, span, Image.INTERPOLATE_LANCZOS)
	var result: Array = []
	for eye: Dictionary in info.eye_masks:
		var mask: Image = load(AvatarCatalog.ROOT + String(eye.file)).get_image()
		if mask.is_compressed():
			mask.decompress()
		var image := Image.create(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8)
		var origin := Vector2(eye.rect[0], eye.rect[1])
		var center := Vector2(eye.center[0], eye.center[1])
		for y in image.get_height():
			for x in image.get_width():
				var coverage := mask.get_pixel(x, y).a
				if coverage <= 0.0:
					continue
				var delta := origin + Vector2(x + 0.5, y + 0.5) - center
				var sample := Vector2i((delta + Vector2.ONE * span * 0.5).floor())
				if sample.x < 0 or sample.y < 0 or sample.x >= span or sample.y >= span:
					continue
				var color := source.get_pixelv(sample)
				# The provided iris has a transparent central pupil. Its backing is
				# composited BEFORE applying the same eye mask, never drawn outside it.
				if delta.length() < span * (11.0 / 92.0):
					var pupil := Color("17100C")
					color = pupil.blend(color)
				color.a *= coverage
				image.set_pixel(x, y, color)
		result.append({"texture": ImageTexture.create_from_image(image), "rect": Rect2(origin, Vector2(mask.get_size()))})
	_cache[key] = result
	return result
