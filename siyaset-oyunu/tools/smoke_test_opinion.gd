extends SceneTree
## Güç (aktivite) kuralları: miting/provokasyon, yatırım, İL İL yasa etkileri,
## iktidar yorgunluğu, vekil momentumu, il başkanlığı, anket/gözcü/karalama,
## deste ağırlıkları ve sönme (yerel mod, RPC yok).
## `godot --headless --script res://tools/smoke_test_opinion.gd`

var mm
var pm
var cm
var gm
var gp
var cp
var voters: Dictionary
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func ideology(e: int, s: int, a: int) -> Dictionary:
	return {"economic": e, "social": s, "administrative": a}

## Yeni oyun; illerin görüşü deterministik olsun diye örnek dosyadan alınır.
func new_game(ideologies: Dictionary) -> void:
	mm.players = {}
	pm.parties = {}
	for peer_id in ideologies.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.3, 0.5, 0.7), "ideology": ideologies[peer_id].duplicate(), "ready": true,
		}
	cm.init_game()
	cm.province_ideology = voters.duplicate(true)
	cm.turn_order = ideologies.keys()
	cm.current_turn_index = 0

func pass_round() -> void:
	for i in cm.turn_order.size():
		cm._apply_pass(cm.current_turn_peer_id())

func all_posts_to(peer_id: int) -> Dictionary:
	var a := {}
	for post in gp.POSTS:
		a[post["id"]] = peer_id
	return a

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

func extreme(axis: String, highest: bool) -> String:
	var best := ""
	for province_id in voters.keys():
		var v := float(voters[province_id][axis])
		if best == "" or (highest and v > float(voters[best][axis])) or (not highest and v < float(voters[best][axis])):
			best = province_id
	return best

