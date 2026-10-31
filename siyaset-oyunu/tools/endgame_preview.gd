extends SceneTree
## OYUN SONU ÖNİZLEME: kısa bir botlu oyunu sanal saatle bitirir, sonra oyun
## sonu dizisini istenen sahneden oynatıp ekran görüntüsü alır.
##   godot --path . --resolution 1280x720 --script res://tools/endgame_preview.gd
## ENDGAME_STAGE: 0 ünvanlar, 1 yolculuk, 2 perde arkası, 3 grafik, 4 kürsü.
## Görüntüler user:// içine endgame_<sahne>_<n>.png.

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var pm = root.get_node("PartyManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	mm.start_offline("Test")
	for i in 5:
		mm.add_bot()
	mm.set_game_length(0.0, 2)
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 3, Color.WHITE, Color("F20C1F"), ["isveren", "ilerici"], true)
	cm.set_rng_seed(7)
	gm.result_hold_seconds = 0.3
	var now := 0.0
	while now < 30000.0 and not cm.game_finished:
		now += 0.2
		cm._process(0.2)
		gm._process(0.2)
		bm.step(now)
		if gm.phase == gm.Phase.VOTING and not gm.has_voted(mm.owner_id) and gm.eligible_voter_ids().has(mm.owner_id):
			gm._apply_vote(mm.owner_id, gm.VOTE_YES)
		if cm.is_my_turn() and not cm.is_turn_blocked():
			cm.pass_turn()
	print("oyun bitti=%s seçimler=%s" % [str(cm.game_finished), str(cm.game_stats.get("elections"))])
	var stage := int(OS.get_environment("ENDGAME_STAGE")) if OS.get_environment("ENDGAME_STAGE") != "" else 3
	var seq: Control = load("res://scripts/endgame_sequence.gd").new()
	seq.set("_stage_index", stage - 1)
	root.add_child(seq)
	for i in 8:
		await create_timer(5.0).timeout
		if DisplayServer.get_name() != "headless":
			root.get_texture().get_image().save_png("%s/endgame_%d_%d.png" % [OS.get_user_data_dir(), stage, i])
	quit()
