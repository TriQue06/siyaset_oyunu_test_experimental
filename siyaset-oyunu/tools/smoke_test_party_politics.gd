extends SceneTree
## PARTİ SİYASETİ TESTİ: birleşme / katılma, iki kişilik partinin kuralları
## (mana bölme, ortak yasa hakkı, 2/3-1/3 oy), kongre, ayrılıp parti kurma,
## fesih, bağımsız siyasetçi ve bağımsızdan parti kurma.
##   godot --headless --path . --script res://tools/smoke_test_party_politics.gd

var _failed := 0
var mm
var cm
var gm
var pm
var PP

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failed += 1
	print("  [%s]  %s%s" % ["OK" if ok else "HATA", label, ("  -> " + detail) if detail != "" else ""])

## Sırayı bu oyuncuya verir ve tur akışını açar (test kısayolu).
func give_turn(peer_id: int) -> void:
	cm.current_turn_index = cm.turn_order.find(peer_id)
	gm._set_phase(gm.Phase.IDLE)

func total_seats() -> int:
	var t := 0
	for k in cm.last_seats.keys():
		t += int(cm.last_seats[k])
	return t

func free_color(except_peer: int) -> Color:
	for color in load("res://scripts/party_presets.gd").COLORS:
		if not color.is_equal_approx(Color.WHITE) and pm.color_owner(color, except_peer) == -1:
			return color
	return Color.RED

