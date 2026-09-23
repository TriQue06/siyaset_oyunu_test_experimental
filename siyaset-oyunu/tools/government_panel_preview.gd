extends SceneTree
## HÜKÜMET PANELİ ÖNİZLEMESİ: koalisyon kurulmuş hâlde sol panel ile
## parlamento diyagramının çakışıp çakışmadığını gösterir.
##   godot --path . --script res://tools/government_panel_preview.gd

const PARTIES := [
	{"name": "Yeni Yol", "leader": "Sen", "color": "F20C1F", "icon": 0},
	{"name": "Halkçı Cephe", "leader": "Bot Ayşe", "color": "1C48C9", "icon": 5},
	{"name": "Millet", "leader": "Bot Mehmet", "color": "F2920C", "icon": 12},
	{"name": "Özgürlük", "leader": "Bot Deniz", "color": "8C21C2", "icon": 20},
	{"name": "Yeşiller", "leader": "Bot Can", "color": "29A33D", "icon": 6},
]

func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), file_name])
	print("screenshot: ", file_name)

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
	mm.players = {}
	pm.parties = {}
	var me: int = root.multiplayer.get_unique_id()
	var ids: Array = [me, 101, 102, 103, 104]
	for i in PARTIES.size():
		var p: Dictionary = PARTIES[i]
		mm.players[ids[i]] = {"name": p["leader"], "bot": i != 0}
		pm.parties[ids[i]] = {"name": p["name"], "icon_index": p["icon"], "icon_color": Color.WHITE,
			"bg_color": Color(p["color"]), "ideology": {"economic": 0, "social": 0, "administrative": 0}, "ready": true}
	cm.init_game()
	gm.result_hold_seconds = 0.0
	cm.turn_order = ids.duplicate()
	cm.last_vote_shares = {ids[0]: 24.5, ids[1]: 22.1, ids[2]: 19.8, ids[3]: 18.4, ids[4]: 15.2}
	cm.last_seats = {ids[0]: 128, ids[1]: 110, ids[2]: 96, ids[3]: 92, ids[4]: 74}
	cm.election_seats = cm.last_seats.duplicate()
	cm.passed_threshold = ids.duplicate()

	# ÜÇ ORTAKLI koalisyon: sol panelin en kalabalık hâli.
	gm.start_formation()
	var assignments := {}
	var owners: Array = [ids[0], ids[1], ids[2]]
	for i in gp.POSTS.size():
		assignments[gp.POSTS[i]["id"]] = owners[i % owners.size()]
	assignments[gp.POST_PM] = ids[0]
	assignments[gp.POST_DEPUTY_PM] = ids[1]
	gm._apply_government_proposal(ids[0], assignments)
	for stage in 2:
		for voter in gm.eligible_voter_ids():
			gm._apply_vote(int(voter), gm.VOTE_YES)
	print("hukumet kuruldu: ", gm.has_government(), " ", gm.last_resolution_reason)

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(25)
	_shot("government_panel")
	var left: Control = scene.get_node("LeftPanel")
	var board: Control = scene.get_node("%ParliamentBoard")
	print("left panel rect=", left.get_global_rect())
	print("parliament board rect=", board.get_global_rect())
	var overlap: bool = left.get_global_rect().intersects(board.get_global_rect())
	print("CAKISMA: ", "VAR" if overlap else "YOK")
	print("=== GOVERNMENT PANEL PREVIEW: PASS ===")
	quit()
