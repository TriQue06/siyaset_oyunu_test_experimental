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
	seed(20240607)  # global RNG: harita tohumu, sıra karıştırma, bot isim/memleket -> deterministik
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
		["isveren", "ilerici"], true)
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
	cm._apply_speech(first, "isci")
	check("toplanınca bu dönem tekrar toplanamaz", not cm.needs_speech(first))
	for i in cm.turn_order.size():
		cm._apply_pass(cm.current_turn_peer_id(), true)
		gm._set_phase(gm.Phase.IDLE)
	check("yeni dönemde ilk oyuncu tekrar toplanabilir", cm.current_turn_peer_id() == first and cm.needs_speech(first),
		"sira %d, donem %d" % [cm.current_turn_peer_id(), cm.round_number])

	print("=== OYLAMA TAKILMASI ===")
	# Yasa oylaması açıkken bir oyuncu oyundan çıkar; kalanlar oy vermişse sonuç açıklanmalı.
	cm.current_turn_index = cm.turn_order.find(me)
	gm._set_phase(gm.Phase.IDLE)
	gm.submit_law(me, "law:isveren")
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
	check("gelir bölünmez", is_equal_approx(cm.turn_income(me) - cm.org_income(me), float(GameRules.FUNDS_PER_ROUND)) or cm.is_government_party(me))

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
	cm.tick(cm.congress_duration(false) + GameRules.ELECTION_NIGHT_PAPER + 0.5)  # gösteri + sonuç gazetesi
	check("gösteri bitince tur akışı devam eder", not cm.congress_active)

	print("=== BAŞKANLIĞI KAYBETMEK ===")
	var lost := false
	for attempt in 20:
		give_turn(me)
		cm.funds[me] = 100.0
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
	cm.funds[me] = 100.0
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
		cm.funds[me] = 100.0
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
	var snapshot: Dictionary = cm.former_parties.get(me, {}).get("orgs", {})
	check("fesih: dağılan teşkilatlar eski parti kaydında", cm.former_parties.has(me) and not snapshot.is_empty(), str(cm.former_parties.get(me, {})))
	check("bağımsız her ilde miting yapabilir", cm.can_miting(me, String(root.get_node("GameMap").province_ids()[5])) or cm.funds_of(me) < GameRules.MITING_FUNDS_COST)
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
	cm.funds[me] = 90.0
	cm.miting(p1)
	check("bağımsız mitingi güvenilirlik kazandırır", cm.credibility_of(me) > 60.0)
	give_turn(me)
	cm.funds[me] = 90.0
	var expect_moved: int = cm.former_org_count(me)
	var expect_share: float = cm.former_org_share(me)
	check("geçiş payı %10-%90 arasında", expect_share >= 0.1 and expect_share <= 0.9 and expect_moved >= 1, "%.2f / %d" % [expect_share, expect_moved])
	cm.found_party({"name": "Doğru Yol", "icon_index": 4, "bg_color": free_color(me)})
	check("bağımsız parti kurdu (80 milyon)", not pm.is_independent(me) and pm.parties[me]["name"] == "Doğru Yol"
		and is_equal_approx(cm.funds_of(me), 10.0), str(cm.funds_of(me)))
	var opened := 0
	for province_id in cm.organizations.keys():
		opened += int(cm.organizations[province_id].get(me, 0))
	check("güvenilirliğe göre miting yaptığı illerde teşkilatla başladı", int(cm.organizations.get(p1, {}).get(me, 0)) >= 1)
	var inherited := 0
	for province_id in snapshot.keys():
		if int(cm.organizations.get(province_id, {}).get(me, 0)) >= int(snapshot[province_id]):
			inherited += 1
	check("feshedilen partinin teşkilatlarından payı kadarı geri geldi", inherited >= expect_moved and not cm.former_parties.has(me),
		"%d / %d" % [inherited, expect_moved])

	print("=== ESKİ PARTİDEN TEŞKİLAT GEÇİŞİ ===")
	var donor := -1
	for bot in mm.bot_ids():
		var n := 0
		for province_id in cm.organizations.keys():
			if int(cm.organizations[province_id].get(int(bot), 0)) > 0:
				n += 1
		if pm.is_leader(int(bot)) and not pm.is_independent(int(bot)):
			donor = int(bot)
	if donor != -1:
		# Eski partinin 6 ilde teşkilatı olsun (geçiş oranı ölçülebilsin).
		var ids: Array = root.get_node("GameMap").province_ids()
		for k in 6:
			var pid_k := String(ids[10 + k])
			if not cm.organizations.has(pid_k):
				cm.organizations[pid_k] = {}
			cm.organizations[pid_k][donor] = 1 + k % 2
	check("teşkilatlı bir bot partisi var", donor != -1)
	if donor != -1:
		var round_now: int = cm.round_number
		cm.former_parties[me] = {"party": donor, "name": "Eski", "round": round_now}
		var fresh: float = cm.former_org_share(me)
		cm.former_parties[me]["round"] = round_now - 8
		var late: float = cm.former_org_share(me)
		check("ayrılıştan beri zaman geçtikçe pay azalır", late < fresh, "%.2f -> %.2f" % [fresh, late])
		cm.former_parties[me]["round"] = round_now
		var nat_before: float = cm.national_of(me)
		cm.national_support[me] = 5.0
		var popular: float = cm.former_org_share(me)
		cm.national_support[me] = -5.0
		var unpopular: float = cm.former_org_share(me)
		cm.national_support[me] = nat_before
		check("ulusal destek payı artırır", popular > unpopular, "%.2f / %.2f" % [popular, unpopular])
		gm.scores[me] = 0
		var low_score: float = cm.former_org_share(me)
		gm.scores[me] = 30
		check("geçmiş başarı (puan) payı artırır", cm.former_org_share(me) > low_score)
		cm.national_support[me] = -50.0
		cm.credibility[me] = 0.0
		cm.former_parties[me]["round"] = round_now - 40
		gm.scores[me] = 0
		check("pay en az %10", is_equal_approx(cm.former_org_share(me), cm.FORMER_ORG_MIN))
		cm.national_support[me] = 50.0
		cm.credibility[me] = 100.0
		cm.former_parties[me]["round"] = round_now
		gm.scores[me] = 100
		check("pay en fazla %90", is_equal_approx(cm.former_org_share(me), cm.FORMER_ORG_MAX))
		cm.national_support[me] = nat_before
		var source: Dictionary = cm.former_org_source(me)
		var count: int = cm.former_org_count(me)
		var moved: Array = cm._transfer_former_orgs(me)
		var left := 0
		for province_id in source.keys():
			if int(cm.organizations[province_id].get(donor, 0)) > 0:
				left += 1
		check("süren partiden teşkilatlar kopar (taşınır)", int(moved[0]) == count and left == source.size() - count,
			"%d taşındı, %d kaldı / %d" % [int(moved[0]), left, source.size()])
		cm.former_parties.erase(me)
	check("bağımsız sandalyesi partiye geçti", int(cm.last_seats.get(me, 0)) == 1)

	print("=== GEÇİCİ PARTİLER ===")
	cm.allow_temporary_parties = true
	mm.random_parties = true  # 0.0.186: lobide varsayılan kapalı
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
			gone_at = -2 if wrapped else step + 1  # kaçıncı hamlede (sıradan silinince indeks kayabilir)
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
	var my_funds: float = cm.funds_of(me)
	var my_name: String = PP.display_name(me)
	var was_leader: bool = pm.parties.has(me)
	cm.rekey_player(me, 777)
	check("geri dönen oyuncu yeni bağlantıyla aynı yerde", cm.turn_order.has(777) and not cm.turn_order.has(me)
		and gm.score_of(777) == my_score and is_equal_approx(cm.funds_of(777), my_funds) and PP.display_name(777) == my_name
		and (pm.parties.has(777) == was_leader))
	cm.rekey_player(777, me)
	mm.players[me].erase("away")
	mm.away_mode = mm.AWAY_BOT

	print("=== BOT GELIR ZAYIFLATMASI ===")
	var some_bot: int = int(mm.bot_ids()[0])
	check("varsayılan zayıflatma 5", is_equal_approx(mm.bot_funds_penalty, 5.0))
	var bot_base := float(GameRules.FUNDS_PER_ROUND_GOVERNMENT if cm.is_government_party(some_bot) else GameRules.FUNDS_PER_ROUND)
	check("bot tur başında 5 az para alır", is_equal_approx(cm.turn_income(some_bot) - cm.org_income(some_bot), bot_base - 5.0))
	check("bot bagis kampanyasindan 5 az alır", is_equal_approx(cm.funds_bonus_amount(some_bot, false), GameRules.FUNDS_BONUS_WEAK - 5.0)
		and is_equal_approx(cm.funds_bonus_amount(some_bot, true), GameRules.FUNDS_BONUS_STRONG - 5.0))
	check("gerçek oyuncu etkilenmez", is_equal_approx(cm.funds_bonus_amount(me, false), float(GameRules.FUNDS_BONUS_WEAK)))
	mm.bot_funds_penalty = 15.0
	check("15 zayıflatma", is_equal_approx(cm.turn_income(some_bot) - cm.org_income(some_bot), bot_base - 15.0))
	mm.bot_funds_penalty = 5.0

	print("=== TEŞKİLAT GELİRİ VE BEDELLER ===")
	# Teşkilat geliri il başına 5 / 10 milyon ₺, toplamı en fazla ORG_INCOME_CAP.
	var saved_orgs: Dictionary = cm.organizations.duplicate(true)
	cm.organizations = {}
	var org_test_pid: String = String(cm._province_ids[5])
	var income_before: int = cm.org_income(me)
	cm.organizations[org_test_pid] = {cm.party_of(me): 1}
	var lvl1: int = cm.org_income(me)
	cm.organizations[org_test_pid][cm.party_of(me)] = 2
	var lvl2: int = cm.org_income(me)
	check("1. seviye teşkilat +5, 2. seviye +10 milyon ₺", income_before == 0 and lvl1 == 5 and lvl2 == 10, "%d %d %d" % [income_before, lvl1, lvl2])
	for i in 20:
		cm.organizations[String(cm._province_ids[i])] = {cm.party_of(me): 2}
	check("teşkilat geliri üst sınırı (sınırsız para yok)", cm.org_income(me) == GameRules.ORG_INCOME_CAP, str(cm.org_income(me)))
	cm.organizations = saved_orgs
	check("yasa bedelsiz, toplantı 5, kongre 10 / üye 20", GameRules.LAW_FUNDS_COST == 0 and GameRules.EARLY_ELECTION_FUNDS_COST == 0 and GameRules.CENSURE_FUNDS_COST == 0 and GameRules.SPEECH_FUNDS_COST == 5
		and cm.CONGRESS_COST == 10 and cm.CONGRESS_REQUEST_COST == 20)

	print("=== GÜNDEM (kriz birleşti) ===")
	var crisis_bot: int = cm.party_of(int(mm.bot_ids()[1]))
	var saved_agenda: Dictionary = cm.agenda
	cm.agenda = {"type": "gundem_isci", "until": cm.round_number + 1}
	check("gündem işçileri istiyor, ayrı kriz yok", cm.crisis_type() == "" and cm.crisis_group() == "isci" and cm.agenda_groups() == ["isci"])
	# Gündem dışı gruba da yasa sunulabilir (eskiden sadece gündem çifti).
	# İki yasa da aynı başlangıçtan (50) ölçülsün: azalan getiri karışmasın.
	for g in ["dindar", "ilerici", "isci", "isveren"]:
		pm.parties[crisis_bot]["groups"][g] = 50.0
	var gb: Dictionary = (pm.parties[crisis_bot]["groups"] as Dictionary).duplicate()
	cm.apply_law_result(crisis_bot, "law:dindar", {}, true, [])
	var off_gain: float = float(pm.parties[crisis_bot]["groups"]["dindar"]) - float(gb["dindar"])
	gb = (pm.parties[crisis_bot]["groups"] as Dictionary).duplicate()
	cm.apply_law_result(crisis_bot, "law:isci", {}, true, [])
	var on_gain: float = float(pm.parties[crisis_bot]["groups"]["isci"]) - float(gb["isci"])
	print("  (grup etkisi: gündem dışı %.2f, gündemde %.2f)" % [off_gain, on_gain])
	check("gündemdeki gruba yasa daha güçlü", on_gain > off_gain * 1.1, "%.2f > %.2f" % [on_gain, off_gain])
	var before_national: float = cm.national_of(crisis_bot)
	cm.apply_law_result(crisis_bot, "law:isci", {}, false, [])
	var gained: float = cm.national_of(crisis_bot) - before_national
	check("gündemin grubuna yasa sunan ulusal destek kazanır", is_equal_approx(gained, PublicOpinion.CRISIS_RESPONSE_NATIONAL), str(gained))
	before_national = cm.national_of(crisis_bot)
	cm.apply_law_result(crisis_bot, "law:isveren", {}, false, [])
	check("karşıt gruba yasa sunan gündem desteği almaz", cm.national_of(crisis_bot) <= before_national + 0.0001)
	cm.agenda = saved_agenda

	print("")
	print("=== %s ===" % ("TUM TESTLER GECTI" if _failed == 0 else "%d TEST BASARISIZ" % _failed))
	quit(1 if _failed > 0 else 0)
