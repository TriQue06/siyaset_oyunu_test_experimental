extends SceneTree
## Güç (aktivite) kuralları: miting/provokasyon, yatırım, yasanın SEÇMEN GRUBU etkileri,
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

## Çekirdek gruplarıyla başlangıç yakınlıkları (boş: nötr).
func groups(core: Array = []) -> Dictionary:
	return VoterGroups.start_affinities(core)

## Bütün gruplarda aynı değer (0 / 100: uç partiler).
func flat(value: float) -> Dictionary:
	var g := {}
	for group in VoterGroups.GROUP_IDS:
		g[group] = value
	return g

## İlin baskın gruplarında 100, karşıtlarında 0 olan parti (ilin "tam uyumlusu").
func matching(profile: Dictionary, invert: bool = false) -> Dictionary:
	var g := {}
	for pair in VoterGroups.PAIR_IDS:
		var pg: Array = VoterGroups.PAIRS[pair]
		var first_leads := VoterGroups.percent(profile, pg[0]) >= 50
		if invert:
			first_leads = not first_leads
		g[pg[0]] = 100.0 if first_leads else 0.0
		g[pg[1]] = 0.0 if first_leads else 100.0
	return g

## Yeni oyun; illerin profilleri deterministik olsun diye örnek veriden alınır.
func new_game(affinities: Dictionary) -> void:
	mm.players = {}
	pm.parties = {}
	for peer_id in affinities.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.3, 0.5, 0.7), "groups": affinities[peer_id].duplicate(), "ready": true,
		}
	cm.init_game()
	cm.province_profiles = voters.duplicate(true)
	cm.turn_order = affinities.keys()
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

