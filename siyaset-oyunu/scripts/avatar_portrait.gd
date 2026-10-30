class_name AvatarPortrait
extends Control
## The original calibrated composition, with per-layer GPU color mapping.
## No per-frame CPU work, pixel scanning, or geometry changes.
var appearance: Dictionary = {}
var _layers: Array[TextureRect] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(_layout)
	_layout()

func set_appearance(value: Dictionary) -> void:
	appearance = AvatarCatalog.clean(value, String(value.get("gender", "m")))
	for layer in _layers:
		remove_child(layer)
		layer.queue_free()
	_layers.clear()
	var face := String(appearance.face)
	for category: String in ["face", "iris", "eyebrows", "beard", "moustache", "hair"]:
		var id: Variant = appearance.get(category)
		if id == null: continue
		var mat := AvatarColors.material_for(String(id), category, appearance)
		if category == "iris":
			for eye: Dictionary in AvatarEyes.layers(face, String(id)):
				_add_layer(eye.texture, eye.rect, mat)
			continue
		if category in ["hair", "beard", "moustache"]:
			var shadow := AvatarCatalog.contact_shadow(face, String(id))
			if shadow != null:
				_add_layer(shadow, Rect2(0, 0, 1254, 1550), null)
		_add_layer(AvatarCatalog.texture(String(id)), AvatarCatalog.layer_rect(String(id), face), mat)
	_layout()

func _add_layer(texture: Texture2D, rect: Rect2, mat: Material) -> void:
	var layer := TextureRect.new()
	layer.texture = texture
	layer.material = mat
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_meta("portrait_rect", rect)
	add_child(layer)
	_layers.append(layer)

func _layout() -> void:
	var factor := minf(size.x / 1254.0, size.y / 1550.0)
	var origin := (size - Vector2(1254, 1550) * factor) * 0.5
	for layer in _layers:
		var rect: Rect2 = layer.get_meta("portrait_rect")
		layer.position = origin + rect.position * factor
		layer.size = rect.size * factor
