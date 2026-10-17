class_name ContentPacks
extends RefCounted
## İÇERİK PAKETLERİ — ALTYAPI (oyunda henüz arayüzü yok, oyuncuya gösterilmez).
## Dış içerik iki türlüdür:
##   MOD: dosya taşıyan paket (parti logoları, siyasetçi portreleri; ileride
##     harita). Lobideki HERKESİN aynı modları yüklemiş olması gerekir: modlar
##     ağ imzasına girer (signature -> MultiplayerManager.network_signature),
##     farklı mod setiyle odaya katılınamaz.
##   AYAR PAKETİ: yalnız veri (lobi ayarları; ileride hazır parti/siyasetçi).
##     Oda sahibi lobiye uygular, değerler RPC ile yayılır; kimse dosya
##     indirmez (bkz. LobbyPreset).
## İçerik kimlikleri "<paket>:<ad>" biçimindedir; yerleşik içerik paketi "base".
##   Portre: "base:<ad>" -> PORTRAITS_DIR/<ad>.png, "<mod>:<ad>" -> modun portresi.
## MOD KLASÖRÜ: mods_dir/<klasör>/mod.json =
##   {"id": "...", "version": "1", "title": "...",
##    "portraits": "portraits",      # klasör: <ad>.png/.jpg/.webp
##    "party_icons": "party_icons"}  # klasör: .svg/.png (yerleşik ikonların ARKASINA eklenir)
## mods_enabled kapalıyken hiçbir mod taranmaz (oyun bugünkü gibi davranır).
## Testler klasörü ve anahtarı değiştirip scan() çağırabilir.

static var mods_enabled := false
static var mods_dir := "user://mods"
const MANIFEST := "mod.json"
const BASE := "base"
const PORTRAITS_DIR := "res://assets/portraits"
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const ICON_EXTENSIONS := ["svg", "png"]

## [{id, version, title, dir, portraits: {ad: yol}, party_icons: [yol]}]
static var _mods: Array = []
static var _scanned := false
static var _texture_cache: Dictionary = {}

## Mod klasörünü (yeniden) tarar. Geçersiz manifestler atlanır.
static func scan() -> void:
	_mods.clear()
	_texture_cache.clear()
	_scanned = true
	if not mods_enabled:
		return
	var dir := DirAccess.open(mods_dir)
	if dir == null:
		return
	var seen := {}
	for folder in dir.get_directories():
		var mod := _read_mod(mods_dir.path_join(folder))
		if mod.is_empty() or seen.has(mod["id"]):
			continue
		seen[mod["id"]] = true
		_mods.append(mod)
	_mods.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))

static func _read_mod(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path.path_join(MANIFEST))
	var manifest = JSON.parse_string(text) if text != "" else null
	if not manifest is Dictionary:
		return {}
	var id := clean_id(String(manifest.get("id", "")))
	if id == "" or id == BASE:
		return {}
	var mod := {"id": id, "version": String(manifest.get("version", "1")),
		"title": String(manifest.get("title", id)), "dir": path, "portraits": {}, "party_icons": []}
	var portraits_dir := String(manifest.get("portraits", ""))
	if portraits_dir != "":
		for file in _files(path.path_join(portraits_dir), IMAGE_EXTENSIONS):
			mod["portraits"][clean_id(file.get_file().get_basename())] = file
	var icons_dir := String(manifest.get("party_icons", ""))
	if icons_dir != "":
		mod["party_icons"] = _files(path.path_join(icons_dir), ICON_EXTENSIONS)
	return mod

static func _files(path: String, extensions: Array) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for file in dir.get_files():
		if extensions.has(file.get_extension().to_lower()):
			out.append(path.path_join(file))
	out.sort()
	return out

## Kimlik parçası: küçük harf, rakam, "_" ve "-" (dosya adı ve ağ için güvenli).
static func clean_id(text: String) -> String:
	var out := ""
	for ch in text.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	return out.left(48)

static func active_mods() -> Array:
	if not _scanned:
		scan()
	return _mods

## Ağ imzasına eklenen mod listesi ("" = mod yok; imza bugünküyle aynı kalır).
static func signature() -> String:
	var parts: Array = []
	for mod in active_mods():
		parts.append("%s@%s" % [mod["id"], mod["version"]])
	return "+".join(parts)

## Yerleşik ikonların ardına eklenecek mod parti ikonları (mod sırasıyla).
static func extra_icon_paths() -> Array:
	var out: Array = []
	for mod in active_mods():
		out.append_array(mod["party_icons"])
	return out

## Mod ikon dosyasının kalıcı kimliği ("<mod>:<dosya>"); bulunamazsa "".
static func icon_id_for_path(path: String) -> String:
	for mod in active_mods():
		if (mod["party_icons"] as Array).has(path):
			return "%s:%s" % [mod["id"], clean_id(path.get_file().get_basename())]
	return ""

# --- Portreler -------------------------------------------------------------------

## Portre kimliğinin dosya yolu; çözülemezse "".
static func portrait_path(portrait_id: String) -> String:
	var parts := portrait_id.split(":", false, 1)
	if parts.size() != 2:
		return ""
	if parts[0] == BASE:
		for ext in IMAGE_EXTENSIONS:
			var path := PORTRAITS_DIR.path_join("%s.%s" % [clean_id(parts[1]), ext])
			if ResourceLoader.exists(path) or FileAccess.file_exists(path):
				return path
		return ""
	for mod in active_mods():
		if mod["id"] == parts[0]:
			return String(mod["portraits"].get(clean_id(parts[1]), ""))
	return ""

static func has_portrait(portrait_id: String) -> bool:
	return portrait_id != "" and portrait_path(portrait_id) != ""

## Seçilebilir bütün portre kimlikleri (yerleşik + modlar).
static func portrait_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(PORTRAITS_DIR)
	if dir != null:
		for file in dir.get_files():
			var file_name := file.trim_suffix(".import").trim_suffix(".remap")
			if IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
				var id := "%s:%s" % [BASE, clean_id(file_name.get_basename())]
				if not out.has(id):
					out.append(id)
	for mod in active_mods():
		for key in mod["portraits"].keys():
			out.append("%s:%s" % [mod["id"], key])
	return out

## Portre dokusu (önbellekli); yoksa null — çağıran baş harfli rozete düşer.
static func portrait_texture(portrait_id: String) -> Texture2D:
	if portrait_id == "":
		return null
	if _texture_cache.has(portrait_id):
		return _texture_cache[portrait_id]
	var path := portrait_path(portrait_id)
	var texture: Texture2D = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif path != "":
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_texture_cache[portrait_id] = texture
	return texture
