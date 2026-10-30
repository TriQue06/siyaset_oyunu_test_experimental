class_name AvatarColors
extends RefCounted
## Stable preset IDs travel through the existing appearance/save/network dictionaries.
## Gradients preserve the source's tonal detail; defaults retain the exact source RGB.
const FIELDS := ["skin_color", "lip_color", "iris_color", "hair_color", "eyebrow_color", "beard_color", "moustache_color"]
const HAIR := [
 ["jet", "Koyu siyah", "08090C", "17191E", "535760"],
 ["black", "Yumuşak siyah", "101013", "29272A", "66616A"],
 ["espresso", "Çok koyu kahve", "130E0D", "32221C", "755342"],
 ["brown", "Koyu kahve", "21150F", "593A25", "AD784B"],
 ["medium_brown", "Kahverengi", "291B16", "77513A", "BE9270"],
 ["light_brown", "Açık kahve", "3C2C21", "987451", "D2B18A"],
 ["chestnut", "Kestane", "321811", "78412C", "BA7950"],
 ["auburn", "Kızıl kahve", "361A16", "874332", "C7885D"],
 ["copper", "Bakır", "4A281B", "B66C36", "EEB573"],
 ["dark_blond", "Koyu sarı", "443720", "9B824C", "D7C38C"],
 ["gold", "Altın sarısı", "62451F", "C49C51", "F3DB94"],
 ["blond", "Açık sarı", "76603B", "D8BD80", "F8E8B7"],
 ["platinum", "Platin", "797163", "DFD7BE", "FBF7E8"],
 ["gray", "Gri", "38383B", "85858A", "C8C9CB"],
 ["silver", "Gümüş", "63666B", "BFC3C7", "ECEEF0"],
 ["white", "Beyaz", "858581", "E5E5DE", "FFFFF7"],
 ["blue_black", "Gece mavisi", "0B1421", "253C58", "6A849E"]]
const SKIN := [
 ["porcelain", "Çok açık", "76594F", "F3D9C5", "FFF0E0"],
 ["light", "Açık", "785044", "EAC1A4", "F9DDC4"],
 ["natural", "Açık buğday", "713E2B", "E6A77F", "F8CA9D"],
 ["medium", "Buğday", "573428", "BD8765", "DCAB84"],
 ["tan", "Esmer", "3E271F", "956448", "BC8964"],
 ["dark", "Koyu", "271A17", "674333", "92644B"],
 ["deep", "Çok koyu", "140F0E", "3D2923", "664737"]]
const MALE_LIPS := [
 ["natural", "Doğal", "512B24", "B77E69", "DDA791"],
 ["pale", "Açık doğal", "67483E", "C29A8B", "DEBBAC"],
 ["pink", "Doğal pembe", "593631", "B9827D", "DDA8A0"],
 ["warm", "Sıcak doğal", "583629", "B58066", "DBA98B"],
 ["rose_brown", "Gül kahvesi", "442A27", "8B5E56", "B78779"],
 ["brown", "Doğal kahve", "30201D", "69473D", "977061"]]
const FEMALE_LIPS := [
 ["natural", "Doğal nude", "512B24", "B77E69", "DDA791"],
 ["pink", "Yumuşak pembe", "70404D", "D693A1", "EDBCC4"],
 ["warm", "Sıcak pembe", "743D40", "D68186", "EDAAAC"],
 ["rose", "Gül", "672C3E", "B95773", "DE8CA0"],
 ["dusty", "Gül kurusu", "503039", "A76C7B", "CB9AA7"],
 ["peach", "Şeftali", "7D4738", "DE9C80", "F0BEA4"],
 ["coral", "Mercan", "7A302C", "DD6F61", "F39C86"],
 ["mauve", "Leylak", "493047", "9C708F", "C49BB6"],
 ["red", "Klasik kırmızı", "570F1B", "B62D41", "DC6570"],
 ["deep_red", "Koyu kırmızı", "340D16", "85243A", "B94B61"],
 ["wine", "Bordo", "2C1222", "64263F", "984C68"],
 ["brown", "Koyu nude", "35231F", "805445", "AF8370"]]
const EYES := [
 ["deep_brown", "Çok koyu kahve", "140E0A", "352419", "78603C"],
 ["brown", "Koyu kahve", "25160D", "6D4526", "C39B58"],
 ["medium_brown", "Kahverengi", "32200F", "8B6335", "D1AD68"],
 ["amber", "Kehribar", "503416", "B58B3E", "ECD58A"],
 ["hazel", "Ela", "353723", "86824A", "C2BA7C"],
 ["green", "Yeşil", "1A3325", "497C4E", "9DBE7C"],
 ["gray_green", "Gri yeşil", "2B3B36", "728D7B", "B9C7AD"],
 ["gray", "Gri", "2B353C", "7A8A94", "C3CDD1"],
 ["blue", "Mavi", "163047", "4C83AB", "A2C7DF"],
 ["light_blue", "Açık mavi", "314B5E", "8DB6CE", "D1E6EE"]]
const SHADER = preload("res://scripts/avatar_recolor.gdshader")
static var _materials: Dictionary = {}

static func palette(field: String, gender: String) -> Array:
	if field == "skin_color": return SKIN
	if field == "lip_color": return FEMALE_LIPS if gender == "f" else MALE_LIPS
	if field == "iris_color": return EYES
	return HAIR

static func default_id(field: String) -> String:
	return "natural" if field in ["skin_color", "lip_color"] else "brown"

static func clean(source: Dictionary, gender: String) -> Dictionary:
	var result := {}
	for field: String in FIELDS:
		var id: Variant = source.get(field, default_id(field))
		result[field] = default_id(field)
		for preset: Array in palette(field, gender):
			if id is String and id == preset[0]: result[field] = id
	return result

static func preset(field: String, value: Dictionary) -> Array:
	var id := String(value.get(field, default_id(field)))
	for option: Array in palette(field, String(value.get("gender", "m"))):
		if option[0] == id: return option
	return palette(field, String(value.get("gender", "m")))[0]

static func _set_gradient(mat: ShaderMaterial, prefix: String, option: Array) -> void:
	for i in 3:
		mat.set_shader_parameter(prefix + ["_shadow", "_base", "_light"][i], Color(option[i + 2]))

static func material_for(id: String, category: String, value: Dictionary) -> ShaderMaterial:
	var field := "eyebrow_color" if category == "eyebrows" else category + "_color"
	if category == "face": field = "skin_color"
	var selected := String(value.get(field, default_id(field)))
	var skin := String(value.get("skin_color", "natural"))
	var lip := String(value.get("lip_color", "natural"))
	var key := "%s:%s:%s:%s:%s" % [id, selected, skin, lip if category == "face" else "", value.get("gender", "m")]
	if _materials.has(key): return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("mode", 0 if category == "face" else (2 if category == "iris" else 1))
	mat.set_shader_parameter("keep_main", selected == default_id(field))
	mat.set_shader_parameter("keep_skin", skin == "natural")
	mat.set_shader_parameter("keep_lips", lip == "natural")
	_set_gradient(mat, "main", preset(field, value))
	_set_gradient(mat, "skin", preset("skin_color", value))
	_set_gradient(mat, "lip", preset("lip_color", value))
	if category != "iris":
		mat.set_shader_parameter("regions", load(AvatarCatalog.ROOT + "color_masks/" + id + ".png"))
	# Bound the shared cache: already visible controls retain their own material refs.
	if _materials.size() >= 256: _materials.clear()
	_materials[key] = mat
	return mat
