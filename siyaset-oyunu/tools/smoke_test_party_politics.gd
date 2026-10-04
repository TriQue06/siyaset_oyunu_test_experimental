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
	check("mana geliri bölünür", is_equal_approx(cm.turn_income(b1), cm.turn_income(me))
		and cm.turn_income(me) < float(GameRules.MANA_PER_ROUND), str(cm.turn_income(me)))
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
	cm.found_party({"name": "Hür Yol", "icon_index": 2, "bg_color": free_color(me)})
	check("ayrılan yeni parti kurdu", pm.is_leader(me) and pm.parties[me]["name"] == "Hür Yol" and pm.deputy_of(b1) == -1,
		str(pm.parties.get(me, {})))
	check("ayrılma 2 mana", is_equal_approx(cm.mana_of(me), 8.0), str(cm.mana_of(me)))
	var my_orgs := 0
	for province_id in cm.organizations.keys():
		if int(cm.organizations[province_id].get(me, 0)) > 0:
			my_orgs += 1
	check("teşkilatların bir kısmı ayrılanla gitti", my_orgs >= 1, str(my_orgs))

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

	print("")
	print("=== %s ===" % ("TUM TESTLER GECTI" if _failed == 0 else "%d TEST BASARISIZ" % _failed))
	quit(1 if _failed > 0 else 0)