## Grubun en yoğun ve en seyrek olduğu iller.
func extreme(group: String, highest: bool) -> String:
	var best := ""
	for province_id in voters.keys():
		var v := VoterGroups.percent(voters[province_id], group)
		if best == "" or (highest and v > VoterGroups.percent(voters[best], group)) or (not highest and v < VoterGroups.percent(voters[best], group)):
			best = province_id
	return best

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	cm.allow_temporary_parties = false
	cm.speech_required = false  # meclis konuşması ayrıca test edilir
	cm.fixed_map_seed = 1950
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	cp = root.get_node("CardPresets")
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	mm.election_threshold = 0.0
	cm.set_rng_seed(12345)
	voters = ElectionModel.load_province_voters()

	print("=== 1) GUC SECIMI ETKILER ===")
	var seats = root.get_node("GameMap").seat_counts()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var same := {1: groups(), 2: groups()}
	var r := ElectionModel.compute(same, seats, voters, 0.0, rng, {"national": {1: 8.0}})
	check("ulusal +8 puanli, ayni grup profilindeki partiden belirgin fazla oy aldi",
		float(r["vote_shares"][1]) > float(r["vote_shares"][2]) + 5.0, str(r["vote_shares"]))
	check("carpan sinirli", near(PublicOpinion.multiplier(100.0, 100.0), PublicOpinion.MAX_MULT) \
		and near(PublicOpinion.multiplier(-100.0, 0.0), PublicOpinion.MIN_MULT))

	print("")
	print("=== 2) PROVOKASYON RISKI ===")
	var konya: Dictionary = voters[TestProvinces.id("konya")]
	check("ile tam uyumlu parti: risk yok", near(PublicOpinion.provocation_risk(VoterGroups.appeal(matching(konya), konya)), 0.0))
	var far_appeal := VoterGroups.appeal(groups(), konya)
	var far_risk := PublicOpinion.provocation_risk(far_appeal)
	check("ildeki hicbir gruba hitap etmeyen parti: en yuksek risk", near(far_risk, PublicOpinion.PROVOCATION_MAX_RISK), "%.2f (uyum %.1f)" % [far_risk, far_appeal])
	check("il baskanligi riski azaltir", PublicOpinion.provocation_risk(far_appeal, 2) < far_risk * 0.6)
	check("risk PROVOCATION_MAX_RISK'te durur", near(PublicOpinion.provocation_risk(-50.0), PublicOpinion.PROVOCATION_MAX_RISK))
	new_game({1: matching(konya), 2: groups()})
	check("cm.miting_risk ildeki uyumu kullanir", cm.miting_risk(2, TestProvinces.id("konya")) > cm.miting_risk(1, TestProvinces.id("konya")))

	print("")
	print("=== 3) MITING ===")
	new_game({1: matching(konya), 2: groups()})
	check("ile hitap eden partinin riski 0", near(cm.miting_risk(1, TestProvinces.id("konya")), 0.0), "%.2f" % cm.miting_risk(1, TestProvinces.id("konya")))
	var g_before: Dictionary = pm.parties[1]["groups"].duplicate()
	cm._apply_miting(1, TestProvinces.id("konya"))
	check("basarili miting: il +MITING_LOCAL", near(cm.local_of(TestProvinces.id("konya"), 1), PublicOpinion.MITING_LOCAL))
	check("basarili miting: genel ulusal puan yazmaz", near(cm.national_of(1), 0.0))
	check("basarili miting: grup yakinligi degisti (ulusal hitap)", str(pm.parties[1]["groups"]) != str(g_before))
	check("ilde olay kaydi var", cm.province_events.get(TestProvinces.id("konya"), []).size() == 1)
	new_game({1: matching(konya), 2: groups()})
	cm._add_local(TestProvinces.id("konya"), 1, 10.0)
	var provoked := 0
	var succeeded := 0
	for i in 40:
		cm.local_support[TestProvinces.id("konya")][2] = 0.0
		cm._apply_miting(2, TestProvinces.id("konya"))
		var value: float = cm.local_of(TestProvinces.id("konya"), 2)
		if near(value, PublicOpinion.PROVOCATION_LOCAL):
			provoked += 1
		elif near(value, PublicOpinion.MITING_LOCAL):
			succeeded += 1
	check("riskli ilde hem provokasyon hem basari gorulur", provoked > 0 and succeeded > 0 and provoked + succeeded == 40,
		"provokasyon %d, basari %d" % [provoked, succeeded])
	check("olay kaydi sinirli", cm.province_events[TestProvinces.id("konya")].size() == cm.PROVINCE_EVENT_LIMIT)

	print("")
	print("=== 4) YATIRIM ===")
	new_game({1: groups(["isci", "dindar"]), 2: groups(["isci", "milliyetci"]), 3: groups(["isveren", "ilerici"])})
	pass_round()
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	gm.start_formation()
	var coalition := all_posts_to(1)
	coalition[gp.POST_DEPUTY_PM] = 2
	gm._apply_government_proposal(1, coalition)
	gm._apply_vote(2, true)
	gm._apply_vote(3, false)
	check("hukumet (1+2) kuruldu", gm.has_government() and gm.government_party_ids().size() == 2)
	cm.funds = {1: 100, 2: 100, 3: 100}
	cm.turn_order = [3, 1, 2]
	cm.current_turn_index = 0
	check("muhalefet yatirim yapamaz", not cm.can_invest(3, TestProvinces.id("izmir")))
	cm.current_turn_index = 1
	check("hukumet partisi yatirim yapabilir", cm.can_invest(1, TestProvinces.id("izmir")))
	check("gecersiz il reddedilir", not cm.can_invest(1, "atlantis"))
	cm.local_support = {}
	cm.national_support = {}
	cm._apply_invest_move(1, TestProvinces.id("izmir"))
	check("yatirim hazineden: parti kasasi degismedi", cm.funds_of(1) == 100)
	check("getiren parti il: etkinin hemen gelen payi", near(cm.local_of(TestProvinces.id("izmir"), 1), float(cm.investment_shares(1)[1]) * Economy.INVEST_IMMEDIATE))
	check("ortak il: hemen gelen pay", near(cm.local_of(TestProvinces.id("izmir"), 2), float(cm.investment_shares(1).get(2, 0.0)) * Economy.INVEST_IMMEDIATE))
	check("muhalefet etkilenmez", near(cm.local_of(TestProvinces.id("izmir"), 3), 0.0))
	var inv_shares: Dictionary = cm.investment_shares(1)
	var inv_sum := 0.0
	for k in inv_shares:
		inv_sum += float(inv_shares[k])
	check("yatirim paylari toplami INVEST_LOCAL", near(inv_sum, PublicOpinion.INVEST_LOCAL))
	var pts1: int = gm.round_points_of(1)
	var pts2: int = gm.round_points_of(2)
	var rest: float = PublicOpinion.INVEST_LOCAL * (1.0 - PublicOpinion.INVEST_OWN_SHARE)
	check("getirene %50 + makam payi", near(float(inv_shares[1]), PublicOpinion.INVEST_LOCAL * PublicOpinion.INVEST_OWN_SHARE + rest * pts1 / float(pts1 + pts2)), "%.2f" % float(inv_shares[1]))
	check("ortaga makam puaniyla orantili pay", near(float(inv_shares.get(2, 0.0)), rest * pts2 / float(pts1 + pts2)), "%.2f" % float(inv_shares.get(2, 0.0)))
	check("ortagin makami var", pts1 > 0 and pts2 > 0, "%d / %d" % [pts1, pts2])
	check("yatirim ayrica ulusal puan yazmaz (ekonomi ivmesi uzerinden)", near(cm.national_of(1), 0.0))
	check("yatirim getirene ildeki gruplardan hitap kazandirir", float(pm.parties[1]["groups"]["isveren"]) > 0.0 		and float(pm.parties[3]["groups"]["isci"]) <= float(groups(["isveren", "ilerici"])["isci"]))
	check("yatirim destede degil (hamle)", not cm._draw_weights(1).has("yatirim"))

	print("")
	print("=== 5) YASA ETKILERI: SECMEN GRUPLARI (ULUSAL) ===")
	cm.national_support = {}
	cm.local_support = {}
	cm.crisis = {}
	var g3: Dictionary = pm.parties[3]["groups"].duplicate()
	var g1: Dictionary = pm.parties[1]["groups"].duplicate()
	var g2: Dictionary = pm.parties[2]["groups"].duplicate()
	var law_emp: String = cp.law_type("isveren")
	check("muhalefet yasa getirebilir", gm.submit_law(3, law_emp) and gm.proposal_kind == gm.KIND_LAW)
	gm._apply_vote(3, gm.VOTE_YES)
	gm._apply_vote(1, gm.VOTE_YES)   # iktidar muhalefetin yasasına EVET
	gm._apply_vote(2, gm.VOTE_NO)
	check("yasa gecti (290 EVET)", gm.phase == gm.Phase.GOVERNING and gm.last_resolution_reason.find("kabul") != -1, gm.last_resolution_reason)
	var d3 := float(pm.parties[3]["groups"]["isveren"]) - float(g3["isveren"])
	var d3o := float(pm.parties[3]["groups"]["isci"]) - float(g3["isci"])
	check("getiren: hedef grupta guclu artis (kabul)", d3 > PublicOpinion.LAW_GROUP_GAIN_PASSED * 0.5, "%.2f" % d3)
	check("getiren: karsit grupta kazanc yok (%0'in altina inmez)", d3o <= 0.0 and float(pm.parties[3]["groups"]["isci"]) >= 0.0, "%.2f" % d3o)
	check("iktidar muhalefete EVET: hedef gruba biraz yaklasir ama ulusal kaybeder",
		float(pm.parties[1]["groups"]["isveren"]) > float(g1["isveren"]) and near(cm.national_of(1), PublicOpinion.LAW_GOV_YES_ON_OPPOSITION))
	check("HAYIR: karsit gruba yaklasir", float(pm.parties[2]["groups"]["isci"]) > float(g2["isci"]) \
		and float(pm.parties[2]["groups"]["isveren"]) <= float(g2["isveren"]))
	check("yasa il aktivitesine yazmaz (ayni etki iki kez sayilmaz)", cm.local_support.is_empty(), str(cm.local_support))
	var high_emp := extreme("isveren", true)
	var low_emp := extreme("isveren", false)
	check("yasanin oy etkisi grubun yogun oldugu ilde daha buyuk",
		VoterGroups.appeal(pm.parties[3]["groups"], voters[high_emp]) - VoterGroups.appeal(g3, voters[high_emp]) \
		> VoterGroups.appeal(pm.parties[3]["groups"], voters[low_emp]) - VoterGroups.appeal(g3, voters[low_emp]))

	var g2b: Dictionary = pm.parties[2]["groups"].duplicate()
	var g3b: Dictionary = pm.parties[3]["groups"].duplicate()
	gm.submit_law(1, cp.law_type("ilerici"))
	gm._apply_vote(1, gm.VOTE_YES)
	gm._apply_vote(2, gm.VOTE_ABSTAIN)
	gm._apply_vote(3, gm.VOTE_YES)   # muhalefet iktidarın yasasına EVET: ceza yok
	check("muhalefet iktidara EVET: hedef gruba yaklasir, ulusal ceza yok", float(pm.parties[3]["groups"]["ilerici"]) > float(g3b["ilerici"]) \
		and near(cm.national_of(3), 0.0))
	check("cekimser etkilenmez", str(pm.parties[2]["groups"]) == str(g2b))

	var g2c: Dictionary = pm.parties[2]["groups"].duplicate()
	gm.submit_law(2, cp.law_type("milliyetci"))
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(1, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_NO)
	check("yasa reddedildi", gm.last_resolution_reason.find("reddedildi") != -1, gm.last_resolution_reason)
	var d2 := float(pm.parties[2]["groups"]["milliyetci"]) - float(g2c["milliyetci"])
	check("reddedilen yasanin getiricisi kucuk (vaat) kazanc",
		d2 > 0.0 and d2 <= PublicOpinion.LAW_GROUP_GAIN_REJECTED + 0.001, "%.2f" % d2)
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
	cm.organizations = {TestProvinces.id("konya"): {3: 2}}
	cm.local_support = {}
	mods = cm.election_modifiers()
	check("vekil calmanin secim momentumu kaldirildi", near(float(mods["national"][3]), 1.0),
		"%.2f" % float(mods["national"][3]))
	check("calma bedeli ulusal puana anlik ama cok kucuk yazilir", near(PublicOpinion.steal_thief_national(10), -0.08) and near(PublicOpinion.steal_victim_national(10), 0.12))
	check("il baskanligi il carpanina girer", near(float(mods["local"][TestProvinces.id("konya")][3]), PublicOpinion.org_activity(2)))
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	cm.election_seats = {}
	cm.organizations = {}

	print("")
	print("=== 7) GENSORU HAMLESI ===")
	cm.funds = {1: 100, 2: 100, 3: 100}
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
	check("gensoru hamlesi bedeli, oylama acildi", cm.funds_of(3) == 100 - GameRules.CENSURE_FUNDS_COST and gm.phase == gm.Phase.VOTING)
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
	cm.local_support = {TestProvinces.id("konya"): {3: 2.0}}
	cm.organizations = {TestProvinces.id("konya"): {3: 1}}
	var round_before: int = cm.round_number
	cm.current_turn_index = 0
	pass_round()
	check("secimsiz tur gecti", cm.round_number == round_before + 1 and gm.has_government(), "tur %d" % cm.round_number)
	check("ulusal puan %10 sondu", near(cm.national_of(3), 4.0 * PublicOpinion.NATIONAL_DECAY), "%.3f" % cm.national_of(3))
	check("il puani %15 sondu", near(cm.local_of(TestProvinces.id("konya"), 3), 2.0 * PublicOpinion.LOCAL_DECAY), "%.3f" % cm.local_of(TestProvinces.id("konya"), 3))
	check("teskilat sonmedi", near(cm.activity_of(TestProvinces.id("konya"), 3), 2.0 * PublicOpinion.LOCAL_DECAY + PublicOpinion.org_activity(1)))

	print("")
	print("=== 9) TESKILAT BILGISI, KARALAMA ===")
	var w: Dictionary = cm._draw_weights(3)
	check("karalama destede; anket ve gozcu destede degil", not w.has("anket") and not w.has("gozcu") and w.has("karalama"))
	cm.funds[3] = 50
	cm.organizations = {}
	cm.local_support = {}
	cm.turn_order = [3, 1, 2]
	cm.current_turn_index = 0
	cm.inventories[3] = ["karalama"]
	cm._apply_play(3, 0, -1, "")
	check("il secilmeden karalama oynanamaz (kart elde)", cm.inventories[3].size() == 1 and cm.current_turn_peer_id() == 3)
	cm._apply_organization(3, TestProvinces.id("ankara"))
	check("teskilat: anket (sadece kurana)", not cm.province_poll(3, TestProvinces.id("ankara")).is_empty() and cm.province_poll(1, TestProvinces.id("ankara")).is_empty())
	# Karalama artık teşkilat ister; 3 numaranın Ankara teşkilatı dursun.
	cm.organizations = {TestProvinces.id("ankara"): {3: 1}}
	check("teskilatsiz ilde karalama oynanamaz", not cm.can_play_card(3, "karalama", 1, TestProvinces.id("izmir")))
	check("karalama kendine oynanamaz", not cm.can_play_card(3, "karalama", 3, TestProvinces.id("ankara")))
	check("karalama gecersiz partiye oynanamaz", not cm.can_play_card(3, "karalama", 99, TestProvinces.id("ankara")))
	cm.current_turn_index = 0
	var damage: float = minf(PublicOpinion.propaganda_damage(cm.party_strength(TestProvinces.id("ankara"), 1)), -PublicOpinion.PROPAGANDA_FLOOR)
	cm._apply_play(3, 0, 1, TestProvinces.id("ankara"))
	check("karalama: hedefe eksi, yapana arti", near(cm.local_of(TestProvinces.id("ankara"), 1), -damage) and cm.local_of(TestProvinces.id("ankara"), 3) > 0.0,
		"hedef %.2f, yapan %.2f" % [cm.local_of(TestProvinces.id("ankara"), 1), cm.local_of(TestProvinces.id("ankara"), 3)])
	cm.local_support[TestProvinces.id("ankara")][1] = -2.5
	cm.inventories[3] = ["karalama"]
	cm.current_turn_index = 0
	cm._apply_play(3, 0, 1, TestProvinces.id("ankara"))
	check("karalama il puanini tabanin altina itemez", near(cm.local_of(TestProvinces.id("ankara"), 1), PublicOpinion.PROPAGANDA_FLOOR),
		"%.2f" % cm.local_of(TestProvinces.id("ankara"), 1))
	cm.inventories[3] = ["karalama"]
	cm.current_turn_index = 0
	cm._apply_play(3, 0, 1, TestProvinces.id("ankara"))
	check("tabandaki partiye karalama artik eksi yazmaz", near(cm.local_of(TestProvinces.id("ankara"), 1), PublicOpinion.PROPAGANDA_FLOOR))
	check("ilde guclu partiye karalama daha az isler", PublicOpinion.propaganda_damage(6.0) < PublicOpinion.propaganda_damage(1.0))
	check("ilde guclu karalayan daha cok kazanir", PublicOpinion.propaganda_gain(6.0) > PublicOpinion.propaganda_gain(1.0))
	var weak: float = cm.party_strength(TestProvinces.id("ankara"), 2)
	cm.organizations = {TestProvinces.id("ankara"): {2: GameRules.ORG_MAX_LEVEL}}
	check("il baskanligi ildeki gucu artirir", cm.party_strength(TestProvinces.id("ankara"), 2) > weak)

	cm.current_turn_index = 0
	cm.funds[3] = 30
	cm.agenda = {"type": "gundem_dindar", "until": cm.round_number + 1}
	var law_soc: String = cp.law_type("dindar")
	cm._apply_law(3, law_soc)
	check("yasa hamlesi meclise geldi, 5 milyon harcandi",
		gm.phase == gm.Phase.VOTING and gm.proposal_law == law_soc and cm.funds_of(3) == 30 - GameRules.LAW_FUNDS_COST, "kasa %d" % cm.funds_of(3))
	check("oylama sirasinda tur durur", cm.is_turn_blocked())
	check("yasayi getirenin oyu bastan EVET", int(gm.votes.get(3, 99)) == gm.VOTE_YES and gm.has_voted(3))

	print("")
	print("=== 10) BONUS KARTLAR: POPULIZM, BAGIS KAMPANYASI ===")
	gm._clear_proposal()
	gm._set_phase(gm.Phase.GOVERNING)
	cm.turn_order = [3, 1, 2]
	cm.current_turn_index = 0
	cm.funds = {1: 100, 2: 100, 3: 100}
	cm.local_support = {}
	cm.national_support = {}
	check("populizm ve bagis kampanyasi destede", cm._draw_weights(3).has("populizm") and cm._draw_weights(3).has("bagis_kampanyasi"))
	cm.inventories[3] = ["populizm", "bagis_kampanyasi"]
	cm._apply_play(3, 0)
	check("populizm 10 milyon, 3 yil", cm.funds_of(3) == 90 and cm.populism_rounds_left(3) == GameRules.POPULISM_ROUNDS)
	check("populizmde sira devretmez", cm.current_turn_peer_id() == 3)
	cm._apply_miting(3, TestProvinces.id("konya"))
	var pop_gain: float = cm.local_of(TestProvinces.id("konya"), 3)
	check("populizm: iyi etki buyur", pop_gain > PublicOpinion.MITING_LOCAL + 0.001 or near(pop_gain, PublicOpinion.PROVOCATION_LOCAL * PublicOpinion.POPULISM_BAD_MULT),
		"%.2f" % pop_gain)
	cm.local_support = {}
	cm._add_local(TestProvinces.id("konya"), 3, -2.0, true)
	check("populizm: kendi hamlesinin kotu etkisi kuculur", near(cm.local_of(TestProvinces.id("konya"), 3), -2.0 * PublicOpinion.POPULISM_BAD_MULT))
	cm._add_local(TestProvinces.id("konya"), 3, -2.0)
	check("populizm: baskasinin karalamasi etkilenmez", near(cm.local_of(TestProvinces.id("konya"), 3), -2.0 * PublicOpinion.POPULISM_BAD_MULT - 2.0))
	cm._apply_play(3, 0)
	check("bagis kampanyasi (zayif) +30 milyon", cm.funds_of(3) == 90 + GameRules.FUNDS_BONUS_WEAK and GameRules.FUNDS_BONUS_WEAK == 30)
	check("bagis kampanyasi sirayi devretmez", cm.current_turn_peer_id() == 3)
	cm.round_number += GameRules.POPULISM_ROUNDS
	check("populizm 5 tur sonra biter", cm.populism_rounds_left(3) == 0)

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
