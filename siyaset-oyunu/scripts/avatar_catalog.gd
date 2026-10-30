class_name AvatarCatalog
extends RefCounted
## Original PNG canvases and individually calibrated attachments, in portrait pixels.
const ROOT := "res://assets/avatar/"
const CATEGORIES := ["face", "hair", "eyebrows", "iris", "moustache", "beard"]
const OPTIONAL := ["hair", "moustache", "beard"]
static var _catalog: Dictionary = {}
static var _textures: Dictionary = {}

static func data() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	return _catalog

static func options(category: String, gender: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in data().assets:
		var item: Dictionary = data().assets[id]
		if item.category == category and item.gender in [gender, "both"]:
			result.append(id)
	return result

static func clean(value: Variant, gender: String) -> Dictionary:
	gender = "f" if gender == "f" else "m"
	var source: Dictionary = value if value is Dictionary else {}
	var result := {"gender": gender}
	for category: String in CATEGORIES:
		var choices := options(category, gender)
		var selected: Variant = source.get(category)
		if selected is String and choices.has(selected):
			result[category] = selected
		elif OPTIONAL.has(category) or choices.is_empty():
			result[category] = null
		else:
			result[category] = choices[0]
	result.merge(AvatarColors.clean(source, gender))
	return result

static func texture(id: String) -> Texture2D:
	if not _textures.has(id):
		_textures[id] = load(ROOT + String(data().assets[id].file))
	return _textures[id]

static func contact_shadow(face: String, id: String) -> Texture2D:
	var key := face + "__" + id
	if not _textures.has(key):
		var path := ROOT + "contact_shadows/" + key + ".png"
		_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key]

static func layer_rect(id: String, face: String) -> Rect2:
	var item: Dictionary = data().assets[id]
	var tex := texture(id)
	var offset := Vector2(item.offset[0], item.offset[1])
	var extent := tex.get_size() * Vector2(item.scale[0], item.scale[1])
	var correction: Array = data().faces[face].corrections.get(item.category, [0, 0, 1, 1])
	# Corrections pivot at the face center, preserving symmetric attachments.
	offset.x = 627.0 + (offset.x - 627.0) * float(correction[2]) + float(correction[0])
	offset.y = 180.0 + (offset.y - 180.0) * float(correction[3]) + float(correction[1])
	extent *= Vector2(correction[2], correction[3])
	var fit: Array = data().faces[face].get("asset_corrections", {}).get(id, [0, 0, 1, 1])
	offset.x = 627.0 + (offset.x - 627.0) * float(fit[2]) + float(fit[0])
	offset.y = 180.0 + (offset.y - 180.0) * float(fit[3]) + float(fit[1])
	extent *= Vector2(fit[2], fit[3])
	return Rect2(offset, extent)
