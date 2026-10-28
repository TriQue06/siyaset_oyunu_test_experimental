extends SceneTree
## OY = SEÇMEN kuralları (0.0.284): puanın seçmene çevrilmesi, miting/provokasyon,
## yatırım, yasanın SEÇMEN GRUBU etkileri, gensoru, teşkilat, karalama, popülizm,
## deste ağırlıkları ve etkilerin kalıcılığı (yerel mod, RPC yok).
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
	# Eski serbest akış: bu test mekanikleri sınar (tur akışı: smoke_test_turn_flow).
	cm.enforce_turn_flow = false
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	cp = root.get_node("CardPresets")
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	mm.election_threshold = 0.0
	cm.set_rng_seed(12345)
	voters = ElectionModel.load_province_voters()

	print("=== 1) PUAN = SECMEN ===")
	var konya_id := TestProvinces.id("konya")
	new_game({1: groups(), 2: groups()})
	var v1: float = cm.voter_total(1)
	var share_before: float = float(cm._expected_national().get(1, 0.0))
	cm._add_national(1, 8.0)
	check("ulke geneli +8: kararsizlardan secmen kazanir", cm.voter_total(1) > v1, "%.0f -> %.0f" % [v1, cm.voter_total(1)])
	cm._national_cache = {}
	check("ayni profildeki rakipten fazla oy alir", float(cm._expected_national().get(1, 0.0)) > float(cm._expected_national().get(2, 0.0)) and float(cm._expected_national().get(1, 0.0)) > share_before)
	v1 = cm.voter_total(1)
	cm._add_national(1, -1.0)
	check("ulke geneli -1: kendi secmeninin VOTER_LOSS'u kararsiza doner", absf(cm.voter_total(1) - v1 * (1.0 - PublicOpinion.VOTER_LOSS)) < v1 * 0.0001,
		"%.0f -> %.0f" % [v1, cm.voter_total(1)])
	var here: float = cm.voter_total(1, konya_id)
	var other_id := TestProvinces.id("izmir")
	var there: float = cm.voter_total(1, other_id)
	cm._add_local(konya_id, 1, -2.0)
	check("il etkisi yalniz o ilde", cm.voter_total(1, konya_id) < here and near(cm.voter_total(1, other_id), there))

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
	var mv: float = cm.voter_total(1, konya_id)
	cm._apply_miting(1, TestProvinces.id("konya"))
	check("basarili miting: ilde secmen kazanir", cm.voter_total(1, konya_id) > mv)
	check("basarili miting: grup yakinligi degisti (ulusal hitap)", str(pm.parties[1]["groups"]) != str(g_before))
	check("ilde olay kaydi var", cm.province_events.get(TestProvinces.id("konya"), []).size() == 1)
	new_game({1: matching(konya), 2: groups()})
	var provoked := 0
	var succeeded := 0
	for i in 40:
		var before: float = cm.voter_total(2, konya_id)
		cm._apply_miting(2, TestProvinces.id("konya"))
		if cm.voter_total(2, konya_id) < before:
			provoked += 1
		else:
			succeeded += 1
	check("riskli ilde hem provokasyon hem basari gorulur", provoked > 0 and succeeded > 0,
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
	var izmir := TestProvinces.id("izmir")
	var iv1: float = cm.voter_total(1, izmir)
	var iv2: float = cm.voter_total(2, izmir)
	var iv3: float = cm.voter_total(3, izmir)
	var iv_else: float = cm.voter_total(1, konya_id)
	cm._apply_invest_move(1, izmir)
	check("yatirim hazineden: parti kasasi degismedi", cm.funds_of(1) == 100)
	check("getiren parti ilde secmen kazanir", cm.voter_total(1, izmir) > iv1)
	check("ortagin da sonraki dilimlerde payi var", cm.pending_investments(2).size() == 1 and iv2 >= 0.0)
	check("muhalefet kazanmaz", cm.voter_total(3, izmir) <= iv3 + 0.001)
	var inv_shares: Dictionary = cm.investment_shares(1)
	var inv_sum := 0.0
	for k in inv_shares:
		inv_sum += float(inv_shares[k])
	check("yatirim paylari toplami 1", near(inv_sum, 1.0))
	var pts1: int = gm.round_points_of(1)
	var pts2: int = gm.round_points_of(2)
	var rest: float = 1.0 - PublicOpinion.INVEST_OWN_SHARE
	check("getirene %50 + makam payi", near(float(inv_shares[1]), PublicOpinion.INVEST_OWN_SHARE + rest * pts1 / float(pts1 + pts2)), "%.2f" % float(inv_shares[1]))
	check("ortaga makam puaniyla orantili pay", near(float(inv_shares.get(2, 0.0)), rest * pts2 / float(pts1 + pts2)), "%.2f" % float(inv_shares.get(2, 0.0)))
	check("ortagin makami var", pts1 > 0 and pts2 > 0, "%d / %d" % [pts1, pts2])
	check("yatirim baska ile secmen yazmaz", near(cm.voter_total(1, konya_id), iv_else))
	check("yatirim getirene ildeki gruplardan hitap kazandirir", float(pm.parties[1]["groups"]["isveren"]) > 0.0 		and float(pm.parties[3]["groups"]["isci"]) <= float(groups(["isveren", "ilerici"])["isci"]))
	check("yatirim destede degil (hamle)", not cm._draw_weights(1).has("yatirim"))

	print("")
	print("=== 5) YASA ETKILERI: SECMEN GRUPLARI (ULUSAL) ===")
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
	check("iktidar muhalefete EVET: hedef gruba biraz yaklasir ama ilgisiz gruplarda secmen kaybeder",
		float(pm.parties[1]["groups"]["isveren"]) > float(g1["isveren"]) and float(pm.parties[1]["groups"]["genc"]) < float(g1["genc"]))
	check("HAYIR: karsit gruba yaklasir", float(pm.parties[2]["groups"]["isci"]) > float(g2["isci"]) \
		and float(pm.parties[2]["groups"]["isveren"]) <= float(g2["isveren"]))
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
	# 0.0.228: seçmen tabanı — EVET veren de grubun seçmeninden çeker; getiren
	# daha çok çektiği için çekimserin seçmeninden de alabilir (çalma).
	var gain3 := float(pm.parties[3]["groups"]["ilerici"]) - float(g3b["ilerici"])
	var gain2 := float(pm.parties[2]["groups"]["ilerici"]) - float(g2b["ilerici"])
	# Getiren parti grubun seçmeninden çok daha fazla çektiği için EVET verenin
	# net payı düşebilir; burada yalnız ulusal cezanın olmadığı sınanır.
	check("muhalefet iktidara EVET: ilgisiz gruplarda kayip yok", near(float(pm.parties[3]["groups"]["genc"]), float(g3b["genc"])), "EVET %.3f / cekimser %.3f" % [gain3, gain2])
	check("cekimser hedef grupta kazanmaz", gain2 <= 0.0001, "%.3f" % gain2)

	var g2c: Dictionary = pm.parties[2]["groups"].duplicate()
	gm.submit_law(2, cp.law_type("milliyetci"))
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(1, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_NO)
	check("yasa reddedildi", gm.last_resolution_reason.find("reddedildi") != -1, gm.last_resolution_reason)
	var d2 := float(pm.parties[2]["groups"]["milliyetci"]) - float(g2c["milliyetci"])
	# 0.0.228: kazanç seçmen olarak (grubun %'si); reddedilen yasa geçene göre küçük.
	check("reddedilen yasanin getiricisi kucuk (vaat) kazanc",
		d2 > 0.0 and d2 <= PublicOpinion.LAW_GROUP_GAIN_REJECTED * cm.NATIONAL_PULL_MULT + 0.001, "%.2f" % d2)
	check("yasa sadece meclis varken ve kurma asamasi disinda", gm.can_submit_law())

	print("")
	print("=== 6) VEKIL CALMA BEDELI ===")
	check("calma bedeli kucuk", near(PublicOpinion.steal_thief_national(10), -0.08) and near(PublicOpinion.steal_victim_national(10), 0.12))

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
	var cv3: float = cm.voter_total(3)
	cm._apply_censure_move(3)
	check("gensoru hamlesi bedeli, oylama acildi", cm.funds_of(3) == 100 - GameRules.CENSURE_FUNDS_COST and gm.phase == gm.Phase.VOTING)
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	var score3_before: int = gm.score_of(3)
	gm._apply_vote(3, gm.VOTE_YES)
	gm._apply_vote(1, gm.VOTE_NO)
	gm._apply_vote(2, gm.VOTE_NO)
	check("reddedilen gensoru: hukumet gorevde", gm.has_government() and gm.phase == gm.Phase.GOVERNING, gm.last_resolution_reason)
	check("reddedilen gensoruyu veren secmen kaybeder", cm.voter_total(3) < cv3, "%.0f -> %.0f" % [cv3, cm.voter_total(3)])
	check("puan tablosu etkilenmez", gm.score_of(3) == score3_before, str(gm.score_of(3)))

	print("")
	print("=== 8) ETKILER KALICI (SONME YOK) ===")
	cm.last_seats = {1: 200, 2: 100, 3: 90}
	cm.inventories[3] = []
	cm._add_national(3, 2.0)
	cm.economy["investments"] = []  # bekleyen yatırım dilimleri muhalefetten seçmen çeker
	cm.invest_requests = {}
	var kv3: float = cm.voter_total(3)
	var round_before: int = cm.round_number
	cm.current_turn_index = 0
	pass_round()
	check("secimsiz tur gecti", cm.round_number == round_before + 1 and gm.has_government(), "tur %d" % cm.round_number)
	check("muhalefetin secmeni tur sonunda sonmez", near(cm.voter_total(3), kv3), "%.0f -> %.0f" % [kv3, cm.voter_total(3)])

	print("")
	print("=== 9) TESKILAT BILGISI, KARALAMA ===")
	var w: Dictionary = cm._draw_weights(3)
	# 0.0.272: anket kartı yeniden destede (ilk tur ve seçim sonrası ilk tur hariç).
	var poll_ok: bool = w.has("anket") == (cm.round_number > 1 and cm.round_number != cm.last_election_round + 1)
	check("karalama destede; gozcu degil; anket kurala gore", poll_ok and not w.has("gozcu") and w.has("karalama"))
	cm.funds[3] = 50
	cm.organizations = {}
	cm.turn_order = [3, 1, 2]
	cm.current_turn_index = 0
	cm.inventories[3] = ["karalama"]
	cm._apply_play(3, 0, -1, "")
	check("il secilmeden karalama oynanamaz (kart elde)", cm.inventories[3].size() == 1 and cm.current_turn_peer_id() == 3)
	var ank := TestProvinces.id("ankara")
	var org_before: float = cm.voter_total(3, ank)
	cm._apply_organization(3, TestProvinces.id("ankara"))
	check("teskilat kurulunca ilde secmen kazanilir", cm.voter_total(3, ank) > org_before)
	check("teskilat: anket (sadece kurana)", not cm.province_poll(3, TestProvinces.id("ankara")).is_empty() and cm.province_poll(1, TestProvinces.id("ankara")).is_empty())
	# Karalama artık teşkilat ister; 3 numaranın Ankara teşkilatı dursun.
	cm.organizations = {TestProvinces.id("ankara"): {3: 1}}
	# 0.0.237: karalama yine tek başına oynanır (il + parti).
	check("karalama karti teskilatli ilde rakibe oynanir", cm.can_play_card(3, "karalama", 1, TestProvinces.id("ankara")))
	check("karalama karti teskilatsiz ilde oynanamaz", not cm.can_play_card(3, "karalama", 1, TestProvinces.id("izmir")))
	check("teskilatsiz ilde karalama yapilamaz", not cm.can_smear(3, 1, TestProvinces.id("izmir")))
	check("karalama kendine yapilamaz", not cm.can_smear(3, 3, TestProvinces.id("ankara")))
	check("karalama gecersiz partiye yapilamaz", not cm.can_smear(3, 99, TestProvinces.id("ankara")))
	check("kart eldeyken teskilatli ilde karalama yapilabilir", cm.can_smear(3, 1, TestProvinces.id("ankara")))
	cm.current_turn_index = 0
	var tv1: float = cm.voter_total(1, ank)
	var tv3: float = cm.voter_total(3, ank)
	cm._apply_propaganda(3, 1, TestProvinces.id("ankara"))
	check("karalama: hedef ilde secmen kaybeder, yapan kazanir", cm.voter_total(1, ank) < tv1 and cm.voter_total(3, ank) > tv3,
		"hedef %.0f -> %.0f, yapan %.0f -> %.0f" % [tv1, cm.voter_total(1, ank), tv3, cm.voter_total(3, ank)])
	var tv1b: float = cm.voter_total(1, ank)
	cm.current_turn_index = 0
	cm._apply_propaganda(3, 1, TestProvinces.id("ankara"))
	check("ikinci karalama da yalniz bir kismini goturur (ucurum yok)", cm.voter_total(1, ank) < tv1b and cm.voter_total(1, ank) > tv1b * 0.5)

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
	check("populizm ve bagis kampanyasi destede", cm._draw_weights(3).has("populizm") and cm._draw_weights(3).has("bagis_kampanyasi"))
	cm.inventories[3] = ["populizm", "bagis_kampanyasi"]
	cm._apply_play(3, 0)
	# 0.0.231: popülizm anında kart, oynama bedeli yok (eski kayıttan elde kalan da bedelsiz).
	check("populizm bedelsiz, 3 yil", cm.funds_of(3) == 100 and cm.populism_rounds_left(3) == GameRules.POPULISM_ROUNDS)
	check("populizmde sira devretmez", cm.current_turn_peer_id() == 3)
	var pv: float = cm.voter_total(3)
	cm._add_national(3, -2.0, true)
	check("populizm: kendi hamlesinin kotu etkisi kuculur", absf(cm.voter_total(3) - pv * (1.0 - 2.0 * PublicOpinion.POPULISM_BAD_MULT * PublicOpinion.VOTER_LOSS)) < pv * 0.0001)
	pv = cm.voter_total(3)
	cm._add_national(3, -2.0)
	check("populizm: baskasinin etkisi kuculmez", absf(cm.voter_total(3) - pv * (1.0 - 2.0 * PublicOpinion.VOTER_LOSS)) < pv * 0.0001)
	cm._apply_play(3, 0)
	check("bagis kampanyasi (zayif) +30 milyon", cm.funds_of(3) == 100 + GameRules.FUNDS_BONUS_WEAK and GameRules.FUNDS_BONUS_WEAK == 30)
	check("bagis kampanyasi sirayi devretmez", cm.current_turn_peer_id() == 3)
	cm.round_number += GameRules.POPULISM_ROUNDS
	check("populizm 5 tur sonra biter", cm.populism_rounds_left(3) == 0)

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
