extends SceneTree
## Seçim modeli, tur/seçim döngüsü, süre sınırları, koalisyon rızası, ayrılan
## oyuncular ve oyun sonu kurallarının uçtan uca testi (yerel mod, RPC yok).
## `godot --headless --script res://tools/smoke_test_rules.gd`

var mm
var pm
var cm
var gm
var gp
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

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

func _initialize() -> void:
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
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
	check("secmen verisi her il icin var", voters.size() == seat_file.size(), "%d/%d" % [voters.size(), seat_file.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var parties := {1: ideology(1, 1, 2), 2: ideology(0, -1, 1), 3: ideology(-2, -2, -2)}
	var r := ElectionModel.compute(parties, seat_file, voters, 0.0, 1.0, rng)
	check("toplam 390 vekil", int(sum_values(r["seats"])) == 390, str(r["seats"]))
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
	check("baraj sonrasi yine 390", int(sum_values(rt["seats"])) == 390)
	var r100 := ElectionModel.compute(parties, seat_file, voters, 100.0, 1.0, rng)
	check("kimse gecemezse baraj uygulanmaz", int(sum_values(r100["seats"])) == 390 and r100["passed_threshold"].size() == 3)

	print("")
	print("=== 3) SECIM TAKVIMI ===")
	check("secim turlari 1,4,7,10", GameRules.is_election_round(1) and GameRules.is_election_round(4) \
		and GameRules.is_election_round(10) and not GameRules.is_election_round(2) and not GameRules.is_election_round(3))
	check("sonraki secim 2 -> 4", GameRules.next_election_round(2) == 4)
	check("son secimden sonra -1", GameRules.next_election_round(GameRules.MAX_ROUNDS - 1) == -1)

	print("")
	print("=== 4) TUR AKISI + ILK SECIM ===")
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	check("tur 1, meclis yok", cm.round_number == 1 and cm.last_seats.is_empty())
	pass_round()
	check("1. tur sonunda secim yapildi", cm.last_election_round == 1 and int(sum_values(cm.last_seats)) == 390, str(cm.last_seats))
	check("tur 2'ye gecildi", cm.round_number == 2)
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
	gm._apply_vote(1, true)
	gm._apply_vote(2, false)
	check("herkes oy vermeden oylama bitmez", gm.phase == gm.Phase.VOTING)
	gm._apply_vote(3, true)
	check("ortak HAYIR dedi -> teklif dustu", not gm.has_government() and gm.phase == gm.Phase.FORMING)
	check("sebep ortagin reddi", gm.last_resolution_reason.find("kabul etmedi") != -1, gm.last_resolution_reason)
	check("teklif hakki yandi", gm.attempts_left() == 2)
	gm._apply_government_proposal(1, coalition)
	gm._apply_vote(2, true)
	check("ortak evet dese de herkes oy verene kadar bekler", gm.phase == gm.Phase.VOTING)
	gm._apply_vote(1, true)
	gm._apply_vote(3, false)
	check("herkes oy verdi -> kabul", gm.has_government() and gm.phase == gm.Phase.GOVERNING)

	print("")
	print("=== 6) SECIMSIZ TURLAR: HUKUMET GOREVDE, PUAN BIRIKIR ===")
	cm.current_turn_index = 0
	var pts1: int = gm.round_points_of(1)
	pass_round()
	check("tur 2 sonunda secim YOK", cm.last_election_round == 1 and cm.round_number == 3)
	check("hukumet hala gorevde", gm.has_government())
	check("puan eklendi", gm.score_of(1) == pts1, "%d vs %d" % [gm.score_of(1), pts1])
	pass_round()
	check("tur 3 sonunda da secim yok", cm.last_election_round == 1 and gm.score_of(1) == pts1 * 2)
	pass_round()
	check("tur 4 sonunda SECIM", cm.last_election_round == 4 and cm.round_number == 5)
	check("secim oncesi puan yazildi", gm.score_of(1) == pts1 * 3)

	print("")
	print("=== 7) TUR SONU GENSORUYA DENK GELIRSE ERTELENIR ===")
	form_government({1: 200, 2: 100, 3: 90}, all_posts_to(1))
	check("hukumet kuruldu", gm.has_government())
	cm.current_turn_index = cm.turn_order.size() - 1
	var last_peer: int = cm.current_turn_peer_id()
	cm.inventories[last_peer] = ["gensoru"]
	var round_before: int = cm.round_number
	cm._apply_play(last_peer, 0)
	check("gensoru oylamasi acildi", gm.phase == gm.Phase.VOTING)
	check("tur sonu ERTELENDI", cm.round_number == round_before)
	gm._apply_vote(1, false)
	gm._apply_vote(2, false)
	gm._apply_vote(3, false)
	check("gensoru reddedildi, tur simdi kapandi", gm.phase == gm.Phase.GOVERNING and cm.round_number == round_before + 1,
		"faz %d, tur %d" % [gm.phase, cm.round_number])

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
	print("=== 9) RAKIBE IDEOLOJI KARTI ===")
	cm.current_turn_index = 0
	var me: int = cm.current_turn_peer_id()
	var rival: int = cm.turn_order[1]
	var my_eco: int = int(pm.parties[me]["ideology"]["economic"])
	var rival_eco: int = int(pm.parties[rival]["ideology"]["economic"])
	cm.inventories[me] = ["socialist"]
	cm._apply_play(me, 0, rival)
	check("rakibin ekseni kaydi", int(pm.parties[rival]["ideology"]["economic"]) == maxi(-3, rival_eco - 1))
	check("kendi eksenim degismedi", int(pm.parties[me]["ideology"]["economic"]) == my_eco)
	cm.inventories[cm.current_turn_peer_id()] = ["capitalist"]
	var idx_before_invalid: int = cm.current_turn_index
	cm._apply_play(cm.current_turn_peer_id(), 0, 999)
	check("gecersiz hedef -> kart elde kalir", cm.current_turn_index == idx_before_invalid and cm.my_inventory() != null)

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
	check("sirada 2 oyuncu kaldi", cm.turn_order == [1, 3], str(cm.turn_order))
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
	print("=== 12) SON TUR -> OYUN SONU ===")
	new_game({1: ideology(1, 1, 2), 2: ideology(-1, -1, 1), 3: ideology(2, 2, -1)})
	pass_round()
	form_government({1: 200, 2: 100, 3: 90}, all_posts_to(1))
	cm.round_number = GameRules.MAX_ROUNDS
	cm.current_turn_index = 0
	pass_round()
	check("oyun bitti", cm.game_finished)
	check("kazanan iktidar partisi", cm.final_ranking.size() == 3 and int(cm.final_ranking[0]["peer_id"]) == 1, str(cm.final_ranking))
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
	gm._apply_vote(1, gm.VOTE_YES)
	gm._apply_vote(3, gm.VOTE_YES)
	check("herkes oy vermeden sonuclanmaz", gm.phase == gm.Phase.VOTING)
	gm._apply_vote(2, gm.VOTE_ABSTAIN)
	check("ortak cekimser -> riza yok, teklif dustu", not gm.has_government() and gm.last_resolution_reason.find("kabul etmedi") != -1, gm.last_resolution_reason)
	gm._apply_government_proposal(1, all_posts_to(1))
	gm._apply_vote(1, gm.VOTE_YES)
	gm._apply_vote(2, gm.VOTE_ABSTAIN)
	gm._apply_vote(3, gm.VOTE_NO)
	check("cekimser HAYIR sayilmaz -> hukumet kuruldu", gm.has_government(), gm.last_resolution_reason)

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
