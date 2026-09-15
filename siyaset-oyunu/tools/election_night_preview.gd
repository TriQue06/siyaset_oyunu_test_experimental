extends SceneTree
## Seçim gecesi ekranını 6 partili örnek bir seçimle açar, birkaç anda ekran
## görüntüsü kaydeder (user:// altına) ve sonuna kadar oynatıp hata arar.
##   godot --script res://tools/election_night_preview.gd

const PARTIES := [
	{"name": "Yeni Yol", "leader": "Sen", "color": "F20C1F", "icon": 0, "ideology": {"economic": 1, "social": 1, "administrative": 2}},
	{"name": "Halkçı", "leader": "Bot Ayşe", "color": "1C48C9", "icon": 5, "ideology": {"economic": -2, "social": -1, "administrative": 1}},
	{"name": "Millet", "leader": "Bot Mehmet", "color": "F2920C", "icon": 12, "ideology": {"economic": 1, "social": 2, "administrative": 2}},
	{"name": "Özgürlük", "leader": "Bot Deniz", "color": "8C21C2", "icon": 20, "ideology": {"economic": 2, "social": -2, "administrative": -1}},
	{"name": "Yeşiller", "leader": "Bot Can", "color": "29A33D", "icon": 6, "ideology": {"economic": -1, "social": -2, "administrative": -2}},
	{"name": "Anadolu", "leader": "Bot Elif", "color": "13DBED", "icon": 30, "ideology": {"economic": -1, "social": 2, "administrative": -2}},
]

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	mm.room_code = ""
	mm.election_threshold = 7.0
	mm.players = {}
	pm.parties = {}
	for i in PARTIES.size():
		var p: Dictionary = PARTIES[i]
		mm.players[i + 1] = {"name": p["leader"], "bot": true}
		pm.parties[i + 1] = {
			"name": p["name"], "icon_index": p["icon"], "icon_color": Color.WHITE,
			"bg_color": Color(p["color"]), "ideology": p["ideology"].duplicate(), "ready": true,
		}
	cm.init_game()
	cm.turn_order = [1, 2, 3, 4, 5, 6]
	cm._hold_election(1, false)

	var scene: Node = (load("res://scenes/ElectionResults.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var out := OS.get_user_data_dir()
	for moment in [3.0, 9.0, 16.0, GameRules.ELECTION_NIGHT_SECONDS]:
		scene._t = moment
		scene._refresh_left = 0.0
		scene._map_refresh_left = 0.0
		for i in 45:  # yumuşatma otursun
			await process_frame
		if DisplayServer.get_name() != "headless":
			var path := "%s/election_night_%02d.png" % [out, int(moment)]
			root.get_texture().get_image().save_png(path)
			print("screenshot: ", path)
	print("=== PREVIEW DONE ===")
	quit()
