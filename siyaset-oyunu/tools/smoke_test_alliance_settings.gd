extends SceneTree
var fails := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	print(("[OK] " if ok else "[HATA] ") + message)
	if not ok:
		fails += 1
func run() -> void:
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	var presets = root.get_node("PartyPresets")
	var brain = load("res://scripts/bot_brain.gd")
	var economy = load("res://scripts/economy.gd")
	mm.room_code = ""
	mm.players = {1: {"name": "Human"}, 2: {"name": "Bot", "bot": true}}
	pm.parties = {1: {"name": "Human", "groups": {}, "ready": true}, 2: {"name": "Bot", "groups": {}, "ready": true}}
	cm.init_game()
	cm.turn_order = [1, 2]
	cm.current_turn_index = 0
	gm.phase = gm.Phase.IDLE
	cm._apply_create_alliance(1, "Alliance", presets.COLORS[0])
	check(cm.alliances.size() == 1, "preset alliance created")
	cm.last_vote_shares = {1: 30.0, 2: 3.0}
	mm.election_threshold = 7.0
	cm._apply_invite_alliance_party(1, 1, 2)
	bm._handle_alliance_invitations(100.0)
	bm._handle_alliance_invitations(110.0)
	check(cm.alliance_of(2) == 1, "below-threshold bot accepts without waiting for its turn")
	check(brain.choose_alliance_request(2) == -1, "member does not request another alliance")
	pm.parties[3] = {"name": "Other", "groups": {}}
	cm.turn_order.append(3)
	cm.current_turn_index = 2
	cm._apply_create_alliance(3, "Duplicate", presets.COLORS[0])
	check(cm.alliances.size() == 1, "duplicate alliance color rejected")
	for seconds in [15, 30, 45, 60]:
		mm._apply_vote_timeout(seconds)
		gm._set_phase(gm.Phase.VOTING)
		check(is_equal_approx(gm.phase_seconds_left(), float(seconds)), "vote deadline %d" % seconds)
	var screen = load("res://scripts/game_screen.gd")
	check(screen.can_instantiate(), "game screen compiles")
	var lobby = load("res://scripts/room_lobby.gd")
	check(lobby.can_instantiate(), "lobby compiles")
	quit(1 if fails else 0)
