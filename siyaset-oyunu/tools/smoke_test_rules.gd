extends SceneTree
## Seçim modeli, tur/seçim döngüsü, para ve hamleler, süre sınırları, koalisyon
## rızası, ayrılan oyuncular, illerin seçmen profilleri ve oyun sonu kurallarının uçtan uca
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

## Çekirdek gruplarıyla başlangıç yakınlıkları (boş: nötr).
func groups(core: Array = []) -> Dictionary:
	return VoterGroups.start_affinities(core)

## 3 oyunculu yeni bir oyun başlatır; turn_order deterministik [1, 2, 3].
func new_game(affinities: Dictionary) -> void:
	mm.players = {}
	pm.parties = {}
	var i := 0
	for peer_id in affinities.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.2 * i, 0.5, 0.7), "groups": affinities[peer_id], "ready": true,
		}
		i += 1
	cm.init_game()
	cm.turn_order = affinities.keys()
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

## Partinin ülke geneli (vekil ağırlıklı) grup uyumu.
func national_appeal(affinities: Dictionary, voters: Dictionary, seats: Dictionary) -> float:
	var sum := 0.0
	var total := 0.0
	for province_id in voters.keys():
		sum += VoterGroups.appeal(affinities, voters[province_id]) * float(seats.get(province_id, 0))
		total += float(seats.get(province_id, 0))
	return sum / maxf(1.0, total)

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	# Eski serbest akış: bu test mekanikleri sınar (tur akışı: smoke_test_turn_flow).
	cm.enforce_turn_flow = false
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	cp = root.get_node("CardPresets")
	mm.room_code = ""  # yerel mod
	gm.result_hold_seconds = 0.0
	mm.election_threshold = 0.0

	print("=== 1) D'HONDT ===")
	var alloc := ElectionModel.dhondt({1: 0.5, 2: 0.3, 3: 0.2}, [1, 2, 3], 10)
	check("10 koltuk dagitildi", int(alloc[1]) + int(alloc[2]) + int(alloc[3]) == 10, str(alloc))
	check("dagilim 5/3/2", alloc[1] == 5 and alloc[2] == 3 and alloc[3] == 2, str(alloc))

	print("")
	print("=== 2) SECIM MODELI ===")
	var seat_file = root.get_node("GameMap").seat_counts()
	var voters := ElectionModel.load_province_voters()
	check("ornek secmen verisi her il icin var", voters.size() == seat_file.size(), "%d/%d" % [voters.size(), seat_file.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var parties := {1: groups(["isveren", "milliyetci"]), 2: groups(["ilerici", "milliyetci"]), 3: groups(["isci", "ozerkci"])}
	var r := ElectionModel.compute(parties, seat_file, voters, 0.0, rng)
	check("toplam %d vekil (%d il + %d ulusal liste)" % [cm.TOTAL_SEATS, cm.TOTAL_SEATS - ElectionModel.NATIONAL_LIST_SEATS, ElectionModel.NATIONAL_LIST_SEATS], int(sum_values(r["seats"])) == cm.TOTAL_SEATS, str(r["seats"]))
	check("oy oranlari toplami 100", absf(sum_values(r["vote_shares"]) - 100.0) < 0.01, str(sum_values(r["vote_shares"])))
	var best_appeal := 1
	var worst_appeal := 1
	for id in parties.keys():
		if national_appeal(parties[id], voters, seat_file) > national_appeal(parties[best_appeal], voters, seat_file):
			best_appeal = id
		if national_appeal(parties[id], voters, seat_file) < national_appeal(parties[worst_appeal], voters, seat_file):
			worst_appeal = id
	# 0.0.186 GRUP BAZLI OY: bir grubu tek başına sahiplenen parti (3: işçi ve
	# özerkçi çekirdeği kimsede yok) o grubun oylarının çoğunu alır.
	var owner_parties: Dictionary = parties.duplicate(true)
	owner_parties[3]["isci"] = 60.0
	var in_isci: Dictionary = ElectionModel.shares_in_group(owner_parties, "isci")
	check("grubun %60'ina hitap eden parti o grubun cogunu alir", float(in_isci[3]) > 0.6, str(in_isci))
	var focused := {1: groups(["emekli", "dindar"]), 2: groups(["genc", "ilerici"]), 3: groups(["isci", "milliyetci"]),
		4: groups(["isveren", "ozerkci"]), 5: groups(["isci", "dindar"]), 6: groups(["isveren", "milliyetci"])}
	(focused[1] as Dictionary)["emekli"] = 88.0
	var in_emekli: Dictionary = ElectionModel.shares_in_group(focused, "emekli")
	print("  (6 parti; emeklilere 88 yakinliktaki parti emekli oylarinin %%%.0f'ini alir)" % (float(in_emekli[1]) * 100.0))
	check("emeklilere uzun sure odaklanan parti emeklilerin %70-90'ini alir", float(in_emekli[1]) >= 0.7 and float(in_emekli[1]) <= 0.9, str(in_emekli[1]))
	var per_province_ok := true
	for province_id in r["province_results"].keys():
		var n := 0
		for peer_id in r["province_results"][province_id].keys():
			n += int(r["province_results"][province_id][peer_id]["seats"])
		if n != int(seat_file[province_id]):
			per_province_ok = false
	check("her ilin koltuklari tam dagitildi", per_province_ok)

	rng.seed = 42
	var smallest := 1
	for id in parties.keys():
		if float(r["vote_shares"][id]) < float(r["vote_shares"][smallest]):
			smallest = id
	var share3: float = float(r["vote_shares"][smallest])
	var rt := ElectionModel.compute(parties, seat_file, voters, share3 + 0.5, rng)
	check("baraj alti parti 0 vekil", int(rt["seats"][smallest]) == 0 and not rt["passed_threshold"].has(smallest), str(rt["seats"]))
	check("baraj sonrasi vekil sayisi ayni", int(sum_values(rt["seats"])) == cm.TOTAL_SEATS)
	var r100 := ElectionModel.compute(parties, seat_file, voters, 100.0, rng)
	check("kimse gecemezse baraj uygulanmaz", int(sum_values(r100["seats"])) == cm.TOTAL_SEATS and r100["passed_threshold"].size() == 3)
	var expected := ElectionModel.expected_shares(parties, voters[TestProvinces.id("konya")])
	check("beklenen paylar (anket) toplami 100", absf(sum_values(expected) - 100.0) < 0.01, str(expected))

	print("")
	print("=== 3) SECIM TAKVIMI ===")
	check("varsayilan: 2 yilda bir (4 tur), 5 secim = 20 tur", GameRules.ELECTION_INTERVAL == 4 and GameRules.MAX_ROUNDS == 20 \
		and GameRules.is_election_round(4) and GameRules.is_election_round(20) and not GameRules.is_election_round(22))
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
	new_game({1: groups(["isveren", "milliyetci"]), 2: groups(["isci", "milliyetci"]), 3: groups(["isveren", "dindar"])})
	check("tur 1, meclis yok", cm.round_number == 1 and cm.last_seats.is_empty())
	var funds_before_election: Dictionary = {}
	for i in 9:
		pass_round()
	check("9 tur sonunda henuz secim yok", cm.last_seats.is_empty() and cm.round_number == 10)
	funds_before_election = cm.funds.duplicate()
	pass_round()
	check("10. tur sonunda ilk secim yapildi", cm.last_election_round == 10 and int(sum_values(cm.last_seats)) == cm.TOTAL_SEATS, str(cm.last_seats))
	check("tur 11'e gecildi", cm.round_number == 11)
	# 0.0.188: seçimden sonra sıra oy oranına göre yeniden dizilir; yeni turun
	# geliri yeni sıranın ilk oyuncusuna gider. Toplamda: turda herkes bir sıra
	# geliri (+FUNDS_PER_ROUND) ve seçim bonusu aldı; toplam aynı.
	var gained := 0.0
	var bonus_ok := true
	for id in cm.turn_order:
		# Hediye kart anında bağış kampanyası olabilir (0.0.231): o para ayrı.
		var diff: float = cm.funds_of(id) - float(funds_before_election[id]) - cm.instant_funds_of(id, cm.last_gift_draws.get(id, []))
		gained += diff
		if diff < float(GameRules.ELECTION_FUNDS_BONUS) - 0.01:
			bonus_ok = false
	var expected_total := float(cm.turn_order.size()) * float(GameRules.FUNDS_PER_ROUND + GameRules.ELECTION_FUNDS_BONUS)
	check("secim sonrasi herkese secim parasi, toplam gelir dogru", bonus_ok and is_equal_approx(gained, expected_total),
		"%s -> %s" % [funds_before_election, cm.funds])
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
	var gov_funds_before: Dictionary = cm.funds.duplicate()
	gm._apply_vote(3, false)
	check("herkes oy verdi -> kabul", gm.has_government() and gm.phase == gm.Phase.GOVERNING)
	check("yeni hukumetin partilerine +1 milyon, digerlerine yok", cm.funds_of(1) == int(gov_funds_before[1]) + GameRules.GOVERNMENT_FUNDS_BONUS \
		and cm.funds_of(2) == int(gov_funds_before[2]) + GameRules.GOVERNMENT_FUNDS_BONUS and cm.funds_of(3) == int(gov_funds_before[3]),
		"%s -> %s" % [gov_funds_before, cm.funds])

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
	# Gensoruyu muhalefet oyuncusu 3'ün verebilmesi için bu senaryodaki
	# oyuncu sırasını açıkça sabitle; Dictionary.keys() sırasına güvenme.
	cm.turn_order = [1, 2, 3]
	cm.current_turn_index = cm.turn_order.size() - 1
	var last_peer: int = cm.current_turn_peer_id()
	var round_before: int = cm.round_number
	# Hükümet azınlıkta olmalı ve gensoruyu muhalefet verir.
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	cm.funds[last_peer] = 10
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
	print("=== 9) PARTI KASASI VE HAMLELER ===")
	new_game({1: groups(), 2: groups(), 3: groups()})
	cm.funds = {1: GameRules.FUNDS_START, 2: GameRules.FUNDS_START, 3: GameRules.FUNDS_START}
	cm._grant_turn_income()
	check("sirasi gelen +FUNDS_PER_ROUND alir, digerleri almaz", cm.funds_of(1) == GameRules.FUNDS_START + GameRules.FUNDS_PER_ROUND 		and cm.funds_of(2) == GameRules.FUNDS_START, str(cm.funds))
	cm.funds[1] = 1
	cm._apply_pass(1)
	check("turu bitirmek para vermez: harcanan para geri dolmaz", cm.funds_of(1) == 1, str(cm.funds))
	check("sirasi gelen 2 gelirini aldi", cm.funds_of(2) == GameRules.FUNDS_START + GameRules.FUNDS_PER_ROUND)
	var hand3_before: int = cm.inventories[3].size()
	cm.tick(GameRules.TURN_TIMEOUT + 1.0)
	check("sure dolunca sira devreder", cm.current_turn_peer_id() == 3)
	# KART ÇEKME HAMLESİ YOK: sıra gelince otomatik TAM 1 kart dağıtılır.
	check("sira gelince otomatik 1 kart dagitildi", cm.inventories[3].size() == hand3_before + 1,
		"%d -> %d" % [hand3_before, cm.inventories[3].size()])
	cm.funds[3] = 0
	check("para yoksa teskilat yok", not cm.can_build_organization(3, TestProvinces.id("ankara")))
	cm._apply_pass(3)
	check("tur bitti: 1 birikmis kasasina gelir ekledi (1 + gelir)", cm.round_number == 2 and cm.funds_of(1) == 1 + GameRules.FUNDS_PER_ROUND 		and cm.funds_of(3) == 0, str(cm.funds))
	var gov_before: Dictionary = gm.government.duplicate()
	gm.government = {"pm": 1, "ministry_health": 2}
	check("hukumetteki parti tur basina FUNDS_PER_ROUND_GOVERNMENT alir", cm.turn_income(1) == GameRules.FUNDS_PER_ROUND_GOVERNMENT 		and cm.turn_income(2) == GameRules.FUNDS_PER_ROUND_GOVERNMENT)
	check("muhalefet normal gelir alir", cm.turn_income(3) == GameRules.FUNDS_PER_ROUND)
	check("hukumet geliri 10 fazla", GameRules.FUNDS_PER_ROUND_GOVERNMENT == GameRules.FUNDS_PER_ROUND + 10)
	gm.government = gov_before

	check("gozcu destede yok", not cm._draw_pool(1).has("gozcu"))
	check("miting hamle, destede yok, 15 milyon", not cm._draw_pool(1).has("miting") and GameRules.MITING_FUNDS_COST == 15)
	check("kartlarin fiyati yok (0.0.232)", not cp.has_method("card_cost"))

	var law_type: String = cp.law_type("isveren")
	check("yasa hamlesi turu okunur", cp.is_law_card(law_type) and cp.law_data(law_type)["group"] == "isveren" \
		and cp.law_data(law_type)["opposite"] == "isci" and not cp.is_law_card("miting") and not cp.is_law_card("law:yok"))
	cm.funds[1] = 10
	check("ilk secimden once yasa yapilamaz (meclis yok)", not cm.can_propose_law(1))
	var isveren_before := float(pm.parties[1]["groups"]["isveren"])
	cm._apply_law(1, law_type)
	check("secim oncesi yasa reddedildi: para ve grup destegi degismedi", cm.funds_of(1) == 10 and near(float(pm.parties[1]["groups"]["isveren"]), isveren_before))
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	cm.agenda = {}
	check("gundem yokken de yasa sunulabilir (0.0.182)", cm.can_propose_law(1, law_type))
	cm.agenda = {"type": "gundem_dindar", "until": cm.round_number + 1}
	check("gundem baska gruptayken de bu yasa sunulabilir", cm.can_propose_law(1, law_type))
	cm.agenda = {"type": "gundem_isci", "until": cm.round_number + 1}
	check("gundem ciftinin iki grubu icin de yasa sunulabilir", cm.can_propose_law(1, law_type) and cm.can_propose_law(1, cp.law_type("isci")))
	cm._apply_law(1, law_type)
	check("yasa bedava, meclis oylamasi acildi, sira devretmedi", cm.funds_of(1) == 10 - GameRules.LAW_FUNDS_COST and gm.phase == gm.Phase.VOTING 		and cm.current_turn_peer_id() == 1)
	for id in [1, 2, 3]:
		gm._apply_vote(id, gm.VOTE_ABSTAIN)
	check("turda ikinci yasa yok", not cm.can_propose_law(1))
	cm.last_seats = {}
	var funds1: int = cm.funds_of(1)

	check("teskilat yokken anket yok", cm.province_poll(1, TestProvinces.id("ankara")).is_empty())
	var projection: Dictionary = cm.province_projection(TestProvinces.id("ankara"))
	var projected := 0
	for id in projection.keys():
		projected += int(projection[id]["seats"])
	check("anlik vekil tahmini ilin vekil sayisina esit", projected == cm.province_seat_count(TestProvinces.id("ankara")), str(projection))
	cm.funds[1] = GameRules.ORG_FUNDS_COST
	cm.inventories[1] = []
	check("teskilat kurulabilir", cm.can_build_organization(1, TestProvinces.id("ankara")))
	cm._apply_organization(1, TestProvinces.id("ankara"))
	check("teskilat kuruldu, para harcandi; para bitti -> sira devretmez", cm.organization_level(TestProvinces.id("ankara"), 1) == 1 		and cm.funds_of(1) == 0 and cm.current_turn_peer_id() == 1)
	cm.current_turn_index = cm.turn_order.find(1)
	check("teskilat 1: az oy bonusu + yaklasik anket (sadece kurana)", near(cm.activity_of(TestProvinces.id("ankara"), 1) - cm.local_of(TestProvinces.id("ankara"), 1), PublicOpinion.org_activity(1)) \
		and cm.poll_error(1, TestProvinces.id("ankara")) == GameRules.POLL_ERROR_LOW \
		and not cm.province_poll(1, TestProvinces.id("ankara")).is_empty() and cm.province_poll(2, TestProvinces.id("ankara")).is_empty())
	check("para yetmezse kurulamaz", not cm.can_build_organization(1, TestProvinces.id("izmir")))
	cm.funds[1] = 50
	for i in 5:
		cm._apply_organization(1, TestProvinces.id("izmir"))
	check("en fazla ORG_MAX_LEVEL (10 + 30 milyon)", cm.organization_level(TestProvinces.id("izmir"), 1) == GameRules.ORG_MAX_LEVEL and cm.funds_of(1) == 50 - GameRules.ORG_FUNDS_COST - GameRules.ORG_UPGRADE_FUNDS_COST,
		"seviye %d, para %d" % [cm.organization_level(TestProvinces.id("izmir"), 1), cm.funds_of(1)])
	check("seviye arttikca oy bonusu artar", PublicOpinion.org_activity(1) < PublicOpinion.org_activity(2))
	var poll3: Dictionary = cm.province_poll(1, TestProvinces.id("izmir"))
	var poll_seats := 0
	for id in poll3.keys():
		poll_seats += int(poll3[id]["seats"])
	check("teskilat 2: yuksek isabetli anket, ilin vekilleri dagitildi", cm.poll_error(1, TestProvinces.id("izmir")) == GameRules.POLL_ERROR_HIGH \
		and poll_seats == cm.province_seat_count(TestProvinces.id("izmir")), str(poll3))
	check("anket ayni turda degismez", str(cm.province_poll(1, TestProvinces.id("izmir"))) == str(poll3))
	cm.organizations[TestProvinces.id("izmir")][1] = 1
	check("teskilat 1: yaklasik anket (2. seviyeden az isabetli)", cm.poll_error(1, TestProvinces.id("izmir")) == GameRules.POLL_ERROR_LOW \
		and GameRules.POLL_ERROR_LOW > GameRules.POLL_ERROR_HIGH and cm.poll_error(2, TestProvinces.id("izmir")) < 0.0)
	cm.organizations[TestProvinces.id("izmir")][1] = GameRules.ORG_MAX_LEVEL
	cm.funds[1] = 1
	check("para yetmezse miting yapilamaz", not cm.can_miting(1, TestProvinces.id("izmir")))
	cm.funds[1] = GameRules.MITING_FUNDS_COST + 10
	var izmir_before: float = cm.local_of(TestProvinces.id("izmir"), 1) + cm.national_of(1)
	cm._apply_miting_move(1, TestProvinces.id("izmir"))
	check("miting hamlesi 15 milyon, etki yazildi, para kaldi -> sira devretmedi", cm.funds_of(1) == 10 and cm.current_turn_peer_id() == 1 \
		and not near(cm.local_of(TestProvinces.id("izmir"), 1) + cm.national_of(1), izmir_before))
	cm.inventories[1] = ["bagis_kampanyasi"]
	cm.funds[1] = GameRules.MITING_FUNDS_COST
	cm.organizations[TestProvinces.id("konya")] = {1: 1}
	cm._apply_miting_move(1, TestProvinces.id("konya"))
	check("para bitti -> sira devretmez", cm.funds_of(1) == 0 and cm.current_turn_peer_id() == 1)
	cm.inventories[1] = []
	cm.funds[1] = 2
	var next_peer: int = cm.turn_order[(cm.turn_order.find(1) + 1) % cm.turn_order.size()]
	cm.organizations[TestProvinces.id("sivas")] = {1: 1}
	cm._apply_miting_move(1, TestProvinces.id("sivas"))
	check("para bitse de sira kendiliginden devretmez", cm.current_turn_peer_id() == 1)
	cm._apply_pass(1)
	check("turu bitir -> sira devreder", cm.current_turn_peer_id() == next_peer)
	cm.current_turn_index = cm.turn_order.find(1)
	cm.inventories[1] = []

	print("")
	print("=== 9b) YASA VE OYLAR GRUP DESTEGINI DEGISTIRIR ===")
	cm.last_seats = {1: 150, 2: 140, 3: 100}
	cm.crisis = {}
	var g1: Dictionary = pm.parties[1]["groups"].duplicate()
	var g2: Dictionary = pm.parties[2]["groups"].duplicate()
	var g3: Dictionary = pm.parties[3]["groups"].duplicate()
	cm.apply_law_result(1, cp.law_type("ilerici"), {1: 1, 2: 1, 3: -1}, true, [])
	var gain1 := float(pm.parties[1]["groups"]["ilerici"]) - float(g1["ilerici"])
	var loss1 := float(pm.parties[1]["groups"]["dindar"]) - float(g1["dindar"])
	check("kabul: sunan hedef grupta kazanir, karsit grupta daha az kaybeder", gain1 > PublicOpinion.LAW_GROUP_GAIN_PASSED * 0.5 and loss1 <= 0.0 and absf(loss1) < gain1,
		"%+.2f / %+.2f" % [gain1, loss1])
	check("EVET hedef gruba yaklasir", float(pm.parties[2]["groups"]["ilerici"]) > float(g2["ilerici"]) \
		and float(pm.parties[2]["groups"]["dindar"]) <= float(g2["dindar"]))
	check("HAYIR karsit gruba yaklasir", float(pm.parties[3]["groups"]["dindar"]) > float(g3["dindar"]) \
		and float(pm.parties[3]["groups"]["ilerici"]) <= float(g3["ilerici"]))
	check("yasa diger gruplara dokunmaz", near(float(pm.parties[1]["groups"]["isci"]), float(g1["isci"])) \
		and near(float(pm.parties[2]["groups"]["emekli"]), float(g2["emekli"])))
	var g1b: Dictionary = pm.parties[1]["groups"].duplicate()
	cm.apply_law_result(1, cp.law_type("ilerici"), {2: 0}, false, [])
	var rejected_gain := float(pm.parties[1]["groups"]["ilerici"]) - float(g1b["ilerici"])
	check("ret: sunan yine kazanir ama kabulden az", rejected_gain > 0.0 and rejected_gain < gain1, "%.2f" % rejected_gain)
	var g2c: Dictionary = pm.parties[2]["groups"].duplicate()
	cm.apply_law_result(1, cp.law_type("ilerici"), {2: 0}, false, [])
	var abstain_gain := false
	for group in VoterGroups.GROUP_IDS:
		if float(pm.parties[2]["groups"][group]) > float(g2c[group]) + 0.0001:
			abstain_gain = true
	# Çekimser oy kendi başına bir şey kazandırmaz; sunan partinin kazancı ondan pay alabilir (seçmen çalma).
	check("cekimser grup destegi kazandirmaz", not abstain_gain)
	pm.parties[3]["groups"]["isveren"] = 99.5
	pm.apply_group_deltas([{"peer": 3, "group": "isveren", "amount": 20.0}])
	check("destek 100'u asamaz", float(pm.parties[3]["groups"]["isveren"]) <= 100.0)
	pm.parties[3]["groups"]["isci"] = 0.5
	pm.apply_group_deltas([{"peer": 3, "group": "isci", "amount": -20.0}])
	check("destek 0'in altina inmez", float(pm.parties[3]["groups"]["isci"]) >= 0.0)
	check("il baskanligi miting riskini azaltir",
		PublicOpinion.provocation_risk(2.0, 2) < PublicOpinion.provocation_risk(2.0, 0) and PublicOpinion.provocation_risk(20.0, 0) == 0.0)

	print("")
	print("=== 10) VEKIL CALMA IL VERISIZ UYGULANMAZ ===")
	cm.last_seats = {1: 100, 2: 100}
	cm.last_province_results = {}
	check("il verisi yoksa calma yok", not cm._apply_steal(1, 2, "steal_strong") and cm.last_seats[2] == 100)

	print("")
	print("=== 11) AYRILAN OYUNCU ===")
	new_game({1: groups(["isveren", "milliyetci"]), 2: groups(["isci", "milliyetci"]), 3: groups(["isveren", "dindar"])})
	cm.current_turn_index = 1  # sira 2'de
	cm.remove_player(2)
	check("siradaki oyuncu ayrildi -> sira sonrakine gecti", cm.current_turn_peer_id() == 3, str(cm.current_turn_peer_id()))
	check("sirada 2 oyuncu kaldi, kasasi silindi", cm.turn_order == [1, 3] and not cm.funds.has(2), str(cm.turn_order))
	new_game({1: groups(["isveren", "milliyetci"]), 2: groups(["isci", "milliyetci"]), 3: groups(["isveren", "dindar"])})
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
	new_game({1: groups(["isveren", "milliyetci"]), 2: groups(["isci", "milliyetci"]), 3: groups(["isveren", "dindar"])})
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
	new_game({1: groups(["isveren", "milliyetci"]), 2: groups(["isci", "milliyetci"]), 3: groups(["isveren", "dindar"])})
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
	check("oyun 2000'de baslar", GameRules.year_of_round(1) == 2000)
	check("iki tur bir yil", GameRules.year_of_round(2) == 2000 and GameRules.year_of_round(3) == 2001)
	check("ilk secim 8. turun sonunda: 2004", GameRules.is_election_round(8) and GameRules.election_year(8) == 2004)
	check("secimler 4 yilda bir", GameRules.election_year(16) == 2008 and GameRules.election_year(24) == 2012)

	print("")
	print("=== 14) KOALISYONDAN CEKILME ===")
	new_game({1: groups(["isveren", "milliyetci"]), 2: groups(["isci", "milliyetci"]), 3: groups(["isveren", "dindar"])})
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
	new_game({1: groups(["isveren", "milliyetci"]), 2: groups(["isci", "milliyetci"]), 3: groups(["isveren", "dindar"])})
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
	print("=== 15) ILLERIN SECMEN PROFILLERI ===")
	new_game({1: groups(), 2: groups(), 3: groups()})
	var profiles: Dictionary = cm.province_profiles
	check("haritadaki her bolgenin profili uretildi", profiles.size() == root.get_node("GameMap").ids.size() and profiles.size() >= 30, str(profiles.size()))
	var valid := true
	for province_id in profiles.keys():
		if not VoterGroups.is_valid_profile(profiles[province_id]):
			valid = false
		for group in VoterGroups.GROUP_IDS:
			if VoterGroups.percent(profiles[province_id], group) + VoterGroups.percent(profiles[province_id], VoterGroups.opposite(group)) != 100:
				valid = false
	check("her ilde dort cift, her cift tam %100", valid)
	var nb: Dictionary = VoterGroups.neighbors()
	check("komsuluk bulundu", nb.size() == root.get_node("GameMap").ids.size() and (nb.get(TestProvinces.id("ankara"), []) as Array).size() >= 3, str(nb.get(TestProvinces.id("ankara"), [])))
	var near_sum := 0.0
	var near_n := 0
	for province_id in nb.keys():
		for other in nb[province_id]:
			near_sum += profile_distance(profiles[province_id], profiles[other])
			near_n += 1
	var ids: Array = profiles.keys()
	var far_sum := 0.0
	var far_n := 0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			far_sum += profile_distance(profiles[ids[i]], profiles[ids[j]])
			far_n += 1
	var near_avg := near_sum / maxf(1.0, near_n)
	var far_avg := far_sum / maxf(1.0, far_n)
	check("komsu iller birbirine belirgin benzer profil", near_avg < far_avg * 0.8, "komsu %.2f, genel %.2f" % [near_avg, far_avg])
	var identical := 0
	for province_id in nb.keys():
		for other in nb[province_id]:
			if str(profiles[province_id]) == str(profiles[other]):
				identical += 1
	check("komsular birebir ayni degil", identical < near_n / 4, "%d/%d" % [identical, near_n])
	var spread_ok := true
	for pair in VoterGroups.PAIR_IDS:
		var lo := 100
		var hi := 0
		for province_id in ids:
			lo = mini(lo, int(profiles[province_id][pair]))
			hi = maxi(hi, int(profiles[province_id][pair]))
		if hi - lo < 30:
			spread_ok = false
	check("her ciftte belirgin bolgesel yogunlasma (en az 30 puan fark)", spread_ok)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 5
	var r2 := RandomNumberGenerator.new()
	r2.seed = 5
	check("ayni tohum ayni profiller", str(VoterGroups.generate_profiles(r1, ids)) == str(VoterGroups.generate_profiles(r2, ids)))
	var before_profiles := str(cm.province_profiles)
	cm.organizations[TestProvinces.id("ankara")] = {1: 2}
	cm.funds[1] = 200
	cm.current_turn_index = cm.turn_order.find(1)
	cm._apply_miting_move(1, TestProvinces.id("ankara"))
	cm._decay_opinion()
	check("miting ve tur sonu il profilini degistirmez", str(cm.province_profiles) == before_profiles)
	check("cekirdek secimi: farkli ciftten 2 grup", VoterGroups.is_valid_core(["isci", "dindar"]) \
		and not VoterGroups.is_valid_core(["isci", "isveren"]) and not VoterGroups.is_valid_core(["isci"]) \
		and VoterGroups.is_valid_core(VoterGroups.random_core()))
	var start := VoterGroups.start_affinities(["isci", "dindar"])
	check("cekirdek %10, digerleri %0", near(float(start["isci"]), VoterGroups.CORE_START) \
		and near(float(start["isveren"]), 0.0) and near(float(start["genc"]), 0.0))
	check("desteden yasa ve ideoloji karti gelmez", not cm._draw_pool(1).has("capitalist") and not cm._draw_pool(1).has("law_privatization"))

	print("")
	print("=== 13) GUNDEM TAKVIMI ===")
	GameRules.configure(4, 7)
	new_game({1: groups(), 2: groups(), 3: groups()})
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
	var pattern_ok := true
	for rr in range(9, 20):
		if calendar[rr] == "":
			pattern_ok = false
	check("ilk secimden sonra her tur gundem", pattern_ok, str(calendar))
	var pairs_ok := true
	for rr in range(9, 19):
		if cp.agenda_data(calendar[rr])["pair"] == cp.agenda_data(calendar[rr + 1])["pair"]:
			pairs_ok = false
	check("arka arkaya gelen gundemler farkli cift", pairs_ok)
	cm.round_number = 9
	cm.agenda = {"type": calendar[9], "until": 10}
	check("gundem tek grubu odullendirir", cm.agenda_groups().size() == 1 and cm.crisis_type() == "")
	check("0.0.268: karsit kayip birebir (oran 1)", is_equal_approx(float(VoterGroups.data("emekli")["law_backlash"]), 1.0))

	print("")
	print("=== 14) GRUP YAKINLIGINA BAGLI VEKIL CALMA, IL TAVANI, SECIM HEDIYESI ===")
	check("notr (orta yakinlik) guclu: 10-16", str(cp.steal_range("steal_strong", 0.5)) == str({"min": 10, "max": 16}))
	check("ayni grup profili guclu: 20-32", str(cp.steal_range("steal_strong", 1.0)) == str({"min": 20, "max": 32}))
	check("zit uclar: normal 1-2, guclu 6-9", str(cp.steal_range("steal_weak", 0.0)) == str({"min": 1, "max": 2}) \
		and str(cp.steal_range("steal_strong", 0.0)) == str({"min": 6, "max": 9}))
	check("vekil calmanin iki varyanti var", cp.STEAL_CARD_TYPES.size() == 2 and not cp.STEAL_CARD_TYPES.has("steal_medium"))
	var all_first := {}
	var all_second := {}
	for pair in VoterGroups.PAIR_IDS:
		all_first[VoterGroups.PAIRS[pair][0]] = 100.0
		all_first[VoterGroups.PAIRS[pair][1]] = 0.0
		all_second[VoterGroups.PAIRS[pair][0]] = 0.0
		all_second[VoterGroups.PAIRS[pair][1]] = 100.0
	pm.parties[1]["groups"] = all_first.duplicate()
	pm.parties[2]["groups"] = all_second.duplicate()
	pm.parties[3]["groups"] = all_first.duplicate()
	check("yakinlik: ayni grup profili 1, tamamen zit 0", is_equal_approx(cm.group_closeness(1, 3), 1.0) and is_equal_approx(cm.group_closeness(1, 2), 0.0))
	var typical := VoterGroups.party_closeness(VoterGroups.start_affinities(["isci", "dindar"]), VoterGroups.start_affinities(["isveren", "ilerici"]))
	# Hitap modeli: herkes %0'dan (çekirdekte %10'dan) başlar; profiller oyun içinde ayrışır.
	check("baslangicta zit cekirdekli partiler henuz birbirine yakin ama ayni degil", typical > 0.6 and typical < 1.0, "%.2f" % typical)
	var capped := ElectionModel.cap_shares({1: 0.95, 2: 0.04, 3: 0.01})
	check("il oy tavani: kimse %68'i asamaz, toplam 1", float(capped[1]) <= ElectionModel.PROVINCE_MAX_SHARE + 0.0001 \
		and is_equal_approx(float(capped[1]) + float(capped[2]) + float(capped[3]), 1.0), str(capped))
	var hands_before := {}
	for id in cm.turn_order:
		hands_before[id] = cm.inventories.get(id, []).size()
	cm._hold_election(cm.round_number, false)
	var gift_ok := true
	# Seçimden sonra rastgele yeni bir parti katılabilir: sadece eskilere bak.
	for id in hands_before.keys():
		# Hediye kart anında kartsa (0.0.231) ele girmez, hemen uygulanır.
		var gift: Array = cm.last_gift_draws.get(id, [])
		var to_hand := 0
		for entry in gift:
			if String(entry["result"]) == "hand":
				to_hand += 1
		if gift.is_empty() or cm.inventories[id].size() != mini(int(hands_before[id]) + to_hand, cm.MAX_HAND_SIZE):
			gift_ok = false
	check("secimden sonra herkese 1 kart hediye", gift_ok)
	check("gundem karti destede yok", not cm._draw_pool(1).has("gundem_isci"))

	print("")
	print("=== 15) YENI KARTLAR, CALMA BEDELI, GENSORU PUANI ===")
	var kaset_target: int = cm.turn_order[1]
	var kaset_player: int = cm.turn_order[0]
	cm.current_turn_index = 0
	cm.funds[kaset_player] = 9
	cm.last_seats[kaset_target] = maxi(20, int(cm.last_seats.get(kaset_target, 0)))
	cm.last_seats[kaset_player] = maxi(20, int(cm.last_seats.get(kaset_player, 0)))
	cm.turmoil = {}
	# Seçim hediyesi anında popülizm olabilir (0.0.231): kaset hasarını büyütmesin.
	cm.populism.erase(cm.party_of(kaset_player))
	var nat_before: float = cm.national_of(kaset_target)
	cm._apply_card_effect(kaset_player, "kaset", kaset_target)
	check("kaset: hedefin ulusal destegi dustu", near(cm.national_of(kaset_target), nat_before - PublicOpinion.REPUTATION_NATIONAL_DAMAGE),
		"%.2f -> %.2f" % [nat_before, cm.national_of(kaset_target)])
	check("kaset: hedefte karisiklik cikar", near(cm.turmoil_of(kaset_target), PublicOpinion.TURMOIL_REPUTATION))
	cm._apply_card_effect(kaset_player, "isyan", kaset_target)
	check("ic karisiklik: karisiklik buyur, cekimser zorlamasi yok", near(cm.turmoil_of(kaset_target),
		PublicOpinion.TURMOIL_REPUTATION + PublicOpinion.TURMOIL_REBELLION) and not "rebellion" in cm)
	check("kaset kendine oynanamaz", not cm.can_play_card(kaset_player, "kaset", kaset_player))

	var thief: int = cm.turn_order[0]
	var victim: int = cm.turn_order[1]
	var thief_nat: float = cm.national_of(thief)
	var victim_nat: float = cm.national_of(victim)
	var seats_before: int = int(cm.last_seats[victim])
	cm._apply_steal(thief, victim, "steal_weak")
	var moved: int = seats_before - int(cm.last_seats[victim])
	# NORMAL calma bedelsiz: calanin ulusal puani DEGISMEZ, magdur yine kazanir.
	check("normal calmada calanin bedeli yok, calinan kazanir", moved > 0 \
		and is_equal_approx(cm.national_of(thief), thief_nat) and cm.national_of(victim) > victim_nat,
		"%d vekil, %.2f / %.2f" % [moved, cm.national_of(thief) - thief_nat, cm.national_of(victim) - victim_nat])
	# GUCLU calma hala bedel oder.
	var strong_nat: float = cm.national_of(thief)
	cm._apply_steal(thief, victim, "steal_strong")
	check("guclu calmada bedel var", cm.national_of(thief) < strong_nat,
		"%.3f" % (cm.national_of(thief) - strong_nat))
	check("bedeller kucuk (en fazla 1 puan)", absf(cm.national_of(thief) - thief_nat) <= 1.0 \
		and absf(cm.national_of(victim) - victim_nat) <= 0.8)

	print("")
	print("=== 16) ERKEN SECIM TAKVIMI TAMAMEN KAYAR ===")
	GameRules.configure(2, 5)  # 4 turda bir: 4, 8, 12, 16, 20
	new_game({1: groups(), 2: groups(), 3: groups()})
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.last_election_round = 4
	cm.round_number = 6
	cm.schedule_early_election()
	check("erken secim karari: sonraki secim bu tur", cm.next_election_round() == 6)
	cm._finish_round()
	var cal: Array = []
	for rr in range(7, GameRules.MAX_ROUNDS + 1):
		if GameRules.is_election_round(rr):
			cal.append(rr)
	check("takvim 6'dan itibaren 4 turda bir: 10, 14, 18; oyun 18'de biter (secim sayisi korunur)",
		cal == [10, 14, 18] and GameRules.MAX_ROUNDS == 18, "%s, son tur %d" % [str(cal), GameRules.MAX_ROUNDS])
	check("ust seritteki sonraki secim yeni takvimden", cm.next_election_round() == 10, str(cm.next_election_round()))
	var packed_cal: Dictionary = cm._pack_state(false)
	GameRules.configure(2, 5)
	cm._apply_state(packed_cal)
	check("kayit / istemci: uzayan oyun durumla tasinir", GameRules.MAX_ROUNDS == 18)

	# 0.0.239: ERKEN SEÇİMLER SEÇİM SAYISINA DAHİL. Yalnız son seçim kalmışken
	# yapılan erken seçim oyunun son seçimidir (eskiden bir seçim daha eklenirdi).
	GameRules.configure(2, 5)
	new_game({1: groups(), 2: groups(), 3: groups()})
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.last_election_round = 16
	cm.round_number = 18
	cm.schedule_early_election()
	cm._finish_round()
	check("son secim kalmisken erken secim oyunun son secimi", GameRules.MAX_ROUNDS == 18 and cm.final_election_pending,
		"son tur %d, final %s" % [GameRules.MAX_ROUNDS, str(cm.final_election_pending)])
	# Hükümet kurulamadığı için yapılan seçim de erken seçim sayılır: takvim kayar, sayı korunur.
	GameRules.configure(2, 5)
	new_game({1: groups(), 2: groups(), 3: groups()})
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.last_election_round = 4
	cm.round_number = 6
	gm.government = {}
	gm._set_phase(gm.Phase.IDLE)
	cm._finish_round()
	var cal2: Array = []
	for rr in range(7, GameRules.MAX_ROUNDS + 1):
		if GameRules.is_election_round(rr):
			cal2.append(rr)
	check("hukumetsizlik secimi de sayiya dahil: 10, 14, 18", cm.last_election_round == 6 and cal2 == [10, 14, 18],
		"%s, son tur %d" % [str(cal2), GameRules.MAX_ROUNDS])

	print("")
	print("=== 17) SECIM SONRASI SIRA, AFET, SON TURDA ERKEN SECIM ===")
	GameRules.configure(2, 5)  # 4, 8, 12, 16, 20
	new_game({1: groups(), 2: groups(), 3: groups()})
	cm.turn_order = [1, 2, 3]
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	gm.government = {"pm": 2, "deputy_pm": 1}
	gm.main_gov_peer_id = 2
	gm._set_phase(gm.Phase.GOVERNING)
	# Son turda (seçim bu turun sonunda) erken seçim önergesi verilemez.
	cm.round_number = 8
	cm.current_turn_index = cm.turn_order.find(3)
	check("secim bu turun sonundaysa erken secim yok", cm.election_this_round() and not cm.can_early_election(3))
	cm.round_number = 6
	check("secime daha varken erken secim onergesi verilebilir", not cm.election_this_round() and cm.can_early_election(3))
	# Turun son oyuncusu pas geçer: tur kapanır, seçim yapılır.
	cm.round_number = 8
	cm.current_turn_index = cm.turn_order.size() - 1
	var income_before := {}
	for p in cm.turn_order:
		income_before[p] = cm.funds_of(int(p))
	cm._apply_pass(int(cm.turn_order[cm.current_turn_index]))
	var sorted_ok := true
	for i in range(cm.turn_order.size() - 1):
		var a: float = float(cm.last_vote_shares.get(cm.party_of(int(cm.turn_order[i])), 0.0))
		var b: float = float(cm.last_vote_shares.get(cm.party_of(int(cm.turn_order[i + 1])), 0.0))
		if a < b:
			sorted_ok = false
	check("secimden sonra sira oy oranina gore (buyukten kucuge)", cm.last_election_round == 8 and sorted_ok and cm.current_turn_index == 0,
		"%s / %s" % [str(cm.turn_order), str(cm.last_vote_shares)])
	check("secimden hemen sonraki tur afet yok", not cm.has_disaster())
	# İlk sıradaki oyuncu yeni turun gelirini aldı (seçim parası + tur geliri).
	var first := int(cm.turn_order[0])
	var others_ok := true
	for p in cm.turn_order:
		if int(p) != first and cm.funds_of(int(p)) - float(income_before[p]) - cm.instant_funds_of(int(p), cm.last_gift_draws.get(p, [])) > float(GameRules.ELECTION_FUNDS_BONUS) + 0.01:
			others_ok = false
	check("tur geliri yeni siradaki ilk oyuncuya, digerlerine yalniz secim parasi",
		cm.funds_of(first) - float(income_before[first]) > float(GameRules.ELECTION_FUNDS_BONUS) + 0.01 and others_ok)
	# Seçimden sonraki ikinci turdan itibaren afet çıkabilir (zorla: borç ve son tur değil).
	var disasters := 0
	for trial in 40:
		cm.disaster = {"term_count": 0}
		cm.round_number = 9
		cm._roll_disaster()
		if cm.has_disaster():
			disasters += 1
	check("sonraki turlarda afet cikabilir", disasters > 0, str(disasters))

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()

## İki il profili arasındaki fark (dört çiftin yüzde farklarının ortalaması).
func profile_distance(a: Dictionary, b: Dictionary) -> float:
	var sum := 0.0
	for pair in VoterGroups.PAIR_IDS:
		sum += absf(float(a.get(pair, 50)) - float(b.get(pair, 50)))
	return sum / VoterGroups.PAIR_IDS.size()
