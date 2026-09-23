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

func _measure(left: Control, board: Control, label: String) -> void:
	await _frames(4)
	var lr := left.get_global_rect()
	var br := board.get_global_rect()
	print("OLCUM [%s]  sol=%.0f..%.0f (min %.0f)  tahta=%.0f..%.0f  -> %s" % [
		label, lr.position.x, lr.end.x, left.get_combined_minimum_size().x,
		br.position.x, br.end.x,
		"CAKISMA VAR" if lr.intersects(br) else "temiz"])

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
	# EN-BOY ORANI ÖNEMLİ: stretch "expand" olduğu için mantıksal genişlik
	# pencerenin oranına göre değişiyor (16:9 -> 1152, 4:3 -> 864 gibi).
	# Tablet 4:3/16:10 olduğunda ekran BELİRGİN ŞEKİLDE DARALIYOR.
	# Sol panelin BÜYÜYEBİLDİĞİ durumları tek tek dene.
	await _measure(left, board, "normal")

	# 1) İL PANELİ AÇIK: eskiden içerik uzadıkça panel boyu büyüyüp
	# parlamento diyagramının üstünü kapatıyordu.
	scene._on_province_clicked("ankara")
	await _frames(10)
	var prov: Control = scene._province_panel
	var pr := prov.get_global_rect()
	var br2 := board.get_global_rect()
	print("OLCUM [il paneli]  panel y=%.0f..%.0f  tahta y=%.0f..%.0f  -> %s" % [
		pr.position.y, pr.end.y, br2.position.y, br2.end.y,
		"CAKISMA VAR" if pr.intersects(br2) else "temiz"])
	_shot("province_panel_open")
	prov.hide()
	await _frames(4)

	# 2) UZUN PARTİ ADLARI
	for peer_id in pm.parties.keys():
		pm.parties[peer_id]["name"] = "Cumhuriyetçi Kalkınma"
	pm.parties_updated.emit()
	scene._refresh_government_panel()
	await _frames(6)
	await _measure(left, board, "uzun parti adlari")

	# 3) KOALİSYONDAN ÇEKİL onay yazısı (butona bir kez basılmış hâli)
	var gov_box: VBoxContainer = scene.get_node("%GovernmentVBox")
	for child in gov_box.get_children():
		if child is Button:
			(child as Button).text = "Emin misin? Tekrar dokun (ortağın yalnız düşerse −5)"
	await _frames(6)
	await _measure(left, board, "cekilme onayi")
	print("=== GOVERNMENT PANEL PREVIEW: PASS ===")
	quit()
