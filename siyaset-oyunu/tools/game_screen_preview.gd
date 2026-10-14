extends SceneTree
## Oyun ekranını 6 partili örnek bir seçim ve koalisyon hükümetiyle açar;
## normal görünümün, parti profilinin ve meclis oylamasının ekran görüntüsünü
## user:// altına kaydeder.
##   godot --resolution 1600x900 --script res://tools/game_screen_preview.gd

const PARTIES := [
	{"name": "Yeni Yol", "leader": "Sen", "color": "F20C1F", "icon": 0, "core": ["isveren", "milliyetci"]},
	{"name": "Halkçı", "leader": "Bot Ayşe", "color": "1C48C9", "icon": 5, "core": ["isci", "milliyetci"]},
	{"name": "Millet", "leader": "Bot Mehmet", "color": "F2920C", "icon": 12, "core": ["dindar", "milliyetci"]},
	{"name": "Özgürlük", "leader": "Bot Deniz", "color": "8C21C2", "icon": 20, "core": ["isveren", "ilerici"]},
	{"name": "Yeşiller", "leader": "Bot Can", "color": "29A33D", "icon": 6, "core": ["isci", "ozerkci"]},
	{"name": "Anadolu", "leader": "Bot Elif", "color": "13DBED", "icon": 30, "core": ["dindar", "ozerkci"]},
]

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path := "%s/%s.png" % [OS.get_user_data_dir(), name]
	root.get_texture().get_image().save_png(path)
	print("screenshot: ", path)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var gp = root.get_node("GovernmentPresets")
	root.get_node("BotManager").set_process(false)
	mm.room_code = ""
	mm.election_threshold = 7.0
	mm.players = {}
	pm.parties = {}
	for i in PARTIES.size():
		var p: Dictionary = PARTIES[i]
		mm.players[i + 1] = {"name": p["leader"], "bot": i > 0}
		pm.parties[i + 1] = {
			"name": p["name"], "icon_index": p["icon"], "icon_color": Color.WHITE,
			"bg_color": Color(p["color"]), "core": (p["core"] as Array).duplicate(), "groups": VoterGroups.start_affinities(p["core"]), "ready": true,
		}
	cm.init_game()
	cm.turn_order = [1, 2, 3, 4, 5, 6]
	cm.current_turn_index = 0
	cm._hold_election(1, false)
	# Koalisyon: 1 başbakan, 3 yardımcı + 2 bakanlık.
	var assign := {}
	for post in gp.POSTS:
		assign[post["id"]] = 1
	assign[gp.POST_DEPUTY_PM] = 3
	assign["ministry_education"] = 3
	gm.result_hold_seconds = 0.0
	gm._apply_government_proposal(gm.mandate_peer_id(), assign)

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(20)
	# Mecliste: koalisyon görüşmesi bitti mi? (görevli 1 değilse teklif geçersiz kalabilir)
	print("phase=", gm.phase, " stage=", gm.proposal_stage, " mandate=", gm.mandate_peer_id())
	_shot("preview_coalition_stage")
	if gm.is_coalition_stage():
		for partner in gm.proposal_partner_ids():
			gm._apply_vote(partner, gm.VOTE_YES)
	gm._apply_vote(2, gm.VOTE_NO)
	await _frames(10)
	_shot("preview_parliament_vote")
	for peer_id in gm.eligible_voter_ids():
		if not gm.has_voted(peer_id):
			gm._apply_vote(peer_id, gm.VOTE_ABSTAIN)
	await _frames(20)
	_shot("preview_governing")
	scene._hovered_peer_id = 3
	scene._show_tooltip_for(3)
	await _frames(10)
	_shot("preview_profile")
	print("=== PREVIEW DONE ===")
	quit()
