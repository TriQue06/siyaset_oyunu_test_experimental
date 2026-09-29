extends SceneTree
## İdeolojik dönüşüm ve SİYASİ KALE testleri (yerel mod, RPC yok):
## parti görüşü değişiminin bedeli, görüşe aykırı yasanın mana bedeli, illerin
## seçmen merkezinin çekilmesi, kalenin kurulması/kalkanı/kaybedilmesi,
## altıgen haritanın bütünlüğü ve olay logu.
##   godot --headless --path . --script res://tools/smoke_test_ideology.gd

var mm
var pm
var cm
var gm
var game_map
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func ideology(e: float, s: float, a: float) -> Dictionary:
	return {"economic": e, "social": s, "administrative": a}

func near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) < eps

func new_game(ideologies: Dictionary) -> void:
	mm.players = {}
	pm.parties = {}
	for peer_id in ideologies.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.3, 0.5, 0.7), "ideology": ideologies[peer_id].duplicate(), "ready": true,
		}
	cm.init_game()
	cm.turn_order = ideologies.keys()
	cm.current_turn_index = 0

func _initialize() -> void:
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	game_map = root.get_node("GameMap")
	cm.fixed_map_seed = 1950
	mm.room_code = ""
	gm.result_hold_seconds = 0.0

	print("=== 1) ALTIGEN HARITA ===")
	var ok_contiguous := true
	for id in game_map.ids:
		var cells: Array = game_map.region_cells(id)
		var seen := {cells[0]: true}
		var queue: Array = [cells[0]]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for n in HexGridGenerator.neighbor_cells(cur, game_map.cols, game_map.rows):
				if not seen.has(n) and game_map.region_at_cell(n) == id:
					seen[n] = true
					queue.append(n)
		if seen.size() != cells.size():
			ok_contiguous = false
	check("her secim bolgesi bitisik altigenlerden olusur", ok_contiguous)
	var total := 0
	var min_seats := 999
	for id in game_map.ids:
		total += game_map.seats_of(id)
		min_seats = mini(min_seats, game_map.seats_of(id))
	check("il vekilleri toplami 300, her bolgede en az 2", total == HexGridGenerator.PROVINCE_SEATS and total == 300 and min_seats >= 2, "%d / min %d" % [total, min_seats])
	var names := {}
	for id in game_map.ids:
		names[game_map.name_of(id)] = true
	check("bolge adlari benzersiz", names.size() == game_map.ids.size())
	var a: Dictionary = HexGridGenerator.generate(99)
	var b: Dictionary = HexGridGenerator.generate(99)
	check("ayni tohum ayni harita", str(a) == str(b))
	var probe: String = game_map.ids[3]
	var cell: int = game_map.region_cells(probe)[0]
	check("noktadan bolge bulunur", game_map.province_at(game_map.cell_center(cell)) == probe)

	cm.fixed_map_seed = 0
	mm.map_seed = mm.clean_map_seed(" 00123-45 ")
	check("tohum temizlenir (sadece rakam)", mm.map_seed == "12345", mm.map_seed)
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	check("lobi tohumu oyunun haritasini belirler", game_map.seed_value() == 12345 		and str(game_map.data["cells"]) == str(HexGridGenerator.generate(12345)["cells"]))
	mm.map_seed = ""
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	check("tohum bossa rastgele tohum atanir", game_map.seed_value() > 0 and game_map.seed_value() != 12345)
	check("bos tohum temizlenince bos kalir", mm.clean_map_seed("abc") == "" and mm.clean_map_seed("0") == "")
	cm.fixed_map_seed = 1950

	print("")
	print("=== 2) PARTI GORUSU DEGISIMININ BEDELI ===")
	check("merkezde kaymak bedava", near(PublicOpinion.ideology_shift_national(0.0, 0.5), 0.0) \
		and near(PublicOpinion.ideology_shift_national(0.5, 0.0), 0.0) and near(PublicOpinion.ideology_shift_national(1.0, 1.5), 0.0))
	check("radikallesmek tabani sarsar", near(PublicOpinion.ideology_shift_national(1.5, 2.0), -PublicOpinion.RADICAL_STEP_COST) \
		and near(PublicOpinion.ideology_shift_national(2.0, 3.0), -2.0 * PublicOpinion.RADICAL_STEP_COST))
	check("yerlesik gorusten donmek tabani sarsar (koklu gorus daha pahali)",
		PublicOpinion.ideology_shift_national(2.5, 2.0) < PublicOpinion.ideology_shift_national(1.0, 0.5) \
		and PublicOpinion.ideology_shift_national(1.0, 0.5) < 0.0)

	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	var cp = root.get_node("CardPresets")
	check("gorusune uygun yasa bedelsiz", cm.law_mana_cost(1, cp.law_type("economic", 1)) == GameRules.LAW_MANA_COST)
	check("gorusune aykiri yasa +1 mana", cm.law_mana_cost(1, cp.law_type("economic", -1)) == GameRules.LAW_MANA_COST + 1)
	pm.parties[1]["ideology"]["economic"] = 2.5
	check("koklu gorusune aykiri yasa +2 mana", cm.law_mana_cost(1, cp.law_type("economic", -1)) == GameRules.LAW_MANA_COST + 2)

	print("")
	print("=== 3) ILLERIN DONUSUMU VE SIYASI KALE ===")
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	var pid: String = game_map.ids[0]
	cm.province_ideology[pid] = ideology(-2.0, 0.0, 0.0)
	var before: Dictionary = cm.province_ideology[pid].duplicate()
	cm._pull_province(pid, 1, PublicOpinion.MITING_PULL)
	var moved: float = float(cm.province_ideology[pid]["economic"]) - float(before["economic"])
	check("miting ilin seçmenini partiye cekti", near(moved, (1.5 - -2.0) * PublicOpinion.MITING_PULL), "%.3f" % moved)
	check("teskilat yokken kale olmaz", cm.stronghold_of(pid) == -1)
	cm.organizations[pid] = {1: 1}
	cm.province_ideology[pid] = ideology(1.5, 1.5, 1.0)
	cm._update_stronghold(pid)
	check("%75+ yakin + teskilat = siyasi kale", cm.stronghold_of(pid) == 1, str(cm.stronghold_closeness(pid, 1)))
	var extra: bool = false
	for entry in cm._pending_log:
		if String(entry["kind"]) == "stronghold":
			extra = true
	check("kale olayi loga iliştirilir", extra)
	var c_before := float(cm.province_ideology[pid]["economic"])
	cm._pull_province(pid, 2, PublicOpinion.MITING_PULL)
	var shielded_move := absf(float(cm.province_ideology[pid]["economic"]) - c_before)
	var free_move := absf((-1.5 - c_before) * PublicOpinion.MITING_PULL)
	check("rakip kaleyi %70 daha yavas cevirir", near(shielded_move, free_move * (1.0 - PublicOpinion.STRONGHOLD_RESISTANCE)),
		"%.3f / %.3f" % [shielded_move, free_move])
	# Parti kendi görüşünü değiştirir: il yerinde kalır, kale hemen yıkılmaz.
	var center_before: Dictionary = cm.province_ideology[pid].duplicate()
	pm.parties[1]["ideology"] = ideology(0.5, 1.5, 1.0)
	cm._update_stronghold(pid)
	check("parti kayinca ilin gorusu degismez", str(cm.province_ideology[pid]) == str(center_before))
	check("kucuk kaymada kale yikilmaz", cm.stronghold_of(pid) == 1, "%.2f" % cm.stronghold_closeness(pid, 1))
	pm.parties[1]["ideology"] = ideology(-2.5, -2.0, -2.0)
	cm._update_stronghold(pid)
	check("kalesinden cok uzaklasan parti kaleyi kaybeder", cm.stronghold_of(pid) == -1, "%.2f" % cm.stronghold_closeness(pid, 1))
	check("kalesinden uzaklasan parti orada daha az destek alir",
		ElectionModel.support(ideology(-2.5, -2.0, -2.0), center_before) < ElectionModel.support(ideology(1.5, 1.5, 1.0), center_before))

	print("")
	print("=== 5) ANAYASA: SAYIM YONTEMI, YASA ORANI, REFERANDUM ===")
	var votes3 := {1: 0.47, 2: 0.33, 3: 0.20}
	check("D'Hondt", str(ElectionModel.dhondt(votes3, [1, 2, 3], 7)) == str({1: 4, 2: 2, 3: 1}), str(ElectionModel.dhondt(votes3, [1, 2, 3], 7)))
	check("Hare kotasi + en buyuk kalan", str(ElectionModel.hare(votes3, [1, 2, 3], 7)) == str({1: 3, 2: 2, 3: 2}), str(ElectionModel.hare(votes3, [1, 2, 3], 7)))
	check("kazanan hepsini alir", str(ElectionModel.winner_takes_all(votes3, [1, 2, 3], 7)) == str({1: 7, 2: 0, 3: 0}))
	ElectionModel.seat_method = "wta"
	check("wta'da ulusal liste D'Hondt kalir", str(ElectionModel.allocate(votes3, [1, 2, 3], 7, true)) == str({1: 4, 2: 2, 3: 1}))
	mm.reset_constitution_rules()
	check("varsayilan: D'Hondt, yasa %50, anayasa %67, referandum %50", ElectionModel.seat_method == "dhondt" 		and mm.law_pass_percent == 50 and mm.constitution_percent == 67 and mm.referendum_percent == 50)
	check("yasa %50 = basit cogunluk", gm.law_passes(51, 49) and not gm.law_passes(50, 50))
	check("varsayilanda 251-249 gecer", gm.law_passes(251, 249))
	mm.law_pass_percent = 67
	check("yasa %67: 2/3 EVET ister", not gm.law_passes(60, 40) and gm.law_passes(70, 30))
	mm.law_pass_percent = 33
	check("yasa %33: 1/3 EVET yeter", gm.law_passes(34, 66) and not gm.law_passes(33, 67))
	mm.reset_constitution_rules()
	check("referandum esigi kabul oraninin altinda olmali", not mm.valid_constitution_rules(
		{"seat_method": "hare", "law_pass": 50, "constitution": 50, "referendum": 50}) 		and mm.valid_constitution_rules({"seat_method": "hare", "law_pass": 50, "constitution": 67, "referendum": 50}))

	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5), 3: ideology(1.5, -1.5, 1.5)})
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.election_seats = cm.last_seats.duplicate()
	cm.round_number = 12
	cm.last_election_round = 8
	cm.current_turn_index = 0
	var change := {"threshold": mm.election_threshold, "interval": mm.election_interval, "seat_method": "hare",
		"law_pass": 60, "constitution": 75, "referendum": 33}
	check("gecersiz paket reddedilir", (func():
		cm._apply_constitution_proposal(1, {"seat_method": "hare", "constitution": 50, "referendum": 67})
		return gm.proposal_kind == "").call())
	cm._apply_constitution_proposal(1, change)
	gm._apply_vote(2, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_NO)
	check("%50 alti EVET: ne kabul ne referandum", mm.seat_method == "dhondt" and gm.last_resolution_reason.find("HALKOYU") == -1,
		gm.last_resolution_reason)
	cm.law_rounds = {}
	cm.national_support = {1: 8.0, 3: 8.0, 2: -8.0}
	cm._apply_constitution_proposal(1, change)
	gm._apply_vote(2, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_YES)
	check("%60 EVET (%67 alti, %50 ustu): halkoyuna gider", gm.last_resolution_reason.find("HALKOYUNA") != -1, gm.last_resolution_reason)
	check("halk kabul edince kurallar degisir", mm.seat_method == "hare" and ElectionModel.seat_method == "hare" 		and mm.law_pass_percent == 60 and mm.constitution_percent == 75 and mm.referendum_percent == 33, gm.last_resolution_reason)
	cm.law_rounds = {}
	# Tek parti EVET (200 ≥ %33), halkın desteği HAYIR tarafında: kesin red.
	cm.last_seats = {1: 200, 2: 150, 3: 150}
	pm.parties[2]["ideology"] = pm.parties[1]["ideology"].duplicate()
	cm.national_support = {1: -10.0, 2: 10.0}
	cm._apply_constitution_proposal(1, {"threshold": mm.election_threshold, "interval": mm.election_interval,
		"seat_method": "wta", "law_pass": 60, "constitution": 75, "referendum": 33})
	gm._apply_vote(2, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_ABSTAIN)
	check("halk reddederse kurallar degismez", mm.seat_method == "hare" and gm.last_resolution_reason.find("reddetti") != -1,
		gm.last_resolution_reason)
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	check("yeni oyunda kurallar varsayilana doner", mm.seat_method == "dhondt" and ElectionModel.seat_method == "dhondt" 		and mm.constitution_percent == 67)

	print("")
	print("=== 4) OLAY LOGU ===")
	cm.clear_event_log()
	cm.log_event("deneme", 1, pid, "miting")
	check("log kaydi tutulur", cm.event_log.size() == 1 and cm.event_log[0]["province"] == pid)
	for i in cm.EVENT_LOG_LIMIT + 10:
		cm.log_event("kayit %d" % i)
	check("log siniri asilmaz", cm.event_log.size() == cm.EVENT_LOG_LIMIT)

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit(1 if fails > 0 else 0)
