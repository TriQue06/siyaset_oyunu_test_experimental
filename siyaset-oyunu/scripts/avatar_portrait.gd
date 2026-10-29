class_name AvatarPortrait
extends Control
## Composes unmodified textures in one shared coordinate space. No per-frame work.
var appearance: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func set_appearance(value: Dictionary) -> void:
	appearance = AvatarCatalog.clean(value, String(value.get("gender", "m")))
	queue_redraw()

func _draw() -> void:
	if appearance.is_empty():
		return
	draw_portrait(self, appearance, Rect2(Vector2.ZERO, size))

static func draw_portrait(target: Control, value: Dictionary, area: Rect2) -> void:
	var factor := minf(area.size.x / 1254.0, area.size.y / 1550.0)
	var origin := area.position + (area.size - Vector2(1254, 1550) * factor) * 0.5
	var face := String(value.face)
	for category: String in ["face", "iris", "eyebrows", "beard", "moustache", "hair"]:
		var id: Variant = value.get(category)
		if id == null:
			continue
		if category == "iris":
			_draw_eyes(target, face, String(id), origin, factor)
			continue
		var rect := AvatarCatalog.layer_rect(String(id), face)
		var texture := AvatarCatalog.texture(String(id))
		if category in ["hair", "beard"]:
			# Subtle contact shade below the original layer; source colors stay untouched.
			for shift in [Vector2(-2, 3), Vector2(2, 4), Vector2(0, 6)]:
				target.draw_texture_rect(texture, Rect2(origin + (rect.position + shift) * factor, rect.size * factor), false, Color(0.12, 0.08, 0.05, 0.045))
		target.draw_texture_rect(texture, Rect2(origin + rect.position * factor, rect.size * factor), false)

static func _draw_eyes(target: Control, face: String, iris: String, origin: Vector2, factor: float) -> void:
	var info: Dictionary = AvatarCatalog.data().faces[face]
	for eye: Array in info.eyes:
		var center := Vector2(eye[0], eye[1])
		var width: float = info.eye_size[0]
		var height: float = info.eye_size[1]
		var iris_span: float = info.get("iris_span", 92.0)
		var points := PackedVector2Array()
		var uv := PackedVector2Array()
		# Almond-shaped clip stays inside the original white eye area.
		for step in 32:
			var angle := TAU * float(step) / 32.0
			var p := center + Vector2(cos(angle) * width * 0.5, sin(angle) * height * 0.5)
			points.append(origin + p * factor)
			uv.append((p - center) / iris_span + Vector2(0.5, 0.5))
		# The supplied iris is a ring with a transparent pupil opening.
		# A dark backing under that opening leaves all source PNG colors intact.
		target.draw_circle(origin + center * factor, iris_span * (11.0 / 92.0) * factor, Color("17100C"))
		target.draw_polygon(points, PackedColorArray([Color.WHITE]), uv, AvatarCatalog.texture(iris))
