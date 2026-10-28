extends SceneTree
## EKONOMİ ve VERGİ testleri (yerel mod, RPC yok): yüksek vergiyle hazine
## birikmesi, her sırada hükümete yazılan vergi etkisi (döngü çarpanı, bakanlık
## payı), hazineden yatırım (tek sefer harcama, dilimler), çift sayım olmaması,
## durum kaydı/yükleme (eski sürüm dahil), botların aynı kurallarla vergi ve
## yatırım kararları. 0.0.259: ekonomi göstergeleri ve kademeli baskı yok.
##   godot --headless --path . --script res://tools/smoke_test_economy.gd

var mm
var pm
var cm
var gm
var cp
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) < eps

## 1 başbakan, 2 ortak, 3 muhalefet; hükümet çoğunlukta.
func new_game() -> void:
	mm.players = {}
	pm.parties = {}
	var cores := {1: ["isveren", "dindar"], 2: ["isci", "milliyetci"], 3: ["genc", "ilerici"]}
	for peer_id in cores.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.3, 0.5, 0.7), "groups": VoterGroups.start_affinities(cores[peer_id]), "ready": true,
		}
	cm.init_game()
	cm.turn_order = [1, 2, 3]
	cm.current_turn_index = 0
	cm.last_seats = {1: 250, 2: 100, 3: 150}
	cm.election_seats = cm.last_seats.duplicate()
	gm.government = {"pm": 1, "deputy_pm": 2}
	gm.main_gov_peer_id = 1
	gm._set_phase(gm.Phase.GOVERNING)
	cm.funds = {1: 500.0, 2: 500.0, 3: 500.0}
	cm.agenda = {}
	cm.crisis = {}

func give_turn(peer_id: int) -> void:
	cm.current_turn_index = cm.turn_order.find(peer_id)
	cm.law_rounds.erase(cm.party_of(peer_id))

## Vergi yasası: 1 sunar, 2 ve 3 oy verir (sonuç anında).
func pass_tax(level: int, partner_vote: int = 1, opposition_vote: int = -1) -> bool:
	give_turn(1)
	var before: int = cm.tax_level()
	cm._apply_law(1, cp.tax_law_type(level))
	if not gm.is_voting():
		return false
	gm._apply_vote(2, partner_vote)
	gm._apply_vote(3, opposition_vote)
	return cm.tax_level() == level and before != level

## Tur sonu (seçimsiz): seçim takvimi uzak.
func end_round() -> void:
	cm._finish_round()

