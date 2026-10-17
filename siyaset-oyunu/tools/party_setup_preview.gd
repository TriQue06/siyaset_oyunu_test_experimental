extends SceneTree
## Parti kurma sihirbazı önizlemesi + testi: beş adım, aday kartı, renk kilidi,
## memleket tıklaması (gerçek fare olayıyla), hazır akışı, oda sahibinin bot
## düzenlemesi. Ekran görüntüleri user:// içine party_setup_<adım>.png.
##   godot --resolution 1600x900 --path . --script res://tools/party_setup_preview.gd

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/party_setup_%s.png" % [OS.get_user_data_dir(), name])

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var gmap = root.get_node("GameMap")
	gmap.generate_new(4242)
	var colors: Array = load("res://scripts/party_presets.gd").COLORS
	var me: int = root.multiplayer.get_unique_id()
	mm.room_code = ""
	mm.owner_id = me
	mm.players = {me: {"name": "Barış"}, 77: {"name": "Ayşe"}}
	pm.parties = {77: {"name": "Yeşiller", "icon_index": 2, "icon_color": Color.WHITE, "bg_color": colors[0], "core": ["isci", "dindar"], "groups": VoterGroups.start_affinities(["isci", "dindar"]), "ready": true}}
	pm.politicians = {}
	pm.my_politician = {}
	for i in 3:
		var id: int = mm.BOT_ID_BASE - i
		mm.players[id] = {"name": "Bot %d" % i, "bot": true}
		pm.add_bot_party(id)
		check("bot %d oyuncunun rengini almadi" % i, not Color(pm.parties[id]["bg_color"]).is_equal_approx(colors[0]))

	var scene: Node = (load("res://scenes/PartySetup.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(6)
	check("sihirbaz ilk adimda", scene._step == 0)
	check("rastgele ad geldi", scene._first_name != "" and scene._surname != "")
	check("odada 5 oyuncu", scene._players_list.get_child_count() == 5, str(scene._players_list.get_child_count()))
	check("eksikken hazir olunamaz", not scene._missing_steps().is_empty())
	_shot("1_siyasetci")

	scene._show_step(1)
	scene._on_background_pressed("gazeteci")
	scene._on_trait_pressed("sert")
	await _frames(3)
	check("meslek ve kisilik adimi tamam", scene._step_done(1))
	_shot("2_meslek")

	scene._show_step(2)
	await _frames(4)
	var target := String(gmap.province_ids()[3])
	var pos: Vector2 = scene._map.get_global_transform() * gmap.center_of(target)
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	root.push_input(move, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev, true)
		await process_frame
	check("memleket gercek tiklamayla secildi", scene._hometown == target, "%s / %s" % [target, scene._hometown])
	check("siyasetci tamamlaninca gonderildi", pm.politicians.has(me) and pm.politicians[me]["background"] == "gazeteci"
		and pm.politicians[me]["trait"] == "sert" and pm.politicians[me]["hometown"] == target)
	check("portre alani var (bos)", pm.politicians.get(me, {}).get("portrait", "x") == "")
	_shot("3_memleket")

	scene._show_step(3)
	scene._name_edit.text = "Deneme"
	scene._on_party_name_changed("Deneme")
	await _frames(3)
	check("benim rengim Ayse'ninkinden farkli", not Color(pm.parties[me]["bg_color"]).is_equal_approx(colors[0]))
	pm.set_my_party("Deneme", 1, Color.WHITE, colors[0], scene._core)
	check("baskasinin rengi reddedildi", not Color(pm.parties[me]["bg_color"]).is_equal_approx(colors[0]))
	var bot: int = mm.BOT_ID_BASE
	var bot_color: Color = pm.parties[bot]["bg_color"]
	scene._on_color_selected(colors.find(bot_color))
	await _frames(2)
	check("botun rengini aldim", Color(pm.parties[me]["bg_color"]).is_equal_approx(bot_color))
	check("bot baska renge gecti", not Color(pm.parties[bot]["bg_color"]).is_equal_approx(bot_color))
	scene._on_icon_selected(6)
	await _frames(3)
	check("logo secildi", int(pm.parties[me]["icon_index"]) == 6)
	_shot("4_kimlik")

	check("secmen adimi gorulmeden hazir olunamaz", not scene._step_done(4))
	scene._show_step(4)
	scene._on_core_pressed("genc")
	await _frames(3)
	check("cekirdek gecerli ve partide", VoterGroups.is_valid_core(pm.parties[me]["core"]) and pm.parties[me]["core"].has("genc"))
	check("her adim tamam", scene._missing_steps().is_empty(), str(scene._missing_steps()))
	_shot("5_secmen")

	# Oda sahibi bot düzenler.
	var my_before: Dictionary = pm.parties[me].duplicate()
	var edited_bot: int = mm.BOT_ID_BASE - 1
	scene._start_editing(edited_bot)
	await _frames(3)
	check("bot duzenlemede ilk adim", scene._step == 0 and scene._editing_bot())
	scene._name_edit.text = "Robotlar"
	scene._on_party_name_changed("Robotlar")
	scene._on_icon_selected(3)
	scene._on_background_pressed("hukukcu")
	scene._on_trait_pressed("teknokrat")
	var bot_home := String(gmap.province_ids()[5])
	scene._on_province_clicked(bot_home)
	await _frames(3)
	var bot_party: Dictionary = pm.parties[edited_bot]
	check("oda sahibi botun adini ve logosunu degistirdi", bot_party["name"] == "Robotlar" and int(bot_party["icon_index"]) == 3, str(bot_party))
	var bot_pol: Dictionary = pm.politicians[edited_bot]
	check("oda sahibi botun meslegini, kisiligini, memleketini degistirdi", bot_pol["background"] == "hukukcu"
		and bot_pol["trait"] == "teknokrat" and bot_pol["hometown"] == bot_home, str(bot_pol))
	check("kendi partim degismedi", pm.parties[me]["name"] == my_before["name"] and int(pm.parties[me]["icon_index"]) == int(my_before["icon_index"]))
	_shot("bot")
	var changed := 0
	for n in 5:
		var core_before: Array = (pm.parties[edited_bot]["core"] as Array).duplicate()
		scene._on_bot_random_pressed()
		await _frames(2)
		var core_after: Array = pm.parties[edited_bot]["core"]
		check("ekrandaki cekirdek = botun cekirdegi", scene._core == core_after, "%s / %s" % [scene._core, core_after])
		if not (core_after.has(core_before[0]) and core_after.has(core_before[1])):
			changed += 1
	check("bot profili rastgele: cekirdek gruplar yenilendi", changed >= 4, "%d/5 degisti" % changed)
	scene._start_editing(-1)
	await _frames(3)
	check("kendime donunce taslak geri geldi", scene._party_name == "Deneme" and scene._background_id == "gazeteci"
		and scene._name_edit.text == "Deneme" and scene._step == 4)

	# Hazır: siyasetçi + parti birlikte; kilitliyken içerik kapalı.
	scene._on_next_pressed()
	await _frames(3)
	check("hazir oldum", pm.is_ready(me) and scene._is_locked and scene._blocker.visible)
	scene._on_province_clicked(String(gmap.province_ids()[0]))
	check("kilitliyken memleket degismez", scene._hometown == target)
	_shot("hazir")
	scene._on_next_pressed()
	await _frames(2)
	check("hazirligi iptal ettim", not pm.is_ready(me) and not scene._is_locked)

	# Sahne yeniden açılınca (geri dönüş / yeniden bağlanma) taslak yerinde.
	scene.queue_free()
	await _frames(2)
	var again: Node = (load("res://scenes/PartySetup.tscn") as PackedScene).instantiate()
	root.add_child(again)
	await _frames(4)
	check("yeniden acilinca secimler yerinde", again._background_id == "gazeteci" and again._trait_id == "sert"
		and again._hometown == target and again._party_name == "Deneme")
	mm.owner_id = 77
	check("oda sahibi olmayan bot partisini degistiremez", (func():
		pm.set_bot_party(edited_bot, "Hacker", 0, colors[1]); return pm.parties[edited_bot]["name"] == "Robotlar").call())
	print("=== PARTY SETUP PREVIEW: %s ===" % ("PASS" if fails == 0 else "%d HATA" % fails))
	quit()
