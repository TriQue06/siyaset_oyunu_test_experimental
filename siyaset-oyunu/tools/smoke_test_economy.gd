extends SceneTree
## EKONOMİ ve VERGİ testleri (yerel mod, RPC yok): yüksek vergiyle hazine
## birikmesi, indirimin hemen + kademeli etkisi, gelir düşüşü, hazineden
## yatırım (tek sefer harcama, dilimler), yüksek vergide erken seçim, indirimden
## sonra sadece gerçekleşen etkinin sayılması, koalisyon ortaklarının payı, çift
## sayım olmaması, durum kaydı/yükleme (eski sürüm dahil), botların aynı
## kurallarla vergi ve yatırım kararları.
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
	var result := ElectionModel.compute(cm._group_profiles(cm.round_number), cm._province_seat_counts, cm.province_voters(),
		0.0, rng, cm.election_modifiers())
	return float(result["vote_shares"].get(pid, 0.0))

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	cp = root.get_node("CardPresets")
	cm.allow_temporary_parties = false
	cm.speech_required = false
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
	check("reddedilen vergi yasası kademeyi değiştirmez", not rejected and cm.tax_level() == Economy.TAX_NORMAL
		and near(float(cm.economy["pressure"]), 0.0))
	check("reddedilen yasa yine de dönemin yasa hakkını kullanır", cm.has_proposed_law_this_round(1)
		and not cm.can_propose_tax_law(1, Economy.TAX_HIGH))

	print("")
	print("=== 1) YÜKSEK VERGİ: HAZİNE BİRİKİR, HÜKÜMET DESTEK KAYBEDER ===")
	new_game()
	var share_normal := election_share(1)
	var groups_before := str(pm.parties[1]["groups"])
	var national_before := str(cm.national_support)
	check("vergi artırımı kabul edildi", pass_tax(Economy.TAX_HIGH))
	check("baskının bir kısmı hemen hissedilir", near(float(cm.economy["pressure"]), Economy.TAX_IMMEDIATE),
		"%.3f" % float(cm.economy["pressure"]))
	check("vergi yasası kalıcı grup yakınlığına yazmaz", str(pm.parties[1]["groups"]) == groups_before)
	check("vergi yasası ulusal puana yazmaz", str(cm.national_support) == national_before)
	var treasury0: float = cm.state_treasury()
	var revenues: Array = []
	for i in 4:
		var expected: float = cm.expected_revenue()
		end_round()
		revenues.append(float(cm.economy["revenue"]))
		check("tur %d: gelir hazineye bir kez girdi" % (i + 1), near(float(cm.economy["revenue"]), expected, 0.01))
	var gained: float = cm.state_treasury() - treasury0
	check("4 tur yüksek vergi: hazine birikti", gained > 4.0 * Economy.TAX_REVENUE[Economy.TAX_NORMAL] * 0.9, "+%.0f" % gained)
	check("yüksek vergi geliri normalden fazla", float(revenues[0]) > Economy.revenue(Economy.TAX_NORMAL, 50.0))
	var pressure_high: float = float(cm.economy["pressure"])
	check("baskı turlar içinde arttı (kademeli)", pressure_high > Economy.TAX_IMMEDIATE + 0.4, "%.3f" % pressure_high)
	var share_high := election_share(1)
	check("yüksek vergide başbakanın oyu düştü", share_high < share_normal - 0.3, "%.2f -> %.2f" % [share_normal, share_high])
	check("ekonomi yüksek vergide yavaşladı", cm.economy_index() < Economy.START_INDEX)

	print("")
	print("=== 2-3) VERGİ İNDİRİMİ: HEMEN + KADEMELİ, GELİR DÜŞER ===")
	var mood_high: Dictionary = cm.economy_mood(1)
	check("indirim (yüksek → normal) kabul edildi", pass_tax(Economy.TAX_NORMAL))
	var pressure_cut: float = float(cm.economy["pressure"])
	check("indirim anında baskı kısmen azaldı", near(pressure_cut, pressure_high * (1.0 - Economy.TAX_IMMEDIATE)),
		"%.3f -> %.3f" % [pressure_high, pressure_cut])
	check("indirim tüm memnuniyetsizliği bir anda silmez", pressure_cut > 0.3 and not Economy.is_settled(cm.economy))
	check("indirimin önizlemesi: yerleşmeye birkaç tur var", Economy.rounds_to_settle(cm.economy) >= 3, str(Economy.rounds_to_settle(cm.economy)))
	var share_cut_now := election_share(1)
	end_round()
	var share_cut_1 := election_share(1)
	end_round()
	var share_cut_2 := election_share(1)
	check("oy indirim anında biraz toparlandı", share_cut_now > share_high, "%.2f -> %.2f" % [share_high, share_cut_now])
	check("oy sonraki turlarda toparlanmaya devam etti", share_cut_1 > share_cut_now and share_cut_2 > share_cut_1,
		"%.2f -> %.2f -> %.2f" % [share_cut_now, share_cut_1, share_cut_2])
	check("indirimden sonra gelir düştü", float(cm.economy["revenue"]) < float(revenues[3]),
		"%.0f -> %.0f" % [float(revenues[3]), float(cm.economy["revenue"])])
	check("işverenlerin memnuniyetsizliği azaldı", float(cm.economy_mood(1).get("isveren", 0.0)) > float(mood_high.get("isveren", 0.0)))

	print("")
	print("=== 4) HAZİNEDEN YATIRIM: TEK SEFER HARCAMA, DİLİMLER ===")
	new_game()
	var province: String = String(cm._province_ids[3])
	give_turn(1)
	var t_before: float = cm.state_treasury()
	var funds_before: float = cm.funds_of(1)
	check("hazine yetiyor: yatırım yapılabilir", cm.can_invest(1, province))
	cm._apply_invest_move(1, province)
	check("hazineden tam bir kez yatırım bedeli düştü", near(cm.state_treasury(), t_before - Economy.INVEST_COST))
	check("tamamı devletten: parti kasası değişmedi", near(cm.funds_of(1), funds_before))
	var immediate: float = cm.local_of(province, 1)
	check("etkinin yarısı hemen geldi", near(immediate, PublicOpinion.INVEST_LOCAL * Economy.INVEST_IMMEDIATE), "%.2f" % immediate)
	check("ortağa da hemen gelen pay", near(cm.local_of(province, 2), PublicOpinion.INVEST_PARTNER_LOCAL * Economy.INVEST_IMMEDIATE))
	check("kalan dilimler bekliyor", cm.pending_investments(1).size() == 1 and int(cm.pending_investments(1)[0]["rounds_left"]) == Economy.INVEST_DELAY_ROUNDS)
	check("muhalefet yatırımdan pay almaz", cm.pending_investments(3).is_empty() and near(cm.local_of(province, 3), 0.0))
	cm.economy["treasury"] = Economy.INVEST_COST - 1.0
	check("hazine yetmezse tamamı devletten ödenemez", not cm.can_invest(1, province, 1.0))
	var keep_funds: float = cm.funds_of(1)
	cm.funds[1] = 2.0
	check("hazine ve kasa birlikte yetmezse yatırım yapılamaz", not cm.can_invest(1, province))
	cm.funds[1] = keep_funds
	cm.economy["treasury"] = 1000.0
	var tranche: float = PublicOpinion.INVEST_LOCAL * (1.0 - Economy.INVEST_IMMEDIATE) / Economy.INVEST_DELAY_ROUNDS
	var local_before: float = cm.local_of(province, 1)
	var treasury_before_round: float = cm.state_treasury()
	end_round()
	var expected_local: float = PublicOpinion.clamp_points(local_before + tranche) * PublicOpinion.LOCAL_DECAY
	check("1. dilim tur sonunda geldi (sonra söndü)", near(cm.local_of(province, 1), expected_local, 0.01),
		"%.2f / %.2f" % [cm.local_of(province, 1), expected_local])
	check("tur sonunda hazineden tekrar yatırım bedeli düşmez", cm.state_treasury() > treasury_before_round)
	end_round()
	check("2 tur sonra yatırım tamamlandı (bekleyen yok)", cm.pending_investments(1).is_empty())
	var after_done: float = cm.local_of(province, 1)
	end_round()
	check("tamamlanan yatırım tekrar dilim yazmaz", cm.local_of(province, 1) < after_done)
	check("yatırım ekonomiyi canlandırdı", cm.economy_index() > Economy.START_INDEX, "%.1f" % cm.economy_index())
	check("yatırım ayrıca ulusal puan yazmaz", near(cm.national_of(1), 0.0))

	print("")
	print("=== 5) YÜKSEK VERGİDE ERKEN SEÇİM ===")
	new_game()
	var base_share := election_share(1)
	var base_partner := election_share(2)
	var base_opposition := election_share(3)
	pass_tax(Economy.TAX_HIGH)
	end_round()
	end_round()
	var early_share := election_share(1)
	var early_partner := election_share(2)
	var early_opposition := election_share(3)
	check("başbakanın partisi yüksek vergide erken seçimde kaybeder", early_share < base_share, "%.2f -> %.2f" % [base_share, early_share])
	check("muhalefet bundan kazanır", early_opposition > base_opposition)
	var mods: Dictionary = cm.election_modifiers()
	check("erken seçime ayrı bir ekonomi cezası eklenmez (ulusal çarpan aynı)",
		near(float(mods["national"].get(1, 0.0)), float(cm.national_support.get(1, 0.0)) + PublicOpinion.GOVERNMENT_FATIGUE))
	# Gerçek erken seçim: sandık o ana kadar gerçekleşen etkiyle kurulur.
	cm.early_election_pending = true
	var pressure_at_vote: float = float(cm.economy["pressure"])
	cm.set_rng_seed(5)
	end_round()
	check("erken seçim yapıldı", cm.last_election_round == cm.round_number - 1 and not cm.early_election_pending)
	check("seçim tur sonu ekonomisinden sonra (gelir girdi, baskı bir adım ilerledi)",
		float(cm.economy["pressure"]) > pressure_at_vote and float(cm.economy["revenue"]) > 0.0)

	print("")
	print("=== 6) İNDİRİMDEN SONRA SEÇİM: SADECE GERÇEKLEŞEN FAYDA ===")
	new_game()
	pass_tax(Economy.TAX_HIGH)
	for i in 3:
		end_round()
	pass_tax(Economy.TAX_NORMAL)
	var partial := election_share(1)
	var settled_state: Dictionary = cm.economy.duplicate(true)
	cm.economy["pressure"] = 0.0
	var full := election_share(1)
	cm.economy = settled_state
	check("yeni indirimde seçim: fayda henüz tam değil", partial < full - 0.2, "%.2f < %.2f" % [partial, full])
	# Bekleyen yatırım dilimi seçimde sayılmaz.
	give_turn(1)
	var inv_province: String = String(cm._province_ids[7])
	cm.local_support = {}
	cm._apply_invest_move(1, inv_province)
	var mods_now: Dictionary = cm.election_modifiers()
	var local_now: float = float(mods_now["local"].get(inv_province, {}).get(1, 0.0)) \
		- (cm.activity_of(inv_province, 1) - cm.local_of(inv_province, 1))
	check("seçim girdisinde yatırımın sadece gelen payı var", near(local_now, PublicOpinion.INVEST_LOCAL * Economy.INVEST_IMMEDIATE, 0.01),
		"%.2f" % local_now)

	print("")
	print("=== 7) KOALİSYON ORTAKLARI ===")
	new_game()
	pass_tax(Economy.TAX_HIGH)
	end_round()
	var mood_pm: Dictionary = cm.economy_mood(1)
	var mood_partner: Dictionary = cm.economy_mood(2)
	check("ortak da ekonomik memnuniyetsizliği taşır", not mood_partner.is_empty())
	check("ortağın payı başbakanınkinden küçük (PARTNER_SHARE)", near(float(mood_partner.get("isveren", 0.0)),
		float(mood_pm.get("isveren", 0.0)) * Economy.PARTNER_SHARE, 0.01))
	check("muhalefet ekonomiden etkilenmez", cm.economy_mood(3).is_empty())
	var partner_now := election_share(2)
	cm.economy["pressure"] = 0.0
	cm.economy["index"] = Economy.START_INDEX
	var partner_neutral := election_share(2)
	check("ortağın oyu da yüksek vergide düşük", partner_now < partner_neutral, "%.2f < %.2f" % [partner_now, partner_neutral])

	print("")
	print("=== 8) ÇİFT SAYIM YOK ===")
	new_game()
	pass_tax(Economy.TAX_HIGH)
	end_round()
	var raw: Dictionary = pm.parties[1]["groups"]
	var eff: Dictionary = cm.effective_groups(1)
	var mood: Dictionary = cm.economy_mood(1)
	var ok_layer := true
	for group in VoterGroups.GROUP_IDS:
		var expected_value := clampf(float(raw[group]) + float(mood.get(group, 0.0)), 0.0, 100.0)
		if not near(float(eff[group]), expected_value):
			ok_layer = false
	check("seçimdeki grup değeri = kalıcı yakınlık + ekonomi (bir kez)", ok_layer)
	var eff_again: Dictionary = cm.effective_groups(1)
	check("tekrar sormak etkiyi biriktirmez", str(eff) == str(eff_again))
	var econ_copy: Dictionary = cm.economy.duplicate(true)
	cm._push_state({"type": "opinion"})
	cm.opinion_changed.emit()
	check("durum yayını / arayüz yenilemesi ekonomiyi ilerletmez", str(econ_copy) == str(cm.economy))

	print("")
	print("=== 9) KAYIT / YÜKLEME (GEÇİŞ SIRASINDA) ===")
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
	check("yüklemeden sonra geçiş sürüyor", not Economy.is_settled(cm.economy) and cm.pending_investments(1).size() == 1)
	var copy_after: Dictionary = cm.economy.duplicate(true)
	Economy.advance(copy_after)
	check("yüklemeden sonra bir tur aynı sonucu verir (çift etki yok)", near(float(copy_after["treasury"]), float(reference["treasury"]))
		and near(float(copy_after["pressure"]), float(reference["pressure"])))
	var old_state: Dictionary = packed.duplicate(true)
	old_state.erase("economy")
	cm._apply_state(old_state)
	check("eski sürüm durumu: ekonomi güvenli varsayılanla başlar", str(cm.economy) == str(Economy.start_state()))
	var partial_state: Dictionary = packed.duplicate(true)
	partial_state["economy"] = {"tax": Economy.TAX_HIGH, "treasury": 900.0}
	cm._apply_state(partial_state)
	check("eksik alanlar doldurulur", cm.tax_level() == Economy.TAX_HIGH and near(cm.state_treasury(), 900.0)
		and cm.economy.has("investments") and cm.economy.has("pressure"))

	print("")
	print("=== 10) GÖSTERİM YARDIMCILARI ===")
	check("para biçimi", Economy.money_text(1240.0) == "1.240" and Economy.money_text(-5.0) == "−5"
		and Economy.money_full(100.0) == "100 milyon ₺")
	check("yüzde biçimi", Economy.percent_text(8.44) == "%8,4")
	new_game()
	check("göstergeler aralıkta", cm.inflation() > 0.0 and cm.unemployment() > 0.0 and cm.economy_index() <= 100.0)
	pass_tax(Economy.TAX_LOW)
	check("düşük vergi enflasyonu hemen artırır (gösterge güncel)", cm.inflation() > Economy.INFLATION_BASE)
	check("yerleşme oranı 0..1", Economy.settle_ratio(cm.economy) > 0.0 and Economy.settle_ratio(cm.economy) < 1.0,
		"%.2f" % Economy.settle_ratio(cm.economy))

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
	print("=== 12) FİNANSMAN PAYLAŞIMI ===")
	new_game()
	give_turn(1)
	cm.funds[1] = 100.0
	cm.economy["treasury"] = 1000.0
	var r: Dictionary = cm.funding_range(1, "invest")
	check("yatırım: 0/100 ve 100/0 serbest (yeterli bakiye)", near(float(r["min"]), 0.0) and near(float(r["max"]), 1.0))
	var sp := Economy.split_cost(Economy.INVEST_COST, 0.3)
	check("paylaşım: devlet %30 = 30 milyon ₺, parti 70 milyon ₺ (aynı birim, kur yok)", near(float(sp["state"]), 30.0) and near(float(sp["party"]), 70.0)
		and not sp.has("mana"))
	check("paylaşım %5 adıma oturur", near(float(Economy.split_cost(100.0, 0.33)["share"]), 0.35))
	cm.economy["treasury"] = 40.0
	r = cm.funding_range(1, "invest")
	check("hazine 40 iken devlet payı en fazla %40", near(float(r["max"]), 0.4), str(r))
	check("hazineyi aşan paylaşım reddedilir", not cm.can_invest(1, String(cm._province_ids[1]), 0.5)
		and cm.funding_block_reason(1, "invest", 0.5).contains("hazine"))
	cm.economy["treasury"] = 1000.0
	cm.funds[1] = 30.0
	r = cm.funding_range(1, "invest")
	check("kasa 30 milyon ₺: parti en fazla 30 → devlet en az %70", near(float(r["min"]), 0.7), str(r))
	check("kasayı aşan paylaşım reddedilir", not cm.can_invest(1, String(cm._province_ids[1]), 0.3))
	cm.funds[1] = 100.0
	var prov2 := String(cm._province_ids[2])
	var t0: float = cm.state_treasury()
	var m0: float = cm.funds_of(1)
	cm._apply_invest_move(1, prov2, 0.3)
	check("seçilen paylaşım tam bir kez uygulandı (hazine −30)", near(cm.state_treasury(), t0 - 30.0))
	check("parti kasası: tam 70 milyon ₺ pay (ayrı hamle bedeli yok)", near(cm.funds_of(1), m0 - 70.0))
	var ledger: Array = cm.economy["ledger"]
	var rec: Dictionary = ledger[-1]
	check("işlem kaydı doğru", int(rec["party"]) == 1 and String(rec["kind"]) == "invest" and String(rec["province"]) == prov2
		and near(float(rec["party_million"]), 70.0) and near(float(rec["state_million"]), 30.0) and int(rec["round"]) == cm.round_number
		and not bool(rec["investigated"]), str(rec))
	check("yatırımın etkisi paylaşımdan bağımsız (aynı il etkisi)", near(cm.local_of(prov2, 1), PublicOpinion.INVEST_LOCAL * Economy.INVEST_IMMEDIATE))
	give_turn(3)
	cm.funds[3] = 100.0
	var opp_province := ""
	for pid in cm._province_ids:
		cm.organizations[String(pid)] = {3: 1}
		opp_province = String(pid)
		break
	r = cm.funding_range(3, "miting")
	check("muhalefet devlet hazinesini kullanamaz (miting %100 parti)", near(float(r["max"]), 0.0) and not bool(r["state_allowed"]))
	check("muhalefete devlet paylı miting reddedilir", not cm.can_miting(3, opp_province, 0.5))

	print("")
	print("=== 13) FİNANSMAN SORUŞTURMASI ===")
	new_game()
	cm.economy["treasury"] = 2000.0
	var p_inv := String(cm._province_ids[4])
	# 1: tamamen devletten yatırım (meşru), 2: kendi kasasından yatırım.
	give_turn(1)
	cm._apply_invest_move(1, p_inv, 1.0)
	give_turn(2)
	cm._apply_invest_move(2, p_inv, 0.0)
	var nat1: float = cm.national_of(1)
	var nat2: float = cm.national_of(2)
	give_turn(3)
	check("muhalefet soruşturma açabilir", cm.can_open_inquiry(3, 1))
	cm._apply_inquiry(3, 1)
	check("meşru devlet yatırımı usulsüzlük sayılmaz (ceza yok)", near(cm.national_of(1), nat1) and near(cm.turmoil_of(1), 0.0))
	check("kanıt yoksa ödül de uydurulmaz", near(cm.national_of(1), nat1))
	check("bedel soruşturandan düştü", near(cm.funds_of(3), 500.0 - Economy.INQUIRY_FUNDS_COST))
	check("partin dönemde tek soruşturma açar", not cm.can_open_inquiry(3, 2))
	cm.economy["inquiries"] = {}
	cm._apply_inquiry(3, 2)
	var gain: float = cm.national_of(2) - nat2
	check("kendi kasasından yatırım doğrulandı: sınırlı şeffaflık ödülü", gain > 0.0 and gain <= Economy.TRANSPARENCY_MAX + 0.001
		and near(gain, Economy.transparency_gain(100.0)), "%.2f" % gain)
	check("ödül soruşturana değil hedefe", near(cm.national_of(3), 0.0))
	cm.economy["inquiries"] = {}
	cm._apply_inquiry(3, 2)
	check("aynı işlem ikinci kez ödül vermez", near(cm.national_of(2) - nat2, gain))
	var mit_entry := {"kind": "miting", "party_million": 30.0}
	check("kendi parasıyla miting ödüle çeyrek ağırlıkla girer", near(Economy.transparency_amount(mit_entry), 7.5)
		and Economy.transparency_gain(Economy.transparency_amount(mit_entry) * 2.0) == 0.0)
	check("ödül üst sınırı ve azalan getiri", Economy.transparency_gain(10000.0) <= Economy.TRANSPARENCY_MAX
		and Economy.transparency_gain(400.0) < 4.0 * Economy.transparency_gain(100.0) and Economy.transparency_gain(10.0) == 0.0)
	# Usulsüzlük: hükümet partisi mitingi devlet parasıyla.
	var p_mit := String(cm._province_ids[6])
	cm.organizations[p_mit] = {1: 1}
	give_turn(1)
	check("hükümet partisi mitingi devletten ödeyebilir", cm.can_miting(1, p_mit, 1.0))
	var tm_before: float = cm.state_treasury()
	var funds_mit: float = cm.funds_of(1)
	cm._apply_miting_move(1, p_mit, 1.0)
	check("devletten miting: hazine −15, parti kasası değişmedi", near(cm.state_treasury(), tm_before - float(GameRules.MITING_FUNDS_COST)) and near(cm.funds_of(1), funds_mit))
	var nat_before: float = cm.national_of(1)
	var cred_before: float = cm.credibility_of(3)
	cm.economy["inquiries"] = {}
	give_turn(3)
	cm._apply_inquiry(3, 1)
	check("partizan kamu harcaması usulsüzlük olarak bulundu", cm.national_of(1) < nat_before - 0.5 and cm.turmoil_of(1) > 0.0,
		"%.2f -> %.2f" % [nat_before, cm.national_of(1)])
	check("usulsüzlüğü bulan güvenilirlik kazanır", cm.credibility_of(3) >= cred_before or near(cred_before, cm.CREDIBILITY_MAX))
	var nat_after: float = cm.national_of(1)
	cm.economy["inquiries"] = {}
	cm._apply_inquiry(3, 1)
	check("aynı usulsüzlük ikinci kez ceza vermez", near(cm.national_of(1), nat_after))
	# Hükümet partisi de açabilir (kendini denetletme dahil).
	cm.economy["inquiries"] = {}
	give_turn(1)
	check("hükümet partisi de soruşturma açabilir", cm.can_open_inquiry(1, 3) and cm.can_open_inquiry(1, 1))
	cm.last_seats = {}
	check("meclis yokken soruşturma açılmaz", not cm.can_open_inquiry(1, 3))
	cm.last_seats = {1: 250, 2: 100, 3: 150}
	# Kayıt ve yükleme: defter durumla gider; eski durumda boş başlar.
	var packed_ledger: Dictionary = cm._pack_state(false).duplicate(true)
	var ledger_size: int = (cm.economy["ledger"] as Array).size()
	cm.economy = Economy.start_state()
	cm._apply_state(packed_ledger)
	check("işlem defteri durumla taşınır", (cm.economy["ledger"] as Array).size() == ledger_size and ledger_size >= 3)
	# Bot: gizli tutarlara bakmaz; kendi kasasından harcadıysa kendini denetletir.
	new_game()
	cm.economy["treasury"] = 2000.0
	give_turn(1)
	cm._apply_invest_move(1, String(cm._province_ids[3]), 0.0)
	cm.economy["inquiries"] = {}
	give_turn(1)
	var inquiry_choice: Dictionary = bb._eval_inquiry(1)
	check("bot kendi kasasından ödediği harcamayı denetletir", int(inquiry_choice.get("target", -1)) == 1, str(inquiry_choice))
	give_turn(3)
	cm.funds[3] = 5.0
	check("bot da kasası yetmeden soruşturma açamaz", bb._eval_inquiry(3).is_empty())

	print("")
	print("=== 14) KANIT SAKLAMA VE BOT FİNANSMANI ===")
	new_game()
	# 120 kapsam içi kayıt: eski 80 sınırı kanıt silerdi; artık hepsi kalır.
	var big: Array = []
	for i in 120:
		big.append({"id": i, "round": cm.round_number, "party": 1, "kind": "miting", "province": "", "total": 15.0,
			"party_million": 0.0, "state_million": 15.0, "investigated": false})
	check("kapsamdaki incelenmemiş kanıt sayı sınırıyla silinmez", Economy.prune_ledger(big, cm.round_number).size() == 120)
	big.append({"id": 999, "round": cm.round_number - Economy.INQUIRY_SCOPE_ROUNDS - 1, "party": 1, "kind": "miting",
		"province": "", "total": 15.0, "party_million": 15.0, "state_million": 0.0, "investigated": false})
	check("kapsamı geçen kayıt temizlenir", Economy.prune_ledger(big, cm.round_number).size() == 120)
	var many: Array = []
	for i in Economy.LEDGER_LIMIT + 50:
		many.append({"id": i, "round": cm.round_number, "party": 1, "kind": "invest", "province": "", "total": 100.0,
			"party_million": 0.0, "state_million": 100.0, "investigated": i < 100})
	var pruned: Array = Economy.prune_ledger(many, cm.round_number)
	var open_left := 0
	for e in pruned:
		if not bool(e["investigated"]):
			open_left += 1
	check("güvenlik sınırında önce incelenmiş kayıtlar gider", open_left == Economy.LEDGER_LIMIT + 50 - 100, "%d" % open_left)
	# Bot: hükümette ve kasası darken mitingi bazen devletten öder; muhalefette asla.
	cm.economy["treasury"] = 2000.0
	cm.economy["ledger"] = []
	seed(4242)
	var partisan := 0
	for i in 200:
		cm.funds[1] = 20.0
		if bb.miting_state_share(1) > 0.0:
			partisan += 1
	check("hükümet botu bazen partizan finansman seçer (zorunlu değil)", partisan > 0 and partisan < 200, "%d/200" % partisan)
	var opp := 0
	for i in 100:
		cm.funds[3] = 20.0
		if bb.miting_state_share(3) > 0.0:
			opp += 1
	check("muhalefet botu devlet parası kullanamaz", opp == 0)
	# Kendi açık usulsüzlükleri birikince durur (kanıt bilgisi değil, kendi kaydı).
	var p_org := String(cm._province_ids[7])
	cm.organizations[p_org] = {1: 1}
	for k in bb.PARTISAN_MAX_OPEN:
		give_turn(1)
		cm.funds[1] = 100.0
		cm._apply_miting_move(1, p_org, 1.0)
	var after_open := 0
	for i in 100:
		cm.funds[1] = 20.0
		if bb.miting_state_share(1) > 0.0:
			after_open += 1
	check("kendi açık usulsüzlükleri birikince bot durur", after_open == 0)
	# Botun usulsüzlüğü insanla aynı soruşturmayla bulunur.
	var nat_b: float = cm.national_of(1)
	give_turn(3)
	cm.funds[3] = 100.0
	cm.economy["inquiries"] = {}
	cm._apply_inquiry(3, 1)
	check("botun partizan harcaması da usulsüzlük olarak bulunur", cm.national_of(1) < nat_b)
	# Yatırımda hazine yetmezse bot kalanı kasadan tamamlar.
	cm.economy["treasury"] = 60.0
	cm.funds[1] = 100.0
	check("bot yatırımı: hazine yetmezse devlet payı hazine kadar", near(bb.invest_state_share(1), 0.6))
	# Kademeli teşkilat bedeli: ilk 5 sabit, sonra her teşkilat +1.
	cm.organizations = {}
	check("ilk teşkilat sabit bedel", near(cm.org_cost_for(1), float(GameRules.ORG_FUNDS_COST)))
	for i in 12:
		cm.organizations[String(cm._province_ids[i])] = {cm.party_of(1): 1}
	check("12 teşkilatlı partiye yeni teşkilat 17", near(cm.org_cost_for(1), float(GameRules.ORG_FUNDS_COST) + 7.0 * GameRules.ORG_COST_STEP),
		str(cm.org_cost_for(1)))
	give_turn(1)
	cm.funds[1] = 16.0
	check("bedel yetmezse teşkilat kurulamaz", not cm.can_build_organization(1, String(cm._province_ids[20])))
	cm.funds[1] = 50.0
	cm._apply_organization(1, String(cm._province_ids[20]))
	check("kurulunca tam kademeli bedel düşer", near(cm.funds_of(1), 50.0 - 17.0), str(cm.funds_of(1)))

	print("")
	if fails == 0:
		print("EKONOMİ TESTLERİ: HEPSİ GEÇTİ")
	else:
		print("EKONOMİ TESTLERİ: %d HATA" % fails)
	quit(1 if fails > 0 else 0)
