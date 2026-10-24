extends SceneTree
## TUR AKIŞI TESTİ (0.0.231): sıra başında tek kart çekimi (anında / saklanabilir),
## afet yardım kararı (geçilen karar aynı sıra yeniden açılmaz), MECLİS akışı
## (gensoru → toplantı → yasa → soruşturma; geçilen aşama geri gelmez, uygun
## olmayan atlanır), il hamlelerinde bütçe kademeleri, sıra başına 3 miting /
## 3 yatırım sınırı ve mitingin içinde karalama.
##   godot --headless --path . --script res://tools/smoke_test_turn_flow.gd

var mm
var pm
var cm
var gm
var gp
var cp
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func groups(core: Array = []) -> Dictionary:
	return VoterGroups.start_affinities(core)

func new_game() -> void:
	mm.players = {}
	pm.parties = {}
	pm.politicians = {}
	var cores := {1: ["isveren", "milliyetci"], 2: ["isci", "ilerici"], 3: ["emekli", "dindar"]}
	var i := 0
	for peer_id in cores.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.2 * i, 0.5, 0.7), "core": cores[peer_id], "groups": groups(cores[peer_id]), "ready": true}
		i += 1
	cm.init_game()
	cm.turn_order = [1, 2, 3]
	cm.current_turn_index = 0
	cm._grant_turn_income()

## Sırayı peer'e verir ve yeni sıra başlatır (gelir + akış).
func give_turn(peer_id: int) -> void:
	cm.current_turn_index = cm.turn_order.find(peer_id)
	cm._turn_time_left = GameRules.TURN_TIMEOUT
	cm._grant_turn_income()

func finish_vote(choice: int) -> void:
	for voter in gm.voter_ids():
		if not gm.votes.has(voter):
			gm._apply_vote(voter, choice)
	for n in 4:
		gm.tick(1.0)

func all_posts_to(peer_id: int) -> Dictionary:
	var a := {}
	for post in gp.POSTS:
		a[post["id"]] = peer_id
	return a

