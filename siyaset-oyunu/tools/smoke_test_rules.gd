extends SceneTree
## Seçim modeli, tur/seçim döngüsü, mana ve hamleler, süre sınırları, koalisyon
## rızası, ayrılan oyuncular, illerin görüşü ve oyun sonu kurallarının uçtan uca
## testi (yerel mod, RPC yok).
## `godot --headless --script res://tools/smoke_test_rules.gd`

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

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

func ideology(e: int, s: int, a: int) -> Dictionary:
	return {"economic": e, "social": s, "administrative": a}

## 3 oyunculu yeni bir oyun başlatır; turn_order deterministik [1, 2, 3].
func new_game(ideologies: Dictionary) -> void:
	mm.players = {}
	pm.parties = {}
	var i := 0
	for peer_id in ideologies.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.2 * i, 0.5, 0.7), "ideology": ideologies[peer_id], "ready": true,
		}
		i += 1
	cm.init_game()
	cm.turn_order = ideologies.keys()
	cm.current_turn_index = 0

func pass_round() -> void:
	for i in cm.turn_order.size():
		cm._apply_pass(cm.current_turn_peer_id())

func sum_values(d: Dictionary) -> float:
	var total := 0.0
	for k in d.keys():
		total += float(d[k])
	return total

func all_posts_to(peer_id: int) -> Dictionary:
	var a := {}
	for post in gp.POSTS:
		a[post["id"]] = peer_id
	return a

## Hükümeti deterministik bir meclisle doğrudan kurar.
func form_government(seats: Dictionary, assignments: Dictionary) -> void:
	cm.last_seats = seats.duplicate()
	gm.start_formation()
	gm._apply_government_proposal(gm.mandate_peer_id(), assignments)
	for peer_id in seats.keys():
		gm._apply_vote(peer_id, true)

func extreme(voters: Dictionary, axis: String, highest: bool) -> String:
	var best := ""
	for province_id in voters.keys():
		var v := float(voters[province_id][axis])
		if best == "" or (highest and v > float(voters[best][axis])) or (not highest and v < float(voters[best][axis])):
			best = province_id
	return best

