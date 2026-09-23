extends SceneTree
## ÇEVRİM DIŞI AKIŞ TESTİ: tek başına + botlarla oynanan bir oyunu SANAL SAATLE
## baştan sona oynatır ve OYUNUN TAKILDIĞI yerleri yakalar (hükümet oylaması
## yanıtsız kalması, sıranın dönmemesi, aşamanın kilitlenmesi).
##   godot --headless --path . --script res://tools/smoke_test_offline_flow.gd

const DT := 0.2
## Hiçbir şey değişmeden geçen bu kadar sanal saniye = TAKILMA.
const STALL_LIMIT := 400.0
const MAX_SECONDS := 45000.0
## Sadece botlar bekleniyorsa oylama en geç bu kadar sanal saniyede çözülmeli.
const BOT_VOTE_LIMIT := 15.0
## Görevli bot en geç bu kadar sanal saniyede hükümet teklifini vermeli.
const BOT_FORM_LIMIT := 20.0

var _failed := 0
var mm
var cm
var gm
var pm
var bm

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failed += 1
	print("  [%s]  %s%s" % ["OK" if ok else "HATA", label, ("  -> " + detail) if detail != "" else ""])

func _signature() -> String:
	return "%d|%d|%d|%d|%s|%d|%d|%d|%d|%d|%s" % [gm.phase, cm.round_number, cm.current_turn_index,
		gm.votes.size(), gm.proposal_kind, gm.proposal_stage, gm.mandate_index, gm.attempts_used,
		cm.state_version, gm.state_version, str(cm.game_finished)]

## Oy vermesi beklenen ama henüz vermemiş partiler.
func _pending_voters() -> Array:
	var pending: Array = []
	for peer_id in gm.eligible_voter_ids():
		if not gm.has_voted(peer_id):
			pending.append("%s%d" % ["bot" if mm.is_bot(peer_id) else "insan", peer_id])
	return pending

func _diagnose() -> String:
	return "asama=%d tur=%d sira=%d teklif=%s/%d oy=%d/%d bekleyen=%s sure=%.1f" % [gm.phase,
		cm.round_number, cm.current_turn_index, gm.proposal_kind, gm.proposal_stage,
		gm.eligible_voter_ids().size() - _pending_voters().size(), gm.eligible_voter_ids().size(),
		str(_pending_voters()), gm.phase_seconds_left()]

## Bir oyunu sonuna kadar oynatır. human_votes: insan oyuncu oylamalara katılsın mı?
## Döner: {"stall": bool, "where": String, "seconds": float, "elections": int}
func play(seed_value: int, human_votes: bool) -> Dictionary:
	mm.start_offline("Barış")
	for i in 5:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 3, Color.WHITE, Color("F20C1F"),
		{"economic": 0, "social": 0, "administrative": 0}, true)
	if mm.stage != mm.Stage.IN_GAME:
		return {"stall": true, "where": "oyun hic baslamadi", "seconds": 0.0, "elections": 0}
	cm.set_rng_seed(seed_value)
	bm._rng.seed = seed_value
	gm.result_hold_seconds = 0.5

	var me: int = mm.owner_id
	var now := 0.0
	var last_signature := _signature()
	var last_change := 0.0
	var elections := 0
	var bot_wait_since := -1.0
	var form_wait_since := -1.0
	var last_round: int = cm.round_number
	while now < MAX_SECONDS and not cm.game_finished:
		now += DT
		cm._process(DT)
		gm._process(DT)
		bm.step(now)
		if human_votes and gm.phase == gm.Phase.VOTING and not gm.has_voted(me) \
				and gm.eligible_voter_ids().has(me):
			gm._apply_vote(me, gm.VOTE_YES)
		if cm.round_number != last_round:
			if GameRules.is_election_round(last_round):
				elections += 1
			last_round = cm.round_number
		if gm.phase == gm.Phase.VOTING:
			var pending := _pending_voters()
			var only_bots := not pending.is_empty()
			for peer_id in gm.eligible_voter_ids():
				if not gm.has_voted(peer_id) and not mm.is_bot(peer_id):
					only_bots = false
			if only_bots:
				if bot_wait_since < 0.0:
					bot_wait_since = now
				elif now - bot_wait_since > BOT_VOTE_LIMIT:
					return {"stall": true, "where": "BOTLAR OY VERMIYOR: " + _diagnose(),
						"seconds": now, "elections": elections}
			else:
				bot_wait_since = -1.0
		else:
			bot_wait_since = -1.0
		# BOT GOREVLI HUKUMET TEKLIFI VERMELI: teklif etmezse kurma suresi bosa yanar.
		if gm.phase == gm.Phase.FORMING and mm.is_bot(gm.mandate_peer_id()) 				and gm.phase_seconds_left() <= GameRules.FORMATION_TIMEOUT:
			if form_wait_since < 0.0:
				form_wait_since = now
			elif now - form_wait_since > BOT_FORM_LIMIT:
				return {"stall": true, "where": "BOT HUKUMET TEKLIF ETMIYOR: " + _diagnose(),
					"seconds": now, "elections": elections}
		else:
			form_wait_since = -1.0
		if fmod(now, 500.0) < DT:
			print("    ... %.0f sn: %s" % [now, _diagnose()])
		var signature := _signature()
		if signature != last_signature:
			last_signature = signature
			last_change = now
		elif now - last_change > STALL_LIMIT:
			return {"stall": true, "where": _diagnose(), "seconds": now, "elections": elections}
	return {"stall": not cm.game_finished, "where": "sure doldu: " + _diagnose(),
		"seconds": now, "elections": elections}

func _initialize() -> void:
	await process_frame
	mm = root.get_node("MultiplayerManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	pm = root.get_node("PartyManager")
	bm = root.get_node("BotManager")
	bm.set_process(false)  # sanal saatle biz süreceğiz

	print("=== CEVRIM DISI TAM OYUN (insan OY VERIYOR) ===")
	for seed_value in [11, 22, 33]:
		var result := play(seed_value, true)
		check("seed %d: oyun takilmadan bitti" % seed_value, not result["stall"],
			"%s (%.0f sn, %d secim)" % [result["where"], result["seconds"], result["elections"]])

	print("")
	print("=== CEVRIM DISI TAM OYUN (insan HIC OY VERMIYOR / AFK) ===")
	for seed_value in [11, 22, 33]:
		var result := play(seed_value, false)
		check("seed %d: oyun takilmadan bitti" % seed_value, not result["stall"],
			"%s (%.0f sn, %d secim)" % [result["where"], result["seconds"], result["elections"]])

	print("")
	print("=== %s ===" % ("TUM TESTLER GECTI" if _failed == 0 else "%d TEST BASARISIZ" % _failed))
	quit(1 if _failed > 0 else 0)