## Seçim hesabının (ElectionModel.compute, _hold_election ile aynı girdiler)
## aynı tohumla verdiği oy payı.
func election_share(pid: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var result := ElectionModel.compute(cm._group_profiles(), cm._province_seat_counts, cm.province_voters(),
		0.0, rng, {}, cm.vb_election_state())
	return float(result["vote_shares"].get(pid, 0.0))

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	# Eski serbest akış: bu test ekonomi mekaniklerini sınar (tur akışı: smoke_test_turn_flow).
	cm.enforce_turn_flow = false
	gm = root.get_node("GovernmentManager")
	cp = root.get_node("CardPresets")
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	# Seçimler 8 yılda bir: testteki turlar seçimsiz geçer (seçim elle denenir).
	GameRules.configure(8, 12)

	print("=== 0) VERGİ YASASI KURALLARI ===")
	new_game()
	check("oyun normal vergiyle ve başlangıç hazinesiyle başlar", cm.tax_level() == Economy.TAX_NORMAL
		and near(cm.state_treasury(), Economy.START_TREASURY))
	check("vergi yasası bir yasa (meclis akışı)", cp.is_law_card(cp.tax_law_type(Economy.TAX_HIGH))
		and cp.law_data(cp.tax_law_type(Economy.TAX_HIGH)).is_empty())
	give_turn(1)
	check("hükümet partisi gündem olmadan vergi yasası sunabilir", cm.agenda_type() == "" and cm.can_propose_tax_law(1, Economy.TAX_HIGH))
	check("aynı kademeye yasa sunulamaz", not cm.can_propose_tax_law(1, Economy.TAX_NORMAL))
	check("yasa hakkı boşken yasa butonu açık", cm.can_propose_law(1))
	give_turn(3)
	check("muhalefet vergi yasası sunamaz", not cm.can_propose_tax_law(3, Economy.TAX_LOW)
		and cm.tax_law_block_reason(3, Economy.TAX_LOW).contains("hükümet"))
	gm.government = {}
	gm.main_gov_peer_id = -1
	give_turn(1)
	check("hükümet yokken kimse vergi değiştiremez", not cm.can_propose_tax_law(1, Economy.TAX_HIGH))
	new_game()
	var rejected := pass_tax(Economy.TAX_HIGH, -1, -1)
	check("reddedilen vergi yasası kademeyi değiştirmez", not rejected and cm.tax_level() == Economy.TAX_NORMAL)
	check("reddedilen yasa yine de dönemin yasa hakkını kullanır", cm.has_proposed_law_this_round(1)
		and not cm.can_propose_tax_law(1, Economy.TAX_HIGH))

	print("")
	print("=== 1) YÜKSEK VERGİ: HAZİNE BİRİKİR ===")
	new_game()
	var groups_before := str(pm.parties[1]["groups"])
	var voters_before: float = cm.voter_total(1)
	check("vergi artırımı kabul edildi", pass_tax(Economy.TAX_HIGH))
	check("vergi yasası kalıcı grup yakınlığına yazmaz", str(pm.parties[1]["groups"]) == groups_before)
	check("vergi yasası kabul anında seçmene yazmaz", near(cm.voter_total(1), voters_before))
	check("grup değerine ekonomi katmanı eklenmez", str(cm.effective_groups(1)) == str(cm.effective_groups(1))
		and not cm.has_method("economy_mood") and not cm.has_method("economy_index"))
	var treasury0: float = cm.state_treasury()
	var revenues: Array = []
	for i in 4:
		var expected: float = cm.expected_revenue()
		end_round()
		revenues.append(float(cm.economy["revenue"]))
		check("tur %d: gelir hazineye bir kez girdi" % (i + 1), near(float(cm.economy["revenue"]), expected, 0.01))
	var gained: float = cm.state_treasury() - treasury0
	check("4 tur yüksek vergi: hazine birikti", gained > 4.0 * Economy.TAX_REVENUE[Economy.TAX_NORMAL] * 0.9, "+%.0f" % gained)
	check("yüksek vergi geliri normalden fazla", float(revenues[0]) > Economy.revenue(Economy.TAX_NORMAL))
	check("gelir sabit (ekonomi göstergesi yok)", near(float(revenues[0]), float(revenues[3])))

	print("")
	print("=== 2) VERGİ ETKİSİ: HER SIRADA, SEÇİME YAKLAŞTIKÇA ARTAR ===")
	GameRules.configure(2, 12)
	new_game()
	var interval: int = GameRules.ELECTION_INTERVAL
	check("seçim döngüsü 4 tur", interval == 4, str(interval))
	var mults: Array = []
	for r in range(1, interval + 1):
		cm.round_number = r
		mults.append(cm.tax_cycle_mult())
	check("1. tur ×1 … son tur ×%d" % interval, str(mults) == str(range(1, interval + 1)), str(mults))
	cm.round_number = interval + 1
	check("seçimden sonraki tur yine ×1", cm.tax_cycle_mult() == 1, str(cm.tax_cycle_mult()))
	cm.round_number = 2
	check("normal vergi seçmeni etkilemez", near(cm.tax_turn_effect(Economy.TAX_NORMAL), 0.0))
	check("düşük vergi artı, yüksek vergi eksi", cm.tax_turn_effect(Economy.TAX_LOW) > 0.0 and cm.tax_turn_effect(Economy.TAX_HIGH) < 0.0)
	check("2. turda etki 2 kat", near(cm.tax_turn_effect(Economy.TAX_HIGH), 2.0 * Economy.TAX_TURN_NATIONAL[Economy.TAX_HIGH]))
	cm.economy["tax"] = Economy.TAX_HIGH
	var b1: float = cm.voter_total(1)
	var b2: float = cm.voter_total(2)
	var b3: float = cm.voter_total(3)
	cm._apply_tax_tick()
	var total_tick: float = cm.tax_turn_effect()
	var lost1: float = (b1 - cm.voter_total(1)) / b1
	var lost2: float = (b2 - cm.voter_total(2)) / b2
	check("yüksek vergi: hükümet partileri seçmen kaybeder", lost1 > 0.0 and lost2 > 0.0, "%.4f / %.4f" % [lost1, lost2])
	check("muhalefet etkilenmez", near(cm.voter_total(3), b3))
	check("kayıp bakanlık payına göre bölünür", near(lost1, -total_tick * cm.quota_share(1) * PublicOpinion.VOTER_LOSS, 0.0005)
		and near(lost2, -total_tick * cm.quota_share(2) * PublicOpinion.VOTER_LOSS, 0.0005), "%.4f / %.4f" % [lost1, lost2])
	var after_one: float = cm.voter_total(1)
	cm._apply_tax_tick()
	check("her sırada tekrar yazılır (birikir)", cm.voter_total(1) < after_one)
	cm.economy["tax"] = Economy.TAX_LOW
	cm.round_number = interval
	b1 = cm.voter_total(1)
	cm._apply_tax_tick()
	check("düşük vergi hükümete seçmen kazandırır", cm.voter_total(1) > b1)
	cm.economy["tax"] = Economy.TAX_NORMAL
	b1 = cm.voter_total(1)
	cm._apply_tax_tick()
	check("normal vergi hiçbir şey yazmaz", near(cm.voter_total(1), b1))
	cm.round_number = 1
	cm.early_election_pending = true
	check("erken seçim kabul edilince çarpan en yüksek", cm.tax_cycle_mult() == interval)
	cm.early_election_pending = false
	gm.government = {}
	gm.main_gov_peer_id = -1
	cm.economy["tax"] = Economy.TAX_HIGH
	b1 = cm.voter_total(1)
	cm._apply_tax_tick()
	check("hükümet yokken kimseye yazılmaz", near(cm.voter_total(1), b1))
	# Sıra başı: _grant_turn_income vergiyi bir kez yazar.
	new_game()
	cm.round_number = 1
	cm.economy["tax"] = Economy.TAX_LOW
	b1 = cm.voter_total(1)
	give_turn(1)
	cm._grant_turn_income()
	check("sıra başında vergi yazıldı", cm.voter_total(1) > b1)
	var share_before := election_share(1)
	for i in 6:
		cm._apply_tax_tick()
	check("düşük vergi biriktikçe başbakanın oyu artar", election_share(1) > share_before, "%.2f -> %.2f" % [share_before, election_share(1)])
	GameRules.configure(8, 12)

	print("")
	print("=== 4) HAZİNEDEN YATIRIM: TEK SEFER HARCAMA, DİLİMLER ===")
	new_game()
	var province: String = String(cm._province_ids[3])
	give_turn(1)
	var t_before: float = cm.state_treasury()
	var funds_before: float = cm.funds_of(1)
	check("hazine yetiyor: yatırım yapılabilir", cm.can_invest(1, province))
	var v_inv1: float = cm.voter_total(1, province)
	var v_inv2: float = cm.voter_total(2, province)
	var v_inv3: float = cm.voter_total(3, province)
	var elsewhere: String = String(cm._province_ids[0])
	var v_else: float = cm.voter_total(1, elsewhere)
	cm._apply_invest_move(1, province)
	check("hazineden tam bir kez yatırım bedeli düştü", near(cm.state_treasury(), t_before - Economy.INVEST_COST))
	check("tamamı devletten: parti kasası değişmedi", near(cm.funds_of(1), funds_before))
	var immediate: float = cm.voter_total(1, province) - v_inv1
	check("etkinin bir kısmı hemen geldi (seçmen)", immediate > 0.0, "%.2f" % immediate)
	check("ortağa da hemen gelen pay", cm.voter_total(2, province) > v_inv2)
	check("kalan dilimler bekliyor", cm.pending_investments(1).size() == 1 and int(cm.pending_investments(1)[0]["rounds_left"]) == Economy.INVEST_DELAY_ROUNDS)
	check("muhalefet yatırımdan pay almaz", cm.pending_investments(3).is_empty() and cm.voter_total(3, province) <= v_inv3 + 0.001)
	cm.economy["treasury"] = Economy.INVEST_COST - 1.0
	check("hazine yetmezse tamamı devletten ödenemez", not cm.can_invest(1, province, 1.0))
	var keep_funds: float = cm.funds_of(1)
	cm.funds[1] = 2.0
	check("hazine ve kasa birlikte yetmezse yatırım yapılamaz", not cm.can_invest(1, province))
	cm.funds[1] = keep_funds
	cm.economy["treasury"] = 1000.0
	var local_before: float = cm.voter_total(1, province)
	var treasury_before_round: float = cm.state_treasury()
	end_round()
	check("1. dilim tur sonunda geldi", cm.voter_total(1, province) > local_before,
		"%.2f -> %.2f" % [local_before, cm.voter_total(1, province)])
	check("tur sonunda hazineden tekrar yatırım bedeli düşmez", cm.state_treasury() > treasury_before_round)
	end_round()
	check("2 tur sonra yatırım tamamlandı (bekleyen yok)", cm.pending_investments(1).is_empty())
	var after_done: float = cm.voter_total(1, province)
	end_round()
	check("tamamlanan yatırım tekrar dilim yazmaz", near(cm.voter_total(1, province), after_done))
	check("yatırım başka ile seçmen yazmaz", near(cm.voter_total(1, elsewhere), v_else))

	print("")
	print("=== 5) YÜKSEK VERGİDE ERKEN SEÇİM ===")
	new_game()
	pass_tax(Economy.TAX_HIGH)
	cm.early_election_pending = true
	cm.set_rng_seed(5)
	var revenue_before: float = cm.state_treasury()
	end_round()
	check("erken seçim yapıldı", cm.last_election_round == cm.round_number - 1 and not cm.early_election_pending)
	check("seçim tur sonu gelirinden sonra (gelir girdi)", float(cm.economy["revenue"]) > 0.0 and cm.state_treasury() > revenue_before)
	# Bekleyen yatırım dilimi seçimde sayılmaz: dilim tur sonuna kadar seçmene yazılmaz.
	new_game()
	give_turn(1)
	var inv_province: String = String(cm._province_ids[7])
	cm._apply_invest_move(1, inv_province)
	var now_voters: float = cm.voter_total(1, inv_province)
	check("bekleyen dilim tur içinde seçmene yazılmaz", not cm.pending_investments(1).is_empty() and near(cm.voter_total(1, inv_province), now_voters))

	print("")
	print("=== 8) ÇİFT SAYIM YOK ===")
	new_game()
	pass_tax(Economy.TAX_HIGH)
	end_round()
	var raw: Dictionary = pm.parties[1]["groups"]
	var eff: Dictionary = cm.effective_groups(1)
	var eff_again: Dictionary = cm.effective_groups(1)
	check("tekrar sormak etkiyi biriktirmez", str(eff) == str(eff_again))
	var econ_copy: Dictionary = cm.economy.duplicate(true)
	var voters_copy: float = cm.voter_total(1)
	cm._push_state({"type": "opinion"})
	cm.opinion_changed.emit()
	check("durum yayını / arayüz yenilemesi ekonomiyi ilerletmez", str(econ_copy) == str(cm.economy) and near(voters_copy, cm.voter_total(1)))
	check("ham yakınlık sözlüğü değişmedi", raw.size() == VoterGroups.GROUP_IDS.size())

	print("")
	print("=== 8b) HAZİNE KOTASI: BAKANLIK PUANINA ORANTILI ===")
	new_game()
	cm.economy["treasury"] = 400.0
	var pm_share: float = cm.quota_share(1)
	var dep_share: float = cm.quota_share(2)
	var pm_pts: float = float(gm.round_points_of(1))
	var dep_pts: float = float(gm.round_points_of(2))
	check("paylar bakanlık puanıyla orantılı", near(pm_share, pm_pts / (pm_pts + dep_pts)) and near(dep_share, dep_pts / (pm_pts + dep_pts)),
		"%.3f / %.3f (puan %d / %d)" % [pm_share, dep_share, int(pm_pts), int(dep_pts)])
	check("paylar toplamı 1", near(pm_share + dep_share, 1.0))
	check("muhalefetin kotası yok", near(cm.state_quota(3), 0.0))
	give_turn(1)
	cm.funds[1] = 1000.0
	var spam := 0
	for n in 10:
		var range_now: Dictionary = cm.funding_range(1, "invest")
		var share_now: float = float(range_now["max"])
		if share_now <= 0.0:
			break
		cm._apply_invest_move(1, String(cm._province_ids[n % cm._province_ids.size()]), share_now)
		spam += 1
	var spent_by_pm: float = 400.0 - cm.state_treasury()
	check("önce oynayan ortak hazineden kotasından fazlasını harcayamaz", spent_by_pm <= 400.0 * pm_share + 0.01,
		"%.1f harcadı, kota %.1f (%d yatırım)" % [spent_by_pm, 400.0 * pm_share, spam])
	check("sonra oynayan ortağın kotası duruyor", near(cm.state_quota(2), 400.0 * dep_share), "%.1f" % cm.state_quota(2))
	check("kota bitince devlet payı 0", near(float(cm.funding_range(1, "invest")["max"]), 0.0))
	# 0.0.231: sırada en fazla 3 yatırım; kota denemesi yeni sırada sürer.
	cm._start_turn_flow(1)
	check("kota bitince yatırım yapılamaz (0.0.238: kasadan tamamlama yok)", not cm.can_invest(1, String(cm._province_ids[0]), 0.0)
		and not cm.can_invest(1, String(cm._province_ids[0]), 1.0))
	give_turn(2)
	cm.funds[2] = 0.0
	var dep_quota: float = cm.state_quota(2)
	check("ortak kotası yetiyorsa hazineden yatırım yapabilir", (dep_quota >= Economy.INVEST_COST) == cm.can_invest(2, String(cm._province_ids[1]), 1.0),
		"kota %.1f" % dep_quota)
	end_round()
	check("yeni dönemde kota yeni hazineden hesaplanır", near(cm.state_quota(1), cm.state_treasury() * pm_share, 0.01),
		"%.1f / %.1f" % [cm.state_quota(1), cm.state_treasury() * pm_share])

	print("")
	print("=== 9) KAYIT / YÜKLEME ===")
	new_game()
	pass_tax(Economy.TAX_HIGH)
	end_round()
	pass_tax(Economy.TAX_LOW)
	give_turn(1)
	cm._apply_invest_move(1, String(cm._province_ids[2]))
	var packed: Dictionary = cm._pack_state(true).duplicate(true)
	var saved := str(cm.economy)
	var reference: Dictionary = cm.economy.duplicate(true)
	Economy.advance(reference)
	cm.economy = Economy.start_state()
	cm._apply_state(packed)
	check("yüklenen ekonomi aynı", str(cm.economy) == saved)
	check("yüklemeden sonra yatırım dilimi sürüyor", cm.pending_investments(1).size() == 1 and cm.tax_level() == Economy.TAX_LOW)
	var copy_after: Dictionary = cm.economy.duplicate(true)
	Economy.advance(copy_after)
	check("yüklemeden sonra bir tur aynı sonucu verir (çift etki yok)", near(float(copy_after["treasury"]), float(reference["treasury"])))
	var old_state: Dictionary = packed.duplicate(true)
	old_state.erase("economy")
	cm._apply_state(old_state)
	check("eski sürüm durumu: ekonomi güvenli varsayılanla başlar", str(cm.economy) == str(Economy.start_state()))
	var partial_state: Dictionary = packed.duplicate(true)
	partial_state["economy"] = {"tax": Economy.TAX_HIGH, "treasury": 900.0}
	cm._apply_state(partial_state)
	check("eksik alanlar doldurulur", cm.tax_level() == Economy.TAX_HIGH and near(cm.state_treasury(), 900.0)
		and cm.economy.has("investments") and cm.economy.has("prev"))

	print("")
	print("=== 10) GÖSTERİM YARDIMCILARI ===")
	check("para biçimi", Economy.money_text(1240.0) == "1.240" and Economy.money_text(-5.0) == "−5"
		and Economy.money_full(100.0) == MoneyIcon.GLYPH + " 100 M")
	check("milyonun altı bin (B), simge başta", GameRules.money(0.59) == MoneyIcon.GLYPH + " 590 B" and GameRules.amount(2.5) == "2,5 M"
		and GameRules.amount(1240.0) == "1.240 M" and GameRules.amount(-5.0) == "−5 M", GameRules.money(0.59))
	check("para karakteri gösterilmez (yer tutucu simgeye döner)", not Economy.money_full(100.0).contains("¤")
		and not GameRules.cost_text(15.0).contains("¤"))
	check("yüzde biçimi", Economy.percent_text(8.44) == "%8,4")

	print("")
	print("=== 11) BOTLAR AYNI KURALLARLA ===")
	new_game()
	var bb = load("res://scripts/bot_brain.gd")
	give_turn(1)
	cm.economy["treasury"] = 50.0
	check("bot: hazine azken ve seçim uzakken vergiyi artırmak ister", bb._desired_tax() == Economy.TAX_HIGH)
	var tax_choice: Dictionary = bb._best_tax_law(1)
	check("bot (başbakan) vergi artırım yasası önerir", String(tax_choice.get("law", "")) == cp.tax_law_type(Economy.TAX_HIGH),
		str(tax_choice))
	check("bot ortak vergi yasası önermez", bb._best_tax_law(2).is_empty())
	check("bot: hazine yetmezken yatırım değerlendirmez", bb._eval_investment(1).is_empty())
	cm.economy["treasury"] = Economy.INVEST_COST * 1.5
	check("bot: seçim uzakken son yedeği harcamaz", bb._eval_investment(1).is_empty())
	cm.economy["treasury"] = Economy.INVEST_COST * 4.0
	# 0.0.269: bot yalnız teşkilatlı ilde yatırım yapar.
	cm.organizations[String(cm._province_ids[0])] = {cm.party_of(1): 1}
	check("bot: yeterli hazinede yatırım değerlendirir", not bb._eval_investment(1).is_empty())
	cm.economy["tax"] = Economy.TAX_HIGH
	cm.early_election_pending = true
	check("bot: seçim yaklaşınca yüksek vergiyi indirir", bb._desired_tax() == Economy.TAX_NORMAL)
	check("bot muhalefet: vergi artırımına HAYIR", bb._tax_law_vote(3, cp.tax_law_type(Economy.TAX_HIGH), 1, [1, 2])
		== gm.VOTE_NO)
	cm.economy["tax"] = Economy.TAX_NORMAL
	check("bot ortak: seçime yakın artırıma destek vermez", bb._tax_law_vote(2, cp.tax_law_type(Economy.TAX_HIGH), 1, [1, 2])
		!= gm.VOTE_YES)
	check("bot ortak: indirime EVET", bb._tax_law_vote(2, cp.tax_law_type(Economy.TAX_NORMAL), 1, [1, 2]) == gm.VOTE_YES)
	cm.early_election_pending = false
	cm.economy["treasury"] = 0.0
	cm.funds[1] = 20.0
	give_turn(1)
	check("botlar da hazinesiz ve kasasız yatırım yapamaz (aynı kural)", not cm.can_invest(1))

	print("")
	print("=== 12) FİNANSMAN: MİTİNG KASADAN, YATIRIM HAZİNEDEN (0.0.238) ===")
	new_game()
	give_turn(1)
	cm.funds[1] = 100.0
	cm.economy["treasury"] = 1000.0
	var r: Dictionary = cm.funding_range(1, "invest")
	check("yatırım: tamamı devletten (paylaşım seçimi yok)", near(float(r["min"]), 1.0) and near(float(r["max"]), 1.0), str(r))
	check("yatırımın kasadan ödenen kısmı reddedilir", not cm.can_invest(1, String(cm._province_ids[1]), 0.5)
		and not cm.can_invest(1, String(cm._province_ids[1]), 0.0))
	cm.economy["treasury"] = 40.0
	check("kota yatırıma yetmezse yatırım yapılamaz", not cm.can_invest(1, String(cm._province_ids[1]), 1.0)
		and cm.funding_block_reason(1, "invest", 1.0).to_lower().contains("hazine"), cm.funding_block_reason(1, "invest", 1.0))
	cm.economy["treasury"] = 1000.0
	var prov2 := String(cm._province_ids[2])
	var t0: float = cm.state_treasury()
	var m0: float = cm.funds_of(1)
	cm._apply_invest_move(1, prov2, 1.0)
	check("yatırım hazineden düştü, parti kasası değişmedi", near(cm.state_treasury(), t0 - cm.invest_tier_cost(cm.DEFAULT_TIER)) and near(cm.funds_of(1), m0))
	check("işlem defteri tutulmuyor", not cm.economy.has("ledger") or (cm.economy["ledger"] as Array).is_empty())
	var p_mit := String(cm._province_ids[6])
	cm.organizations[p_mit] = {1: 1}
	r = cm.funding_range(1, "miting")
	check("hükümet partisi de mitingi kasadan öder", near(float(r["max"]), 0.0) and not bool(r["state_allowed"]))
	check("devlet paylı miting reddedilir", not cm.can_miting(1, p_mit, 1.0) and not cm.can_miting(1, p_mit, 0.5))
	var tm_before: float = cm.state_treasury()
	var funds_mit: float = cm.funds_of(1)
	cm._apply_miting_move(1, p_mit, 0.0)
	check("miting: hazine değişmedi, kasadan düştü", near(cm.state_treasury(), tm_before) and cm.funds_of(1) < funds_mit)
	cm.funds[1] = 5.0
	check("kasa yetmezse miting yok", not cm.can_miting(1, p_mit, 0.0))
	check("afet yardımında devlet hazinesi yok", not bool(cm.aid_limits(1)["state_allowed"]) and near(float(cm.aid_limits(1)["state_max"]), 0.0))
	check("meclis akışında soruşturma aşaması yok", not cm.PARL_STAGES.has("inquiry"))

	print("")
	print("=== 14) TEŞKİLAT BEDELİ ===")
	new_game()
	# 0.0.227: teşkilat bedeli sabit (artan fiyat yok).
	cm.organizations = {}
	check("ilk teşkilat sabit bedel", near(cm.org_cost_for(1), float(GameRules.ORG_FUNDS_COST)))
	for i in 12:
		cm.organizations[String(cm._province_ids[i])] = {cm.party_of(1): 1}
	check("12 teşkilatlı partiye de yeni teşkilat 10", near(cm.org_cost_for(1), float(GameRules.ORG_FUNDS_COST)), str(cm.org_cost_for(1)))
	give_turn(1)
	cm.funds[1] = 9.0
	check("bedel yetmezse teşkilat kurulamaz", not cm.can_build_organization(1, String(cm._province_ids[20])))
	cm.funds[1] = 50.0
	cm._apply_organization(1, String(cm._province_ids[20]))
	check("kurulunca sabit bedel (10) düşer", near(cm.funds_of(1), 50.0 - 10.0), str(cm.funds_of(1)))

	print("")
	if fails == 0:
		print("EKONOMİ TESTLERİ: HEPSİ GEÇTİ")
	else:
		print("EKONOMİ TESTLERİ: %d HATA" % fails)
	quit(1 if fails > 0 else 0)
