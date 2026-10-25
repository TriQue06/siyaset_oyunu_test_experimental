extends SceneTree
## İTTİFAK SİMÜLASYONU (0.0.254): 6 bot (barajlı), ilk 12 tur. Seçimden önce ve
## sonra kaç ittifak kuruldu, kaçar partili? Bot ittifak davranışını gözlemek için.
##   godot --headless --path . -s res://tools/alliance_sim.gd

func _initialize() -> void:
	await process_frame
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	var brain = load("res://scripts/bot_brain.gd")
	bm.set_process(false)
	cm.allow_temporary_parties = false
	for game_seed in [11, 22, 33, 44]:
		cm.set_rng_seed(game_seed)
		seed(game_seed)
		mm.room_code = ""
		gm.result_hold_seconds = 0.0
		mm.election_threshold = 7.0
		mm.players = {}
		pm.parties = {}
		mm.stage = mm.Stage.PARTY_SETUP
		for i in 6:
			var id: int = mm.BOT_ID_BASE - i
			mm.players[id] = {"name": "Bot %d" % i, "bot": true}
			pm.add_bot_party(id)
		cm.init_game()
		var steps := 0
		var turn_actions := 0
		var last_bot := -1
		var stats := {"pre_max": 0, "pre_count": 0, "post_max": 0, "post_count": 0}
		while steps < 6000 and not cm.game_finished and cm.round_number <= 12:
			steps += 1
			bm._handle_alliance_invitations(1.0e9)
			bm._handle_alliance_invitations(2.0e9)
			var phase := "post" if cm.last_election_round > 0 else "pre"
			for a in cm.alliances.values():
				stats[phase + "_max"] = maxi(int(stats[phase + "_max"]), (a.get("members", []) as Array).size())
			stats[phase + "_count"] = maxi(int(stats[phase + "_count"]), cm.alliances.size())
			if cm.congress_active:
				cm.tick(30.0)
				continue
			if gm.phase == gm.Phase.VOTING:
				for bot in gm.eligible_voter_ids():
					if not gm.has_voted(bot):
						gm._apply_vote(bot, brain.choose_vote(bot))
						break
			elif gm.phase == gm.Phase.FORMING:
				var holder: int = gm.mandate_peer_id()
				gm._apply_government_proposal(holder, brain.build_government(holder))
				if gm.phase == gm.Phase.FORMING:
					gm.tick(GameRules.FORMATION_TIMEOUT + 100.0)
			else:
				var bot: int = cm.current_turn_peer_id()
				if bot != last_bot:
					last_bot = bot
					turn_actions = 0
				if cm.needs_turn_draw(bot):
					cm._apply_draw(bot)
					continue
				if cm.aid_pending(bot):
					cm._apply_skip_aid(bot)
					continue
				# BotManager._handle_turn ile aynı: önce ittifak hamlesi.
				var move: Dictionary = brain.choose_alliance_move(bot)
				if not move.is_empty() and turn_actions < 12:
					turn_actions += 1
					match String(move["type"]):
						"request":
							cm._apply_request_alliance(bot, int(move["alliance_id"]))
						"create":
							cm._apply_create_alliance(bot, String(move["name"]), move["color"])
						"invite":
							cm._apply_invite_alliance_party(bot, int(move["alliance_id"]), int(move["party"]))
						"leave":
							cm._apply_leave_alliance(bot)
					continue
				var done: Dictionary = bm.do_action(bot) if turn_actions < 12 else {}
				turn_actions += 1
				if done.is_empty():
					cm._apply_pass(bot, true)
					turn_actions = 0
		print("tohum %d | ilk secimden once: en fazla %d ittifak, en buyugu %d parti | sonra: en fazla %d ittifak, en buyugu %d parti" % [
			game_seed, stats["pre_count"], stats["pre_max"], stats["post_count"], stats["post_max"]])
	quit()

static func _summary(cm) -> String:
	if cm.alliances.is_empty():
		return "ittifak yok"
	var parts: PackedStringArray = []
	for a in cm.alliances.values():
		parts.append("%s (%d parti)" % [String(a.get("name", "?")), (a.get("members", []) as Array).size()])
	return ", ".join(parts)
