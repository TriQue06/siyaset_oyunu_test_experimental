extends SceneTree
## CANLI OYUN SONU ÖNİZLEMESİ: 6 partili, uzun bir oyunu (varsayılan 6 seçim)
## sanal saatle oynatır; oyuncunun koltuğunu da bot yönetir, böylece bütün
## partilerin dolu bir geçmişi olur. Sonra oyun sonu dizisini baştan oynatır ve
## pencere açık kalır (kapatınca biter).
##   godot --path . --resolution 1600x900 --script res://tools/endgame_live.gd
## ENDGAME_ELECTIONS: seçim sayısı (2..12), ENDGAME_SEED: rastgelelik tohumu.

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var pm = root.get_node("PartyManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	var elections := int(OS.get_environment("ENDGAME_ELECTIONS")) if OS.get_environment("ENDGAME_ELECTIONS") != "" else 6
	var game_seed := int(OS.get_environment("ENDGAME_SEED")) if OS.get_environment("ENDGAME_SEED") != "" else 11
	mm.start_offline("Barış")
	for i in 5:
		mm.add_bot()
	mm.set_game_length(0.0, elections)
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 3, Color.WHITE, Color("F20C1F"), ["isveren", "ilerici"], true)
	cm.set_rng_seed(game_seed)
	gm.result_hold_seconds = 0.3
	# Oyuncunun koltuğu da botta: her parti oynar, geçmiş dolu olur.
	mm.players[mm.owner_id]["away"] = true
	var now := 0.0
	var last_election := -1
	while now < 400000.0 and not cm.game_finished:
		now += 0.25
		cm._process(0.25)
		gm._process(0.25)
		bm.step(now)
		var done := int(cm.game_stats.get("elections", 0)) if cm.game_stats.get("elections") is int else -1
		if done != last_election:
			last_election = done
			print("seçim %s / %d (sanal %.0f sn)" % [str(cm.game_stats.get("elections")), elections, now])
	mm.players[mm.owner_id]["away"] = false
	print("oyun bitti=%s seçimler=%s" % [str(cm.game_finished), str(cm.game_stats.get("elections"))])
	var seq: Control = load("res://scripts/endgame_sequence.gd").new()
	root.add_child(seq)
	# Oyunda GameScreen._on_game_over jenerik müziğini başlatır; burada elle.
	root.get_node("AudioManager").play_music("credits")
