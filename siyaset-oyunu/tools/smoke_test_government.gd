extends SceneTree
## Hükümet kurma / oylama / vekil çalma kurallarının uçtan uca testi.

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

func setup_parties(seats: Dictionary) -> void:
	mm.players = {}
	pm.parties = {}
	cm.last_seats = {}
	cm.last_vote_shares = {}
	var i := 0
	for peer_id in seats.keys():
		mm.players[peer_id] = {"name": "Oyuncu%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": i % 6,
			"icon_color": Color.WHITE, "bg_color": Color(0.2 * i, 0.4, 0.6),
			"ideology": {"economic": 0, "social": 0, "administrative": 0}, "ready": true,
		}
		cm.last_seats[peer_id] = seats[peer_id]
		cm.last_vote_shares[peer_id] = float(seats[peer_id])
		i += 1
	cm.turn_order = seats.keys()

func _initialize() -> void:
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	cp = root.get_node("CardPresets")
	mm.room_code = ""  # yerel mod: RPC yok, doğrudan uygula
	gm.result_hold_seconds = 0.0

	print("=== 1) GOREV SIRASI (koltuk sayisina gore) ===")
	# 2 en cok vekile sahip ama 3'un oy orani daha yuksek olsa bile sira 2'de olmali
	setup_parties({1: 100, 2: 180, 3: 110})
	cm.last_vote_shares = {1: 30.0, 2: 20.0, 3: 50.0}
	gm.start_formation()
	check("gorev en cok VEKILI olana verildi", gm.mandate_peer_id() == 2,
		"beklenen 2, gelen %d" % gm.mandate_peer_id())
	check("sira dogru (2 > 3 > 1)", gm.mandate_order == [2, 3, 1], str(gm.mandate_order))
	check("faz FORMING", gm.phase == gm.Phase.FORMING)
	check("toplam sandalye 390", gm.total_seats() == 390, str(gm.total_seats()))

	print("")
	print("=== 2) TEKLIF KABUL (hayir oylari salt cogunlugu GECMEZ) ===")
	var assign := {}
	for post in gp.POSTS:
		assign[post["id"]] = 2
	assign[gp.POST_DEPUTY_PM] = 3   # ortak: 3
	gm._apply_government_proposal(gm.mandate_peer_id(), assign)
	check("faz VOTING", gm.phase == gm.Phase.VOTING)
	check("teklif sahibinin oyu otomatik EVET", int(gm.votes.get(2, 99)) == gm.VOTE_YES, str(gm.votes))
	check("1. asama: koalisyon gorusmesi", gm.is_coalition_stage())
	check("1. asamada sadece ortak oy verir", gm.eligible_voter_ids() == [3], str(gm.eligible_voter_ids()))
	gm._apply_vote(1, false)   # ortak degil: sayilmaz
	check("ortak olmayanin oyu 1. asamada sayilmadi", not gm.votes.has(1))
	gm._apply_vote(3, false)   # ortak reddetti
	check("ortak HAYIR -> teklif REDDEDILDI", not gm.has_government() and gm.phase == gm.Phase.FORMING,
		"hukumet: %s" % str(gm.government))
	check("hak azaldi (2/3 kaldi)", gm.attempts_left() == 2, str(gm.attempts_left()))
	check("gorev hala 2'de", gm.mandate_peer_id() == 2)
	check("koalisyon reddinde puan cezasi yok", gm.score_of(3) == 0, str(gm.score_of(3)))

	print("")
	print("=== 3) AZINLIK HUKUMETI GECEBILIR (muhalefet dagilirsa) ===")
	gm._apply_government_proposal(gm.mandate_peer_id(), assign)
	gm._apply_vote(3, true)    # ortak kabul etti
	check("2. asama: meclis oylamasi", gm.phase == gm.Phase.VOTING and not gm.is_coalition_stage())
	check("ortagin ve teklif sahibinin EVET'i tasindi", int(gm.votes.get(2, 0)) == gm.VOTE_YES and int(gm.votes.get(3, 0)) == gm.VOTE_YES)
	check("2. asamada herkes oy verebilir", gm.eligible_voter_ids().size() == 3)
	gm._apply_vote(1, false)   # 100 hayir  => 100 < 195, gecmeli
	check("hukumet KURULDU", gm.has_government())
	check("hukumete HAYIR diyene puan cezasi yok (istikrar kaldirildi)", gm.score_of(1) == 0, str(gm.score_of(1)))
	check("EVET diyenlere ceza yok", gm.score_of(2) == 0 and gm.score_of(3) == 0)
	check("ana iktidar partisi = basbakanligi tutan", gm.main_gov_peer_id == 2, str(gm.main_gov_peer_id))
	check("faz GOVERNING", gm.phase == gm.Phase.GOVERNING)
	check("hukumet partileri [2,3]", gm.government_party_ids().has(2) and gm.government_party_ids().has(3),
		str(gm.government_party_ids()))
	check("salt cogunluk VAR (290/390)", gm.has_majority(), "%d/%d" % [gm.government_seats(), gm.total_seats()])

	print("")
	print("=== 4) PUANLAR (bakanlik+2, byrd+5, basbakan+10) ===")
	# 2: basbakanlik(10) + 6 bakanlik(12) = 22 ; 3: basbakan yrd (5)
	check("2 tur puani 22", gm.round_points_of(2) == 22, str(gm.round_points_of(2)))
	check("3 tur puani 5", gm.round_points_of(3) == 5, str(gm.round_points_of(3)))
	gm.award_round_scores()
	gm.award_round_scores()
	check("puan BIRIKIYOR (2 tur -> 44)", gm.score_of(2) == 44, str(gm.score_of(2)))
	check("puan BIRIKIYOR (2 tur -> 10)", gm.score_of(3) == 10, str(gm.score_of(3)))

	print("")
	print("=== 5) VEKIL CALMA ===")
	var before_total: int = gm.total_seats()
	check("kendinden calamaz", not cm.is_valid_steal_target(1, 1))
	check("meclis disindan calamaz", not cm.is_valid_steal_target(1, 99))
	cm.last_seats[3] = 1
	check("tek vekilliden de calinabilir", cm.is_valid_steal_target(1, 3))
	cm.last_seats[3] = 110
	check("gecerli hedef", cm.is_valid_steal_target(1, 3))
	var seats1: int = cm.last_seats[1]
	cm.last_seats[1] = 0
	check("vekilsiz (meclis disi) parti vekil calamaz", not cm.is_valid_steal_target(1, 3))
	cm.last_seats[1] = seats1
	cm._apply_steal(1, 2, "steal_strong")
	check("toplam sandalye DEGISMEDI (sifir toplamli)", gm.total_seats() == before_total,
		"%d -> %d" % [before_total, gm.total_seats()])
	# Vekili az olan parti sıfıra inebilir; sonra meclis dışı sayılır.
	cm.last_seats[1] = 100
	var three_total: int = int(cm.last_seats[3])
	cm.last_seats[3] = 2
	# 2 vekilin ikisi de ulusal listeden (il sonuçları dokunulmadan).
	var saved_results: Dictionary = cm.last_province_results
	cm.last_province_results = {}
	cm.national_list[3] = 2
	cm._apply_steal(1, 3, "steal_strong")
	check("vekili az olan parti 0'a inebilir", int(cm.last_seats[3]) == 0, str(cm.last_seats[3]))
	check("vekilsiz parti oy veremez", not gm.voter_ids().has(3))
	cm.last_province_results = saved_results
	cm.last_seats[3] = three_total

	print("")
	print("=== 6) DESTE HAVUZU (kosullu kartlar) ===")
	var pool: Array = cm._draw_pool()
	check("vekil calma kartlari destede (meclis var)", pool.has("steal_strong"))
	check("gensoru destede yok (hamle)", not pool.has("gensoru"))
	# Hukumeti azinliga dusur
	cm.last_seats = {1: 300, 2: 50, 3: 40}
	check("hukumet artik AZINLIK", not gm.has_majority(), "%d/%d" % [gm.government_seats(), gm.total_seats()])


	print("")
	print("=== 7) GENSORU ===")
	gm.submit_censure(3)
	gm._apply_vote(1, gm.VOTE_NO)       # 300 hayir
	gm._apply_vote(2, gm.VOTE_ABSTAIN)
	gm._apply_vote(3, gm.VOTE_YES)      # 90 evet: HAYIR fazla
	check("HAYIR EVET'ten fazlaysa gensoru REDDEDILIR", gm.has_government() and gm.phase == gm.Phase.GOVERNING, gm.last_resolution_reason)
	gm.submit_censure(1)
	check("faz VOTING", gm.phase == gm.Phase.VOTING)
	check("teklif turu censure", gm.proposal_kind == gm.KIND_CENSURE)
	gm._apply_vote(1, true)    # 300 evet (gensoru kabul)
	gm._apply_vote(2, false)
	gm._apply_vote(3, false)   # 90 hayir -> 90 < 195, gensoru GECER
	check("hukumet DUSTU", not gm.has_government())
	check("yeniden kurma asamasi basladi", gm.phase == gm.Phase.FORMING)
	check("gorev en buyuk partide (1)", gm.mandate_peer_id() == 1, str(gm.mandate_peer_id()))
	check("puanlar KORUNDU", gm.score_of(2) == 44, str(gm.score_of(2)))

	print("")
	print("=== 8) 3 TEKLIF HAKKI BITINCE SIRA DEVREDER ===")
	setup_parties({1: 200, 2: 190})
	gm.start_formation()
	check("gorev 1de (200 vekil)", gm.mandate_peer_id() == 1)
	# Simdi gercek red senaryosu: 2 daha buyuk olsun
	setup_parties({1: 110, 2: 180, 3: 100})
	gm.start_formation()
	check("gorev 2'de (180 vekil)", gm.mandate_peer_id() == 2)
	var a3 := {}
	for post in gp.POSTS:
		a3[post["id"]] = 2
	gm._apply_government_proposal(gm.mandate_peer_id(), a3)
	check("tek parti: koalisyon asamasi atlandi", gm.phase == gm.Phase.VOTING and not gm.is_coalition_stage())
	gm._apply_vote(1, false)
	gm._apply_vote(3, false)   # 210 hayir > 195 -> red
	for attempt in 2:
		gm._apply_government_proposal(gm.mandate_peer_id(), a3)
		gm._apply_vote(1, false)
		gm._apply_vote(3, false)
	check("3 red sonrasi sira DEVRETTI (1'e)", gm.mandate_peer_id() == 1,
		"gelen %d, index %d" % [gm.mandate_peer_id(), gm.mandate_index])
	check("hak sifirlandi (3)", gm.attempts_left() == 3, str(gm.attempts_left()))

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
