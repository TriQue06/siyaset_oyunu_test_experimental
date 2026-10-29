extends SceneTree
var fails := 0
func check(label: String, ok: bool) -> void:
	print("[OK] " if ok else "[FAIL] ", label)
	if not ok: fails += 1
func frames(n: int = 4) -> void:
	for i in n: await process_frame
func shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/avatar-review/" + name + ".png")
func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var map = root.get_node("GameMap")
	root.get_node("BotManager").set_process(false)
	map.generate_new(4242)
	var me := root.multiplayer.get_unique_id()
	mm.room_code = ""
	mm.owner_id = me
	mm.players = {me: {"name": "Barış"}}
	pm.parties = {}
	pm.politicians = {}
	pm.my_politician = {}
	check("all 40 supplied pieces catalogued", AvatarCatalog.data().assets.size() == 40)
	var bad := AvatarCatalog.clean({"face": "../../invalid", "hair": "hair_24", "beard": "beard_02", "unexpected": 1}, "f")
	check("gender compatibility and safe identifiers", bad.face == "face_12" and bad.hair == "hair_24" and bad.beard == null and not bad.has("unexpected"))
	var scene = load("res://scenes/PartySetup.tscn").instantiate()
	root.add_child(scene)
	await frames()
	scene._open_avatar_editor()
	await frames()
	var editor = scene._avatar_editor
	check("editor opens from setup", is_instance_valid(editor))
	editor._choose_category("hair")
	editor._select("hair", "hair_16")
	editor._select("beard", "beard_02")
	editor._select("moustache", "moustache_15")
	await frames()
	check("live preview follows visual selection", editor._preview.appearance.hair == "hair_16")
	check("incomplete setup retains structured draft", pm.my_politician.appearance.beard == "beard_02")
	await shot("editor_male")
	editor._select_gender("f")
	editor._select("hair", "hair_26")
	await frames()
	check("female has no beard or moustache tabs", editor._tabs.get_child_count() == 4 and editor.appearance.beard == null and editor.appearance.moustache == null)
	check("female face and eyebrows compatible", editor.appearance.face == "face_12" and editor.appearance.eyebrows == "brow_04")
	await shot("editor_female")
	editor._select_gender("m")
	check("switch back preserves male selections", editor.appearance.beard == "beard_02" and editor.appearance.hair == "hair_16")
	editor.queue_free()
	await frames()
	scene._on_background_pressed("gazeteci")
	scene._on_province_clicked(String(map.province_ids()[0]))
	var expected: Dictionary = scene._appearance.duplicate(true)
	check("host keeps appearance", pm.politicians[me].appearance == expected)
	var packed: Dictionary = load("res://scripts/save_game.gd")._collect()
	var path := "user://avatar-roundtrip.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(packed)
	file.close()
	file = FileAccess.open(path, FileAccess.READ)
	var restored: Dictionary = file.get_var()
	file.close()
	check("save serialization retains all appearance fields", restored.pm.politicians[me].appearance == expected and restored.pm.my_politician.appearance == expected)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	scene.free()
	scene = load("res://scenes/PartySetup.tscn").instantiate()
	root.add_child(scene)
	await frames()
	check("reopened setup restores appearance", scene._appearance == expected)
	await shot("setup_avatar")
	scene._is_locked = true
	scene._open_avatar_editor()
	check("ready players cannot change appearance", not is_instance_valid(scene._avatar_editor))
	scene.free()
	await frames()
	print("AVATAR FAILURES: ", fails)
	quit(1 if fails else 0)
