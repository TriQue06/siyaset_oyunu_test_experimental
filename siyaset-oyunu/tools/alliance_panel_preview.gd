extends SceneTree
## İTTİFAK PANELİ: bana gelen davet (kabul/ret), üye onay durumu, lider ★.
##   PREVIEW_SIZE=1920x1080 godot --path . --script res://tools/alliance_panel_preview.gd

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
	mm.start_offline("Barış")
	for i in 4:
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
	var me: int = mm.owner_id
	var others: Array = []
	for pid in cm.party_ids():
		if int(pid) != cm.party_of(me):
			others.append(int(pid))
	# Bot 1 ittifak kurar, bot 2'yi alır, beni ve bot 3'ü davet eder.
	cm.current_turn_index = cm.turn_order.find(others[0])
	cm._apply_create_alliance(others[0], "Millet Cephesi", root.get_node("PartyPresets").COLORS[3])
	var a: int = cm.alliance_of(others[0])
	cm._apply_invite_alliance_party(others[0], a, others[1])
	cm._apply_answer_alliance(others[1], cm.pending_alliance_request(a, others[1]), true)
	cm._apply_invite_alliance_party(others[0], a, me)
	cm._apply_invite_alliance_party(others[0], a, others[2])
	cm._apply_answer_alliance(others[1], cm.pending_alliance_request(a, me), true)
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(30)
	if scene.get("_event_fx") != null:
		for i in 6:
			scene._event_fx.skip()
	scene._on_alliance_button_pressed()
	await _frames(10)
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/alliance_panel.png" % OS.get_user_data_dir())
		print("screenshot: alliance_panel")
	quit()
