extends SceneTree
## Ağ olmadan, 6 partili ÖRNEK OYUN. Sen 1. partisin; diğer 5 partiyi basit
## botlar oynar (kart çeker/oynar, oy verir, görev kendilerindeyse hükümet
## kurar). Oyun doğrudan bir seçimle, meclis oluşmuş hâlde başlar.
##   godot --script res://tools/demo_game.gd

const HUMAN := 1
const BOT_DELAY := 1.2

const PARTIES := [
	{"name": "Yeni Yol", "leader": "Sen", "color": "F20C1F", "icon": 0, "ideology": {"economic": 1, "social": 1, "administrative": 2}},
	{"name": "Halkçı", "leader": "Bot Ayşe", "color": "1C48C9", "icon": 5, "ideology": {"economic": -2, "social": -1, "administrative": 1}},
	{"name": "Millet", "leader": "Bot Mehmet", "color": "F2920C", "icon": 12, "ideology": {"economic": 1, "social": 2, "administrative": 2}},
	{"name": "Özgürlük", "leader": "Bot Deniz", "color": "8C21C2", "icon": 20, "ideology": {"economic": 2, "social": -2, "administrative": -1}},
	{"name": "Yeşiller", "leader": "Bot Can", "color": "29A33D", "icon": 6, "ideology": {"economic": -1, "social": -2, "administrative": -2}},
	{"name": "Anadolu", "leader": "Bot Elif", "color": "13DBED", "icon": 30, "ideology": {"economic": -1, "social": 2, "administrative": -2}},
]

var mm
var pm
var cm
var gm
var gp
var _bot_timer := 0.0
var _rng := RandomNumberGenerator.new()

func _initialize() -> void:
	await process_frame
	_rng.randomize()
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	mm.room_code = ""
	mm.election_threshold = 3.0
	mm.axis_sharpness_start = 1.0
	mm.axis_sharpness_increment = 0.1
	mm.players = {}
	pm.parties = {}
	for i in PARTIES.size():
		var p: Dictionary = PARTIES[i]
		mm.players[i + 1] = {"name": p["leader"]}
		pm.parties[i + 1] = {
			"name": p["name"], "icon_index": p["icon"], "icon_color": Color.WHITE,
			"bg_color": Color(p["color"]), "ideology": p["ideology"].duplicate(), "ready": true,
		}
	cm.init_game()
	cm.turn_order = [1, 2, 3, 4, 5, 6]
	cm.current_turn_index = 0
	cm.inventories[HUMAN] = ["miting", "capitalist", "law_privatization"]
	cm._hold_election(1, false)
	change_scene_to_file("res://scenes/GameScreen.tscn")

func _process(delta: float) -> bool:
	if cm == null or cm.game_finished:
		return false
	# Yerel modda host zamanlayıcıları kendiliğinden işlemez.
	cm.tick(delta)
	gm.tick(delta)
	_bot_timer += delta
	if _bot_timer < BOT_DELAY:
		return false
	_bot_timer = 0.0
	if gm.phase == gm.Phase.VOTING:
		_bots_vote()
	elif gm.phase == gm.Phase.FORMING:
		_bot_form()
	elif not cm.is_turn_blocked() and cm.current_turn_peer_id() != HUMAN:
		_bot_turn(cm.current_turn_peer_id())
	return false

func _bots_vote() -> void:
	for peer_id in gm.voter_ids():
		if peer_id == HUMAN or gm.votes.has(peer_id):
			continue
		gm._apply_vote(peer_id, _bot_choice(peer_id))
		return  # her adımda bir oy: oyların tek tek geldiği görülsün

func _bot_choice(peer_id: int) -> int:
	match gm.proposal_kind:
		gm.KIND_GOVERNMENT:
			if peer_id == gm.proposal_peer_id or gm.proposal_partner_ids().has(peer_id):
				return gm.VOTE_YES
			return [gm.VOTE_NO, gm.VOTE_ABSTAIN, gm.VOTE_YES][_rng.randi_range(0, 2)]
		gm.KIND_CENSURE:
			return gm.VOTE_NO if gm.government_party_ids().has(peer_id) else gm.VOTE_YES
		gm.KIND_LAW:
			var expectation: int = cm.law_expectation(peer_id, gm.proposal_law)
			if expectation > 0:
				return gm.VOTE_YES
			if expectation < 0:
				return gm.VOTE_NO
			return gm.VOTE_ABSTAIN
	return gm.VOTE_ABSTAIN

## Görev bir botta: en büyük ikinci partiyle koalisyon teklif eder.
func _bot_form() -> void:
	var holder: int = gm.mandate_peer_id()
	if holder == HUMAN or holder == -1:
		return
	var partner := -1
	for peer_id in gm.mandate_order:
		if peer_id != holder and peer_id != HUMAN:
			partner = peer_id
			break
	var assignments := {}
	for post in gp.POSTS:
		assignments[post["id"]] = holder
	if partner != -1:
		assignments[gp.POST_DEPUTY_PM] = partner
		assignments["ministry_health"] = partner
	gm._apply_government_proposal(holder, assignments)

func _bot_turn(bot: int) -> void:
	if cm.inventories.get(bot, []).size() < cm.MAX_HAND_SIZE:
		cm._apply_draw(bot)
	var hand: Array = cm.inventories.get(bot, [])
	var provinces: Array = cm.last_province_results.keys()
	for i in hand.size():
		var card_type: String = hand[i]
		var target := -1
		var province := ""
		var cp = root.get_node("CardPresets")
		if cp.needs_target(card_type):
			for peer_id in cm.turn_order:
				if cm.is_valid_steal_target(bot, peer_id):
					target = peer_id
					break
		elif cp.needs_province_target(card_type) and not provinces.is_empty():
			province = provinces[_rng.randi_range(0, provinces.size() - 1)]
		if cm.can_play_card(bot, card_type, target, province):
			cm._apply_play(bot, i, target, province)
			return
	cm._apply_pass(bot)
