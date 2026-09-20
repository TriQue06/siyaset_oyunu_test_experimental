extends SceneTree
## Ağ olmadan, 6 partili ÖRNEK OYUN. Sen 1. partisin; diğer 5 partiyi oyunun
## bot sistemi (BotManager + BotBrain) insan hızında oynar. Oyun doğrudan bir
## seçimle, meclis oluşmuş hâlde başlar.
##   godot --script res://tools/demo_game.gd

const PARTIES := [
	{"name": "Yeni Yol", "leader": "Sen", "color": "F20C1F", "icon": 0, "ideology": {"economic": 1, "social": 1, "administrative": 2}},
	{"name": "Halkçı", "leader": "Bot Ayşe", "color": "1C48C9", "icon": 5, "ideology": {"economic": -2, "social": -1, "administrative": 1}},
	{"name": "Millet", "leader": "Bot Mehmet", "color": "F2920C", "icon": 12, "ideology": {"economic": 1, "social": 2, "administrative": 2}},
	{"name": "Özgürlük", "leader": "Bot Deniz", "color": "8C21C2", "icon": 20, "ideology": {"economic": 2, "social": -2, "administrative": -1}},
	{"name": "Yeşiller", "leader": "Bot Can", "color": "29A33D", "icon": 6, "ideology": {"economic": -1, "social": -2, "administrative": -2}},
	{"name": "Anadolu", "leader": "Bot Elif", "color": "13DBED", "icon": 30, "ideology": {"economic": -1, "social": 2, "administrative": -2}},
]

var cm
var gm

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	mm.room_code = ""
	mm.election_threshold = 3.0
	mm.axis_sharpness_start = 1.0
	mm.axis_sharpness_increment = 0.1
	mm.players = {}
	pm.parties = {}
	for i in PARTIES.size():
		var p: Dictionary = PARTIES[i]
		mm.players[i + 1] = {"name": p["leader"], "bot": i > 0}
		pm.parties[i + 1] = {
			"name": p["name"], "icon_index": p["icon"], "icon_color": Color.WHITE,
			"bg_color": Color(p["color"]), "ideology": p["ideology"].duplicate(), "ready": true,
		}
	cm.init_game()
	cm.turn_order = [1, 2, 3, 4, 5, 6]
	cm.current_turn_index = 0
	cm.inventories[1] = ["miting", "capitalist", "law_privatization"]
	cm._hold_election(1, false)
	change_scene_to_file("res://scenes/GameScreen.tscn")

func _process(delta: float) -> bool:
	# Ağsız oyunda host zamanlayıcıları kendiliğinden işlemez (odada işler).
	if cm != null and not cm.turn_order.is_empty():
		cm.tick(delta)
		gm.tick(delta)
	return false
