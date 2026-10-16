extends SceneTree
## TÜRKİYE HARİTASI: altıgen ve net modda oyun ekranı (seçimden sonra).
##   PREVIEW_SIZE=1920x1080 godot --path . --script res://tools/turkey_map_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await process_frame
	var forced := OS.get_environment("PREVIEW_SIZE")
	if forced != "":
		var parts := forced.split("x")
		for i in 3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
			await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	for mode in ["turkiye_altigen"]:
		mm.start_offline("Barış")
		mm.set_world_setting("map_mode", mode)
		for i in 3:
			mm.add_bot()
		mm.start_game()
		pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "ilerici"], true)
		cm.set_rng_seed(4242)
		bm._rng.seed = 4242
		gm.result_hold_seconds = 0.2
		var now := 0.0
		while now < 4000.0 and not (gm.has_government() and cm.round_number >= 6):
			now += 0.2
			cm.tick(0.2)
			gm.tick(0.2)
			bm.step(now)
			if gm.phase == gm.Phase.VOTING and gm.eligible_voter_ids().has(mm.owner_id) and not gm.has_voted(mm.owner_id):
				gm._apply_vote(mm.owner_id, gm.VOTE_YES)
		var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
		root.add_child(scene)
		await _frames(30)
		if scene.get("_event_fx") != null:
			for i in 4:
				scene._event_fx.skip()
		await _frames(5)
		if DisplayServer.get_name() != "headless":
			var markers: Node = scene.find_child("SeatMarkers", true, false)
			for scale in [1.0, 0.7, 0.55, 0.45]:
				markers.dot_radius = 4.6 * scale
				markers.dot_spacing = 4.4 * scale
				markers.dot_outline_width = 2.0 * scale
				markers._rebuild()
				await _frames(3)
				root.get_texture().get_image().save_png("%s/turkey_%s_%d.png" % [OS.get_user_data_dir(), mode, int(scale * 100)])
				print("screenshot: ", mode, " ", scale)
		scene.queue_free()
		await _frames(3)
		mm.leave_room()
	quit()