func form_government(seats: Dictionary, assignments: Dictionary) -> void:
	cm.last_seats = seats.duplicate()
	cm.last_election_round = 1
	gm.start_formation()
	gm._apply_government_proposal(gm.mandate_peer_id(), assignments)
	for peer_id in seats.keys():
		gm._apply_vote(peer_id, true)
	for n in 4:
		gm.tick(1.0)

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	cp = root.get_node("CardPresets")
	root.get_node("BotManager").set_process(false)
	mm.room_code = ""
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	gm.result_hold_seconds = 0.0
	mm.election_threshold = 0.0
	cm.set_rng_seed(77)

	print("=== 1) ILK SECIM ONCESI: KART CEK, MECLIS YOK, IL HAMLELERI ===")
	new_game()
	check("miting / yatirim siniri varsayilan 5 (lobi ayari)", cm.action_limit(1) == 5 and mm.WORLD_OPTIONS["action_limit"] == [4, 5, 6])
	# Aşağıdaki sınır denemeleri lobide 4 (en küçük seçenek) seçilmiş gibi.
	mm.world_settings["action_limit"] = 4
	check("sira basinda kart cekilmedi, KART CEK bekleniyor", cm.needs_turn_draw(1) and cm.inventories[1].is_empty())
	var time_before: float = cm._turn_time_left
	cm.tick(5.0)
	check("cekim beklenirken tur sayaci islemez", is_equal_approx(cm._turn_time_left, time_before))
	var funds0: float = cm.funds_of(1)
	cm._apply_draw(1)
	var draws: Array = cm.turn_draws(1)
	check("kart cekildi", not cm.needs_turn_draw(1) and not draws.is_empty(), str(draws))
	cm._apply_draw(1)
	check("ayni sirada ikinci cekim yok", cm.turn_draws(1) == draws)
	# Yeniden bağlanma: durum paketlenip geri uygulanınca çekim hakkı geri gelmez.
	cm._apply_state(cm._pack_state(true))
	check("yeniden baglanma cift cekim saglamaz", not cm.needs_turn_draw(1))
	check("ilk secimden once meclis akisi yok", cm.parliament_stage(1) == "")
	var province: String = cm._province_ids[0]
	cm.funds[1] = 200.0
	cm._apply_organization(1, province)
	check("il panelinden teskilat kurulur", cm.organization_level(province, 1) == 1)
	var before_miting: float = cm.funds_of(1)
	cm._apply_miting_move(1, province, 0.0, [], 0)
	check("kucuk miting 10 milyon", is_equal_approx(before_miting - cm.funds_of(1), 10.0) and cm.miting_count(1) == 1)
	cm._apply_miting_move(1, province, 0.0, [], 2)
	check("buyuk miting 25 milyon", is_equal_approx(before_miting - cm.funds_of(1), 35.0) and cm.miting_count(1) == 2)
	cm._apply_miting_move(1, province, 0.0, [], 1)
	check("orta miting 15 milyon, 3. hak", is_equal_approx(before_miting - cm.funds_of(1), 50.0) and cm.miting_count(1) == 3)
	cm._apply_miting_move(1, province, 0.0, [], 0)
	check("4. miting (sinir 4)", cm.miting_count(1) == 4)
	check("5. miting reddedilir", not cm.can_miting(1, province))
	var after_four: float = cm.funds_of(1)
	cm._apply_miting_move(1, province, 0.0, [], 1)
	check("5. miting otorite tarafinda da reddedilir", cm.miting_count(1) == 4 and is_equal_approx(cm.funds_of(1), after_four))
	cm.funds[2] = 5.0
	give_turn(2)
	cm._apply_draw(2)
	check("yeni sirada miting hakki tazelenir", cm.miting_count(2) == 0)
	var poor: float = cm.funds_of(2)
	cm.funds[2] = 9.0
	cm._apply_miting_move(2, province, 0.0, [], 0)
	check("para yetmezse miting yok, kasa eksiye dusmez", cm.miting_count(2) == 0 and cm.funds_of(2) >= 0.0)
	cm.funds[2] = poor

	print("=== 2) ANINDA VE SAKLANABILIR KARTLAR ===")
	var instant_ok := true
	var hand_ok := true
	var saw_instant := false
	var saw_hand := false
	for n in 40:
		give_turn(3)
		cm.inventories[3] = []
		cm.populism.erase(3)
		var funds_before: float = cm.funds_of(3)
		cm._apply_draw(3)
		for entry in cm.turn_draws(3):
			var card := String(entry["card"])
			if String(entry["result"]) == "instant":
				saw_instant = true
				if cm.inventories[3].has(card):
					instant_ok = false
			elif String(entry["result"]) == "hand":
				saw_hand = true
				if not cm.inventories[3].has(card):
					hand_ok = false
		var expected: float = cm.instant_funds_of(3, cm.turn_draws(3))
		if not is_equal_approx(cm.funds_of(3) - funds_before, expected):
			instant_ok = false
		# Aynı durumun yeniden yayını bonusu tekrar vermez.
		var funds_after: float = cm.funds_of(3)
		cm._apply_state(cm._pack_state(false))
		if not is_equal_approx(cm.funds_of(3), funds_after):
			instant_ok = false
	check("anindaki kart ele girmez, etkisi bir kez uygulanir", saw_instant and instant_ok)
	check("saklanabilir kart ele girer", saw_hand and hand_ok)
	check("bonus kart destede yok", not cm._draw_weights(3).has("bonus_kart"))
	cm.populism[cm.party_of(3)] = cm.round_number + 1
	check("popülizm surerken desteden popülizm cikmaz", not cm._draw_weights(3).has(cp.POPULISM_CARD_TYPE))
	check("popülizm bir donem surer", GameRules.POPULISM_ROUNDS == 1 and cm.populism_rounds_left(3) == 1)
	cm.populism.erase(cm.party_of(3))
	# OLUMSUZ / ESNEK ŞANS KARTLARI
	cm.funds[3] = 50.0
	var fine_entry: Array = []
	cm._resolve_draw(3, cp.PENALTY_CARD_TYPE, fine_entry, PackedStringArray())
	check("para cezasi kasanin %20'sini siler", is_equal_approx(cm.funds_of(3), 40.0) and is_equal_approx(float(fine_entry[0]["amount"]), 10.0))
	var national_before: float = cm.national_of(3)
	var turmoil_before: float = cm.turmoil.get(cm.party_of(3), 0.0)
	cm._resolve_draw(3, cp.SELF_TURMOIL_CARD_TYPE, [], PackedStringArray())
	check("parti ici karisiklik oyuncunun kendisini vurur", cm.national_of(3) < national_before
		and float(cm.turmoil.get(cm.party_of(3), 0.0)) > turmoil_before)
	give_turn(3)
	var limit_before: int = cm.action_limit(3)
	cm._resolve_draw(3, cp.FLEX_CARD_TYPE, [], PackedStringArray())
	check("esnek hareket o sira siniri iki katina cikarir", cm.action_limit(3) == limit_before * 2)
	give_turn(3)
	check("esnek hareket sonraki sirada biter", cm.action_limit(3) == limit_before)
	check("olumsuz kartlar anindadir, ele girmez", cm.is_instant_card(cp.PENALTY_CARD_TYPE) and cm.is_negative_card(cp.SELF_TURMOIL_CARD_TYPE))
	cm.inventories[3] = [cp.REPUTATION_CARD_TYPE]
	var free_funds: float = cm.funds_of(3)
	cm._apply_play(3, 0, 1)
	check("kartlarin fiyati yok", cm.inventories[3].is_empty() and is_equal_approx(cm.funds_of(3), free_funds))
	check("kart bozdurma yok", not cm.has_method("discard_card"))
	give_turn(3)
	cm.inventories[3] = []
	for k in cm.MAX_HAND_SIZE:
		cm.inventories[3].append(cp.REBELLION_CARD_TYPE)
	cm._apply_draw(3)
	check("el doluysa kart cekilmez (eski kural), kayip kart yok", cm.inventories[3].size() == cm.MAX_HAND_SIZE
		and String(cm.turn_draws(3)[0]["result"]) == "full")
	give_turn(1)
	cm._apply_pass(1)
	check("kart cekmeden biten sirada kart yine verilir", cm.current_turn_peer_id() == 2 and cm.turn_flow.get("peer") == 2)

	print("=== 3) MECLIS: GRUBU OLAN MUHALEFET ===")
	new_game()
	form_government({1: 300, 2: 120, 3: 80}, all_posts_to(1))
	check("hukumet kuruldu", gm.has_government() and gm.has_majority())
	cm.funds = {1: 200.0, 2: 200.0, 3: 200.0}
	give_turn(2)
	cm._apply_draw(2)
	check("cogunluk hukumetinde gensoru yok, ilk asama toplanti", cm.parliament_stage(2) == "speech", cm.parliament_stage(2))
	check("toplanti karari verilmeden yasa sunulamaz", not cm.can_propose_law(2, cp.law_type("isci")))
	cm._apply_speech(2, "isci")
	check("toplanti yapildi, yasa asamasi", cm.parliament_stage(2) == "law", cm.parliament_stage(2))
	check("toplanti ayni sira tekrar yapilamaz", not cm.needs_speech(2))
	cm._apply_law(2, cp.law_type("isci"))
	check("yasa oylamasi acildi", gm.phase == gm.Phase.VOTING)
	check("oylama surerken akis yasa asamasinda bekler", cm.parliament_stage(2) == "law")
	finish_vote(gm.VOTE_NO)
	check("oylama bitti, sira hala bende", cm.current_turn_peer_id() == 2 and not cm.is_turn_blocked())
	var stage_after_law: String = cm.parliament_stage(2)
	check("yasa alani acik (anayasa / erken secim hakki) ya da sonraki asama", stage_after_law in ["law", ""], stage_after_law)
	check("grup yasasi donemde bir kez", not cm.can_propose_law(2, cp.law_type("ilerici")))
	if stage_after_law == "law":
		check("anayasa hakki yasa alaninda", cm.can_propose_constitution(2))
		cm._apply_parl_pass(2, "law")
	check("meclis akisi tamamlandi (0.0.238: soruşturma aşaması yok)", cm.parliament_stage(2) == "")
	check("tamamlanan akista yasa yeniden acilmaz", not cm.can_propose_constitution(2) and not cm.can_early_election(2))

	print("=== 4) GECILEN ASAMA GERI ALINAMAZ, MECLISE GIRMEDEN TUR BITER ===")
	give_turn(3)
	cm._apply_draw(3)
	check("grubu olan oyuncuda toplanti asamasi", cm.parliament_stage(3) == "speech")
	cm._apply_parl_pass(3, "speech")
	check("toplanti gecildi: ayni sira yapilamaz", not cm.needs_speech(3) and cm.parliament_stage(3) == "law")
	cm._apply_speech(3, "emekli")
	check("gecilen toplantiya dogrudan cagri reddedilir", int(cm.speech_rounds.get(3, 0)) != cm.round_number)
	cm._apply_parl_pass(3, "speech")
	check("gecilmis asamayi tekrar gecmek akisi bozmaz", cm.parliament_stage(3) == "law")
	cm._apply_parl_pass(3, "censure")
	check("sirasi gelmeyen asama gecilemez", cm.parliament_stage(3) == "law")
	cm._apply_pass(3)
	check("meclise girmeden tur bitirilebilir", cm.current_turn_peer_id() != 3)

	print("=== 5) GRUBU / VEKILI OLMAYAN OYUNCU ===")
	cm.last_seats = {1: 480, 2: 20, 3: 0}
	give_turn(3)
	cm._apply_draw(3)
	check("vekilsiz oyuncuda meclis akisi yok", cm.parliament_stage(3) == "", cm.parliament_stage(3))
	give_turn(2)
	cm._apply_draw(2)
	cm.last_seats[2] = cm.group_seat_requirement() - 5
	var small_stage: String = cm.parliament_stage(2)
	check("grubu olmayan vekilli oyuncuda toplanti atlanir", small_stage in ["law", ""], small_stage)

	print("=== 6) AZINLIK HUKUMETI: GENSORU ONCELIKLI ===")
	new_game()
	form_government({1: 200, 2: 180, 3: 120}, all_posts_to(1))
	check("azinlik hukumeti", gm.has_government() and not gm.has_majority())
	cm.funds = {1: 200.0, 2: 200.0, 3: 200.0}
	gm.formed_round = -5
	give_turn(1)
	cm._apply_draw(1)
	check("hukumet partisine gensoru acilmaz", cm.parliament_stage(1) != "censure", cm.parliament_stage(1))
	give_turn(2)
	cm._apply_draw(2)
	check("yetkili muhalefette ilk asama gensoru", cm.parliament_stage(2) == "censure", cm.parliament_stage(2))
	check("gensoru karari verilmeden toplanti yok", not cm.needs_speech(2))
	cm._apply_censure_move(2)
	check("gensoru oylamasi basladi", gm.phase == gm.Phase.VOTING)
	finish_vote(gm.VOTE_NO)
	check("gensoru reddedildi, sira devam ediyor", cm.current_turn_peer_id() == 2 and not cm.is_turn_blocked())
	check("gensorudan sonra akis guncel yetkilerle devam eder", cm.parliament_stage(2) == "speech", cm.parliament_stage(2))
	check("gensoru ayni sira yeniden verilemez", not cm.can_censure(2))

	print("=== 7) VERGI, ANAYASA VE ERKEN SECIM YASA ALANINDA ===")
	give_turn(1)
	cm._apply_draw(1)
	if cm.parliament_stage(1) == "speech":
		cm._apply_parl_pass(1, "speech")
	check("hukumet: yasa alaninda vergi yasasi", cm.parliament_stage(1) == "law" and cm.can_propose_tax_law(1, 0))
	check("yasa alaninda anayasa", cm.can_propose_constitution(1))
	give_turn(3)
	cm._apply_draw(3)
	if cm.parliament_stage(3) == "censure":
		cm._apply_parl_pass(3, "censure")
	if cm.parliament_stage(3) == "speech":
		cm._apply_parl_pass(3, "speech")
	cm.round_number = 2
	check("muhalefet: yasa alaninda erken secim", cm.parliament_stage(3) == "law" and cm.can_early_election(3), cm.parliament_stage(3))
	cm._apply_early_election_move(3)
	check("erken secim oylamasi", gm.phase == gm.Phase.VOTING and gm.proposal_kind == gm.KIND_EARLY)
	finish_vote(gm.VOTE_NO)
	check("erken secim hakki kullanildi", not cm.can_early_election(3))

	print("=== 8) AFET YARDIMI ===")
	new_game()
	cm.last_election_round = 1
	cm.last_seats = {1: 300, 2: 120, 3: 80}
	cm.funds = {1: 200.0, 2: 200.0, 3: 200.0}
	give_turn(1)
	check("afet yokken yardim sahnesi yok", not cm.aid_pending(1) or cm.needs_turn_draw(1))
	cm.start_disaster("deprem", [province])
	check("kart cekilmeden yardim sahnesi acilmaz", not cm.aid_pending(1))
	cm._apply_draw(1)
	check("karttan sonra yardim karari bekleniyor", cm.aid_pending(1))
	cm._apply_skip_aid(1)
	check("BU TUR YARDIM YAPMA: karar kapandi", not cm.aid_pending(1) and cm.aid_decided(1))
	var aid_funds: float = cm.funds_of(1)
	cm._apply_aid_move(1, 10.0, 0.0)
	check("gecilen yardim ayni sira yapilamaz (eski dugme de)", is_equal_approx(cm.funds_of(1), aid_funds))
	give_turn(2)
	cm._apply_draw(2)
	check("sonraki oyuncu yardim karari verebilir", cm.aid_pending(2))
	cm._apply_aid_move(2, 10.0, 0.0)
	check("yardim yapildi, karar kapandi", not cm.aid_pending(2) and cm.disaster_aid_of(2) >= 10.0)
	give_turn(3)
	cm._apply_draw(3)
	cm._apply_organization(3, cm._province_ids[1])
	check("karar vermeden baska hamle: yardim sahnesi gecilmis sayilir", not cm.aid_pending(3))
	give_turn(1)
	cm._apply_draw(1)
	check("yeni sirada yardim yeniden acilir", cm.aid_pending(1))

	print("=== 9) MITINGTE KARALAMA ===")
	new_game()
	cm.funds = {1: 200.0, 2: 200.0, 3: 200.0}
	give_turn(1)
	cm._apply_draw(1)
	var home := province
	cm.organizations[home] = {1: 1}
	cm.inventories[1] = []
	check("kart yokken karalama yapilamaz", not cm.can_smear(1, 2, home) and cm.smear_targets(1, home).is_empty())
	check("kartsiz karalamali miting reddedilir", not cm.can_miting(1, home, 0.0, 1, 2))
	cm.inventories[1] = [cp.PROPAGANDA_CARD_TYPE]
	check("kart varken hedef secilebilir", cm.smear_targets(1, home).has(2))
	var smear_funds: float = cm.funds_of(1)
	cm._apply_miting_move(1, home, 0.0, [], 1, 2)
	check("karalamali miting: kart dustu, karalamanin bedeli yok", cm.inventories[1].is_empty()
		and is_equal_approx(smear_funds - cm.funds_of(1), 15.0))
	check("karalama ayri miting hakki harcamaz", cm.miting_count(1) == 1)
	cm.inventories[1] = [cp.PROPAGANDA_CARD_TYPE]
	check("karalama karti tek basina da oynanabilir", cm.can_play_card(1, cp.PROPAGANDA_CARD_TYPE, 2, home))
	check("iptal edilen hazirlik kart ve hak tuketmez", cm.inventories[1].size() == 1 and cm.miting_count(1) == 1)

	print("=== 10) YATIRIM KADEMELERI VE SINIR ===")
	new_game()
	mm.world_settings["action_limit"] = 3
	form_government({1: 300, 2: 120, 3: 80}, all_posts_to(1))
	cm.funds = {1: 500.0, 2: 200.0, 3: 200.0}
	cm.economy["treasury"] = 2000.0
	give_turn(1)
	cm._apply_draw(1)
	var quota_before: float = cm.state_quota(1)
	var treasury_before: float = cm.state_treasury()
	cm._apply_invest_move(1, province, 1.0, 0)
	check("kucuk yatirim 50 milyon", is_equal_approx(treasury_before - cm.state_treasury(), 50.0) and cm.invest_count(1) == 1,
		"%.1f" % (treasury_before - cm.state_treasury()))
	var funds_mid: float = cm.funds_of(1)
	var treasury_mid: float = cm.state_treasury()
	check("0.0.238: yatirim kasadan odenemez", not cm.can_invest(1, province, 0.0, 2))
	cm._apply_invest_move(1, province, 1.0, 2)
	check("buyuk yatirim 150 milyon (hazineden, kasa degismez)", is_equal_approx(treasury_mid - cm.state_treasury(), 150.0)
		and is_equal_approx(funds_mid, cm.funds_of(1)) and cm.invest_count(1) == 2)
	cm._apply_invest_move(1, province, 1.0, 1)
	check("3. yatirim", cm.invest_count(1) == 3)
	check("4. yatirim reddedilir", not cm.can_invest(1, province, 1.0, 0))
	var treasury_three: float = cm.state_treasury()
	cm._apply_invest_move(1, province, 1.0, 0)
	check("4. yatirim otorite tarafinda da reddedilir", cm.invest_count(1) == 3 and is_equal_approx(cm.state_treasury(), treasury_three))
	check("ekonomi ivmesi sinirda kalir", float(cm.economy.get("boost", 0.0)) <= Economy.BOOST_MAX + 0.0001)
	give_turn(2)
	cm._apply_draw(2)
	check("muhalefet yatirim yapamaz", not cm.can_invest(2, province))
	check("kota eksiye dusmez", cm.state_quota(1) >= -0.001, "%.1f / %.1f" % [quota_before, cm.state_quota(1)])

	print("=== 11) BOTLAR YENI AKISLA OYNAR ===")
	new_game()
	mm.world_settings["action_limit"] = 5
	for id in [1, 2, 3]:
		mm.players[id]["bot"] = true
	var bm = root.get_node("BotManager")
	var now := 0.0
	var draws_ok := true
	var max_mitings := 0
	for step in 4000:
		now += 0.5
		bm.step(now)
		cm.tick(0.5)
		gm.tick(0.5)
		var cur: int = cm.current_turn_peer_id()
		max_mitings = maxi(max_mitings, cm.miting_count(cur) - cm.action_limit(cur) + 5)
		if cm.round_number >= 14 or cm.game_finished:
			break
	check("botlar turlari oynadi (secim dahil)", cm.round_number >= 12 or cm.game_finished, "tur %d" % cm.round_number)
	check("botlar sirada siniri asmadi", max_mitings <= 5, str(max_mitings))
	check("botlar kart cekti", draws_ok and int(cm.turn_flow.get("serial", 0)) > 20)

	print("=== TUR AKISI: %s ===" % ("PASS" if fails == 0 else "%d HATA" % fails))
	quit(1 if fails > 0 else 0)
