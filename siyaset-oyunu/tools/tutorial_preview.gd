extends SceneTree
## İLK OYUN REHBERİ ÖNİZLEMESİ: 10 adım sırayla açılır, her birinin görüntüsü alınır.
## destekleri), yasa paneli (8 grup + etki önizlemesi) ve
## haritanın "Seçmen" katmanı. Ekran görüntüleri kullanıcı veri klasörüne yazılır.
##   godot --resolution 1600x900 --path . --script res://tools/voter_groups_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), name])
	print("screenshot: " + name)

func _initialize() -> void:
	# PREVIEW_SIZE=1280x720 gibi: kullanıcının tam ekran ayarına dokunmadan pencere boyutu.
	await process_frame
	if OS.get_environment("PREVIEW_LANG") != "":
		# Ayar dosyasına yazmadan (GameSettings açılışta dili yükledikten sonra).
		root.get_node("GameSettings").language = OS.get_environment("PREVIEW_LANG")
		TranslationServer.set_locale(OS.get_environment("PREVIEW_LANG"))
	var forced := OS.get_environment("PREVIEW_SIZE")
	if forced != "":
		var parts := forced.split("x")
		for i in 3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
			await process_frame
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 5:
		mm.add_bot()
	mm.start_game()
	var guide_script = load("res://scripts/tutorial_guide.gd")
	guide_script.allow_in_scripts = true
	guide_script.config_path = "user://tutorial_preview.cfg"
	DirAccess.remove_absolute(guide_script.config_path)
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isci", "ilerici"], true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	var me: int = mm.owner_id
	cm.current_turn_index = cm.turn_order.find(me)
	cm.funds[me] = 120.0
	cm._push_state({"type": "timer"})
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(30)
	Input.warp_mouse(Vector2(2, 2))
	var guide = scene._tutorial
	var fails := 0
	var shown := []
	for i in 12:
		if i == 6:
			cm._hold_election(cm.round_number, false)
			gm._set_phase(gm.Phase.IDLE)
			cm.current_turn_index = cm.turn_order.find(me)
		if i == 7:
			gm.government = {"pm": me}
			gm.main_gov_peer_id = me
			gm._set_phase(gm.Phase.GOVERNING)
			cm.current_turn_index = cm.turn_order.find(me)
			cm._push_state({"type": "timer"})
		guide.check_now()
		await _frames(8)
		var id: String = guide.current_id()
		if id == "":
			continue
		shown.append(id)
		_shot("tut_%02d_%s" % [shown.size(), id])
		var rect: Rect2 = guide._panel.get_global_rect()
		var view: Rect2 = root.get_visible_rect()
		if not view.encloses(rect):
			fails += 1
			print("[HATA] panel ekran dışında: %s %s" % [id, str(rect)])
		guide._on_ok()
	print("GÖSTERİLEN: %s" % str(shown))
	if shown.size() != 10:
		fails += 1
		print("[HATA] 10 adım bekleniyordu")
	DirAccess.remove_absolute(guide_script.config_path)
	print("REHBER ÖNİZLEME: %s" % ("HEPSİ GEÇTİ" if fails == 0 else "%d HATA" % fails))
	quit()
