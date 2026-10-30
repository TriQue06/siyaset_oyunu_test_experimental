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
		root.get_texture().get_image().save_png("res://../build/avatar-review/" + name + ("_en" if "--english" in OS.get_cmdline_user_args() else "") + ".png")
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
	for face: String in AvatarCatalog.data().faces:
		var layers := AvatarEyes.layers(face, "iris_03")
		check(face + " has two separately masked eyes", layers.size() == 2)
		var definitions: Array = AvatarCatalog.data().faces[face].eye_masks
		for eye_index in layers.size():
			var pixels: Image = layers[eye_index].texture.get_image()
			var mask: Image = load(AvatarCatalog.ROOT + String(definitions[eye_index].file)).get_image()
			var bounded := true
			var visible := 0
			for y in pixels.get_height():
				for x in pixels.get_width():
					var a := pixels.get_pixel(x, y).a
					if a > mask.get_pixel(x, y).a + 0.005:
						bounded = false
					if a > 0.5:
						visible += 1
			check(face + " eye %d stays inside white and remains visible" % eye_index, bounded and visible > 1500)
		check(face + " reuses cached eye layers", AvatarEyes.layers(face, "iris_03")[0].texture == layers[0].texture)
	for face: String in AvatarCatalog.data().faces:
		var gender: String = AvatarCatalog.data().assets[face].gender
		for category: String in ["hair", "beard", "moustache"]:
			for asset: String in AvatarCatalog.options(category, gender):
				var shadow := AvatarCatalog.contact_shadow(face, asset)
				check(face + "/" + asset + " has a cached face-specific shadow", shadow != null and shadow == AvatarCatalog.contact_shadow(face, asset))
	check("palette counts", AvatarColors.SKIN.size() == 7 and AvatarColors.MALE_LIPS.size() == 6 and AvatarColors.FEMALE_LIPS.size() == 12 and AvatarColors.EYES.size() == 10 and AvatarColors.HAIR.size() == 17)
	var legacy := AvatarCatalog.clean({"hair": "hair_08"}, "m")
	check("legacy appearances receive original colors", legacy.skin_color == "natural" and legacy.hair_color == "brown" and legacy.lip_color == "natural")
	var invalid := AvatarCatalog.clean({"skin_color": "../../invalid", "hair_color": 5, "lip_color": "wine"}, "m")
	check("colors validate IDs and gender lip palette", invalid.skin_color == "natural" and invalid.hair_color == "brown" and invalid.lip_color == "natural")
	var bad := AvatarCatalog.clean({"face": "../../invalid", "hair": "hair_24", "beard": "beard_02", "unexpected": 1}, "f")
	check("gender compatibility and safe identifiers", bad.face == "face_12" and bad.hair == "hair_24" and bad.beard == null and not bad.has("unexpected"))
	if "--english" in OS.get_cmdline_user_args(): TranslationServer.set_locale("en")
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
	editor._select_color("skin_color", "deep")
	editor._select_color("lip_color", "brown")
	editor._select_color("hair_color", "black")
	editor._select_color("eyebrow_color", "espresso")
	editor._select_color("beard_color", "gray")
	editor._select_color("moustache_color", "white")
	editor._select_color("iris_color", "green")
	check("independent colors update live preview", editor._preview.appearance.hair_color == "black" and editor._preview.appearance.beard_color == "gray" and editor._preview.appearance.moustache_color == "white" and editor._preview.appearance.eyebrow_color == "espresso" and editor._preview.appearance.skin_color == "deep" and editor._preview.appearance.lip_color == "brown" and editor._preview.appearance.iris_color == "green")
	await frames()
	check("live preview follows visual selection", editor._preview.appearance.hair == "hair_16")
	check("incomplete setup retains structured draft", pm.my_politician.appearance.beard == "beard_02")
	await shot("editor_male")
	editor._select_gender("f")
	editor._select("hair", "hair_26")
	editor._select_color("lip_color", "wine")
	editor._select_color("hair_color", "copper")
	editor._choose_category("face")
	await frames()
	check("female has no beard or moustache tabs", editor._tabs.get_child_count() == 4 and editor.appearance.beard == null and editor.appearance.moustache == null)
	check("female face and eyebrows compatible", editor.appearance.face == "face_12" and editor.appearance.eyebrows == "brow_04")
	await shot("editor_female")
	editor._select_gender("m")
	check("switch back preserves independent color selections", editor.appearance.hair_color == "black" and editor.appearance.beard_color == "gray" and editor.appearance.lip_color == "brown")
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
