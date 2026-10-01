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
	cm.speech_required = false  # meclis konuşması ayrıca test edilir
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
	check("yakin il + 1. seviye teskilat kale DEGIL", cm.stronghold_of(pid) == -1)
	cm.organizations[pid] = {1: GameRules.ORG_MAX_LEVEL}
	for i in int(PublicOpinion.STRONGHOLD_EFFORT) - 1:
		cm._campaign_in(pid, 1, 1.0)
	check("tam teskilat ama az miting: kale degil", cm.stronghold_of(pid) == -1, str(cm.kale_effort_of(pid, 1)))
	cm._campaign_in(pid, 1, 1.0)
	check("tam teskilat + yeterli miting + yakin secmen = siyasi kale", cm.stronghold_of(pid) == 1, str(cm.stronghold_closeness(pid, 1)))
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
	print("=== 5) ANAYASA VE REFERANDUM ===")
	var votes3 := {1: 0.47, 2: 0.33, 3: 0.20}
	check("D'Hondt", str(ElectionModel.dhondt(votes3, [1, 2, 3], 7)) == str({1: 4, 2: 2, 3: 1}))
	check("Hare kotasi + en buyuk kalan", str(ElectionModel.hare(votes3, [1, 2, 3], 7)) == str({1: 3, 2: 2, 3: 2}))
	check("kazanan hepsini alir", str(ElectionModel.winner_takes_all(votes3, [1, 2, 3], 7)) == str({1: 7, 2: 0, 3: 0}))
	ElectionModel.seat_method = "wta"
	check("wta'da ulusal liste D'Hondt kalir", str(ElectionModel.allocate(votes3, [1, 2, 3], 7, true)) == str({1: 4, 2: 2, 3: 1}))
	mm.reset_seat_method()
	check("varsayilan sayim D'Hondt", ElectionModel.seat_method == "dhondt")
	check("yasa: basit cogunluk (251-249 gecer, 250-250 gecmez)", gm.law_passes(251, 249) and not gm.law_passes(250, 250))
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5), 3: ideology(1.5, -1.5, 1.5)})
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.election_seats = cm.last_seats.duplicate()
	cm.round_number = 5
	cm.last_election_round = 4
	cm.current_turn_index = 0
	check("anayasa %67, referandum esigi salt cogunluk", gm.constitution_threshold_seats() == 334 and gm.referendum_threshold_seats() == 251)
	var change := {"threshold": 5.0, "interval": 3, "seat_method": "hare"}
	cm._apply_constitution_proposal(1, change)
	gm._apply_vote(2, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_NO)
	check("%50 alti EVET: reddedilir, referandum yok", not cm.is_referendum_active() and is_equal_approx(mm.election_threshold, 0.0))
	cm.law_rounds = {}
	cm._apply_constitution_proposal(1, change)
	gm._apply_vote(2, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_YES)
	check("300 EVET (%50 ustu, %67 alti): REFERANDUM basladi", cm.is_referendum_active() \
		and gm.last_resolution_reason.find("REFERANDUM") != -1 and is_equal_approx(mm.election_threshold, 0.0), gm.last_resolution_reason)
	check("referandum tam 2 tur surer", int(cm.referendum["end_round"]) == cm.round_number + 1 and cm.referendum_rounds_left() == 2)
	check("taraflar meclis oyundan", cm.referendum_side(1) == gm.VOTE_YES and cm.referendum_side(3) == gm.VOTE_YES \
		and cm.referendum_side(2) == gm.VOTE_NO)
	cm.mana[1] = 20.0
	var no_org: String = game_map.ids[5]
	cm.organizations.erase(no_org)
	check("referandumda yasa/anayasa/teskilat/yatirim/gensoru yok", not cm.can_propose_law(1) and not cm.can_propose_constitution(1) \
		and not cm.can_build_organization(1, no_org) and not cm.can_invest(1) and not cm.can_censure(1))
	check("referandumda teskilatsiz ilde miting ve karalama serbest", cm.can_miting(1, no_org) \
		and cm.can_play_card(1, "karalama", 2, no_org))
	check("erken secim karti referandumda oynanamaz", not cm.can_play_card(1, "erken_secim"))
	var local_before: float = cm.local_of(no_org, 1)
	var national_before: float = cm.national_of(1)
	var yes0: float = float(cm.referendum_projection()["yes"])
	for i in 6:
		cm._apply_referendum_miting(1, no_org, 0.0)
	var yes1: float = float(cm.referendum_projection()["yes"])
	check("EVET mitingi EVET oyunu arttirir", yes1 > yes0, "%.1f -> %.1f" % [yes0, yes1])
	check("referandum mitingi genel secim destegini degistirmez", near(cm.local_of(no_org, 1), local_before) \
		and near(cm.national_of(1), national_before))
	for i in 4:
		cm._apply_reputation(2, 1)
		cm._apply_referendum_propaganda(2, 3, no_org)
	var yes2: float = float(cm.referendum_projection()["yes"])
	check("EVET diyen partiler karalanip iftiraya ugrayinca EVET duser", yes2 < yes1, "%.1f -> %.1f" % [yes1, yes2])
	check("referandumda kaset genel secime islemez", near(cm.national_of(1), national_before))
	# Tur 5 bitiyor: referandum surer. Takvimde secim olsun: ertelenmeli.
	var interval_rounds: int = GameRules.ELECTION_INTERVAL
	GameRules.set_election_anchor(cm.round_number)
	var elections_before: int = cm.last_election_round
	cm._finish_round()
	check("kampanya surerken secim ERTELENIR", cm.is_referendum_active() and cm.last_election_round == elections_before \
		and bool(cm.referendum["postponed"]), str(cm.referendum.get("postponed")))
	check("1 tur kaldi", cm.referendum_rounds_left() == 1)
	# Halk EVET'e kazansin: EVET tarafinin kampanyasi guclu.
	cm.referendum["national"] = {1: 10.0, 3: 10.0, 2: -10.0}
	cm.referendum["local"] = {}
	cm._finish_round()
	check("2. turun sonunda referandum sonuclanir", not cm.is_referendum_active())
	check("referandumla sayim yontemi de degisir", mm.seat_method == "hare" and ElectionModel.seat_method == "hare")
	check("halk kabul edince anayasa yururluge girer", is_equal_approx(mm.election_threshold, 5.0) and mm.election_interval == 3,
		str(mm.election_threshold))
	check("ertelenen secim referandumdan hemen sonra yapilir", cm.last_election_round == cm.round_number - 1,
		"%d / %d" % [cm.last_election_round, cm.round_number])
	var logged := false
	for entry in cm.event_log:
		if String(entry["text"]).find("REFERANDUM SONUCU") != -1:
			logged = true
	check("sonuc loga duser", logged)
	# Halk reddeder.
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5), 3: ideology(1.5, -1.5, 1.5)})
	mm.election_threshold = 0.0
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.election_seats = cm.last_seats.duplicate()
	cm.round_number = 6
	cm.last_election_round = 4
	cm.current_turn_index = 0
	cm._apply_constitution_proposal(1, {"threshold": 5.0, "interval": 3})
	gm._apply_vote(2, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_YES)
	cm.referendum["national"] = {1: -10.0, 3: -10.0, 2: 10.0}
	cm._finish_round()
	cm._finish_round()
	check("halk reddederse kurallar degismez", not cm.is_referendum_active() and is_equal_approx(mm.election_threshold, 0.0))
	cm.law_rounds = {}
	cm.referendum = {}
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)  # önceki turlarda seçim/kurma açılmış olabilir
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.current_turn_index = 0
	cm._apply_constitution_proposal(1, {"threshold": 0.0, "interval": 2, "seat_method": "wta"})
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(3, gm.VOTE_YES)
	check("2/3 ile sayim 'kazanan hepsini alir' olur", mm.seat_method == "wta" and ElectionModel.seat_method == "wta", gm.last_resolution_reason)
	cm.law_rounds = {}
	cm._apply_constitution_proposal(1, {"threshold": 0.0, "interval": 2, "seat_method": "yok"})
	check("gecersiz sayim yontemi reddedilir", gm.proposal_kind == "")
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	check("yeni oyunda sayim D'Hondt'a doner", mm.seat_method == "dhondt" and ElectionModel.seat_method == "dhondt")

	print("")
	print("=== 4) OLAY LOGU ===")
	cm.clear_event_log()
	cm.log_event("deneme", 1, pid, "miting")
	check("log kaydi tutulur", cm.event_log.size() == 1 and cm.event_log[0]["province"] == pid)
	for i in cm.EVENT_LOG_LIMIT + 10:
		cm.log_event("kayit %d" % i)
	check("log siniri asilmaz", cm.event_log.size() == cm.EVENT_LOG_LIMIT)

	print("")
	print("=== 6) MECLIS KONUSMASI ===")
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5), 3: ideology(1.5, -1.5, 1.5)})
	cm.speech_required = true
	cm.speech_done = false
	cm.mana[1] = 10.0
	var org_pid: String = game_map.ids[2]
	cm.organizations[org_pid] = {1: 1}
	check("sira gelince konusma zorunlu", cm.needs_speech(1) and not cm.needs_speech(2))
	check("konusmadan once hamle yok", not cm.can_choose_main_action(1) and not cm.can_miting(1, org_pid) \
		and not cm.can_play_card(1, "mana_bonusu"))
	cm._apply_pass(1, true)
	check("konusmadan tur bitirilemez", cm.current_turn_peer_id() == 1)
	cm._apply_speech(2, "economic", -1)
	check("sirasi olmayan konusamaz", not cm.speech_done)
	cm._apply_speech(1, "economic", -1)
	check("konusma partiyi yarim adim kaydirir", near(float(pm.parties[1]["ideology"]["economic"]), 1.0) and cm.speech_done,
		str(pm.parties[1]["ideology"]))
	check("konusmadan sonra hamle serbest", cm.can_choose_main_action(1) and cm.can_miting(1, org_pid))
	cm._apply_speech(1, "social", 1)
	check("turda tek konusma", near(float(pm.parties[1]["ideology"]["social"]), 1.5))
	cm._apply_pass(1, true)
	check("siradaki oyuncu yine konusmak zorunda", cm.current_turn_peer_id() == 2 and cm.needs_speech(2))
	cm.speech_required = false

	print("")
	print("=== 7) ILLER BASKIN PARTIYI TAKIP EDER ===")
	new_game({1: ideology(3.0, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	var fid: String = game_map.ids[3]
	cm.province_ideology[fid] = ideology(2.5, 1.0, 1.0)
	cm.local_support[fid] = {1: 10.0}
	var shares: Dictionary = cm._province_share_map()[fid]
	var share1 := float(shares[1]) / 100.0
	var before_e := float(cm.province_ideology[fid]["economic"])
	var other: String = game_map.ids[4]
	cm.province_ideology[other] = ideology(-2.0, -1.0, -1.0)
	var other_before := float(cm.province_ideology[other]["economic"])
	var other_share := float(cm._province_share_map()[other][1]) / 100.0
	cm._shift_ideologies([{"peer": 1, "axis": "economic", "delta": -2.0}])
	var moved_f := float(cm.province_ideology[fid]["economic"]) - before_e
	check("guclu oldugu il partiyle birlikte kayar (pay x yari)", near(moved_f, -2.0 * share1 * PublicOpinion.PROVINCE_FOLLOW, 0.01),
		"%.3f (pay %.2f)" % [moved_f, share1])
	check("zayif oldugu il az kayar", absf(float(cm.province_ideology[other]["economic"]) - other_before) < absf(moved_f) \
		and other_share < share1, "%.2f / %.2f" % [other_share, share1])

	print("")
	print("=== 8) KALE KUSATMASI ===")
	# 4 parti: 1 kale sahibi, 2 ona benzer, 3 ve 4 zit gorusde.
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(1.5, 1.5, 1.0), 3: ideology(-1.5, -1.5, -1.5), 4: ideology(-1.5, -1.5, 1.5)})
	var kid: String = game_map.ids[5]
	cm.province_ideology[kid] = ideology(1.5, 1.5, 1.5)
	cm.organizations[kid] = {1: GameRules.ORG_MAX_LEVEL}
	cm.kale_effort[kid] = {1: PublicOpinion.STRONGHOLD_EFFORT}
	cm._update_stronghold(kid)
	check("kale kuruldu", cm.stronghold_of(kid) == 1)
	for i in 6:
		cm._campaign_in(kid, 3, 1.0)
	check("tek parti ne kadar miting yapsa da kaleyi dusuremez", cm.stronghold_of(kid) == 1, "kusatma %.1f" % cm.siege_total(kid))
	for i in 3:
		cm._campaign_in(kid, 4, 1.0)
	check("zit gorusten 2 parti de yetmez", cm.stronghold_of(kid) == 1, "kusatma %.1f" % cm.siege_total(kid))
	cm._campaign_in(kid, 1, 1.0)
	check("sahibinin mitingi kusatmayi geriletir", cm.siege_total(kid) < 4.0, "%.1f" % cm.siege_total(kid))
	cm.siege.erase(kid)
	for p in [3, 4]:
		for i in 3:
			cm._campaign_in(kid, p, 1.0)
	cm._campaign_in(kid, 2, 1.0)
	cm._campaign_in(kid, 2, 1.0)
	check("ucuncu parti katilinca kale duser", cm.stronghold_of(kid) != 1 and cm.kale_effort_of(kid, 1) == 0.0)
	# Benzer görüşte iki parti yeterli.
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(1.5, 1.5, 1.0), 3: ideology(1.5, 1.0, 1.5)})
	cm.province_ideology[kid] = ideology(1.5, 1.5, 1.5)
	cm.organizations[kid] = {1: GameRules.ORG_MAX_LEVEL}
	cm.kale_effort[kid] = {1: PublicOpinion.STRONGHOLD_EFFORT}
	cm._update_stronghold(kid)
	for i in 3:
		cm._campaign_in(kid, 2, 1.0)
	check("benzer gorusten tek parti de dusuremez", cm.stronghold_of(kid) == 1, "%.1f" % cm.siege_total(kid))
	for i in 3:
		cm._campaign_in(kid, 3, 1.0)
	check("benzer gorusten 2 parti kaleyi dusurur", cm.stronghold_of(kid) != 1, "%.1f" % cm.siege_total(kid))

	print("")
	print("=== 9) KARISIKLIK, BOLUNME VE GERI DONUS ===")
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5), 3: ideology(1.5, -1.5, 1.5)})
	mm.players[2]["bot"] = true
	cm.last_seats = {1: 200, 2: 150, 3: 150}
	cm.election_seats = cm.last_seats.duplicate()
	cm.national_list = {1: 80, 2: 60, 3: 60}
	cm.last_election_round = 4
	cm.round_number = 5
	cm.organizations[kid] = {1: 2}
	cm._apply_card_effect(2, "isyan", 1)
	check("tek ic karisiklik bolmez", cm.turmoil_of(1) < PublicOpinion.SPLIT_TURMOIL)
	cm._apply_card_effect(2, "isyan", 1)
	var turn_size: int = cm.turn_order.size()
	cm.current_turn_index = 0
	gm.government = {"pm": 3}  # hükümet var: tur sonunda erken seçim olmasın
	gm.main_gov_peer_id = 3
	gm._set_phase(gm.Phase.GOVERNING)
	GameRules.configure(2, 8)
	GameRules.set_election_anchor(0)
	cm.round_number = 5  # seçim turu değil
	cm._finish_round()
	check("karisiklik esigi asildi: parti bolundu", cm.splinters.size() == 1 and cm.turn_order.size() == turn_size + 1,
		str(cm.splinters))
	var sid: int = int(cm.splinters.keys()[0]) if not cm.splinters.is_empty() else -1
	check("ayrilan parti yapay zeka, ayni gorus, benzer renk", mm.is_bot(sid) \
		and str(pm.parties[sid]["ideology"]) == str(pm.parties[1]["ideology"]) \
		and not Color(pm.parties[sid]["bg_color"]).is_equal_approx(Color(pm.parties[1]["bg_color"])))
	var split_seats := int(cm.last_seats.get(sid, 0))
	check("vekillerin ciddi bolumu gecti", split_seats >= int(200 * PublicOpinion.SPLIT_SEAT_SHARE_MIN) - 1 \
		and cm.last_seats[1] + split_seats == 200, "%d / %d" % [split_seats, cm.last_seats[1]])
	check("ayrilan parti bir daha bolunemez", true)
	cm.turmoil[sid] = 99.0
	cm._check_splits()
	check("ayrilan parti tekrar bolunmez", cm.splinters.size() == 1)
	cm.turmoil[1] = 99.0
	cm._check_splits()
	check("ana partinin ayni anda ikinci ayriligi yok", cm.splinters.size() == 1)
	cm.organizations[kid][sid] = 2
	cm.organizations[kid][1] = 1
	cm.turmoil[1] = 0.5
	cm._check_reunions()
	check("secim atlatmadan geri donmez", cm.splinters.has(sid))
	cm.splinters[sid]["elections"] = 1
	cm.turmoil[1] = 5.0
	cm._check_reunions()
	check("karisiklik surerken 1 secimden sonra donmez", cm.splinters.has(sid))
	gm.scores[sid] = 7
	gm.scores[1] = 3
	cm.splinters[sid]["elections"] = PublicOpinion.SPLIT_MAX_ELECTIONS
	cm._check_reunions()
	check("en gec 4 secimden sonra doner", not cm.splinters.has(sid) and not cm.turn_order.has(sid) and not pm.parties.has(sid))
	check("vekilleri ve teskilatlariyla doner, puan birlesir", cm.last_seats[1] == 200 and cm.organization_level(kid, 1) == 2 \
		and gm.score_of(1) == 10, "%d mv, puan %d" % [cm.last_seats[1], gm.score_of(1)])

	print("")
	print("=== 10) YENI KARTLAR VE KURALLAR ===")
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	check("tur basina mana 3 (hukumet 4)", GameRules.MANA_PER_ROUND == 3 and GameRules.MANA_PER_ROUND_GOVERNMENT == 4)
	check("yasa gecirmek +5 puan", cm.law_pass_score(false) == 5 and cm.law_pass_score(true) == 5)
	check("bakanlik +3, yardimcilik +5, basbakanlik +10", GovernmentPresets.MINISTRY_POINTS == 3 \
		and GovernmentPresets.DEPUTY_PM_POINTS == 5 and GovernmentPresets.PM_POINTS == 10)
	cm.mana[1] = 0.0
	cm._apply_card_effect(1, "mana_bonusu_guclu")
	check("guclu mana bonusu +6", near(cm.mana_of(1), 6.0))
	cm.inventories[1] = []
	cm._apply_card_effect(1, "bonus_kart")
	check("bonus kart 2 kart ceker", cm.inventories[1].size() == 2, str(cm.inventories[1]))
	cm.inventories[2] = ["karalama"]
	cm._apply_card_effect(1, "kart_calma", 2)
	check("kart calma: rakibin kartini alir", cm.inventories[2].is_empty() and cm.inventories[1].size() == 3)
	cm._apply_card_effect(1, "kart_calma", 2)
	check("eli bossa kart bosa gider", cm.inventories[1].size() == 3)
	var bot_name_lengths := {}
	var name_ok := true
	for i in 40:
		var n: String = pm._bot_party_name([])
		bot_name_lengths[n.length()] = true
		if not n.ends_with("P") or n.length() < 2 or n.length() > 3:
			name_ok = false
	check("bot adlari XP bicimi (1-2 harf + P)", name_ok and bot_name_lengths.has(2) and bot_name_lengths.has(3), str(bot_name_lengths.keys()))
	check("parti adi 1-14 karakter", pm.NAME_MAX_LENGTH == 14 and pm.is_valid_name("A") and pm.is_valid_name("12345678901234") \
		and not pm.is_valid_name("123456789012345"))
	mm.players = {10: {"name": "insan"}, 11: {"name": "", "bot": true}, 12: {"name": "", "bot": true}}
	pm.parties = {10: {"name": "Insan", "bg_color": Color("22A9D6")}}
	pm.add_bot_party(11)
	pm.add_bot_party(12)
	var close_pair := false
	var colors: Array = [Color("22A9D6"), Color(pm.parties[11]["bg_color"]), Color(pm.parties[12]["bg_color"])]
	for ci in colors.size():
		for cj in range(ci + 1, colors.size()):
			if pm.color_distance(colors[ci], colors[cj]) < pm.BOT_COLOR_MIN_DISTANCE:
				close_pair = true
	check("bot renkleri oyunculara ve birbirine cok yakin degil", not close_pair, str(colors))
	pm.parties[10]["bg_color"] = colors[1]
	pm._adjust_bot_colors()
	check("oyuncu botun rengine yakin renk secince bot uzaklasir",
		pm.color_distance(Color(pm.parties[11]["bg_color"]), colors[1]) >= pm.BOT_COLOR_MIN_DISTANCE)

	print("")
	print("=== 11) BOTLAR ANAYASA DEGISIKLIGI ONERIR ===")
	var brain = load("res://scripts/bot_brain.gd")
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5), 3: ideology(1.5, -1.5, 1.5)})
	for id in [1, 2, 3]:
		mm.players[id]["bot"] = true
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)
	mm.election_threshold = 7.0
	cm.last_seats = {1: 30, 2: 300, 3: 170}
	cm.last_vote_shares = {1: 6.0, 2: 60.0, 3: 8.0}
	cm.current_turn_index = 0
	cm.round_number = 9
	brain._constitution_rounds = {}
	var plan: Dictionary = brain._best_constitution(1)
	check("buyukler istemezse baraj teklifi cogunluk bulamaz, teklif yok", plan.is_empty(), str(plan))
	cm.last_seats = {1: 120, 2: 200, 3: 180}
	plan = brain._best_constitution(1)
	check("barajda zorlanan bot (ve zorlanan ortagi) barajin dusmesini onerir", not plan.is_empty()
		and float(plan["payload"]["threshold"]) < 7.0, str(plan))
	var action: Dictionary = brain.choose_action(1)
	check("bot hamlesi anayasa teklifi", String(action.get("type", "")) == "constitution", str(action))
	root.get_node("BotManager").do_action(1)
	check("teklif meclise geldi, bot not aldi", gm.proposal_kind == gm.KIND_CONSTITUTION
		and brain._best_constitution(1).is_empty())
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)
	mm.election_threshold = 0.0

	print("")
	print("=== 12) DUSMANCA BARAJ VE KAZANAN HEPSINI ALIR ===")
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5), 3: ideology(1.5, -1.5, 1.5)})
	for id in [1, 2, 3]:
		mm.players[id]["bot"] = true
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)
	mm.election_threshold = 0.0
	cm.last_seats = {1: 260, 2: 230, 3: 10}
	cm.last_vote_shares = {1: 50.0, 2: 47.5, 3: 2.5}
	cm.last_province_results = {}
	brain._constitution_rounds = {}
	var hostile: Dictionary = brain._best_constitution(1)
	check("barajda zorlanan rakibi gorunce bot barajı yukseltmeyi onerir", not hostile.is_empty()
		and float(hostile["payload"]["threshold"]) >= 3.0, str(hostile))
	check("zorlanan parti yukselen baraja HAYIR der", brain._constitution_vote(3, {"threshold": 3.0}) == gm.VOTE_NO)
	check("guvendeki buyuk parti yukselen baraja EVET der", brain._constitution_vote(2, {"threshold": 3.0}) == gm.VOTE_YES)
	# Kazanan hepsini alır: 1 birçok ilde birinci, 2 hiçbirinde.
	var ids: Array = game_map.ids
	for i in ids.size():
		var n: int = game_map.seats_of(ids[i])
		var a_seats: int = n / 2 + 1 if i % 4 != 0 else n / 2
		cm.last_province_results[ids[i]] = {1: {"percent": 52.0 if i % 4 != 0 else 40.0, "seats": a_seats},
			2: {"percent": 45.0 if i % 4 != 0 else 55.0, "seats": n - a_seats}}
	check("cok ilde birinci partiye WTA vekil kazandirir", brain.wta_seat_gain(1) > 10 and brain.wta_seat_gain(2) < 0,
		"%d / %d" % [brain.wta_seat_gain(1), brain.wta_seat_gain(2)])
	mm.election_threshold = 3.0  # baraj zaten rakibi disarida birakiyor
	brain._constitution_rounds = {}
	var wta_plan: Dictionary = brain._best_constitution(1)
	check("bot kazanan hepsini alir sayimini onerir", not wta_plan.is_empty()
		and String(wta_plan["payload"]["seat_method"]) == "wta", str(wta_plan))
	check("az ilde birinci rakip WTA'ya HAYIR der", brain._constitution_vote(2, {"seat_method": "wta"}) == gm.VOTE_NO)
	mm.election_threshold = 0.0
	cm.last_province_results = {}

	print("")
	print("=== 13) KALE DUSEBILIR (ihmal ve oyda geriye dusme) ===")
	new_game({1: ideology(1.5, 1.5, 1.5), 2: ideology(-1.5, -1.5, -1.5)})
	var uid: String = game_map.ids[6]
	cm.province_ideology[uid] = ideology(1.5, 1.5, 1.5)
	cm.organizations[uid] = {1: GameRules.ORG_MAX_LEVEL}
	cm.kale_effort[uid] = {1: PublicOpinion.STRONGHOLD_EFFORT}
	cm._update_stronghold(uid)
	check("kale kuruldu", cm.stronghold_of(uid) == 1)
	var rounds := 0
	while cm.stronghold_of(uid) == 1 and rounds < 40:
		cm.province_ideology[uid] = ideology(1.5, 1.5, 1.5)
		cm._check_stronghold_upkeep()
		rounds += 1
	check("ihmal edilen kale (hic miting yok) zamanla duser", cm.stronghold_of(uid) == -1 and rounds > 4, "%d tur" % rounds)
	cm.kale_effort[uid] = {1: PublicOpinion.STRONGHOLD_EFFORT}
	cm._update_stronghold(uid)
	cm._check_stronghold_upkeep()
	check("bakimli kale tur sonunu atlatir", cm.stronghold_of(uid) == 1)
	# Rakip ilde oyda öne geçer.
	cm.local_support[uid] = {2: 10.0}
	cm.national_support = {2: 10.0}
	pm.parties[2]["ideology"] = ideology(1.5, 1.5, 1.5)
	cm._check_stronghold_upkeep()
	check("rakip oyda one gecince kale duser ve hemen geri gelmez", cm.stronghold_of(uid) != 1 \
		and cm.kale_effort_of(uid, 1) == 0.0)

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit(1 if fails > 0 else 0)
