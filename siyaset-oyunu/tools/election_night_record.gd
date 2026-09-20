extends SceneTree
## Seçim gecesi yayınını 6 partili örnek bir seçimle GERÇEK hızda oynatır;
## --write-movie ile birlikte çalıştırılınca video kaydı alınır.
##   godot --write-movie out.avi --fixed-fps 30 --resolution 1280x720 --script res://tools/election_night_record.gd

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
	root.add_child((load("res://scenes/ElectionResults.tscn") as PackedScene).instantiate())
	# Yayın + kesin sonuç bekleme süresinin sonuna kadar (GameScreen'e dönmeden önce) kaydet.
	var frames := int((GameRules.ELECTION_NIGHT_SECONDS + GameRules.ELECTION_NIGHT_HOLD - 0.5) * 30.0)
	for i in frames:
		await process_frame
	quit()
