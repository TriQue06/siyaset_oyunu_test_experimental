extends SceneTree
## PARTİ SİYASETİ TESTİ: tek liderli partiler, KONGRE (zorunlu / isteğe bağlı /
## üyenin talebi; başkanlığı kaybetme ve geri dönme), üyenin kısıtları, fesih,
## bağımsız siyasetçi (miting güvenilirliği) ve bağımsızdan parti kurma.
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

func check_quiet(_result: Dictionary) -> void:
	pass

func free_color(except_peer: int) -> Color:
	for color in load("res://scripts/party_presets.gd").COLORS:
		if not color.is_equal_approx(Color.WHITE) and pm.color_owner(color, except_peer) == -1:
			return color
	return Color.RED

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	PP = load("res://scripts/politician_presets.gd")
	mm = root.get_node("MultiplayerManager")
	cm = root.get_node("CardManager")
	cm.allow_temporary_parties = false
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

	print("=== TEK LİDER ===")
	check("oy veren sadece genel başkanlar", gm.voter_ids().size() == cm.party_ids().size())
	check("oy ağırlığı partinin bütün vekilleri", gm.vote_weight(me) == int(cm.last_seats.get(me, 0)))
	check("gelir bölünmez", is_equal_approx(cm.turn_income(me), float(GameRules.MANA_PER_ROUND)) or cm.is_government_party(me))

	print("=== KONGRE GÜCÜ ===")
	cm._congress_info(me)["share"] = float(cm.last_vote_shares.get(me, 0.0))
	var base_strength: float = cm.congress_strength(me)
	cm._congress_info(me)["share"] = float(cm.last_vote_shares.get(me, 0.0)) + 6.0
	check("oy kaybı gücü düşürür", cm.congress_strength(me) < base_strength - 20.0, "%.1f -> %.1f" % [base_strength, cm.congress_strength(me)])
	cm._congress_info(me)["share"] = float(cm.last_vote_shares.get(me, 0.0)) - 6.0
	check("oy artışı gücü artırır", cm.congress_strength(me) > base_strength + 15.0)
	cm._congress_info(me)["share"] = float(cm.last_vote_shares.get(me, 0.0))
	var strong: Dictionary = {}
	cm._congress_info(me)["share"] = float(cm.last_vote_shares.get(me, 0.0)) - 10.0
	for attempt in 10:
		strong = cm._compute_congress(me, "voluntary")
		check_quiet(strong)
	check("güçlü başkana en fazla 1 rakip", (strong["candidates"] as Array).size() <= 2, str((strong["candidates"] as Array).size()))
	cm._congress_info(me)["share"] = float(cm.last_vote_shares.get(me, 0.0)) + 15.0
	var weak: Dictionary = cm._compute_congress(me, "voluntary")
	check("zayıf başkana 3 rakip (en fazla 4 aday)", (weak["candidates"] as Array).size() == 4)
	var total_delegates := 0
	for d in weak["round1"]:
		total_delegates += int(d)
	check("1. turda bütün delegeler", total_delegates == cm.CONGRESS_DELEGATES, str(total_delegates))
	if not (weak["round2"] as Array).is_empty():
		check("2. tur iki aday ve bütün delegeler", int(weak["round2"][2]) + int(weak["round2"][3]) == cm.CONGRESS_DELEGATES)

	print("=== ZORUNLU KONGRE ===")
	cm._congress_info(b1)["elections"] = cm.CONGRESS_MAX_ELECTIONS
	cm.current_turn_index = (cm.turn_order.find(b1) - 1 + cm.turn_order.size()) % cm.turn_order.size()
	gm._set_phase(gm.Phase.IDLE)
	cm._advance_turn()
	check("3 seçimdir kongre yoksa sıra gelince kongre başlar", cm.congress_active and cm.elections_since_congress(cm.party_of(b1)) == 0)
	check("kongre sürerken tur akışı durur", cm.is_turn_blocked())
	cm.tick(cm.congress_duration(false) + 0.5)
	check("gösteri bitince tur akışı devam eder", not cm.congress_active)

	print("=== BAŞKANLIĞI KAYBETMEK ===")
	var lost := false
	for attempt in 20:
		give_turn(me)
		cm.mana[me] = 10.0
		cm._congress_info(me)["elections"] = 1
		cm._congress_info(me)["share"] = float(cm.last_vote_shares.get(me, 0.0)) + 20.0
		cm.turmoil[me] = 10.0
		cm.request_congress()
		cm.tick(30.0)
		if pm.is_deputy(me):
			lost = true
			break
	check("zayıf başkan kongreyi kaybetti, partide üye kaldı", lost)
	var new_leader: int = cm.party_of(me)
	check("partinin yeni bot başkanı sırada", new_leader != me and mm.is_bot(new_leader) and cm.turn_order.has(new_leader))
	give_turn(me)
	cm.mana[me] = 10.0
	var some_province: String = String(root.get_node("GameMap").province_ids()[0])
	check("üye yasa sunamaz", not cm.can_propose_law(me))
	check("üye teşkilat kuramaz", not cm.can_build_organization(me, some_province))
	check("üye kart oynayamaz", not cm.can_play_card(me, "populizm"))
	check("üye konuşmak zorunda değil", not cm.needs_speech(me))
	check("üye oy vermez", not gm.voter_ids().has(me) and gm.vote_weight(me) == 0)
	var org_province := ""
	for province_id in cm.organizations.keys():
		if int(cm.organizations[province_id].get(new_leader, 0)) > 0:
			org_province = String(province_id)
	if org_province != "":
		var cred_before: float = cm.credibility_of(me)
		cm.credibility[me] = 50.0
		cm.miting(org_province)
		check("üye miting yapar, güvenilirliği artar", cm.credibility_of(me) > 50.0)
		cm.credibility[me] = cred_before
	var score_me: int = gm.score_of(me)
	var score_leader: int = gm.score_of(new_leader)
	gm.add_party_score(new_leader, 4)
	check("parti puanı başkana da üyeye de aynı yazılır", gm.score_of(me) == score_me + 4 and gm.score_of(new_leader) == score_leader + 4)

	print("=== ÜYENİN KONGRE TALEBİ ===")
	cm._congress_info(new_leader)["elections"] = 0
	check("seçim olmadan kongre istenemez", not cm.can_request_congress(me))
	cm._congress_info(new_leader)["elections"] = 1
	cm.last_vote_shares[new_leader] = float(cm.party_congress[new_leader]["member_share"]) + 2.0
	check("bot başkan oyu artırdıysa kongre istenemez", not cm.can_request_congress(me) and cm.congress_block_reason(me) != "")
	var back := false
	for attempt in 30:
		var leader_now: int = cm.party_of(me)
		if not pm.is_deputy(me):
			back = true
			break
		cm._congress_info(leader_now)["elections"] = 1
		cm.last_vote_shares[leader_now] = float(cm.party_congress[leader_now]["member_share"]) - 8.0
		give_turn(me)
		cm.mana[me] = 10.0
		cm.request_congress()
		cm.tick(30.0)
	check("oy düşünce üye kongreyi kazanıp başkanlığa döndü", back or not pm.is_deputy(me))
	check("eski bot başkan siyasetten çekildi", not cm.turn_order.has(new_leader) or cm.party_of(new_leader) != cm.party_of(me))

	print("=== BOT BAŞKAN DEĞİŞİR ===")
	var bot_name: String = PP.display_name(b2)
	var changed := false
	for attempt in 20:
		cm._congress_info(b2)["share"] = float(cm.last_vote_shares.get(b2, 0.0)) + 20.0
		cm.turmoil[b2] = 10.0
		cm._run_congress(b2, "mandatory")
		cm.tick(30.0)
		if PP.display_name(b2) != bot_name:
			changed = true
			break
	check("zayıf bot başkan kongrede değişti (aynı parti, yeni siyasetçi)", changed and pm.is_leader(b2))
	give_turn(me)

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
	cm.credibility[me] = 60.0
	var p1: String = String(root.get_node("GameMap").province_ids()[3])
	var p2: String = String(root.get_node("GameMap").province_ids()[4])
	cm.local_support[p1] = {me: 5.0}
	cm.local_support[p2] = {me: 3.0}
	cm.mana[me] = 9.0
	cm.miting(p1)
	check("bağımsız mitingi güvenilirlik kazandırır", cm.credibility_of(me) > 60.0)
	give_turn(me)
	cm.mana[me] = 9.0
	cm.found_party({"name": "Doğru Yol", "icon_index": 4, "bg_color": free_color(me)})
	check("bağımsız parti kurdu (8 mana)", not pm.is_independent(me) and pm.parties[me]["name"] == "Doğru Yol"
		and is_equal_approx(cm.mana_of(me), 1.0), str(cm.mana_of(me)))
	var opened := 0
	for province_id in cm.organizations.keys():
		opened += int(cm.organizations[province_id].get(me, 0))
	check("güvenilirliğe göre miting yaptığı illerde teşkilatla başladı", int(cm.organizations.get(p1, {}).get(me, 0)) == 1
		and opened <= mini(cm.FOUND_ORG_MAX, int(cm.credibility_of(me) / cm.FOUND_ORG_PER_CREDIBILITY)), str(opened))
	check("bağımsız sandalyesi partiye geçti", int(cm.last_seats.get(me, 0)) == 1)

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
	check("seçimde hemen feshetmez, tur ortasını bekler", cm.turn_order.has(temp) and pm.parties[temp].has("retire_at"))
	cm.current_turn_index = 0
	var gone_at := -1
	for step in cm.turn_order.size():
		var wrapped: bool = cm._advance_turn()
		if not cm.turn_order.has(temp):
			gone_at = -2 if wrapped else cm.current_turn_index
			break
	check("tur ortasında feshetti", gone_at >= 1, str(gone_at))
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

	print("=== OYUNDAN DÜŞME VE GERİ DÖNME ===")
	var bm = root.get_node("BotManager")
	mm.players[me]["away"] = true
	mm.away_mode = mm.AWAY_BOT
	check("bot modunda düşen oyuncuyu yapay zekâ oynar", mm.is_ai_controlled(me) and not mm.is_bot(me))
	mm.away_mode = mm.AWAY_PASSIVE
	cm.game_finished = false
	cm.congress_active = false
	give_turn(me)
	bm.step(1000.0)
	check("pasif modda sırası kendiliğinden geçer", cm.current_turn_peer_id() != me)
	var my_score: int = gm.score_of(me)
	var my_mana: float = cm.mana_of(me)
	var my_name: String = PP.display_name(me)
	var was_leader: bool = pm.parties.has(me)
	cm.rekey_player(me, 777)
	check("geri dönen oyuncu yeni bağlantıyla aynı yerde", cm.turn_order.has(777) and not cm.turn_order.has(me)
		and gm.score_of(777) == my_score and is_equal_approx(cm.mana_of(777), my_mana) and PP.display_name(777) == my_name
		and (pm.parties.has(777) == was_leader))
	cm.rekey_player(777, me)
	mm.players[me].erase("away")
	mm.away_mode = mm.AWAY_BOT

	print("=== BOT MANA ZAYIFLATMASI ===")
	var some_bot: int = int(mm.bot_ids()[0])
	check("varsayılan zayıflatma 0,5", is_equal_approx(mm.bot_mana_penalty, 0.5))
	var bot_base := float(GameRules.MANA_PER_ROUND_GOVERNMENT if cm.is_government_party(some_bot) else GameRules.MANA_PER_ROUND)
	check("bot tur başında 0,5 az mana alır", is_equal_approx(cm.turn_income(some_bot), bot_base - 0.5))
	check("bot mana bonusundan 0,5 az alır", is_equal_approx(cm.mana_bonus_amount(some_bot, false), GameRules.MANA_BONUS_WEAK - 0.5)
		and is_equal_approx(cm.mana_bonus_amount(some_bot, true), GameRules.MANA_BONUS_STRONG - 0.5))
	check("gerçek oyuncu etkilenmez", is_equal_approx(cm.mana_bonus_amount(me, false), float(GameRules.MANA_BONUS_WEAK)))
	mm.bot_mana_penalty = 1.5
	check("1,5 zayıflatma", is_equal_approx(cm.turn_income(some_bot), bot_base - 1.5))
	mm.bot_mana_penalty = 0.5

	print("=== KRİZ ===")
	var crisis_bot: int = cm.party_of(int(mm.bot_ids()[1]))
	cm.crisis = {"type": "kriz_economic_n", "until": cm.round_number + 1}
	check("kriz açık", cm.crisis_type() == "kriz_economic_n" and cm.crisis_wants("economic", -0.5) and not cm.crisis_wants("economic", 0.5))
	var before_national: float = cm.national_of(crisis_bot)
	cm._shift_ideologies([{"peer": crisis_bot, "axis": "economic", "delta": -0.5}])
	var gained: float = cm.national_of(crisis_bot) - before_national
	check("krizin ucuna dönen kısmi ulusal destek kazanır", gained > 0.0 and gained <= 1.0, str(gained))
	before_national = cm.national_of(crisis_bot)
	cm._shift_ideologies([{"peer": crisis_bot, "axis": "economic", "delta": 0.5}])
	check("ters yöne giden kazanmaz", cm.national_of(crisis_bot) <= before_national + 0.0001)
	cm.crisis = {}

	print("")
	print("=== %s ===" % ("TUM TESTLER GECTI" if _failed == 0 else "%d TEST BASARISIZ" % _failed))
	quit(1 if _failed > 0 else 0)