func _initialize() -> void:
	await process_frame
	PP = load("res://scripts/politician_presets.gd")
	mm = root.get_node("MultiplayerManager")
	cm = root.get_node("CardManager")
	cm.allow_temporary_parties = false
	cm.allow_bot_alliances = false
	gm = root.get_node("GovernmentManager")
	pm = root.get_node("PartyManager")
	root.get_node("BotManager").set_process(false)
	gm.result_hold_seconds = 0.0
	mm.start_offline("Barış")
	for i in 3:
		mm.add_bot()
	mm.start_game()
	pm.set_my_politician(PP.make("Ayla", "Gökyelken", "is_insani", String(root.get_node("GameMap").province_ids()[0])))
	pm.set_party_and_ready("Yeni Yol", 3, Color.WHITE, Color("F20C1F"),
		{"economic": 1.5, "social": -1.5, "administrative": 1.5}, true)
	cm.set_rng_seed(7)
	var me: int = mm.owner_id
	var bots: Array = mm.bot_ids()
	var b1: int = bots[0]
	var b2: int = bots[1]
	var b3: int = bots[2]
	# Meclis olsun: hemen bir seçim.
	cm._hold_election(cm.round_number, false)
	check("seçimden sonra meclis var", total_seats() > 0, str(total_seats()))
	var seats_before := total_seats()

	print("=== HATA DÜZELTMELERİ ===")
	check("party_of(-1) hiçbir partiye ait değil", pm.party_of(-1) == -1 and pm.data_of(-1).is_empty())
	# Turun ilk oyuncusu: önceki dönem konuştuysa yeni dönemde yine konuşabilmeli.
	var first: int = cm.turn_order[0]
	cm.current_turn_index = 0
	gm._set_phase(gm.Phase.IDLE)
	cm._apply_speech(first, "economic", 1)
	check("konuşunca bu dönem tekrar konuşamaz", not cm.needs_speech(first))
	for i in cm.turn_order.size():
		cm._apply_pass(cm.current_turn_peer_id(), true)
		gm._set_phase(gm.Phase.IDLE)
	check("yeni dönemde ilk oyuncu tekrar konuşabilir", cm.current_turn_peer_id() == first and cm.needs_speech(first),
		"sira %d, donem %d" % [cm.current_turn_peer_id(), cm.round_number])

	print("=== OYLAMA TAKILMASI ===")
	# Yasa oylaması açıkken bir oyuncu oyundan çıkar; kalanlar oy vermişse sonuç açıklanmalı.
	cm.current_turn_index = cm.turn_order.find(me)
	gm._set_phase(gm.Phase.IDLE)
	gm.submit_law(me, "law:economic:1")
	var leaver := -1
	for voter in gm.eligible_voter_ids():
		if int(voter) != me and not gm.has_voted(int(voter)):
			leaver = int(voter)
	for voter in gm.eligible_voter_ids():
		if int(voter) != leaver and not gm.has_voted(int(voter)):
			gm._apply_vote(int(voter), gm.VOTE_YES)
	check("bir oy eksik: oylama sürüyor", gm.phase == gm.Phase.VOTING)
	# Ayrılan oyuncu sıra listesinden düşer (ör. parti başka partiye katıldı/feshedildi).
	var saved_order: Array = cm.turn_order.duplicate()
	cm.turn_order.erase(leaver)
	gm.tick(0.1)
	check("eksik oyuncu gidince oylama sonuçlanır", gm.phase != gm.Phase.VOTING, str(gm.phase))
	cm.turn_order = saved_order
	cm.current_turn_index = cm.turn_order.find(me)
	gm._set_phase(gm.Phase.IDLE)

	print("=== BÖLÜNEN KANAT ===")
	# Ana parti bölünen kanadını davet ederse kanat yardımcı olmaz, geri döner.
	var parent_party: int = b3
	cm.last_seats[parent_party] = maxi(20, int(cm.last_seats.get(parent_party, 0)))
	cm._split_party(parent_party)
	var splinter: int = cm.splinter_of(parent_party)
	check("bölünme oldu", splinter != -1)
	check("başka parti bölünen kanadı davet edemez", not cm.is_valid_offer(me, splinter, "invite"))
	check("ana parti geri çağırabilir", cm.is_valid_offer(parent_party, splinter, "invite"))
	cm.current_turn_index = cm.turn_order.find(parent_party)
	cm._apply_send_offer(parent_party, splinter, "invite")
	check("kanat ana partiye geri döndü (yardımcı olmadı)", not cm.turn_order.has(splinter) and pm.deputy_of(parent_party) == -1
		and not cm.splinters.has(splinter))
	cm.current_turn_index = cm.turn_order.find(me)

	print("=== BİRLEŞME ===")
	pm.parties[b1]["ideology"] = pm.parties[me]["ideology"].duplicate()
	give_turn(me)
	var me_seats := int(cm.last_seats.get(me, 0))
	var b1_seats := int(cm.last_seats.get(b1, 0))
	cm.send_offer(b1, "invite")
	check("bot daveti kabul etti, parti birleşti", pm.deputy_of(me) == b1 and not pm.parties.has(b1),
		str(pm.parties.get(me, {}).get("deputy", -1)))
	check("vekiller ev sahibine geçti", int(cm.last_seats.get(me, 0)) == me_seats + b1_seats and total_seats() == seats_before,
		"%d + %d -> %d" % [me_seats, b1_seats, int(cm.last_seats.get(me, 0))])
	check("yardımcı genel başkanın hemen ardından oynar", cm.turn_order.find(b1) == cm.turn_order.find(me) + 1, str(cm.turn_order))
	check("party_of yardımcıyı partiye bağlar", cm.party_of(b1) == me and pm.data_of(b1)["name"] == "Yeni Yol")
	var base := float(GameRules.MANA_PER_ROUND_GOVERNMENT if cm.is_government_party(me) else GameRules.MANA_PER_ROUND)
	check("mana: genel başkan yarı+1, yardımcı yarı+0,5", is_equal_approx(cm.turn_income(me), base * 0.5 + 1.0)
		and is_equal_approx(cm.turn_income(b1), base * 0.5 + 0.5), "%s / %s" % [cm.turn_income(me), cm.turn_income(b1)])
	check("birleşme başlangıç katkısı", cm.contributions.has(me) and cm.contributions.has(b1))
	check("iki üye de oy verir", gm.voter_ids().has(me) and gm.voter_ids().has(b1))
	check("oy 2/3 - 1/3 bölünür", gm.vote_weight(me) + gm.vote_weight(b1) == gm.seats_of(me) and gm.vote_weight(me) > gm.vote_weight(b1),
		"%d / %d" % [gm.vote_weight(me), gm.vote_weight(b1)])
	cm.law_rounds[me] = cm.round_number
	check("yasa hakkı ortak", cm.has_proposed_law_this_round(b1))
	cm.law_rounds.erase(me)
	cm.speech_rounds[me] = cm.round_number
	give_turn(b1)
	cm._grant_turn_income()
	check("grup toplantısı ortak", not cm.needs_speech(b1))

	print("=== KONGRE ===")
	cm.mana[b1] = 20.0
	cm.turmoil[me] = 10.0  # kriz: rakip neredeyse kesin kazanır
	var swapped := false
	for attempt in 6:
		var leader: int = pm.party_of(b1)
		give_turn(b1)
		cm.round_number += 1
		cm.mana[b1] = 20.0
		cm._apply_congress(b1)
		if pm.party_of(b1) == b1:
			swapped = true
			break
		cm.turmoil[pm.party_of(b1)] = 10.0
	check("kongrede yardımcı genel başkan oldu", swapped and pm.deputy_of(b1) == me, str(pm.parties.keys()))
	check("parti verisi yeni anahtara taşındı", int(cm.last_seats.get(b1, 0)) == me_seats + b1_seats and not cm.last_seats.has(me))

	print("=== AYRILIP PARTİ KURMA ===")
	# Şimdi me yardımcı (b1 genel başkan). me ayrılıp parti kurar.
	cm.organizations["px1"] = {b1: 2}
	cm.organizations["px2"] = {b1: 1}
	cm.organizations["px3"] = {b1: 1}
	give_turn(me)
	cm.mana[me] = 10.0
	var seats_party_before := int(cm.last_seats.get(b1, 0))
	var total_before_split := total_seats()
	cm.found_party({"name": "Hür Yol", "icon_index": 2, "bg_color": free_color(me)})
	check("ayrılan pay oranında vekil götürdü", int(cm.last_seats.get(me, 0)) > 0
		and int(cm.last_seats.get(me, 0)) < seats_party_before and total_seats() == total_before_split,
		"%d / %d" % [int(cm.last_seats.get(me, 0)), seats_party_before])
	check("ayrılan yeni parti kurdu", pm.is_leader(me) and pm.parties[me]["name"] == "Hür Yol" and pm.deputy_of(b1) == -1,
		str(pm.parties.get(me, {})))
	check("ayrılma 2 mana", is_equal_approx(cm.mana_of(me), 8.0), str(cm.mana_of(me)))
	var my_orgs := 0
	for province_id in cm.organizations.keys():
		if int(cm.organizations[province_id].get(me, 0)) > 0:
			my_orgs += 1
	check("teşkilatların bir kısmı ayrılanla gitti", my_orgs >= 1, str(my_orgs))

	print("=== GENEL BAŞKAN AYRILIR ===")
	# b1 (genel başkan) b3'ü davet eder; sonra genel başkan ayrılır, parti b3'e kalır.
	pm.parties[b3]["ideology"] = pm.parties[b1]["ideology"].duplicate()
	give_turn(b1)
	cm._apply_send_offer(b1, b3, "invite")
	check("üçüncü birleşme", pm.deputy_of(b1) == b3)
	var party_name_before: String = pm.parties[b1]["name"]
	give_turn(b1)
	cm.mana[b1] = 10.0
	cm._apply_found(b1, {"name": "Öz Yol", "icon_index": 6, "bg_color": free_color(b1)})
	check("genel başkan ayrıldı, parti yardımcıya kaldı", pm.is_leader(b3) and pm.parties[b3]["name"] == party_name_before
		and pm.parties.has(b1) and pm.parties[b1]["name"] == "Öz Yol")

	print("=== FESİH VE BAĞIMSIZLIK ===")
	cm.last_seats[me] = 10
	cm.election_seats[me] = 10
	cm.last_province_results[String(root.get_node("GameMap").province_ids()[1])][me] = {"percent": 10.0, "seats": 10}
	var total_now := total_seats()
	give_turn(me)
	cm.dissolve_party()
	check("fesih: bağımsız oldu", pm.is_independent(me))
	check("fesih: vekiller bloğa ve partilere dağıldı", int(cm.last_seats.get(me, 0)) == 0
		and int(cm.last_seats.get(pm.BLOC_ID, 0)) == 5 and total_seats() == total_now,
		"blok %d" % int(cm.last_seats.get(pm.BLOC_ID, 0)))
	var any_org := false
	for province_id in cm.organizations.keys():
		if int(cm.organizations[province_id].get(me, 0)) > 0:
			any_org = true
	check("fesih: teşkilatlar silindi", not any_org)
	check("bağımsız her ilde miting yapabilir", cm.can_miting(me, String(root.get_node("GameMap").province_ids()[5])) or cm.mana_of(me) < GameRules.MITING_MANA_COST)
	check("bağımsız teşkilat kuramaz", not cm.can_build_organization(me, String(root.get_node("GameMap").province_ids()[5])))
	check("blok oy vermez", not gm.voter_ids().has(pm.BLOC_ID))

	print("=== BAĞIMSIZ SEÇİMİ ===")
	var home: String = PP.hometown_of(me)
	cm.local_support[home] = {me: 10.0}
	cm._hold_election(cm.round_number, false)
	check("bağımsız memleketinden 1 sandalye", int(cm.last_seats.get(me, 0)) == 1, str(cm.last_seats.get(me, 0)))
	check("blok seçimde dağıldı", not pm.parties.has(pm.BLOC_ID) and not cm.last_seats.has(pm.BLOC_ID))
	check("bağımsız hükümet kuramaz", not gm.mandate_order.has(me))

	print("=== BAĞIMSIZDAN PARTİ ===")
	give_turn(me)
	cm.mana[me] = 9.0
	cm.found_party({"name": "Doğru Yol", "icon_index": 4, "bg_color": free_color(me)})
	check("bağımsız parti kurdu (8 mana)", not pm.is_independent(me) and pm.parties[me]["name"] == "Doğru Yol"
		and is_equal_approx(cm.mana_of(me), 1.0), str(cm.mana_of(me)))
	check("bağımsız sandalyesi partiye geçti", int(cm.last_seats.get(me, 0)) == 1)

	print("=== YARDIMCI OYUNDAN AYRILIR ===")
	pm.parties[b2]["ideology"] = pm.parties[me]["ideology"].duplicate()
	give_turn(me)
	cm.send_offer(b2, "invite")
	check("ikinci birleşme", pm.deputy_of(me) == b2)
	mm.players.erase(b2)
	cm.remove_player(b2)
	check("yardımcı gidince parti kalır", pm.is_leader(me) and pm.deputy_of(me) == -1 and not cm.turn_order.has(b2))

	print("=== BOT İTTİFAKLARI ===")
	mm.add_bot()
	mm.add_bot()
	var BB = load("res://scripts/bot_brain.gd")
	cm.allow_bot_alliances = true
	# İki tek kişilik, aynı görüşte, zayıf bot.
	var pair: Array = []
	for peer in cm.party_ids():
		if cm._is_plain_bot_party(int(peer)) and pm.member_count(int(peer)) == 1 and not cm.is_government_party(int(peer)):
			pair.append(int(peer))
	pair = pair.slice(0, 2)
	var merged := false
	if pair.size() == 2:
		pm.parties[pair[1]]["ideology"] = pm.parties[pair[0]]["ideology"].duplicate()
		cm.passed_threshold.erase(pair[1])
		for attempt in 40:
			cm._bot_alliances()
			if pm.deputy_of(pair[0]) == pair[1] or pm.deputy_of(pair[1]) == pair[0]:
				merged = true
				break
	check("zayıf ve yakın iki bot birleşti", merged, str(pair))
	if merged:
		var host: int = pm.party_of(pair[0])
		var deputy: int = pm.deputy_of(host)
		check("birleşen botlar birbirine dost", BB.is_ally(host, deputy))
		pm.parties[host]["merged_elections"] = cm.BOT_MERGE_ELECTIONS
		cm._bot_alliances()
		check("birlikte büyüyen botlar ayrıldı", pm.deputy_of(host) == -1 and pm.is_leader(deputy))
		check("ayrılan botlar kardeş parti", BB.is_ally(host, deputy) and not BB.is_ally(host, me))
	cm.allow_bot_alliances = false

	print("=== GEÇİCİ PARTİLER ===")
	cm.allow_temporary_parties = true
	var temp := -1
	for attempt in 30:
		cm._hold_election(cm.round_number, false)
		for peer in cm.turn_order:
			if pm.parties.has(peer) and bool(pm.parties[peer].get("temporary", false)):
				temp = int(peer)
		if temp != -1:
			break
	check("rastgele yeni parti katıldı", temp != -1 and mm.players.has(temp))
	check("sandalyesiz başlar, biraz destekle", int(cm.last_seats.get(temp, 0)) == 0 and cm.national_of(temp) > 0.0)
	cm.allow_temporary_parties = false
	cm._hold_election(cm.round_number, false)
	cm._hold_election(cm.round_number, false)
	check("geçici parti en geç iki seçimde feshedip çıktı", not cm.turn_order.has(temp) and not pm.parties.has(temp)
		and not mm.players.has(temp))
	mm.random_parties = false
	cm.allow_temporary_parties = true
	var none := true
	for attempt in 10:
		cm._hold_election(cm.round_number, false)
		for peer in cm.turn_order:
			if pm.parties.has(peer) and bool(pm.parties[peer].get("temporary", false)):
				none = false
	check("lobi ayarı kapalıysa yeni parti gelmez", none)

	print("")
	print("=== %s ===" % ("TUM TESTLER GECTI" if _failed == 0 else "%d TEST BASARISIZ" % _failed))
	quit(1 if _failed > 0 else 0)
