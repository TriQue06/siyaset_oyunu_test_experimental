extends SceneTree
## GERÇEK OYUN HÂLİ: birkaç tur botlarla oynanmış, seçim yapılmış, hükümet
## kurulmuş ve ELDE KART olan bir oyunun ekran görüntüsü.
##   godot --path . --script res://tools/midgame_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	mm.start_offline("Barış")
	for i in 5:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"),
		{"economic": 0, "social": 0, "administrative": 0}, true)
	cm.set_rng_seed(4242)
	bm._rng.seed = 4242
	gm.result_hold_seconds = 0.2
	# SEÇİM VE HÜKÜMET OLUŞANA KADAR sanal saatle oynat.
	var now := 0.0
	while now < 4000.0 and not (gm.has_government() and cm.round_number >= 6):
		now += 0.2
		cm.tick(0.2)
		gm.tick(0.2)
		bm.step(now)
		if gm.phase == gm.Phase.VOTING and gm.eligible_voter_ids().has(mm.owner_id) \
				and not gm.has_voted(mm.owner_id):
			gm._apply_vote(mm.owner_id, gm.VOTE_YES)
	print("tur=%d hukumet=%s elde kart=%d" % [cm.round_number, str(gm.has_government()),
		cm.inventories.get(mm.owner_id, []).size()])

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(30)
	var left: Control = scene.get_node("LeftPanel")
	var board: Control = scene.get_node("%ParliamentBoard")
	var lr := left.get_global_rect()
	var br := board.get_global_rect()
	print("OLCUM sol=%.0f..%.0f tahta=%.0f..%.0f -> %s" % [lr.position.x, lr.end.x,
		br.position.x, br.end.x, "CAKISMA VAR" if lr.intersects(br) else "temiz"])
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/midgame.png" % OS.get_user_data_dir())
		print("screenshot: midgame")
	quit()
