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
