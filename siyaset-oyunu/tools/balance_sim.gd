extends SceneTree
## DENGE SİMÜLASYONU: 6 botlu tam oyunları (MAX_ROUNDS tur) beklemesiz oynatır
## ve ölçümleri JSON'a yazar:
##   - hamle sıklıkları, kazananların hamle profili,
##   - her seçimde güç kaynaklarının payı: il başkanlığı / seçimden önceki son
##     turda kazanılan il puanı / daha önceki turlardan kalan il puanı / ulusal,
##   - şans: aynı girdilerle seçimi farklı tohumlarla tekrarlayınca birinci
##     partinin değişme oranı ve vekil sapması,
##   - iktidar partilerinin bir sonraki seçimde vekil değişimi,
##   - karalanan partinin o ilde yine de vekil çıkarabilme oranı,
##   - EKONOMİ (tur başına): devlet hazinesi, vergi kademesi, ekonomi endeksi,
##     parti kasaları (ortalama / en yüksek), teşkilat sayısı ve geliri.
##   godot --headless --script res://tools/balance_sim.gd -- --games=40 --first=0 --out=C:/yol/sonuc.json

const LUCK_RESEEDS := 10
var _last_done: Dictionary = {}

var mm
var pm
var cm
var gm
var brain
var bm

func _initialize() -> void:
	var games := 20
	var first := 0
	var out := "user://balance_sim.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = int(arg.substr(8))
		elif arg.begins_with("--first="):
			first = int(arg.substr(8))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
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

	var report := {"games": [], "elections": [], "config": {
		"threshold": mm.election_threshold, "max_rounds": GameRules.MAX_ROUNDS,
		"province_noise": ElectionModel.PROVINCE_NOISE, "national_swing": ElectionModel.NATIONAL_SWING,
	}}
	var started := Time.get_ticks_msec()
	for g in games:
		_play_game(first + g, report)
		print("oyun %d/%d bitti (%.0f sn)" % [g + 1, games, (Time.get_ticks_msec() - started) / 1000.0])
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	print("=== SIMULASYON BITTI: %s ===" % out)
	quit()

func _bump(d: Dictionary, key: String, amount: float = 1.0) -> void:
	d[key] = float(d.get(key, 0.0)) + amount

func _play_game(g: int, report: Dictionary) -> void:
	seed(7000 + g)
	cm.set_rng_seed(9000 + g)
	mm.players = {}
	pm.parties = {}
	mm.stage = mm.Stage.PARTY_SETUP
	for i in 6:
		var id: int = mm.BOT_ID_BASE - i
		mm.players[id] = {"name": "Bot %d" % i, "bot": true}
		pm.add_bot_party(id)
	cm.init_game()

	var stats := {}
	var law_types := {}
	for peer_id in cm.turn_order:
		stats[peer_id] = {"actions": {}, "propaganda_received": 0, "gov_rounds": 0}
	var last_round := 0
	var round_snapshot := {}
	var prev_election_round := 0
	var prev_election_seats := {}
	var marks := {}  # province_id -> {hedef: true} (son seçimden beri karalananlar)
	var econ_rounds := []
	var steps := 0
	var turn_actions := 0
	var last_bot := -1
	while not cm.game_finished and steps < 30000:
		steps += 1
		if cm.last_election_round != prev_election_round:
			prev_election_round = cm.last_election_round
			report["elections"].append(_record_election(g, round_snapshot, prev_election_seats, marks))
			prev_election_seats = cm.last_seats.duplicate()
			marks = {}
		if cm.round_number != last_round:
			last_round = cm.round_number
			econ_rounds.append(_econ_snapshot())
			round_snapshot = {}
			for peer_id in gm.government_party_ids():
				if not stats.has(peer_id):
					stats[peer_id] = {"actions": {}, "propaganda_received": 0, "gov_rounds": 0}
				stats[peer_id]["gov_rounds"] = int(stats[peer_id]["gov_rounds"]) + 1

		if cm.congress_active:
			cm.tick(30.0)  # kongre gösterisi: süre dolsun
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

		var bot: int = cm.current_turn_peer_id()
		# Oyun içinde doğan kanatlar / yeni partiler de izlenir.
		if not stats.has(bot):
			stats[bot] = {"actions": {}, "propaganda_received": 0, "gov_rounds": 0}
		var actions: Dictionary = stats[bot]["actions"]
		if bot != last_bot:
			last_bot = bot
			turn_actions = 0
		var done: Dictionary = bm.do_action(bot) if turn_actions < 12 else {}
		_last_done = done
		turn_actions += 1
		if done.is_empty():
			cm._apply_pass(bot, true)
			_bump(actions, "turu_bitir")
			turn_actions = 0
			continue
		match String(done["type"]):
			"law":
				_bump(actions, "yasa")
				_bump(law_types, String(done["law"]))
			"organization":
				_bump(actions, "teskilat")
			"miting":
				_bump(actions, "miting")
			"invest":
				_bump(actions, "yatirim")
			"censure":
				_bump(actions, "gensoru")
			"draw":
				_bump(actions, "kart_cek")
			"card":
				var card := String(done["card"])
				_bump(actions, card if not card.begins_with("steal_") else "vekil_calma")
				if card == "karalama":
					var target := int(done["peer"])
					var province_id := String(done["province"])
					if stats.has(target):
						stats[target]["propaganda_received"] = int(stats[target]["propaganda_received"]) + 1
					var entry: Dictionary = marks.get(province_id, {})
					entry[target] = true
					marks[province_id] = entry

	if not cm.game_finished:
		print("TAKILDI: tur %d faz %d sıra %d kasa %.1f son hamle %s" % [cm.round_number, gm.phase, cm.current_turn_peer_id(),
			cm.funds_of(cm.current_turn_peer_id()), str(_last_done)])
	var parties := []
	for rank in cm.final_ranking.size():
		var row: Dictionary = cm.final_ranking[rank]
		var peer_id: int = int(row["peer_id"])
		parties.append({
			"rank": rank + 1, "score": int(row["score"]), "seats": int(row["seats"]),
			"actions": stats.get(peer_id, {}).get("actions", {}), "gov_rounds": stats.get(peer_id, {}).get("gov_rounds", 0),
			"propaganda_received": stats.get(peer_id, {}).get("propaganda_received", 0),
			"orgs": _org_count(peer_id), "funds_end": cm.funds_of(peer_id),
		})
	report["games"].append({"game": g, "steps": steps, "parties": parties, "law_types": law_types,
		"econ_rounds": econ_rounds})

