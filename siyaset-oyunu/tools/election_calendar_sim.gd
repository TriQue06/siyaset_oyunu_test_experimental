extends SceneTree
## SEÇİM TAKVİMİ SİMÜLASYONU (0.0.266): botlarla baştan sona oyunlar oynatır,
## arada rastgele ERKEN SEÇİM önergesi verdirir ve her turda takvimi izler:
##   - turun başında "sıradaki seçim" (next_election_round) bu turu
##     gösteriyorsa, tur bitince seçim YAPILMALI;
##   - seçim yapılan her tur ya takvimdeki tur ya da erken seçim olmalı;
##   - bant yazısı (sonraki seçim yılı) ile gerçekleşen seçim yılı tutmalı.
## Her oyunun tur tur takvim günlüğü yazılır; uyumsuzluklar [HATA] verir.
##   godot --headless --path . --script res://tools/election_calendar_sim.gd -- --games=6

var mm
var pm
var cm
var gm
var brain
var bm
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	var games := 6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = int(arg.substr(8))
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	cm.allow_temporary_parties = false
	gm = root.get_node("GovernmentManager")
	brain = load("res://scripts/bot_brain.gd")
	bm = root.get_node("BotManager")
	bm.set_process(false)
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	for g in games:
		_play_game(g)
	print("=== %s ===" % ("HEPSİ GEÇTİ" if fails == 0 else "%d HATA" % fails))
	quit(1 if fails > 0 else 0)

func _play_game(g: int) -> void:
	seed(4100 + g)
	cm.set_rng_seed(5100 + g)
	mm.players = {}
	pm.parties = {}
	mm.stage = mm.Stage.PARTY_SETUP
	# Farklı seçim aralıkları (yıl): 1,5 / 2 / 2,5 / 3.
	mm.election_interval = [1.5, 2.0, 2.5, 3.0][g % 4]
	mm.election_count = 4 + g % 3
	GameRules.configure(mm.election_interval, mm.election_count)
	for i in 5:
		var id: int = mm.BOT_ID_BASE - i
		mm.players[id] = {"name": "Bot %d" % i, "bot": true}
		pm.add_bot_party(id)
	cm.init_game()
	print("=== OYUN %d (aralık %d tur, son tur %d) ===" % [g, GameRules.ELECTION_INTERVAL, GameRules.MAX_ROUNDS])
	var rng := RandomNumberGenerator.new()
	rng.seed = 6100 + g
	var steps := 0
	var turn_actions := 0
	var last_bot := -1
	var round_seen := 0
	var expected := -1          # turun başında gösterilen sıradaki seçim turu
	var band_year := -1         # turun başında bantta yazan sonraki seçim yılı
	var early_proposed_round := -1
	var log := []
	while not cm.game_finished and steps < 40000:
		steps += 1
		# Yeni tur: önceki turun takvimi denetlenir.
		if cm.round_number != round_seen:
			if round_seen > 0:
				var held: bool = cm.last_election_round == round_seen
				var early: bool = held and cm.last_election_was_early
				log.append("tur %2d (%s) beklenen %s · %s%s · çıpa %d son %d aralık %d" % [round_seen, GameRules.period_label(round_seen),
					str(expected), "SEÇİM" if held else "-", " (erken)" if early else "", GameRules.ELECTION_ANCHOR, GameRules.MAX_ROUNDS, GameRules.ELECTION_INTERVAL])
				if expected == round_seen:
					check("tur %d: takvimdeki seçim yapıldı" % round_seen, held,
						"son seçim turu %d, faz %d" % [cm.last_election_round, gm.phase])
				if held and expected != round_seen:
					check("tur %d: takvim dışı seçim erken seçim olarak işaretli" % round_seen, early or cm.final_election_pending,
						"beklenen %d" % expected)
				if held and band_year > 0:
					check("tur %d: seçim yılı bantla aynı" % round_seen,
						GameRules.election_year(round_seen) == band_year or early,
						"bant %d, seçim %d" % [band_year, GameRules.election_year(round_seen)])
			round_seen = cm.round_number
			expected = cm.next_election_round()
			band_year = GameRules.election_year(expected) if expected > 0 else -1
		if cm.congress_active:
			cm.tick(30.0)
			continue
		if gm.phase == gm.Phase.VOTING:
			for bot in gm.eligible_voter_ids():
				if not gm.has_voted(bot):
					gm._apply_vote(bot, brain.choose_vote(bot))
					break
			continue
		if gm.phase == gm.Phase.FORMING:
			var holder: int = gm.mandate_peer_id()
			gm._apply_government_proposal(holder, brain.build_government(holder))
			if gm.phase == gm.Phase.FORMING:
				gm.tick(GameRules.FORMATION_TIMEOUT + 100.0)
			continue
		if cm.is_turn_blocked():
			cm.tick(5.0)
			gm.tick(5.0)
			continue
		var bot: int = cm.current_turn_peer_id()
		if bot != last_bot:
			last_bot = bot
			turn_actions = 0
			# Ara sıra erken seçim önergesi (bot kendisi nadiren verir).
			if early_proposed_round != cm.round_number and rng.randf() < 0.12 and cm.can_early_election(bot):
				early_proposed_round = cm.round_number
				cm._apply_early_election_move(bot)
				log.append("    tur %d: erken seçim önergesi (%s)" % [cm.round_number, str(bot)])
				continue
		var done: Dictionary = bm.do_action(bot) if turn_actions < 12 else {}
		turn_actions += 1
		if done.is_empty():
			cm._apply_pass(bot, true)
			turn_actions = 0
	for line in log:
		print("  " + line)
	check("oyun %d bitti" % g, cm.game_finished, "tur %d faz %d" % [cm.round_number, gm.phase])
