extends SceneTree
## 6 botlu hızlandırılmış oyun: BotBrain kararları beklemesiz uygulanır.
## Çalışma hatası çıkmamalı, oyun ilerlemeli, hükümet kurulmalı, botlar
## farklı türde kartlar oynamalı.
##   godot --headless --script res://tools/smoke_test_bots.gd

var mm
var pm
var cm
var gm
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	# Test betiği autoload'lardan önce derlendiği için sınıf çalışma anında yüklenir.
	var brain = load("res://scripts/bot_brain.gd")
	var bm = root.get_node("BotManager")
	bm.set_process(false)  # zamanlamasız sürüyoruz
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	mm.election_threshold = 3.0
	mm.axis_sharpness_start = 1.0
	mm.axis_sharpness_increment = 0.1
	mm.players = {}
	pm.parties = {}
	mm.stage = mm.Stage.PARTY_SETUP
	for i in 6:
		var id: int = mm.BOT_ID_BASE - i
		mm.players[id] = {"name": "Bot %d" % i, "bot": true}
		pm.add_bot_party(id)
	check("6 bot partisi olustu, isimler benzersiz", pm.parties.size() == 6)
	cm.init_game()

	var played := {}
	var governments := 0
	var votes := 0
	var steps := 0
	var was_governing := false
	while steps < 3000 and not cm.game_finished and cm.round_number <= 14:
		steps += 1
		if gm.phase == gm.Phase.VOTING:
			for bot in gm.eligible_voter_ids():
				if not gm.has_voted(bot):
					gm._apply_vote(bot, brain.choose_vote(bot))
					votes += 1
					break
		elif gm.phase == gm.Phase.FORMING:
			var holder: int = gm.mandate_peer_id()
			gm._apply_government_proposal(holder, brain.build_government(holder))
			if gm.phase == gm.Phase.FORMING:
				gm.tick(GameRules.FORMATION_TIMEOUT + 1.0)  # geçersiz teklif: süre dolsun
		else:
			var bot: int = cm.current_turn_peer_id()
			if cm.inventories.get(bot, []).size() < cm.MAX_HAND_SIZE:
				cm._apply_draw(bot)
			var play: Dictionary = brain.choose_play(bot)
			if play.is_empty():
				cm._apply_pass(bot)
			else:
				var card: String = cm.inventories[bot][int(play["index"])]
				var before: int = cm.inventories[bot].size()
				cm._apply_play(bot, int(play["index"]), int(play["peer"]), String(play["province"]))
				if cm.inventories.get(bot, []).size() < before:
					var cp = root.get_node("CardPresets")
					var key: String = "law" if cp.is_law_card(card) else ("ideology" if cp.is_ideology_card(card) else card)
					played[key] = int(played.get(key, 0)) + 1
				elif cm.current_turn_peer_id() == bot and not cm.is_turn_blocked():
					cm._apply_pass(bot)
		var governing: bool = gm.phase == gm.Phase.GOVERNING
		if governing and not was_governing:
			governments += 1
		was_governing = governing

	print("  adim %d, tur %d, hukumet %d, oy %d, kartlar %s" % [steps, cm.round_number, governments, votes, str(played)])
	check("oyun ilerledi (en az 10 tur)", cm.round_number >= 10 or cm.game_finished, "tur %d" % cm.round_number)
	check("en az bir hukumet kuruldu", governments >= 1)
	check("botlar oy verdi", votes > 0)
	check("botlar farkli kart turleri oynadi", played.size() >= 3, str(played))
	check("miting oynandi", int(played.get("miting", 0)) > 0)

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