func _org_count(peer_id: int) -> int:
	var pid: int = cm.party_of(peer_id)
	var n := 0
	for province_id in cm.organizations.keys():
		if int((cm.organizations[province_id] as Dictionary).get(pid, 0)) > 0:
			n += 1
	return n

func _econ_snapshot() -> Dictionary:
	var funds := []
	var org_count := {}
	var incomes := []
	for peer_id in cm.turn_order:
		funds.append(cm.funds_of(peer_id))
		incomes.append(cm.org_income(peer_id))
	for province_id in cm.organizations.keys():
		for pid in (cm.organizations[province_id] as Dictionary).keys():
			if int(cm.organizations[province_id][pid]) > 0:
				org_count[pid] = int(org_count.get(pid, 0)) + 1
	var total_orgs := 0
	var max_orgs := 0
	for pid in org_count.keys():
		total_orgs += int(org_count[pid])
		max_orgs = maxi(max_orgs, int(org_count[pid]))
	var fsum := 0.0
	var fmax := 0.0
	for f in funds:
		fsum += float(f)
		fmax = maxf(fmax, float(f))
	var imax := 0
	for i in incomes:
		imax = maxi(imax, int(i))
	return {"round": cm.round_number, "treasury": cm.state_treasury(), "tax": cm.tax_level(),
		"funds_avg": fsum / maxf(1.0, funds.size()), "funds_max": fmax,
		"orgs_total": total_orgs, "orgs_max": max_orgs, "org_income_max": imax}

func _top_party(seats: Dictionary) -> int:
	var best := -1
	for peer_id in seats.keys():
		if best == -1 or int(seats[peer_id]) > int(seats[best]):
			best = int(peer_id)
	return best

func _record_election(g: int, round_snapshot: Dictionary, prev_seats: Dictionary, marks: Dictionary) -> Dictionary:
	var inputs: Dictionary = cm.last_election_inputs
	var seat_counts: Dictionary = cm._province_seat_counts
	# 0.0.284: ayrı güç (kamuoyu / il puanı) katmanı yok; her şey seçmen tabanında.
	var contrib := {}

	# Şans: aynı girdiler, farklı tohumlar.
	var base_top := _top_party(cm.last_seats)
	var top_changes := 0
	var samples := {}
	for s in LUCK_RESEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 100000 + g * 100 + s
		var r := ElectionModel.compute(inputs["groups"], seat_counts, inputs["voters"], float(inputs["threshold"]),
			rng, inputs.get("alliances", {}), cm.vb_election_state())
		if _top_party(r["seats"]) != base_top:
			top_changes += 1
		for peer_id in r["seats"].keys():
			var list: Array = samples.get(peer_id, [])
			list.append(float(r["seats"][peer_id]))
			samples[peer_id] = list
	var std_sum := 0.0
	for peer_id in samples.keys():
		var list: Array = samples[peer_id]
		var mean := 0.0
		for v in list:
			mean += v
		mean /= list.size()
		var variance := 0.0
		for v in list:
			variance += (v - mean) * (v - mean)
		std_sum += sqrt(variance / list.size())

	# İktidar ve muhalefetin vekil değişimi (bir önceki seçime göre).
	var gov_ids: Array = inputs["gov_ids"]
	var changes := []
	if not prev_seats.is_empty():
		for peer_id in cm.last_seats.keys():
			changes.append({"gov": gov_ids.has(peer_id),
				"change": int(cm.last_seats[peer_id]) - int(prev_seats.get(peer_id, 0))})

	# Karalanan parti o ilde yine vekil çıkarabildi mi?
	var hits := 0
	var still_won := 0
	for province_id in marks.keys():
		for target in marks[province_id].keys():
			hits += 1
			if int(cm.last_province_results.get(province_id, {}).get(target, {}).get("seats", 0)) > 0:
				still_won += 1

	var top_share := 0.0
	for peer_id in cm.last_vote_shares.keys():
		top_share = maxf(top_share, float(cm.last_vote_shares[peer_id]))
	return {
		"game": g, "round": cm.last_election_round, "contrib": contrib,
		"luck_top_changes": top_changes, "luck_reseeds": LUCK_RESEEDS,
		"luck_seat_std_avg": std_sum / maxf(1.0, samples.size()),
		"changes": changes, "propaganda_hits": hits, "propaganda_still_won": still_won,
		"top_vote_share": top_share, "gov_size": gov_ids.size(),
	}