func _initialize() -> void:
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	cp = root.get_node("CardPresets")
	mm.room_code = ""  # yerel mod
	gm.result_hold_seconds = 0.0
	mm.axis_sharpness_start = 1.0
	mm.axis_sharpness_increment = 0.0
	mm.election_threshold = 0.0

	print("=== 1) D'HONDT ===")
	var alloc := ElectionModel.dhondt({1: 0.5, 2: 0.3, 3: 0.2}, [1, 2, 3], 10)
	check("10 koltuk dagitildi", int(alloc[1]) + int(alloc[2]) + int(alloc[3]) == 10, str(alloc))
	check("dagilim 5/3/2", alloc[1] == 5 and alloc[2] == 3 and alloc[3] == 2, str(alloc))

	print("")
	print("=== 2) SECIM MODELI ===")
	var seat_file = JSON.parse_string(FileAccess.get_file_as_string("res://data/province_seats.json"))
	var voters := ElectionModel.load_province_voters()
	check("ornek secmen verisi her il icin var", voters.size() == seat_file.size(), "%d/%d" % [voters.size(), seat_file.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var parties := {1: ideology(1, 1, 2), 2: ideology(0, -1, 1), 3: ideology(-2, -2, -2)}
	var r := ElectionModel.compute(parties, seat_file, voters, 0.0, 1.0, rng)
	check("toplam 400 vekil (390 il + 10 ulusal liste)", int(sum_values(r["seats"])) == 400, str(r["seats"]))
	check("oy oranlari toplami 100", absf(sum_values(r["vote_shares"]) - 100.0) < 0.01, str(sum_values(r["vote_shares"])))
	check("secmene yakin parti daha cok oy aldi", float(r["vote_shares"][1]) > float(r["vote_shares"][3]), str(r["vote_shares"]))
	var per_province_ok := true
	for province_id in r["province_results"].keys():
		var n := 0
		for peer_id in r["province_results"][province_id].keys():
			n += int(r["province_results"][province_id][peer_id]["seats"])
		if n != int(seat_file[province_id]):
			per_province_ok = false
	check("her ilin koltuklari tam dagitildi", per_province_ok)

	rng.seed = 42
	var share3: float = float(r["vote_shares"][3])
	var rt := ElectionModel.compute(parties, seat_file, voters, share3 + 0.5, 1.0, rng)
	check("baraj alti parti 0 vekil", int(rt["seats"][3]) == 0 and not rt["passed_threshold"].has(3), str(rt["seats"]))
	check("baraj sonrasi yine 400", int(sum_values(rt["seats"])) == 400)
	var r100 := ElectionModel.compute(parties, seat_file, voters, 100.0, 1.0, rng)
	check("kimse gecemezse baraj uygulanmaz", int(sum_values(r100["seats"])) == 400 and r100["passed_threshold"].size() == 3)
	var expected := ElectionModel.expected_shares(parties, voters["konya"], 1.0)
	check("beklenen paylar (anket) toplami 100", absf(sum_values(expected) - 100.0) < 0.01, str(expected))

	print("")
	print("=== 3) SECIM TAKVIMI ===")
	check("varsayilan: 4 yilda bir (8 tur), 8 secim = 64 tur", GameRules.ELECTION_INTERVAL == 8 and GameRules.MAX_ROUNDS == 64 \
		and GameRules.is_election_round(8) and GameRules.is_election_round(64) and not GameRules.is_election_round(66))
	# Bu testin geri kalanı 5 YILDA bir (10 tur), 6 seçimlik (60 tur) takvimle yazıldı.
	GameRules.configure(5, 6)
	check("secim turlari 10,20,30 (5,15,25 degil)", GameRules.is_election_round(10) and GameRules.is_election_round(20) \
		and GameRules.is_election_round(30) and not GameRules.is_election_round(5) \
		and not GameRules.is_election_round(15) and not GameRules.is_election_round(25))
	check("sonraki secim 11 -> 20", GameRules.next_election_round(11) == 20)
	check("toplam 60 tur, son turda da secim var", GameRules.MAX_ROUNDS == 60 and GameRules.is_election_round(60) \
		and GameRules.next_election_round(51) == 60)

	print("")
	print("=== 4) KAMPANYA DONEMI + ILK SECIM ===")
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	check("tur 1, meclis yok", cm.round_number == 1 and cm.last_seats.is_empty())
	var mana_before_election: Dictionary = {}
	for i in 9:
		pass_round()
	check("9 tur sonunda henuz secim yok", cm.last_seats.is_empty() and cm.round_number == 10)
	mana_before_election = cm.mana.duplicate()
	pass_round()
	check("10. tur sonunda ilk secim yapildi", cm.last_election_round == 10 and int(sum_values(cm.last_seats)) == 400, str(cm.last_seats))
	check("tur 11'e gecildi", cm.round_number == 11)
	var election_bonus_ok := true
	for id in cm.turn_order:
		# Turdaki herkes sira gelirini (+3) aldi, ustune secim bonusu (+1).
		var expected_mana: int = int(mana_before_election[id]) + GameRules.MANA_PER_ROUND + GameRules.ELECTION_MANA_BONUS
		if cm.mana_of(id) != expected_mana:
			election_bonus_ok = false
	check("secim sonrasi herkese +1 mana", election_bonus_ok, "%s -> %s" % [mana_before_election, cm.mana])
	check("secimde kazanilan vekiller momentum icin kaydedildi", cm.election_seats == cm.last_seats)
	check("hukumet kurma asamasi", gm.phase == gm.Phase.FORMING)
	var idx_before: int = cm.current_turn_index
	cm._apply_pass(cm.current_turn_peer_id())
	check("kurma sirasinda tur ILERLEMEZ", cm.current_turn_index == idx_before)

	print("")
	print("=== 5) KOALISYON RIZASI ===")
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	gm.start_formation()
	var coalition := all_posts_to(1)
	coalition[gp.POST_DEPUTY_PM] = 2
	gm._apply_government_proposal(1, coalition)
	check("1. asama: sadece ortak oy verir", gm.is_coalition_stage() and gm.eligible_voter_ids() == [2], str(gm.eligible_voter_ids()))
	gm._apply_vote(3, true)
	check("ortak olmayan 1. asamada oy veremez", not gm.votes.has(3) and gm.phase == gm.Phase.VOTING)
	gm._apply_vote(2, false)
	check("ortak HAYIR dedi -> teklif dustu", not gm.has_government() and gm.phase == gm.Phase.FORMING)
	check("sebep ortagin reddi", gm.last_resolution_reason.find("kabul etmedi") != -1, gm.last_resolution_reason)
	check("teklif hakki yandi", gm.attempts_left() == 2)
	gm._apply_government_proposal(1, coalition)
	gm._apply_vote(2, true)
	check("ortak kabul -> meclis oylamasi, herkes oy verene kadar bekler", gm.phase == gm.Phase.VOTING and not gm.is_coalition_stage())
	var gov_mana_before: Dictionary = cm.mana.duplicate()
	gm._apply_vote(3, false)
	check("herkes oy verdi -> kabul", gm.has_government() and gm.phase == gm.Phase.GOVERNING)
	check("yeni hukumetin partilerine +1 mana, digerlerine yok", cm.mana_of(1) == int(gov_mana_before[1]) + GameRules.GOVERNMENT_MANA_BONUS \
		and cm.mana_of(2) == int(gov_mana_before[2]) + GameRules.GOVERNMENT_MANA_BONUS and cm.mana_of(3) == int(gov_mana_before[3]),
		"%s -> %s" % [gov_mana_before, cm.mana])

	print("")
	print("=== 6) SECIMSIZ TURLAR: HUKUMET GOREVDE, PUAN BIRIKIR ===")
	cm.current_turn_index = 0
	var pts1: int = gm.round_points_of(1)
	pass_round()
	check("tur 11 sonunda secim YOK", cm.last_election_round == 10 and cm.round_number == 12)
	check("hukumet hala gorevde", gm.has_government())
	check("makam puani kurulusta yazildi, tur sonu eklemez", gm.score_of(1) == pts1, "%d vs %d" % [gm.score_of(1), pts1])
	pass_round()
	pass_round()
	pass_round()
	check("tur 12, 13, 14 sonunda da secim yok", cm.last_election_round == 10 and gm.score_of(1) == pts1)
	while cm.round_number <= 20:
		pass_round()
	check("tur 20 sonunda SECIM", cm.last_election_round == 20 and cm.round_number == 21)
	# Makam puanı hükümet kurulurken TEK SEFER yazıldı; turlar eklemedi.
	check("puan tek seferlik kaldi", gm.score_of(1) == pts1, "%d vs %d" % [gm.score_of(1), pts1])

	print("")
	print("=== 7) GENSORU OYLAMASI SIRAYI DEVRETMEZ ===")
	form_government({1: 200, 2: 100, 3: 90}, all_posts_to(1))
	check("hukumet kuruldu", gm.has_government())
	cm.current_turn_index = cm.turn_order.size() - 1
	var last_peer: int = cm.current_turn_peer_id()
	var round_before: int = cm.round_number
	# Hükümet azınlıkta olmalı ve gensoruyu muhalefet verir.
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	cm.mana[last_peer] = 10
	cm._apply_censure_move(last_peer)
	check("gensoru oylamasi acildi", gm.phase == gm.Phase.VOTING)
	check("gensoruyu verenin oyu baştan EVET", int(gm.votes.get(last_peer, 99)) == gm.VOTE_YES and gm.has_voted(last_peer))
	check("oylamada turu bitiremez", (func(): cm._apply_pass(last_peer); return cm.round_number == round_before).call())
	gm._apply_vote(1, false)
	gm._apply_vote(2, false)
	gm._apply_vote(3, false)
	check("gensoru reddedildi, sira hala ayni oyuncuda", gm.phase == gm.Phase.GOVERNING and cm.current_turn_peer_id() == last_peer 		and cm.round_number == round_before, "faz %d, tur %d" % [gm.phase, cm.round_number])
	cm._apply_pass(last_peer)
	check("turu bitirince tur kapandi", cm.round_number == round_before + 1)

	print("")
	print("=== 8) SURE SINIRLARI ===")
	var cur: int = cm.current_turn_peer_id()
	cm.tick(GameRules.TURN_TIMEOUT + 1.0)
	check("tur suresi doldu -> otomatik pas", cm.current_turn_peer_id() != cur)
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	gm.start_formation()
	gm.tick(GameRules.FORMATION_TIMEOUT + 1.0)
	check("kurma suresi doldu -> hak yandi", gm.attempts_left() == 2 and gm.phase == gm.Phase.FORMING)
	gm._apply_government_proposal(1, all_posts_to(1))
	gm._apply_vote(1, true)
	gm.tick(GameRules.VOTE_TIMEOUT + 1.0)
	check("oylama suresi doldu -> oy vermeyen cekimser, teklif gecti", gm.has_government(), gm.last_resolution_reason)

	print("")
	print("=== 9) MANA VE HAMLELER ===")
	new_game({1: ideology(0, 0, 0), 2: ideology(0, 0, 0), 3: ideology(0, 0, 0)})
	cm.mana = {1: GameRules.MANA_START, 2: GameRules.MANA_START, 3: GameRules.MANA_START}
	cm._grant_turn_income()
	check("sirasi gelen +MANA_PER_ROUND alir, digerleri almaz", cm.mana_of(1) == GameRules.MANA_START + GameRules.MANA_PER_ROUND 		and cm.mana_of(2) == GameRules.MANA_START, str(cm.mana))
	cm.mana[1] = 1
	cm._apply_pass(1)
	check("turu bitirmek mana vermez: harcanan mana geri dolmaz", cm.mana_of(1) == 1, str(cm.mana))
	check("sirasi gelen 2 gelirini aldi", cm.mana_of(2) == GameRules.MANA_START + GameRules.MANA_PER_ROUND)
	cm.tick(GameRules.TURN_TIMEOUT + 1.0)
	check("sure dolunca sira devreder", cm.current_turn_peer_id() == 3)
	var hand3: int = cm.inventories[3].size()
	check("sira gelince kart otomatik verilmez", hand3 == 0, str(hand3))
	cm._apply_draw(3)
	check("kart cekmek bedava, sira devretmez", cm.inventories[3].size() == 1 and cm.current_turn_peer_id() == 3)
	cm._apply_draw(3)
	check("turda en fazla 1 kart cekilir", cm.inventories[3].size() == 1 and not cm.can_draw_for(3))
	cm.mana[3] = 0
	check("mana yoksa teskilat yok", not cm.can_build_organization(3, "ankara"))
	cm._apply_pass(3)
	check("tur bitti: 1 birikmis manasina gelir ekledi (1 + gelir)", cm.round_number == 2 and cm.mana_of(1) == 1 + GameRules.MANA_PER_ROUND 		and cm.mana_of(3) == 0, str(cm.mana))
	var gov_before: Dictionary = gm.government.duplicate()
	gm.government = {"pm": 1, "ministry_health": 2}
	check("hukumetteki parti tur basina MANA_PER_ROUND_GOVERNMENT alir", cm.turn_income(1) == GameRules.MANA_PER_ROUND_GOVERNMENT 		and cm.turn_income(2) == GameRules.MANA_PER_ROUND_GOVERNMENT)
	check("muhalefet normal gelir alir", cm.turn_income(3) == GameRules.MANA_PER_ROUND)
	check("hukumet geliri 1 fazla", GameRules.MANA_PER_ROUND_GOVERNMENT == GameRules.MANA_PER_ROUND + 1)
	gm.government = gov_before

	check("gozcu destede yok", not cm._draw_pool(1).has("gozcu"))
	check("miting hamle, destede yok, 2 mana", not cm._draw_pool(1).has("miting") and GameRules.MITING_MANA_COST == 2)
	check("kart bedelleri: karalama 1, calma 1/3, kaset 2, isyan 1", cp.card_cost("karalama") == 1 		and cp.card_cost("steal_weak") == 1 and cp.card_cost("steal_strong") == 3 and cp.card_cost("kaset") == 2 and cp.card_cost("isyan") == 1)

	var law_type: String = cp.law_type("economic", 1)
	check("yasa hamlesi turu okunur", cp.is_law_card(law_type) and int(cp.law_data(law_type)["dir"]) == 1 and not cp.is_law_card("miting"))
	cm.mana[1] = 10
	check("ilk secimden once yasa yapilamaz (meclis yok)", not cm.can_propose_law(1))
	cm._apply_law(1, law_type)
	check("secim oncesi yasa reddedildi: mana ve gorus degismedi", cm.mana_of(1) == 10 and near(float(pm.parties[1]["ideology"]["economic"]), 0.0))
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	cm.agenda = {}
	check("gundem yokken yasa sunulamaz", not cm.can_propose_law(1))
	cm.agenda = {"type": "gundem_social_n", "until": cm.round_number + 1}
	check("gundem baska eksendeyse bu yasa sunulamaz", not cm.can_propose_law(1, law_type))
	cm.agenda = {"type": "gundem_economic_n", "until": cm.round_number + 1}
	check("meclis ve gundem varken gundemdeki eksende yasa sunulabilir", cm.can_propose_law(1, law_type))
	cm._apply_law(1, law_type)
	check("yasa bedava, meclis oylamasi acildi, sira devretmedi", cm.mana_of(1) == 10 - GameRules.LAW_MANA_COST and gm.phase == gm.Phase.VOTING 		and cm.current_turn_peer_id() == 1)
	for id in [1, 2, 3]:
		gm._apply_vote(id, gm.VOTE_ABSTAIN)
	check("turda ikinci yasa yok", not cm.can_propose_law(1))
	cm.last_seats = {}
	var mana1: int = cm.mana_of(1)

	check("teskilat yokken il gorusu ve anket yok", not cm.knows_leaning(1, "ankara") and cm.province_poll(1, "ankara").is_empty())
	var projection: Dictionary = cm.province_projection("ankara")
	var projected := 0
	for id in projection.keys():
		projected += int(projection[id]["seats"])
	check("anlik vekil tahmini ilin vekil sayisina esit", projected == cm.province_seat_count("ankara"), str(projection))
	cm.mana[1] = 2
	cm.inventories[1] = []
	cm.has_drawn_this_turn = true  # bedava kart hakkı duruyorsa sıra kendiliğinden geçmez
	check("2 mana ile il baskanligi kurulabilir", cm.can_build_organization(1, "ankara"))
	cm._apply_organization(1, "ankara")
	check("il baskanligi kuruldu, 2 mana harcandi; mana bitti -> sira devretmez", cm.organization_level("ankara", 1) == 1 		and cm.mana_of(1) == 0 and cm.current_turn_peer_id() == 1)
	cm.current_turn_index = cm.turn_order.find(1)
	check("teskilat 1: az oy bonusu + il gorusu, anket yok", near(cm.activity_of("ankara", 1) - cm.local_of("ankara", 1), PublicOpinion.org_activity(1)) \
		and cm.knows_leaning(1, "ankara") and cm.province_poll(1, "ankara").is_empty() and not cm.knows_leaning(2, "ankara"))
	check("mana yetmezse kurulamaz", not cm.can_build_organization(1, "izmir"))
	cm.mana[1] = 20
	for i in 5:
		cm._apply_organization(1, "izmir")
	check("en fazla seviye 3", cm.organization_level("izmir", 1) == GameRules.ORG_MAX_LEVEL and cm.mana_of(1) == 20 - 3 * GameRules.ORG_MANA_COST,
		"seviye %d, mana %d" % [cm.organization_level("izmir", 1), cm.mana_of(1)])
	check("seviye arttikca oy bonusu artar", PublicOpinion.org_activity(1) < PublicOpinion.org_activity(2) and PublicOpinion.org_activity(2) < PublicOpinion.org_activity(3))
	var poll3: Dictionary = cm.province_poll(1, "izmir")
	var poll_seats := 0
	for id in poll3.keys():
		poll_seats += int(poll3[id]["seats"])
	check("teskilat 3: yuksek isabetli anket, ilin vekilleri dagitildi", cm.poll_error(1, "izmir") == GameRules.POLL_ERROR_HIGH \
		and poll_seats == cm.province_seat_count("izmir"), str(poll3))
	check("anket ayni turda degismez", str(cm.province_poll(1, "izmir")) == str(poll3))
	cm.organizations["izmir"][1] = 2
	check("teskilat 2: orta isabetli anket", cm.poll_error(1, "izmir") == GameRules.POLL_ERROR_MEDIUM and not cm.province_poll(1, "izmir").is_empty())
	cm.organizations["izmir"][1] = 3
	cm.mana[1] = 1
	check("mana yetmezse miting yapilamaz", not cm.can_miting(1, "izmir"))
	cm.mana[1] = 3
	var izmir_before: float = cm.local_of("izmir", 1) + cm.national_of(1)
	cm._apply_miting_move(1, "izmir")
	check("miting hamlesi 2 mana, etki yazildi, mana kaldi -> sira devretmedi", cm.mana_of(1) == 1 and cm.current_turn_peer_id() == 1 \
		and not near(cm.local_of("izmir", 1) + cm.national_of(1), izmir_before))
	cm.inventories[1] = ["mana_bonusu"]
	cm.has_drawn_this_turn = true
	cm.mana[1] = 2
	cm._apply_miting_move(1, "konya")
	check("mana bitti -> sira devretmez", cm.mana_of(1) == 0 and cm.current_turn_peer_id() == 1)
	cm.inventories[1] = []
	cm.mana[1] = 2
	var next_peer: int = cm.turn_order[(cm.turn_order.find(1) + 1) % cm.turn_order.size()]
	cm.has_drawn_this_turn = false
	cm._apply_miting_move(1, "sivas")
	check("mana bitti ama kart cekme hakki var -> sira devretmez", cm.current_turn_peer_id() == 1)
	cm._apply_draw(1)
	check("mana yok, kart cekildi -> yine de sira devretmez", cm.current_turn_peer_id() == 1)
	cm._apply_pass(1)
	check("turu bitir -> sira devreder", cm.current_turn_peer_id() == next_peer)
	cm.current_turn_index = cm.turn_order.find(1)
	cm.inventories[1] = []

	print("")
	print("=== 9b) OYLAR IDEOLOJIYI KAYDIRIR ===")
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	var before2 := float(pm.parties[2]["ideology"]["social"])
	var before3 := float(pm.parties[3]["ideology"]["social"])
	var before1 := float(pm.parties[1]["ideology"]["social"])
	cm.apply_law_result(1, cp.law_type("social", -1), {1: 1, 2: 1, 3: -1}, true, [])
	check("sunan 1 adim kaydi", near(float(pm.parties[1]["ideology"]["social"]), before1 - 1.0))
	check("EVET yasa yonune yarim adim", near(float(pm.parties[2]["ideology"]["social"]), before2 - 0.5))
	check("HAYIR ters yone yarim adim", near(float(pm.parties[3]["ideology"]["social"]), before3 + 0.5))
	cm.apply_law_result(1, cp.law_type("social", -1), {2: 0}, false, [])
	check("cekimser kaymaz", near(float(pm.parties[2]["ideology"]["social"]), before2 - 0.5))
	pm.parties[3]["ideology"]["economic"] = 3.0
	pm.apply_ideology_delta(3, "economic", 0.5)
	check("uc sinir 3", near(float(pm.parties[3]["ideology"]["economic"]), 3.0))
	check("il baskanligi miting riskini azaltir",
		PublicOpinion.provocation_risk(ideology(-3, -3, -3), ideology(3, 3, 3), 2) < PublicOpinion.provocation_risk(ideology(-3, -3, -3), ideology(3, 3, 3), 0))

	print("")
	print("=== 10) VEKIL CALMA IL VERISIZ UYGULANMAZ ===")
	cm.last_seats = {1: 100, 2: 100}
	cm.last_province_results = {}
	check("il verisi yoksa calma yok", not cm._apply_steal(1, 2, "steal_strong") and cm.last_seats[2] == 100)

	print("")
	print("=== 11) AYRILAN OYUNCU ===")
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	cm.current_turn_index = 1  # sira 2'de
	cm.remove_player(2)
	check("siradaki oyuncu ayrildi -> sira sonrakine gecti", cm.current_turn_peer_id() == 3, str(cm.current_turn_peer_id()))
	check("sirada 2 oyuncu kaldi, manasi silindi", cm.turn_order == [1, 3] and not cm.mana.has(2), str(cm.turn_order))
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	pass_round()
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	gm.start_formation()
	var c2 := all_posts_to(1)
	c2[gp.POST_DEPUTY_PM] = 2
	gm._apply_government_proposal(1, c2)
	gm._apply_vote(1, true)
	cm.remove_player(2)
	check("teklif edilen ortak ayrildi -> teklif dustu, kurma surer", gm.phase == gm.Phase.FORMING and gm.mandate_peer_id() == 1)
	check("ayrilanin vekilleri meclisten cikti", gm.total_seats() == 250, str(gm.total_seats()))
	gm._apply_government_proposal(1, all_posts_to(1))
	gm._apply_vote(1, true)
	gm._apply_vote(3, true)
	check("kalan meclisle hukumet kuruldu", gm.has_government())
	cm.current_turn_index = 1
	cm.remove_player(3)
	check("tek oyuncu kaldi -> oyun bitti", cm.game_finished and cm.game_end_reason.find("Yeterli") != -1)
	check("oyun bitince tur kilitli", cm.is_turn_blocked())

	print("")
	print("=== 12) SON TUR -> SON SECIM -> HUKUMET -> OYUN SONU ===")
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	cm.round_number = GameRules.MAX_ROUNDS
	cm.current_turn_index = 0
	pass_round()
	check("son turdan sonra oyun HENUZ bitmedi: son secim ve hukumet kurma", not cm.game_finished \
		and cm.last_election_round == GameRules.MAX_ROUNDS and gm.phase == gm.Phase.FORMING)
	var holder: int = gm.mandate_peer_id()
	var score_before: int = gm.score_of(holder)
	gm._apply_government_proposal(holder, all_posts_to(holder))
	for id in [1, 2, 3]:
		gm._apply_vote(id, gm.VOTE_YES)
	check("hukumet kurulunca oyun bitti", cm.game_finished)
	check("son hukumet makam puanini aldi", gm.score_of(holder) > score_before, "%d -> %d" % [score_before, gm.score_of(holder)])
	check("kazanan son hukumet partisi", cm.final_ranking.size() == 3 and int(cm.final_ranking[0]["peer_id"]) == holder, str(cm.final_ranking))
	check("oylama/kurma kapandi", gm.phase == gm.Phase.IDLE)

	print("")
	print("=== 13) CEKIMSER ===")
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	pass_round()
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	gm.start_formation()
	var c3 := all_posts_to(1)
	c3[gp.POST_DEPUTY_PM] = 2
	gm._apply_government_proposal(1, c3)
	gm._apply_vote(3, gm.VOTE_YES)
	check("1. asamada ortak disi oy sayilmaz, sonuclanmaz", gm.phase == gm.Phase.VOTING and not gm.votes.has(3))
	gm._apply_vote(2, gm.VOTE_ABSTAIN)
	check("koalisyon gorusmesinde ortak cekimser kalamaz (oy alinmaz)", not gm.votes.has(2) and gm.is_coalition_stage())
	gm._apply_vote(2, gm.VOTE_NO)
	check("ortak HAYIR -> riza yok, teklif dustu", not gm.has_government() and gm.last_resolution_reason.find("kabul etmedi") != -1, gm.last_resolution_reason)
	gm._apply_government_proposal(1, all_posts_to(1))
	gm._apply_vote(2, gm.VOTE_ABSTAIN)
	gm._apply_vote(3, gm.VOTE_NO)
	check("cekimser HAYIR sayilmaz -> hukumet kuruldu", gm.has_government(), gm.last_resolution_reason)

	print("")
	print("=== 13b) TAKVIM: TURLAR YIL ===")
	GameRules.configure(4, 7)
	check("oyun 1950'de baslar", GameRules.year_of_round(1) == 1950)
	check("iki tur bir yil", GameRules.year_of_round(2) == 1950 and GameRules.year_of_round(3) == 1951)
	check("ilk secim 8. turun sonunda: 1954", GameRules.is_election_round(8) and GameRules.election_year(8) == 1954)
	check("secimler 4 yilda bir", GameRules.election_year(16) == 1958 and GameRules.election_year(24) == 1962)

	print("")
	print("=== 14) KOALISYONDAN CEKILME ===")
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	pass_round()
	cm.last_seats = {1: 150, 2: 60, 3: 140}
	gm.start_formation()
	var c4 := all_posts_to(1)
	c4[gp.POST_DEPUTY_PM] = 2
	gm._apply_government_proposal(1, c4)
	gm._apply_vote(1, gm.VOTE_YES)
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(3, gm.VOTE_NO)
	gm.scores = {}
	check("koalisyon kuruldu", gm.has_government() and gm.government_party_ids().size() == 2)
	check("kucuk ortak cekilebilir, ana parti ve muhalefet cekilemez", gm.can_withdraw(2) and not gm.can_withdraw(1) and not gm.can_withdraw(3))
	gm._apply_withdraw(2)
	check("cekilmek puan tablosuna dokunmaz", gm.score_of(2) == 0, str(gm.score_of(2)))
	check("cekilen ortak ulusal puan kaybetti (kismi)", cm.national_of(2) < 0.0 and cm.national_of(2) >= -2.0, str(cm.national_of(2)))
	check("kucuk ortak cekilince kalanlar etkilenmez", cm.national_of(1) == 0.0, str(cm.national_of(1)))
	check("gorevleri ana partiye gecti, hukumet tek basina", gm.government_party_ids() == [1], str(gm.government_party_ids()))
	check("hukumet cogunlugu kaybetti -> gensoru verilebilir", not gm.has_majority())
	gm.submit_censure(3)
	gm._apply_vote(1, gm.VOTE_NO)
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(3, gm.VOTE_YES)
	check("gensoruyla dustu", not gm.has_government(), gm.last_resolution_reason)
	check("yalniz kalan ana parti agir puan kaybetti", gm.score_of(1) == -gp.ABANDONED_FALL_PENALTY, str(gm.score_of(1)))

	# Buyuk ortak (hukumet sandalyelerinin yarisindan fazlasi) cekilirse kalanlar da kaybeder.
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	pass_round()
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	gm.start_formation()
	var c5 := all_posts_to(1)
	c5[gp.POST_DEPUTY_PM] = 2
	c5["ministry_health"] = 2
	gm._apply_government_proposal(1, c5)
	gm._apply_vote(1, gm.VOTE_YES)
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(3, gm.VOTE_NO)
	gm.scores = {}
	cm.national_support = {}
	gm._apply_withdraw(2)
	check("buyuk ortak cekilince kendi kaybi daha buyuk", cm.national_of(2) <= -1.0, str(cm.national_of(2)))
	check("buyuk ortak cekilince kalan ortak da kaybeder (daha az)", cm.national_of(1) < 0.0 		and cm.national_of(1) > cm.national_of(2), "%.2f / %.2f" % [cm.national_of(1), cm.national_of(2)])
	check("muhalefet etkilenmez", cm.national_of(3) == 0.0, str(cm.national_of(3)))

	print("")
	print("=== 15) ILLERIN GORUSU VE NOTR PARTILER ===")
	new_game({1: ideology(0, 0, 0), 2: ideology(0, 0, 0), 3: ideology(0, 0, 0)})
	var ideo: Dictionary = cm.province_ideology
	check("67 ilin gorusu uretildi", ideo.size() == 67, str(ideo.size()))
	var in_range := true
	for province_id in ideo.keys():
		for axis in ["economic", "social", "administrative"]:
			var v = ideo[province_id][axis]
			if typeof(v) != TYPE_INT or int(v) < -3 or int(v) > 3:
				in_range = false
	check("degerler -3..+3 tam sayi", in_range)
	var nb: Dictionary = ProvinceIdeology.neighbors()
	check("komsuluk bulundu", nb.size() >= 60 and (nb.get("ankara", []) as Array).size() >= 3, str(nb.get("ankara", [])))
	var near_sum := 0.0
	var near_n := 0
	for province_id in nb.keys():
		for other in nb[province_id]:
			near_sum += ElectionModel.distance(ideo[province_id], ideo[other])
			near_n += 1
	var ids: Array = ideo.keys()
	var far_sum := 0.0
	var far_n := 0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			far_sum += ElectionModel.distance(ideo[ids[i]], ideo[ids[j]])
			far_n += 1
	var near_avg := near_sum / maxf(1.0, near_n)
	var far_avg := far_sum / maxf(1.0, far_n)
	check("komsu iller birbirine belirgin yakin gorus", near_avg < far_avg * 0.75, "komsu %.2f, genel %.2f" % [near_avg, far_avg])
	var r1 := RandomNumberGenerator.new()
	r1.seed = 5
	var r2 := RandomNumberGenerator.new()
	r2.seed = 5
	check("ayni tohum ayni harita", str(ProvinceIdeology.generate(r1, ids)) == str(ProvinceIdeology.generate(r2, ids)))
	var axes = root.get_node("IdeologyAxes")
	check("partiler notr baslar", axes.is_valid_start_ideology(axes.default_values()) \
		and not axes.is_valid_start_ideology(ideology(1, 0, 0)))
	check("desteden yasa ve ideoloji karti gelmez", not cm._draw_pool(1).has("capitalist") and not cm._draw_pool(1).has("law_privatization"))

	print("")
	print("=== 13) GUNDEM TAKVIMI ===")
	GameRules.configure(4, 7)
	new_game({1: ideology(0, 0, 0), 2: ideology(0, 0, 0), 3: ideology(0, 0, 0)})
	var calendar := {}
	for rr in range(1, 20):
		cm.round_number = rr
		cm.last_seats = {} if rr <= GameRules.FIRST_ELECTION_ROUND else {1: 150, 2: 140, 3: 110}
		cm._schedule_agenda()
		calendar[rr] = cm.agenda_type()
	var no_early := true
	for rr in range(1, 9):
		if calendar[rr] != "":
			no_early = false
	check("ilk secimden once gundem yok", no_early, str(calendar))
	var pattern_ok: bool = calendar[9] != "" and calendar[10] == "" and calendar[11] == "" and calendar[12] != "" \
		and calendar[13] == "" and calendar[14] == "" and calendar[15] != "" and calendar[16] == "" and calendar[17] == "" and calendar[18] != ""
	check("1 tur gundem, 2 tur ara", pattern_ok, str(calendar))
	check("arka arkaya gelen gundemler farkli eksen", cp.agenda_data(calendar[9])["axis"] != cp.agenda_data(calendar[12])["axis"] \
		and cp.agenda_data(calendar[12])["axis"] != cp.agenda_data(calendar[15])["axis"])

	print("")
	print("=== 14) IDEOLOJIYE BAGLI VEKIL CALMA, IL TAVANI, SECIM HEDIYESI ===")
	check("notr (orta yakinlik) guclu: 10-16", str(cp.steal_range("steal_strong", 0.5)) == str({"min": 10, "max": 16}))
	check("ayni ideoloji guclu: 20-32", str(cp.steal_range("steal_strong", 1.0)) == str({"min": 20, "max": 32}))
	check("zit uclar: normal 1-2, guclu 6-9", str(cp.steal_range("steal_weak", 0.0)) == str({"min": 1, "max": 2}) \
		and str(cp.steal_range("steal_strong", 0.0)) == str({"min": 6, "max": 9}))
	check("vekil calmanin iki varyanti var", cp.STEAL_CARD_TYPES.size() == 2 and not cp.STEAL_CARD_TYPES.has("steal_medium"))
	pm.parties[1]["ideology"] = ideology(3, 3, 3)
	pm.parties[2]["ideology"] = ideology(-3, -3, -3)
	pm.parties[3]["ideology"] = ideology(3, 3, 3)
	check("yakinlik: ayni ideoloji 1, zit uclar 0", is_equal_approx(cm.ideological_closeness(1, 3), 1.0) and is_equal_approx(cm.ideological_closeness(1, 2), 0.0))
	var capped := ElectionModel.cap_shares({1: 0.95, 2: 0.04, 3: 0.01})
	check("il oy tavani: kimse %68'i asamaz, toplam 1", float(capped[1]) <= ElectionModel.PROVINCE_MAX_SHARE + 0.0001 \
		and is_equal_approx(float(capped[1]) + float(capped[2]) + float(capped[3]), 1.0), str(capped))
	var hands_before := {}
	for id in cm.turn_order:
		hands_before[id] = cm.inventories.get(id, []).size()
	cm._hold_election(cm.round_number, false)
	var gift_ok := true
	for id in cm.turn_order:
		if cm.inventories[id].size() != mini(int(hands_before[id]) + 1, cm.MAX_HAND_SIZE):
			gift_ok = false
	check("secimden sonra herkese 1 kart hediye", gift_ok)
	check("gundem karti destede yok", not cm._draw_pool(1).has("gundem_economic_n"))

	print("")
	print("=== 15) YENI KARTLAR, CALMA BEDELI, GENSORU PUANI ===")
	var kaset_target: int = cm.turn_order[1]
	var kaset_player: int = cm.turn_order[0]
	cm.current_turn_index = 0
	cm.mana[kaset_player] = 9
	cm.last_seats[kaset_target] = maxi(20, int(cm.last_seats.get(kaset_target, 0)))
	cm.last_seats[kaset_player] = maxi(20, int(cm.last_seats.get(kaset_player, 0)))
	var nat_before: float = cm.national_of(kaset_target)
	cm._apply_card_effect(kaset_player, "kaset", kaset_target)
	check("kaset: hedefin ulusal destegi dustu", near(cm.national_of(kaset_target), nat_before - PublicOpinion.REPUTATION_NATIONAL_DAMAGE),
		"%.2f -> %.2f" % [nat_before, cm.national_of(kaset_target)])
	cm._apply_card_effect(kaset_player, "isyan", kaset_target)
	check("isyan: hedef partide isyan var", cm.has_rebellion(kaset_target))
	check("isyan tuketilir", cm.consume_rebellion(kaset_target) and not cm.has_rebellion(kaset_target))
	check("kaset kendine oynanamaz", not cm.can_play_card(kaset_player, "kaset", kaset_player))

	var thief: int = cm.turn_order[0]
	var victim: int = cm.turn_order[1]
	var thief_nat: float = cm.national_of(thief)
	var victim_nat: float = cm.national_of(victim)
	var seats_before: int = int(cm.last_seats[victim])
	cm._apply_steal(thief, victim, "steal_weak")
	var moved: int = seats_before - int(cm.last_seats[victim])
	check("calmada calan ulusal kaybeder, calinan kazanir", moved > 0 \
		and cm.national_of(thief) < thief_nat and cm.national_of(victim) > victim_nat,
		"%d vekil, %.2f / %.2f" % [moved, cm.national_of(thief) - thief_nat, cm.national_of(victim) - victim_nat])
	check("bedeller kucuk (en fazla 1 puan)", absf(cm.national_of(thief) - thief_nat) <= 1.0 \
		and absf(cm.national_of(victim) - victim_nat) <= 0.8)

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
