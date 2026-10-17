extends SceneTree
## İTTİFAK SİSTEMİ (0.0.225): bedava kurma, liderin daveti, oybirliği, istek,
## yanıtsızlık = ret, ayrılma (seçim turunda ceza), liderlik devri, seçimle dağılma.
var fails := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String, detail: String = "") -> void:
	if not ok:
		fails += 1
	print(("  [OK]  " if ok else "  [HATA] ") + label + ("  -> " + detail if detail != "" else ""))

var mm
var pm
var cm
var gm

func _turn(peer: int) -> void:
	cm.current_turn_index = cm.turn_order.find(peer)

func run() -> void:
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	var presets = root.get_node("PartyPresets")
	root.get_node("BotManager").set_process(false)
	mm.room_code = ""
	mm.offline_mode = true
	mm.players = {1: {"name": "A"}, 2: {"name": "B"}, 3: {"name": "C"}, 4: {"name": "D"}}
	pm.parties = {}
	for id in [1, 2, 3, 4]:
		pm.parties[id] = {"name": "P%d" % id, "groups": {}, "ready": true}
	check(bool(mm.WORLD_DEFAULTS["alliances"]), "lobi varsayilani: ittifaklar acik")
	cm.init_game()
	cm.turn_order = [1, 2, 3, 4]
	gm.phase = gm.Phase.IDLE
	cm.round_number = 2
	cm.last_seats = {1: 100, 2: 80, 3: 30, 4: 10}
	check(cm.alliances_enabled, "oyun basinda ittifaklar acik")

	print("=== kurma ve davet ===")
	_turn(1)
	var funds_before: float = cm.funds_of(1)
	cm._apply_create_alliance(1, "Birlik", presets.COLORS[0])
	check(cm.alliances.size() == 1 and cm.alliance_leader(1) == 1, "ittifak kuruldu, kurucu lider")
	check(is_equal_approx(cm.funds_of(1), funds_before) and cm.can_choose_main_action(1), "kurmak bedava, hamle hakki gitmedi")
	cm._apply_invite_alliance_party(1, 1, 2)
	cm._apply_invite_alliance_party(1, 1, 3)
	check(cm.alliance_requests.size() == 2, "lider ayni turda birden cok parti davet eder")
	cm._apply_answer_alliance(2, cm.pending_alliance_request(1, 2), true)
	check(cm.alliance_of(2) == 1, "tek uyeli ittifakta (lider) davet kabul edilince katilir")
	# Artık 1 ve 2 üye: 3'ün daveti açıldığında yalnız 1 vardı (oylayan yok).
	var rid3: int = cm.pending_alliance_request(1, 3)
	check((cm.alliance_requests[rid3]["voters"] as Array).is_empty(), "oylayanlar davet anindaki uyeler")
	cm._apply_answer_alliance(3, rid3, true)
	check(cm.alliance_of(3) == 1, "3 katildi")
	_turn(2)
	cm._apply_invite_alliance_party(2, 1, 4)
	check(cm.pending_alliance_request(1, 4) == -1, "lider olmayan uye davet edemez")

	print("=== oybirligi ===")
	_turn(1)
	cm._apply_invite_alliance_party(1, 1, 4)
	var rid4: int = cm.pending_alliance_request(1, 4)
	check((cm.alliance_requests[rid4]["voters"] as Array) == [2, 3], "davette liderin disindaki uyeler oylar", str(cm.alliance_requests[rid4]["voters"]))
	cm._apply_answer_alliance(4, rid4, true)
	cm._apply_answer_alliance(2, rid4, true)
	check(cm.alliance_of(4) == -1, "bir uye henuz onaylamadi: katilim yok")
	cm._apply_answer_alliance(3, rid4, false)
	check(cm.alliance_of(4) == -1 and not cm.alliance_requests.has(rid4), "tek ret basvuruyu dusurur")

	print("=== istek ve yanitsizlik ===")
	_turn(4)
	cm._apply_request_alliance(4, 1)
	var rq: int = cm.pending_alliance_request(1, 4)
	check(rq >= 0 and (cm.alliance_requests[rq]["voters"] as Array).size() == 3, "katilma istegi butun uyelere gider")
	check(cm.alliance_requests_for(1).has(rq) and cm.alliance_requests_for(2).has(rq), "uyeler karar listesinde goruyor")
	cm._apply_answer_alliance(1, rq, true)
	cm._apply_answer_alliance(2, rq, true)
	cm.round_number += cm.ALLIANCE_REQUEST_ROUNDS
	cm._expire_alliance_requests()
	check(not cm.alliance_requests.has(rq) and cm.alliance_of(4) == -1, "yanit vermeyen uye ret sayilir (sure doldu)")
	cm._apply_request_alliance(4, 1)
	rq = cm.pending_alliance_request(1, 4)
	for voter in [1, 2, 3]:
		cm._apply_answer_alliance(voter, rq, true)
	check(cm.alliance_of(4) == 1, "herkes onaylayinca istek sahibi katilir")

	print("=== ayrilma ===")
	cm.round_number = 5
	_turn(3)
	var nat3: float = cm.national_of(3)
	check(not cm.election_this_round(), "normal tur")
	cm._apply_leave_alliance(3)
	check(cm.alliance_of(3) == -1 and is_equal_approx(cm.national_of(3), nat3), "normal turda ayrilmak cezasiz")
	_turn(1)
	cm._apply_leave_alliance(1)
	check(cm.alliance_leader(1) == 2, "lider ayrilinca liderlik en cok vekilli uyeye gecer", str(cm.alliance_leader(1)))
	cm.round_number = GameRules.next_election_round(cm.round_number)
	check(cm.election_this_round(), "secim turu")
	_turn(4)
	var nat4: float = cm.national_of(4)
	cm._apply_leave_alliance(4)
	check(is_equal_approx(cm.national_of(4), nat4 - cm.ALLIANCE_LEAVE_ELECTION_PENALTY), "secim turunda ayrilmak ulusal puan cezasi", "%.1f -> %.1f" % [nat4, cm.national_of(4)])
	check(cm.alliances.is_empty(), "tek uye kalinca ittifak biter")

	print("=== secimle dagilma ===")
	_turn(1)
	cm._apply_create_alliance(1, "Yeni", presets.COLORS[1])
	cm._apply_invite_alliance_party(1, cm.alliance_of(1), 3)
	cm._apply_answer_alliance(3, cm.pending_alliance_request(cm.alliance_of(1), 3), true)
	_turn(2)
	cm._apply_request_alliance(2, cm.alliance_of(1))
	check(not cm.alliance_requests.is_empty(), "acik basvuru var")
	cm.dissolve_all_alliances(true)
	check(cm.alliances.is_empty() and cm.alliance_requests.is_empty(), "secim sonrasi ittifaklar ve basvurular silinir")
	check(cm.were_allies(1, 3) and cm.were_allies(3, 1) and not cm.were_allies(1, 2), "eski ortaklar hatirlanir")

	print("=== ideoloji (etkin hitap) ===")
	var VG = load("res://scripts/voter_groups.gd")
	var a_g := {"emekli": 90.0, "genc": 10.0}
	var b_g := {"emekli": 10.0, "genc": 90.0}
	var mixed: Dictionary = VG.alliance_blend(a_g, [{"groups": a_g, "weight": 1.0}, {"groups": b_g, "weight": 1.0}])
	check(absf(float(mixed["emekli"]) - 70.9) < 0.2 and absf(float(mixed["genc"]) - 32.1) < 0.2, "zit iki parti: emekli 90 -> ~71, genc 10 -> ~32", "%.1f / %.1f" % [mixed["emekli"], mixed["genc"]])
	var same: Dictionary = VG.alliance_blend(a_g, [{"groups": a_g, "weight": 1.0}, {"groups": a_g, "weight": 1.0}])
	check(absf(float(same["emekli"]) - 92.7) < 0.1, "ayni ideoloji: 90 -> 92,7", "%.2f" % same["emekli"])
	var big: Dictionary = VG.alliance_blend(b_g, [{"groups": a_g, "weight": 40.0}, {"groups": b_g, "weight": 10.0}])
	check(float(big["emekli"]) > float(mixed["genc"]), "buyuk ortak daha cok ceker")
	_turn(1)
	cm.alliances_enabled = true
	pm.parties[1]["groups"] = a_g.duplicate()
	pm.parties[3]["groups"] = b_g.duplicate()
	cm.last_vote_shares = {1: 20.0, 3: 20.0}
	var base_emekli: float = float(cm.effective_groups(1)["emekli"])
	cm._apply_create_alliance(1, "Ideoloji", presets.COLORS[4])
	check(cm.alliance_preview_text(3, cm.alliance_of(1)) != "", "katilim onizlemesi var", cm.alliance_preview_text(3, cm.alliance_of(1)))
	cm._apply_invite_alliance_party(1, cm.alliance_of(1), 3)
	cm._apply_answer_alliance(3, cm.pending_alliance_request(cm.alliance_of(1), 3), true)
	check(float(cm.effective_groups(1)["emekli"]) < base_emekli - 10.0, "ittifakta etkin hitap kayar", "%.1f -> %.1f" % [base_emekli, cm.effective_groups(1)["emekli"]])
	check(is_equal_approx(float(pm.parties[1]["groups"]["emekli"]), 90.0), "taban hitap degismez")
	cm.dissolve_all_alliances(true)
	check(is_equal_approx(float(cm.effective_groups(1)["emekli"]), base_emekli), "ittifak dagilinca etkin hitap tabana doner")

	print("=== secim gecesi ===")
	var sim = load("res://scripts/election_night_sim.gd").new()
	var results := {"x": {1: {"percent": 60.0, "seats": 6}, 2: {"percent": 36.0, "seats": 4}, 3: {"percent": 4.0, "seats": 0}}}
	sim.setup(results, {1: 60.0, 2: 36.0, 3: 4.0}, {1: 6, 2: 4, 3: 0}, [1, 2, 3], 7.0, 1, 10.0, {2: 1, 3: 1})
	var mid: Dictionary = sim.sample(9.0)
	check((mid["eligible"] as Array).has(3), "sayim sirasinda: ittifak barajı gecince %4'luk uye baraj alti degil")
	var solo = load("res://scripts/election_night_sim.gd").new()
	solo.setup(results, {1: 60.0, 2: 36.0, 3: 4.0}, {1: 6, 2: 4, 3: 0}, [1, 2], 7.0, 1, 10.0, {})
	check(not (solo.sample(9.0)["eligible"] as Array).has(3), "ittifaksiz %4'luk parti baraj alti")
	_turn(1)
	cm.alliances_enabled = true
	cm._apply_create_alliance(1, "Gece", presets.COLORS[5])
	cm.dissolve_all_alliances(true)
	check(cm.last_election_alliances.size() == 1 and cm.election_alliance_membership().get(1, 0) != 0, "secime giren ittifaklar seçim gecesi icin saklanir")

	print("=== etkilesim ve botlar ===")
	var brain = load("res://scripts/bot_brain.gd")
	cm.alliances_enabled = true
	cm.round_number = 5
	_turn(1)
	cm._apply_create_alliance(1, "Dost", presets.COLORS[6])
	var dost: int = cm.alliance_of(1)
	cm._apply_invite_alliance_party(1, dost, 2)
	cm._apply_answer_alliance(2, cm.pending_alliance_request(dost, 2), true)
	cm.funds[1] = 500.0
	check(not cm.can_play_card(1, root.get_node("CardPresets").REPUTATION_CARD_TYPE, 2), "ortaga kaset oynanamaz")
	check(cm.can_play_card(1, root.get_node("CardPresets").REPUTATION_CARD_TYPE, 3), "ortak olmayana oynanir")
	cm.note_alliance_vote(2, 1, true)
	cm.note_alliance_vote(2, 1, true)
	check(cm.alliance_grievance(1) == 2, "ortagin onergesine HAYIR kuskunluk yazar")
	mm.players[1]["bot"] = true
	check(String(brain.choose_alliance_move(1).get("type", "")) == "leave", "kuskun bot ittifaktan ayrilmak ister")
	cm.round_number = GameRules.next_election_round(cm.round_number)
	check(String(brain.choose_alliance_move(1).get("type", "")) != "leave", "secim turunda (cezali) kuskun bot ayrilmaz")
	cm.round_number = 5
	mm.players[1].erase("bot")
	cm.dissolve_all_alliances(true)
	pm.parties[1]["groups"] = {"emekli": 80.0, "isci": 70.0}
	pm.parties[2]["groups"] = {"genc": 80.0, "isveren": 70.0}
	var plain: float = brain._distance(1, 2)
	check(brain._friend_distance(1, 2) < plain, "eski ortak botlara daha yakin gorunur", "%.2f < %.2f" % [brain._friend_distance(1, 2), plain])
	# Bot barajda zorlanınca ittifak kurar, lider olunca yakın partiyi davet eder.
	mm.election_threshold = 7.0
	mm.players[3]["bot"] = true
	pm.parties[3]["groups"] = {"emekli": 80.0, "isci": 70.0}
	pm.parties[4]["groups"] = {"emekli": 75.0, "isci": 65.0}
	pm.parties[1]["groups"] = {"genc": 80.0, "isveren": 70.0}
	cm.last_vote_shares = {1: 40.0, 2: 40.0, 3: 3.0, 4: 3.0}
	_turn(3)
	var move: Dictionary = brain.choose_alliance_move(3)
	check(String(move.get("type", "")) == "create", "barajdaki bot ittifak kurar", str(move))
	cm._apply_create_alliance(3, String(move["name"]), move["color"])
	move = brain.choose_alliance_move(3)
	check(String(move.get("type", "")) == "invite" and int(move.get("party", -1)) == 4, "lider bot yakin partiyi davet eder", str(move))
	mm.players[3].erase("bot")
	cm.dissolve_all_alliances(false)

	print("=== anayasa ===")
	_turn(1)
	cm._apply_create_alliance(1, "Son", presets.COLORS[2])
	mm.apply_constitution({"alliances_enabled": false})
	check(cm.alliances.is_empty() and not cm.alliances_enabled, "anayasa kapatinca ittifaklar dagilir")
	mm._apply_world_settings(mm._world_with("alliances", false))
	cm.init_game()
	check(not cm.alliances_enabled, "lobide kapatilirsa oyun ittifaksiz baslar")
	mm._apply_world_settings(mm._world_with("alliances", true))
	print("")
	print("SONUC: ", "TUM TESTLER GECTI" if fails == 0 else "%d HATA" % fails)
	quit(1 if fails > 0 else 0)
