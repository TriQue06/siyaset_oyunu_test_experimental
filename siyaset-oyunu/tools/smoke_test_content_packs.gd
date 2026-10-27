extends SceneTree
## İÇERİK PAKETİ ALTYAPISI TESTİ: mod taraması (portre, parti logosu, ağ imzası),
## siyasetçi portre alanı ve ayar paketinin (LobbyPreset) gidiş-dönüşü.
##   godot --headless --path . --script res://tools/smoke_test_content_packs.gd

const TEST_DIR := "user://test_mods"

var _failed := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failed += 1
	print("  [%s]  %s%s" % ["OK" if ok else "HATA", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var presets = root.get_node("PartyPresets")
	var CP = load("res://scripts/content_packs.gd")
	var PP = load("res://scripts/politician_presets.gd")
	var LP = load("res://scripts/lobby_preset.gd")
	print("=== ICERIK PAKETLERI ===")

	# Varsayılan: mod yok, oyun bugünkü gibi.
	check("modlar varsayilan kapali", not CP.mods_enabled and CP.active_mods().is_empty())
	check("ag imzasi = oyun surumu", mm.network_signature() == mm.game_version(), mm.network_signature())
	var base_icons: int = presets.icon_count()
	check("logo kimligi kalici", presets.icon_id(0).begins_with("base:") and presets.icon_index_of(presets.icon_id(4)) == 4)

	# Portre alanı: biçim temizlenir, bozuk kimlik boş kalır.
	var data: Dictionary = PP.make("Ayla", "Gökyelken", "gazeteci", "", "f", "Demo:Ayla Foto")
	check("portre kimligi temizlenir", data["portrait"] == "demo:aylafoto", data["portrait"])
	check("bozuk portre bos kalir", PP.make("A", "B", "gazeteci", "", "m", "bozuk")["portrait"] == "")
	check("bas harfler", PP.initials(data) == "AG")
	check("cozulemeyen portrenin dokusu yok", CP.portrait_texture("base:yok") == null and not CP.has_portrait("base:yok"))
	var portrait = load("res://scripts/politician_portrait.gd").make(data, Color.RED, 64.0)
	root.add_child(portrait)
	await process_frame
	check("portre portresiz de cizilir", portrait.size.x >= 64.0)
	portrait.queue_free()

	# Örnek mod: bir portre + bir parti logosu.
	_make_demo_mod()
	CP.mods_dir = TEST_DIR
	CP.mods_enabled = true
	CP.scan()
	check("mod bulundu", CP.active_mods().size() == 1 and CP.active_mods()[0]["id"] == "demo", str(CP.active_mods()))
	check("mod ag imzasina girer", mm.network_signature() == "%s|demo@2" % mm.game_version(), mm.network_signature())
	check("mod portresi cozulur", CP.has_portrait("demo:ayla") and CP.portrait_texture("demo:ayla") != null)
	check("mod portresi listede", CP.portrait_ids().has("demo:ayla"))
	presets._scan_icons()
	check("mod logosu yerlesiklerin arkasina eklendi", presets.icon_count() == base_icons + 1, "%d" % presets.icon_count())
	check("mod logosu cizilir", presets.get_icon_texture(base_icons, 64) != null)
	check("mod logosunun kimligi", presets.icon_id(base_icons) == "demo:kalkan", presets.icon_id(base_icons))
	check("yerlesik indeksler degismedi", presets.icon_id(0).begins_with("base:"))
	CP.mods_enabled = false
	CP.scan()
	presets._scan_icons()
	check("mod kapatilinca eski haline doner", presets.icon_count() == base_icons and mm.network_signature() == mm.game_version())
	_remove_dir(TEST_DIR)

	# Ayar paketi: yakala -> JSON -> değiştir -> uygula -> eski ayarlar geri gelir.
	print("=== AYAR PAKETI ===")
	mm.start_offline("Barış")
	var pack: Dictionary = LP.capture("Test")
	pack["lobby"]["threshold"] = 7.0
	pack["lobby"]["vote_seconds"] = 45
	pack["lobby"]["away_mode"] = mm.AWAY_PASSIVE
	pack["lobby"]["map_seed"] = "12345"
	pack["lobby"]["world"]["turn_seconds"] = 90
	pack["lobby"]["world"]["province_seats"] = 400
	var parsed: Dictionary = LP.from_json(LP.to_json(pack))
	check("paket JSON gidis-donusu", not parsed.is_empty() and parsed["title"] == "Test")
	check("paket uygulanir", LP.apply(parsed))
	check("baraj", is_equal_approx(mm.election_threshold, 7.0), str(mm.election_threshold))
	check("oylama suresi", mm.vote_timeout == 45)
	check("dusen oyuncu ayari", mm.away_mode == mm.AWAY_PASSIVE)
	check("harita tohumu", mm.map_seed == "12345")
	check("dunya ayarlari (JSON sayilari)", int(mm.world_settings["turn_seconds"]) == 90 and int(mm.world_settings["province_seats"]) == 400,
		str(mm.world_settings))
	check("eksik mod isteyen paket uygulanmaz", not LP.apply({"format": 1, "requires": ["yok"], "lobby": {"threshold": 3.0}})
		and is_equal_approx(mm.election_threshold, 7.0))
	check("gelecek surum paketi reddedilir", LP.from_json('{"format": 99}').is_empty())
	var owner: int = mm.owner_id
	mm.owner_id = -5
	check("oda sahibi olmayan paket uygulayamaz", not LP.apply(parsed))
	mm.owner_id = owner
	print("=== ICERIK PAKETLERI: %s ===" % ("PASS" if _failed == 0 else "%d HATA" % _failed))
	quit(1 if _failed > 0 else 0)

func _make_demo_mod() -> void:
	_remove_dir(TEST_DIR)
	var root_dir := TEST_DIR.path_join("demo_klasor")
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("portraits"))
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("party_icons"))
	var manifest := FileAccess.open(root_dir.path_join("mod.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"id": "Demo", "version": "2", "title": "Demo",
		"portraits": "portraits", "party_icons": "party_icons"}))
	manifest.close()
	var image := Image.create(32, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.ORANGE)
	image.save_png(root_dir.path_join("portraits/Ayla.png"))
	var svg := FileAccess.get_file_as_string("res://assets/icons/icon_01.svg")
	var icon := FileAccess.open(root_dir.path_join("party_icons/kalkan.svg"), FileAccess.WRITE)
	icon.store_string(svg)
	icon.close()

func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