func most_neutral(axis: String) -> String:
	var best := ""
	for province_id in voters.keys():
		if best == "" or absf(float(voters[province_id][axis])) < absf(float(voters[best][axis])):
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
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	mm.axis_sharpness_start = 1.0
	mm.axis_sharpness_increment = 0.0
	mm.election_threshold = 0.0
	cm.set_rng_seed(12345)
	voters = ElectionModel.load_province_voters()

	print("=== 1) GUC SECIMI ETKILER ===")
	var seats = JSON.parse_string(FileAccess.get_file_as_string("res://data/province_seats.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var same := {1: ideology(0, 0, 0), 2: ideology(0, 0, 0)}
	var r := ElectionModel.compute(same, seats, voters, 0.0, 1.0, rng, {"national": {1: 8.0}})
	check("ulusal +8 puanli, ayni gorusteki partiden belirgin fazla oy aldi",
		float(r["vote_shares"][1]) > float(r["vote_shares"][2]) + 5.0, str(r["vote_shares"]))
	check("carpan sinirli", near(PublicOpinion.multiplier(100.0, 100.0), PublicOpinion.MAX_MULT) \
		and near(PublicOpinion.multiplier(-100.0, 0.0), PublicOpinion.MIN_MULT))

	print("")
	print("=== 2) PROVOKASYON RISKI ===")
	var konya: Dictionary = voters["konya"]
	check("secmene yakin parti: risk yok", near(PublicOpinion.provocation_risk(ideology(0, 2, 2), konya), 0.0))
	var far_risk := PublicOpinion.provocation_risk(ideology(-3, -3, -3), konya)
	check("zit uc parti: belirgin risk", far_risk > 0.25 and far_risk <= 0.5, "%.2f" % far_risk)
	check("il baskanligi riski azaltir", PublicOpinion.provocation_risk(ideology(-3, -3, -3), konya, 2) < far_risk * 0.6)
	check("tam zit uclar: risk %50'de durur",
		near(PublicOpinion.provocation_risk(ideology(-3, -3, -3), ideology(3, 3, 3)), 0.5))
	new_game({1: ideology(3, 3, 3), 2: ideology(-3, -3, -3)})
	var before: float = cm.miting_risk(2, "konya")
	cm._add_local("konya", 1, 8.0)
	var after: float = cm.miting_risk(2, "konya")
	check("uc sag parti ilde guclenince uc solun riski artar", after > before and after <= 0.5,
		"%.2f -> %.2f" % [before, after])

	print("")
	print("=== 3) MITING ===")
	new_game({1: ideology(0, 2, 2), 2: ideology(0, 2, 2)})
	check("dengeye yakin partinin riski 0", near(cm.miting_risk(1, "konya"), 0.0), "%.2f" % cm.miting_risk(1, "konya"))
	cm._apply_miting(1, "konya")
	check("basarili miting: il +3", near(cm.local_of("konya", 1), PublicOpinion.MITING_LOCAL))
	check("basarili miting: ulusal +0.5", near(cm.national_of(1), PublicOpinion.MITING_NATIONAL))
	check("ilde olay kaydi var", cm.province_events.get("konya", []).size() == 1)
	new_game({1: ideology(3, 3, 3), 2: ideology(-3, -3, -3)})
	cm._add_local("konya", 1, 10.0)
	var provoked := 0
	var succeeded := 0
	for i in 40:
		cm.local_support["konya"][2] = 0.0
		cm._apply_miting(2, "konya")
		var value: float = cm.local_of("konya", 2)
		if near(value, PublicOpinion.PROVOCATION_LOCAL):
			provoked += 1
		elif near(value, PublicOpinion.MITING_LOCAL):
			succeeded += 1
	check("riskli ilde hem provokasyon hem basari gorulur", provoked > 0 and succeeded > 0 and provoked + succeeded == 40,
		"provokasyon %d, basari %d" % [provoked, succeeded])
	check("olay kaydi sinirli", cm.province_events["konya"].size() == cm.PROVINCE_EVENT_LIMIT)

	print("")
	print("=== 4) YATIRIM ===")
	new_game({1: ideology(0, 0, 0), 2: ideology(0, 0, 0), 3: ideology(1, 1, -1)})
	pass_round()
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	gm.start_formation()
	var coalition := all_posts_to(1)
	coalition[gp.POST_DEPUTY_PM] = 2
	gm._apply_government_proposal(1, coalition)
	gm._apply_vote(2, true)
	gm._apply_vote(3, false)
	check("hukumet (1+2) kuruldu", gm.has_government() and gm.government_party_ids().size() == 2)
	cm.mana = {1: 10, 2: 10, 3: 10}
	cm.turn_order = [3, 1, 2]
	cm.current_turn_index = 0
	check("muhalefet yatirim yapamaz", not cm.can_invest(3, "izmir"))
	cm.current_turn_index = 1
	check("hukumet partisi yatirim yapabilir", cm.can_invest(1, "izmir"))
	check("gecersiz il reddedilir", not cm.can_invest(1, "atlantis"))
	cm.local_support = {}
	cm.national_support = {}
	cm._apply_invest_move(1, "izmir")
	check("yatirim hamlesi 3 mana", cm.mana_of(1) == 10 - GameRules.INVEST_MANA_COST)
	check("getiren parti il +3", near(cm.local_of("izmir", 1), PublicOpinion.INVEST_LOCAL))
	check("ortak il +1.5", near(cm.local_of("izmir", 2), PublicOpinion.INVEST_PARTNER_LOCAL))
	check("muhalefet etkilenmez", near(cm.local_of("izmir", 3), 0.0))
	check("getiren parti ulusal +0.5", near(cm.national_of(1), PublicOpinion.INVEST_NATIONAL))
	check("yatirim destede degil (hamle)", not cm._draw_weights(1).has("yatirim"))

	print("")
	print("=== 5) YASA ETKILERI IL IL ===")
	cm.national_support = {}
	cm.local_support = {}
	var eco_pos := extreme("economic", true)
	var eco_neg := extreme("economic", false)
	var a_pos := PublicOpinion.law_alignment(voters[eco_pos], "economic", 1)
	var a_neg := PublicOpinion.law_alignment(voters[eco_neg], "economic", 1)
	var law_eco: String = cp.law_type("economic", 1)
	check("muhalefet yasa getirebilir", gm.submit_law(3, law_eco) and gm.proposal_kind == gm.KIND_LAW)
	gm._apply_vote(3, gm.VOTE_YES)
	gm._apply_vote(1, gm.VOTE_YES)   # iktidar muhalefetin yasasına EVET
	gm._apply_vote(2, gm.VOTE_NO)
	check("yasa gecti (290 EVET)", gm.phase == gm.Phase.GOVERNING and gm.last_resolution_reason.find("kabul") != -1, gm.last_resolution_reason)
	check("getiren: yakin ilde 2 kat arti", near(cm.local_of(eco_pos, 3), PublicOpinion.law_proposer_delta(a_pos, true)) \
		and cm.local_of(eco_pos, 3) > 0.0, "%.2f" % cm.local_of(eco_pos, 3))
	check("getiren: zit ilde eksi", cm.local_of(eco_neg, 3) < 0.0)
	check("iktidar muhalefete EVET: zit ilde eksi", near(cm.local_of(eco_neg, 1), PublicOpinion.law_vote_delta(a_neg, 1, true, false)) \
		and cm.local_of(eco_neg, 1) < 0.0, "%.2f" % cm.local_of(eco_neg, 1))
	check("iktidar muhalefete EVET: yakin ilde nötr/arti", cm.local_of(eco_pos, 1) >= -0.001 or a_pos < 0.67,
		"%.2f (uyum %.2f)" % [cm.local_of(eco_pos, 1), a_pos])
	check("HAYIR: yakin ilde eksi, zit ilde arti", cm.local_of(eco_pos, 2) < 0.0 and cm.local_of(eco_neg, 2) > 0.0)
	check("yasa ulusal puana yazilmaz", cm.national_support.is_empty(), str(cm.national_support))
	check("getirenin gorusu yasa yonune kaydi", int(pm.parties[3]["ideology"]["economic"]) == 2)

	cm.local_support = {}
	var soc_mid := most_neutral("social")
	var a_mid := PublicOpinion.law_alignment(voters[soc_mid], "social", -1)
	gm.submit_law(1, cp.law_type("social", -1))
	gm._apply_vote(1, gm.VOTE_YES)
	gm._apply_vote(2, gm.VOTE_ABSTAIN)
	gm._apply_vote(3, gm.VOTE_YES)   # muhalefet iktidarın yasasına EVET: istikrar bonusu yok
	check("muhalefet iktidara EVET: sadece ideolojik etki", near(cm.local_of(soc_mid, 3), PublicOpinion.LAW_VOTE_IDEOLOGY * a_mid),
		"%.2f" % cm.local_of(soc_mid, 3))
	var abstain_untouched := true
	for province_id in cm.local_support.keys():
		if cm.local_of(province_id, 2) != 0.0:
			abstain_untouched = false
	check("cekimser etkilenmez", abstain_untouched)

	cm.local_support = {}
	var adm_pos := extreme("administrative", true)
	gm.submit_law(2, cp.law_type("administrative", 1))
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(1, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_NO)
	check("yasa reddedildi", gm.last_resolution_reason.find("reddedildi") != -1, gm.last_resolution_reason)
	check("reddedilen yasanin getiricisi tek kat etki",
		near(cm.local_of(adm_pos, 2), PublicOpinion.law_proposer_delta(PublicOpinion.law_alignment(voters[adm_pos], "administrative", 1), false)))
	check("yasa sadece meclis varken ve kurma asamasi disinda", gm.can_submit_law())

	print("")
	print("=== 6) IKTIDAR YORGUNLUGU, VEKIL MOMENTUMU, IL BASKANLIGI ===")
	cm.national_support = {1: 2.0, 3: 1.0}
	var mods: Dictionary = cm.election_modifiers()
	check("hukumet partisi secime iktidar dengesiyle girer", near(float(mods["national"][1]), 2.0 + PublicOpinion.GOVERNMENT_FATIGUE))
	check("ortak da ayni dengeyi alir", near(float(mods["national"].get(2, 0.0)), PublicOpinion.GOVERNMENT_FATIGUE))
	check("muhalefet yorulmaz", near(float(mods["national"][3]), 1.0))
	check("gercek puan degismedi", near(cm.national_of(1), 2.0))
	cm.election_seats = {1: 200, 2: 100, 3: 90}
	cm.last_seats = {1: 190, 2: 100, 3: 100}
	cm.organizations = {"konya": {3: 2}}
	cm.local_support = {}
	mods = cm.election_modifiers()
	check("vekil calan parti momentumla girer", near(float(mods["national"][3]), 1.0 + PublicOpinion.seat_momentum(10.0 / float(cm.TOTAL_SEATS) * 100.0)),
		"%.2f" % float(mods["national"][3]))
	check("vekil kaybeden parti eksi momentum", float(mods["national"][1]) < 2.0 + PublicOpinion.GOVERNMENT_FATIGUE)
	check("il baskanligi il carpanina girer", near(float(mods["local"]["konya"][3]), PublicOpinion.org_activity(2)))
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	cm.election_seats = {}
	cm.organizations = {}

	print("")
	print("=== 7) GENSORU HAMLESI ===")
	cm.mana = {1: 10, 2: 10, 3: 10}
	cm.turn_order = [3, 1, 2]
	cm.current_turn_index = 0
	check("gensoru destede degil (hamle)", not cm._draw_weights(3).has("gensoru"))
	check("cogunluk hukumeti: gensoru verilemez", not cm.can_censure(3))
	cm.last_seats = {1: 100, 2: 50, 3: 240}
	check("azinlik hukumeti: muhalefet gensoru verebilir", cm.can_censure(3))
	cm.current_turn_index = 1
	check("hukumet partisi gensoru veremez", not cm.can_censure(1))
	cm.current_turn_index = 0
	cm.national_support = {}
	cm._apply_censure_move(3)
	check("gensoru hamlesi 2 mana, oylama acildi", cm.mana_of(3) == 10 - GameRules.CENSURE_MANA_COST and gm.phase == gm.Phase.VOTING)
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	var score3_before: int = gm.score_of(3)
	gm._apply_vote(3, gm.VOTE_YES)
	gm._apply_vote(1, gm.VOTE_NO)
	gm._apply_vote(2, gm.VOTE_NO)
	check("reddedilen gensoru: hukumet gorevde", gm.has_government() and gm.phase == gm.Phase.GOVERNING, gm.last_resolution_reason)
	check("reddedilen gensoruyu veren ulusal destek kaybeder", near(cm.national_of(3), PublicOpinion.CENSURE_REJECTED_NATIONAL),
		"%.2f" % cm.national_of(3))
	check("puan tablosu etkilenmez", gm.score_of(3) == score3_before, str(gm.score_of(3)))

	print("")
	print("=== 8) SONME (IL BASKANLIGI SONMEZ) ===")
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	cm.inventories[3] = []
	cm.national_support = {3: 4.0}
	cm.local_support = {"konya": {3: 2.0}}
	cm.organizations = {"konya": {3: 1}}
	var round_before: int = cm.round_number
	cm.current_turn_index = 0
	pass_round()
	check("secimsiz tur gecti", cm.round_number == round_before + 1 and gm.has_government(), "tur %d" % cm.round_number)
	check("ulusal puan %10 sondu", near(cm.national_of(3), 4.0 * PublicOpinion.NATIONAL_DECAY), "%.3f" % cm.national_of(3))
	check("il puani %15 sondu", near(cm.local_of("konya", 3), 2.0 * PublicOpinion.LOCAL_DECAY), "%.3f" % cm.local_of("konya", 3))
	check("teskilat sonmedi", near(cm.activity_of("konya", 3), 2.0 * PublicOpinion.LOCAL_DECAY + PublicOpinion.org_activity(1)))

	print("")
	print("=== 9) TESKILAT BILGISI, KARALAMA ===")
	var w: Dictionary = cm._draw_weights(3)
	check("karalama destede; anket ve gozcu destede degil", not w.has("anket") and not w.has("gozcu") and w.has("karalama"))
	cm.mana[3] = 50
	cm.organizations = {}
	cm.local_support = {}
	cm.turn_order = [3, 1, 2]
	cm.current_turn_index = 0
	cm.inventories[3] = ["karalama"]
	cm._apply_play(3, 0, -1, "")
	check("il secilmeden karalama oynanamaz (kart elde)", cm.inventories[3].size() == 1 and cm.current_turn_peer_id() == 3)
	cm._apply_organization(3, "ankara")
	check("teskilat: il gorusu (sadece kurana)", cm.knows_leaning(3, "ankara") and not cm.knows_leaning(1, "ankara"))
	cm.organizations = {}
	check("karalama kendine oynanamaz", not cm.can_play_card(3, "karalama", 3, "ankara"))
	check("karalama gecersiz partiye oynanamaz", not cm.can_play_card(3, "karalama", 99, "ankara"))
	cm.current_turn_index = 0
	var damage: float = minf(PublicOpinion.propaganda_damage(cm.party_strength("ankara", 1)), -PublicOpinion.PROPAGANDA_FLOOR)
	cm._apply_play(3, 0, 1, "ankara")
	check("karalama: hedefe eksi, yapana arti", near(cm.local_of("ankara", 1), -damage) and cm.local_of("ankara", 3) > 0.0,
		"hedef %.2f, yapan %.2f" % [cm.local_of("ankara", 1), cm.local_of("ankara", 3)])
	cm.local_support["ankara"][1] = -2.5
	cm.inventories[3] = ["karalama"]
	cm.current_turn_index = 0
	cm._apply_play(3, 0, 1, "ankara")
	check("karalama il puanini tabanin altina itemez", near(cm.local_of("ankara", 1), PublicOpinion.PROPAGANDA_FLOOR),
		"%.2f" % cm.local_of("ankara", 1))
	cm.inventories[3] = ["karalama"]
	cm.current_turn_index = 0
	cm._apply_play(3, 0, 1, "ankara")
	check("tabandaki partiye karalama artik eksi yazmaz", near(cm.local_of("ankara", 1), PublicOpinion.PROPAGANDA_FLOOR))
	check("ilde guclu partiye karalama daha az isler", PublicOpinion.propaganda_damage(6.0) < PublicOpinion.propaganda_damage(1.0))
	check("ilde guclu karalayan daha cok kazanir", PublicOpinion.propaganda_gain(6.0) > PublicOpinion.propaganda_gain(1.0))
	var weak: float = cm.party_strength("ankara", 2)
	cm.organizations = {"ankara": {2: 3}}
	check("il baskanligi ildeki gucu artirir", cm.party_strength("ankara", 2) > weak)

	cm.current_turn_index = 0
	cm.mana[3] = 3
	cm.agenda = {"type": "gundem_social_p", "until": cm.round_number + 1}
	var law_soc: String = cp.law_type("social", 1)
	cm._apply_law(3, law_soc)
	check("yasa hamlesi meclise geldi, 1 mana harcandi",
		gm.phase == gm.Phase.VOTING and gm.proposal_law == law_soc and cm.mana_of(3) == 2, "mana %d" % cm.mana_of(3))
	check("oylama sirasinda tur durur", cm.is_turn_blocked())
	check("yasayi getirenin oyu bastan EVET", int(gm.votes.get(3, 99)) == gm.VOTE_YES and gm.has_voted(3))

	print("")
	print("=== 10) BONUS KARTLAR: POPULIZM, MANA BONUSU ===")
	gm._clear_proposal()
	gm._set_phase(gm.Phase.GOVERNING)
	cm.turn_order = [3, 1, 2]
	cm.current_turn_index = 0
	cm.mana = {1: 10, 2: 10, 3: 10}
	cm.local_support = {}
	cm.national_support = {}
	check("populizm ve mana bonusu destede", cm._draw_weights(3).has("populizm") and cm._draw_weights(3).has("mana_bonusu"))
	cm.inventories[3] = ["populizm", "mana_bonusu"]
	cm._apply_play(3, 0)
	check("populizm 1 mana, 4 tur", cm.mana_of(3) == 9 and cm.populism_rounds_left(3) == GameRules.POPULISM_ROUNDS)
	check("populizmde sira devretmez", cm.current_turn_peer_id() == 3)
	cm._apply_miting(3, "konya")
	var pop_gain: float = cm.local_of("konya", 3)
	check("populizm: iyi etki buyur", pop_gain > PublicOpinion.MITING_LOCAL + 0.001 or near(pop_gain, PublicOpinion.PROVOCATION_LOCAL * PublicOpinion.POPULISM_BAD_MULT),
		"%.2f" % pop_gain)
	cm.local_support = {}
	cm._add_local("konya", 3, -2.0, true)
	check("populizm: kendi hamlesinin kotu etkisi kuculur", near(cm.local_of("konya", 3), -2.0 * PublicOpinion.POPULISM_BAD_MULT))
	cm._add_local("konya", 3, -2.0)
	check("populizm: baskasinin karalamasi etkilenmez", near(cm.local_of("konya", 3), -2.0 * PublicOpinion.POPULISM_BAD_MULT - 2.0))
	cm._apply_play(3, 0)
	check("mana bonusu +5 mana", cm.mana_of(3) == 9 + GameRules.MANA_BONUS_AMOUNT and GameRules.MANA_BONUS_AMOUNT == 5)
	check("mana bonusu sirayi devretmez", cm.current_turn_peer_id() == 3)
	cm.round_number += GameRules.POPULISM_ROUNDS
	check("populizm 5 tur sonra biter", cm.populism_rounds_left(3) == 0)

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
