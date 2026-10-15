extends SceneTree
## OYLAMA KAMERASI: meclis oylaması açılınca harita ile meclis diyagramı yer
## değiştirir, oylama bitince 0,5 sn sonra geri döner. Ara kareler kaydedilir.
##   PREVIEW_SIZE=1920x1080 godot --path . --script res://tools/vote_swap_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), name])
	print("screenshot: ", name)

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
	if DisplayServer.get_name() == "headless":
		quit()
		return
	_shot("vote_swap_0_before")
	gm.result_hold_seconds = 999.0
	gm.submit_law(mm.owner_id, "law:isveren")
	print("oylama: ", gm.is_voting())
	await create_timer(0.12).timeout
	_shot("vote_swap_1_moving")
	await create_timer(1.0).timeout
	_shot("vote_swap_2_swapped")
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)
	print("oylama bitti: ", not gm.is_voting())
	await create_timer(0.3).timeout
	_shot("vote_swap_3_wait")
	await create_timer(1.2).timeout
	_shot("vote_swap_4_back")
	quit()
