extends SceneTree
## Kamuoyu, miting/provokasyon, yatırım, yasa oylaması, iktidar yorgunluğu,
## deste ağırlıkları ve sönme kurallarının testi (yerel mod, RPC yok).
## `godot --headless --script res://tools/smoke_test_opinion.gd`

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

func new_game(ideologies: Dictionary) -> void:
	mm.players = {}
	pm.parties = {}
	for peer_id in ideologies.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.3, 0.5, 0.7), "ideology": ideologies[peer_id], "ready": true,
		}
	cm.init_game()
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

func _initialize() -> void:
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	mm.room_code = ""
	mm.axis_sharpness_start = 1.0
	mm.axis_sharpness_increment = 0.0
	mm.election_threshold = 0.0
	cm.set_rng_seed(12345)

	print("=== 1) KAMUOYU SECIMI ETKILER ===")
	var seats = JSON.parse_string(FileAccess.get_file_as_string("res://data/province_seats.json"))
	var voters := ElectionModel.load_province_voters()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var same := {1: ideology(1, 1, 2), 2: ideology(1, 1, 2)}
	var r := ElectionModel.compute(same, seats, voters, 0.0, 1.0, rng, {"national": {1: 8.0}})
	check("ulusal +8 kamuoyu olan, ayni ideolojideki partiden belirgin fazla oy aldi",
		float(r["vote_shares"][1]) > float(r["vote_shares"][2]) + 5.0, str(r["vote_shares"]))
	check("carpan sinirli", near(PublicOpinion.multiplier(100.0, 100.0), PublicOpinion.MAX_MULT) \
		and near(PublicOpinion.multiplier(-100.0, 0.0), PublicOpinion.MIN_MULT))

	print("")
	print("=== 2) PROVOKASYON RISKI ===")
	var konya: Dictionary = voters["konya"]
	check("secmene yakin parti: risk yok", near(PublicOpinion.provocation_risk(ideology(0, 2, 2), konya), 0.0))
	var far_risk := PublicOpinion.provocation_risk(ideology(-3, -3, -3), konya)
	check("zit uc parti: belirgin risk", far_risk > 0.25 and far_risk <= 0.5, "%.2f" % far_risk)
	check("tam zit uclar: risk %50'de durur",
		near(PublicOpinion.provocation_risk(ideology(-3, -3, -3), {"economic": 3, "social": 3, "administrative": 3}), 0.5))
	new_game({1: ideology(3, 3, 3), 2: ideology(-3, -3, -3)})
	pass_round()
	var before: float = cm.miting_risk(2, "konya")
	cm._add_local("konya", 1, 8.0)
	var after: float = cm.miting_risk(2, "konya")
	check("uc sag parti ilde guclenince uc solun riski artar", after > before and after <= 0.5,
		"%.2f -> %.2f" % [before, after])

	print("")
	print("=== 3) MITING ===")
	new_game({1: ideology(0, 2, 2), 2: ideology(0, 2, 2)})
	pass_round()
	check("dengeye yakin partinin riski 0", near(cm.miting_risk(1, "konya"), 0.0), "%.2f" % cm.miting_risk(1, "konya"))
	cm._apply_miting(1, "konya")
	check("basarili miting: il +3", near(cm.local_of("konya", 1), PublicOpinion.MITING_LOCAL))
	check("basarili miting: ulusal +0.5", near(cm.national_of(1), PublicOpinion.MITING_NATIONAL))
	check("ilde olay kaydi var", cm.province_events.get("konya", []).size() == 1)
	new_game({1: ideology(3, 3, 3), 2: ideology(-3, -3, -3)})
	pass_round()
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
	new_game({1: ideology(2, 1, 1), 2: ideology(-2, -1, 1), 3: ideology(1, 1, -1)})
	pass_round()
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	gm.start_formation()
	var coalition := all_posts_to(1)
	coalition[gp.POST_DEPUTY_PM] = 2
	gm._apply_government_proposal(1, coalition)
	gm._apply_vote(1, true)
	gm._apply_vote(2, true)
	check("hukumet (1+2) kuruldu", gm.has_government() and gm.government_party_ids().size() == 2)
	check("muhalefet yatirim oynayamaz", not cm.can_play_card(3, "yatirim", -1, "izmir"))
	check("hukumet partisi oynayabilir", cm.can_play_card(1, "yatirim", -1, "izmir"))
	check("gecersiz il reddedilir", not cm.can_play_card(1, "yatirim", -1, "atlantis"))
	cm._apply_investment(1, "izmir")
	check("getiren parti il +3", near(cm.local_of("izmir", 1), PublicOpinion.INVEST_LOCAL))
	check("ortak il +1.5", near(cm.local_of("izmir", 2), PublicOpinion.INVEST_PARTNER_LOCAL))
	check("muhalefet etkilenmez", near(cm.local_of("izmir", 3), 0.0))
	check("getiren parti ulusal +0.5", near(cm.national_of(1), PublicOpinion.INVEST_NATIONAL))
	var w_gov: Dictionary = cm._draw_weights(1)
	var w_opp: Dictionary = cm._draw_weights(3)
	check("yatirim karti sadece hukumet destesinde", w_gov.has("yatirim") and not w_opp.has("yatirim"))

	print("")
	print("=== 5) YASA OYLAMASI ===")
	cm.national_support = {}
	cm.local_support = {}
	# Ozellestirme (ekonomi +): 1 tabani +2 (EVET bekler), 2 tabani -2 (HAYIR bekler), 3 tabani +1
	check("muhalefet yasa getirebilir", gm.submit_law(3, "law_privatization") and gm.proposal_kind == gm.KIND_LAW)
	check("hukumet partisi 1 EVET onizleme: taban +0.5, muhalefete evet -0.4",
		near(cm.preview_law_vote(1, true), PublicOpinion.LAW_BASE_REWARD + PublicOpinion.GOVERNMENT_YES_ON_OPPOSITION_ALIGNED),
		"%.2f" % cm.preview_law_vote(1, true))
	check("hukumet partisi 2 EVET onizleme: tabana ters -1.6 ve -1.2",
		near(cm.preview_law_vote(2, true), -PublicOpinion.LAW_BASE_PENALTY_PER_POINT * 2 + PublicOpinion.GOVERNMENT_YES_ON_OPPOSITION),
		"%.2f" % cm.preview_law_vote(2, true))
	check("parti 2 HAYIR onizleme: taban +0.5", near(cm.preview_law_vote(2, false), PublicOpinion.LAW_BASE_REWARD))
	gm._apply_vote(3, true)
	gm._apply_vote(2, false)
	check("sonuc kesinlesmeden oylama surer", gm.phase == gm.Phase.VOTING)
	gm._apply_vote(1, true)
	check("yasa gecti, hukumet fazina donuldu", gm.phase == gm.Phase.GOVERNING and gm.last_resolution_reason.find("kabul") != -1,
		gm.last_resolution_reason)
	check("muhalefet getirdi ve gecti: +0.5 taban +3.5 bonus",
		near(cm.national_of(3), PublicOpinion.LAW_BASE_REWARD + PublicOpinion.LAW_PASSED_OPPOSITION), "%.2f" % cm.national_of(3))
	check("hukumet partisi 1: muhalefet yasasina evet (tabani destekliyor) +0.1",
		near(cm.national_of(1), PublicOpinion.LAW_BASE_REWARD + PublicOpinion.GOVERNMENT_YES_ON_OPPOSITION_ALIGNED), "%.2f" % cm.national_of(1))
	check("parti 2: tabanina uygun HAYIR +0.5", near(cm.national_of(2), PublicOpinion.LAW_BASE_REWARD), "%.2f" % cm.national_of(2))

	# Tabana ters oy: yasanin yonune egilimli illerden yeni secmen
	check("tabana ters oyda egilimli ilden yeni secmen",
		PublicOpinion.law_new_voters_local(voters["istanbul"], CardPresets.LAWS["law_privatization"], true) > 0.0)
	cm.national_support = {}
	cm.local_support = {}
	gm.submit_law(1, "law_nationalization")  # ekonomi -: 1 tabani -2
	gm._apply_vote(1, true)   # tabana ters
	gm._apply_vote(2, false)  # tabani +2 (kamulastirma -) -> -2 bekler HAYIR... tabanina uygun
	gm._apply_vote(3, false)
	var pen := -PublicOpinion.LAW_BASE_PENALTY_PER_POINT * 2
	check("yasa (200 EVET vs 190 HAYIR) gecti", gm.last_resolution_reason.find("kabul") != -1, gm.last_resolution_reason)
	check("tabana ters oy veren getirici: -1.6 + hukumet bonusu +1.5",
		near(cm.national_of(1), pen + PublicOpinion.LAW_PASSED_GOVERNMENT), "%.2f" % cm.national_of(1))
	var gained := false
	for province_id in cm.local_support.keys():
		if cm.local_of(province_id, 1) > 0.0:
			gained = true
	check("tabana ters oy veren parti bazi illerde yeni secmen cekti", gained)
	cm.national_support = {}
	gm.submit_law(2, "law_family")  # sosyal +: 2 tabani -1
	# Sıra önemli: sonuç kesinleşince oylama beklemeden kapanır, sonraki oylar sayılmaz.
	gm._apply_vote(2, true)
	gm._apply_vote(3, false)
	gm._apply_vote(1, false)
	check("reddedilen yasanin getiricisi: tabana ters -0.8 ve red -1.0",
		near(cm.national_of(2), -PublicOpinion.LAW_BASE_PENALTY_PER_POINT + PublicOpinion.LAW_REJECTED), "%.2f" % cm.national_of(2))
	check("yasa sadece meclis varken ve kurma asamasi disinda", gm.can_submit_law())

	print("")
	print("=== 6) IKTIDAR YORGUNLUGU ===")
	cm.national_support = {1: 2.0, 3: 1.0}
	var mods: Dictionary = cm.election_modifiers()
	check("hukumet partisi seçime -1.5 ile girer", near(float(mods["national"][1]), 2.0 + PublicOpinion.GOVERNMENT_FATIGUE))
	check("ortak da yorulur", near(float(mods["national"].get(2, 0.0)), PublicOpinion.GOVERNMENT_FATIGUE))
	check("muhalefet yorulmaz", near(float(mods["national"][3]), 1.0))
	check("gercek puan degismedi", near(cm.national_of(1), 2.0))

	print("")
	print("=== 7) GENSORU DESTESI ===")
	check("cogunluk hukumeti: gensoru yok", not cm._draw_weights(3).has("gensoru"))
	cm.last_seats = {1: 100, 2: 50, 3: 240}
	var w3: Dictionary = cm._draw_weights(3)
	var others := 0.0
	for card_type in w3.keys():
		if card_type != "gensoru":
			others += float(w3[card_type])
	check("azinlik hukumeti: muhalefete gensoru cok yuksek olasilikla", w3.has("gensoru") and float(w3["gensoru"]) > others)
	check("hukumet partisine gensoru gelmez", not cm._draw_weights(1).has("gensoru"))
	cm.inventories[3] = ["gensoru"]
	check("elinde gensoru varsa tekrar gelmez", not cm._draw_weights(3).has("gensoru"))
	check("hukumet partisi gensoru oynayamaz", not cm.can_play_card(1, "gensoru"))

	print("")
	print("=== 8) SONME ===")
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	cm.inventories[3] = []
	cm.national_support = {3: 4.0}
	cm.local_support = {"konya": {3: 2.0}}
	var round_before: int = cm.round_number
	cm.current_turn_index = 0
	pass_round()
	check("secimsiz tur gecti", cm.round_number == round_before + 1 and gm.has_government(), "tur %d" % cm.round_number)
	check("ulusal kamuoyu %10 sondu", near(cm.national_of(3), 4.0 * PublicOpinion.NATIONAL_DECAY), "%.3f" % cm.national_of(3))
	check("il kamuoyu %15 sondu", near(cm.local_of("konya", 3), 2.0 * PublicOpinion.LOCAL_DECAY), "%.3f" % cm.local_of("konya", 3))

	print("")
	print("=== 9) KART OYNAMA AKISI ===")
	check("8 gorev (6 bakanlik)", gp.POSTS.size() == 8)
	cm.current_turn_index = cm.turn_order.find(3)
	cm.inventories[3] = ["law_civil_rights", "miting"]
	cm._apply_play(3, 1, -1, "")
	check("il secilmeden miting oynanamaz (kart elde)", cm.inventories[3].size() == 2 and cm.current_turn_peer_id() == 3)
	cm._apply_play(3, 1, -1, "ankara")
	check("ile miting oynandi, sira gecti", cm.inventories[3].size() == 1 and cm.current_turn_peer_id() != 3)
	cm.current_turn_index = cm.turn_order.find(3)
	cm._apply_play(3, 0)
	check("yasa karti meclise geldi", gm.phase == gm.Phase.VOTING and gm.proposal_law == "law_civil_rights")
	check("oylama sirasinda tur durur", cm.is_turn_blocked())

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
