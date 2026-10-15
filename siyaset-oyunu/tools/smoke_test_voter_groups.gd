extends SceneTree
## SEÇMEN GRUPLARI testleri (yerel mod, RPC yok): grup tanımları, oy hesabı
## (normalizasyon, sıfır destek, dört çiftin tek seçmen sayılması, bölgesel
## yoğunluk ve sayım yöntemleri), miting / yatırım / yasa / grup toplantısının
## etkileri ve çift uygulanmaması; ayrıca altıgen harita, anayasa, olay logu,
## karışıklık ve bölünme.
##   godot --headless --path . --script res://tools/smoke_test_voter_groups.gd

var mm
var pm
var cm
var gm
var game_map
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

## Çekirdek gruplarıyla başlangıç yakınlıkları (boş: nötr).
func groups(core: Array = []) -> Dictionary:
	return VoterGroups.start_affinities(core)

func sum_values(d: Dictionary) -> float:
	var total := 0.0
	for k in d.keys():
		total += float(d[k])
	return total

## Tek bir grubu value yapılmış nötr yakınlıklar.
func with_group(group: String, value: float) -> Dictionary:
	var g := VoterGroups.neutral_affinities()
	g[group] = value
	return g

func near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) < eps

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
	cm.turn_order = affinities.keys()
	cm.current_turn_index = 0

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	cm.allow_temporary_parties = false
	cm.speech_required = false  # meclis konuşması ayrıca test edilir
	gm = root.get_node("GovernmentManager")
	game_map = root.get_node("GameMap")
	cm.fixed_map_seed = 1950
	mm.room_code = ""
	gm.result_hold_seconds = 0.0

	print("=== 1) ALTIGEN HARITA ===")
	var ok_contiguous := true
	for id in game_map.ids:
		var cells: Array = game_map.region_cells(id)
		var seen := {cells[0]: true}
		var queue: Array = [cells[0]]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for n in HexGridGenerator.neighbor_cells(cur, game_map.cols, game_map.rows):
				if not seen.has(n) and game_map.region_at_cell(n) == id:
					seen[n] = true
					queue.append(n)
		if seen.size() != cells.size():
			ok_contiguous = false
	check("her secim bolgesi bitisik altigenlerden olusur", ok_contiguous)
	var total := 0
	var min_seats := 999
	for id in game_map.ids:
		total += game_map.seats_of(id)
		min_seats = mini(min_seats, game_map.seats_of(id))
	check("il vekilleri toplami 300, her bolgede en az 2", total == HexGridGenerator.PROVINCE_SEATS and total == 300 and min_seats >= 2, "%d / min %d" % [total, min_seats])
	var names := {}
	for id in game_map.ids:
		names[game_map.name_of(id)] = true
	check("bolge adlari benzersiz", names.size() == game_map.ids.size())
	var a: Dictionary = HexGridGenerator.generate(99)
	var b: Dictionary = HexGridGenerator.generate(99)
	check("ayni tohum ayni harita", str(a) == str(b))
	var probe: String = game_map.ids[3]
	var cell: int = game_map.region_cells(probe)[0]
	check("noktadan bolge bulunur", game_map.province_at(game_map.cell_center(cell)) == probe)

	cm.fixed_map_seed = 0
	mm.map_seed = mm.clean_map_seed(" 00123-45 ")
	check("tohum temizlenir (sadece rakam)", mm.map_seed == "12345", mm.map_seed)
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"])})
	check("lobi tohumu oyunun haritasini belirler", game_map.seed_value() == 12345 		and str(game_map.data["cells"]) == str(HexGridGenerator.generate(12345)["cells"]))
	mm.map_seed = ""
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"])})
	check("tohum bossa rastgele tohum atanir", game_map.seed_value() > 0 and game_map.seed_value() != 12345)
	check("bos tohum temizlenince bos kalir", mm.clean_map_seed("abc") == "" and mm.clean_map_seed("0") == "")
	cm.fixed_map_seed = 1950

	print("")
	print("=== 2) SECMEN GRUBU TANIMLARI ===")
	check("8 grup, 4 cift", VoterGroups.GROUP_IDS.size() == 8 and VoterGroups.PAIR_IDS.size() == 4)
	var defs_ok := true
	var group_colors := {}
	for group in VoterGroups.GROUP_IDS:
		var d := VoterGroups.data(group)
		for key in ["title", "color", "icon", "opposite", "pair", "blurb", "issues", "law_title", "law_problem", "meeting", "law_backlash", "miting_backlash"]:
			if not d.has(key):
				defs_ok = false
		if VoterGroups.opposite(VoterGroups.opposite(group)) != group or VoterGroups.pair_of(group) != VoterGroups.pair_of(VoterGroups.opposite(group)):
			defs_ok = false
		if not (VoterGroups.PAIRS[VoterGroups.pair_of(group)] as Array).has(group):
			defs_ok = false
		group_colors[VoterGroups.color(group).to_html()] = true
		if float(d["law_backlash"]) <= 0.0 or float(d["law_backlash"]) >= 1.0:
			defs_ok = false
	check("her grubun tum alanlari var, karsit eslesmeleri simetrik", defs_ok)
	check("8 farkli renk", group_colors.size() == 8)
	var icon_ok := true
	for group in VoterGroups.GROUP_IDS:
		if not ["hardhat", "briefcase", "gradcap", "heart", "dome", "rainbow", "pin", "flag"].has(VoterGroups.icon(group)):
			icon_ok = false
	check("her grubun cizilebilen bir simgesi var", icon_ok)
	var prof := {"emek": 65, "kusak": 23, "inanc": 44, "yonetim": 44}
	check("cift yuzdeleri: isci 65 -> isveren 35", VoterGroups.percent(prof, "isci") == 65 and VoterGroups.percent(prof, "isveren") == 35)
	VoterGroups.set_percent(prof, "emekli", 81)
	check("bir tarafi degistirmek karsiti tamamlar", VoterGroups.percent(prof, "genc") == 19 and int(prof["kusak"]) == 19)
	VoterGroups.set_percent(prof, "isci", 140)
	check("yuzde 0..100 disina cikamaz", VoterGroups.percent(prof, "isci") == 100 and VoterGroups.percent(prof, "isveren") == 0)
	check("gecersiz profil reddedilir", not VoterGroups.is_valid_profile({"emek": 50}) and not VoterGroups.is_valid_profile(
		{"emek": 50.5, "kusak": 50, "inanc": 50, "yonetim": 50}) and VoterGroups.is_valid_profile({"emek": 50, "kusak": 50, "inanc": 50, "yonetim": 50}))

	print("")
	print("=== 3) OY HESABI ===")
	var mixed := {"emek": 70, "kusak": 40, "inanc": 55, "yonetim": 30}
	check("hic hitap etmeyen parti her ilde uyum 0", near(VoterGroups.appeal(VoterGroups.neutral_affinities(), mixed), 0.0))
	check("yeni parti: her grupta %0, cekirdekte %10", near(float(groups(["isci", "dindar"])["isci"]), VoterGroups.CORE_START) \
		and near(float(groups(["isci", "dindar"])["isveren"]), 0.0) and near(VoterGroups.CORE_START, 10.0))
	var full_isci := ElectionModel.shares_in_group({1: with_group("isci", 100.0), 2: VoterGroups.neutral_affinities()}, "isci")
	check("%100 hitap: diger partiler o gruptan 0 oy alir", near(float(full_isci[1]), 1.0) and near(float(full_isci[2]), 0.0), str(full_isci))
	var nobody := ElectionModel.shares_in_group({1: VoterGroups.neutral_affinities(), 2: VoterGroups.neutral_affinities(), 3: VoterGroups.neutral_affinities()}, "emekli")
	check("kimse hitap etmiyorsa grup homojen dagilir", near(float(nobody[1]), 1.0 / 3.0) and near(float(nobody[3]), 1.0 / 3.0), str(nobody))
	var half := ElectionModel.shares_in_group({1: with_group("isci", 50.0), 2: VoterGroups.neutral_affinities()}, "isci")
	check("%50 hitap + kararsizlarin esit payi: %75", near(float(half[1]), 0.75), str(half))
	var over := ElectionModel.shares_in_group({1: with_group("isci", 80.0), 2: with_group("isci", 40.0)}, "isci")
	check("hitap toplami 100'u asarsa paylar oranla kuculur", near(float(over[1]), 2.0 / 3.0), str(over))
	var base_appeal := VoterGroups.appeal(VoterGroups.neutral_affinities(), mixed)
	var plus := VoterGroups.appeal(with_group("isci", 20.0), mixed)
	check("dort cift tek secmen: bir gruptaki +20, uyumu pay x 20 / 4 artirir", near(plus - base_appeal, 0.70 * 20.0 / 4.0), "%.3f" % (plus - base_appeal))
	var zero := {}
	for group in VoterGroups.GROUP_IDS:
		zero[group] = 0.0
	var zero_shares := ElectionModel.expected_shares({1: zero, 2: zero.duplicate(), 3: zero.duplicate()}, mixed)
	check("butun destekler sifir: cokmez, esit dagilim", zero_shares.size() == 3 and near(float(zero_shares[1]), 100.0 / 3.0, 0.01) \
		and near(sum_values(zero_shares), 100.0, 0.01), str(zero_shares))
	var odd := ElectionModel.expected_shares({1: groups(["isci", "dindar"]), 2: groups(["isveren", "ilerici"]), 3: zero}, mixed)
	var nonneg := true
	for id in odd.keys():
		if float(odd[id]) < 0.0:
			nonneg = false
	check("oy paylari negatif degil, toplam 100", nonneg and near(sum_values(odd), 100.0, 0.01), str(odd))
	var worker_party := {1: with_group("isci", 80.0), 2: VoterGroups.neutral_affinities()}
	var low_worker := {"emek": 30, "kusak": 50, "inanc": 50, "yonetim": 50}
	var high_worker := {"emek": 85, "kusak": 50, "inanc": 50, "yonetim": 50}
	var s_low := float(ElectionModel.expected_shares(worker_party, low_worker)[1])
	var s_high := float(ElectionModel.expected_shares(worker_party, high_worker)[1])
	check("grubun payi artinca o grupta guclu partinin oyu artar", s_high > s_low + 5.0, "%.1f -> %.1f" % [s_low, s_high])
	var one_group := ElectionModel.expected_shares({1: with_group("isci", 100.0), 2: VoterGroups.neutral_affinities()}, high_worker)
	check("tek grupta tam destek bile ili tamamen almaz (orantili etki)", float(one_group[1]) < 85.0 and float(one_group[1]) > 55.0, str(one_group))
	var seat_file = root.get_node("GameMap").seat_counts()
	var voters := ElectionModel.load_province_voters()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var regional := {1: groups(["ozerkci", "isci"]), 2: groups(["milliyetci", "isveren"]), 3: groups(["genc", "ilerici"])}
	var seats_by_method := {}
	for method in ElectionModel.SEAT_METHODS:
		ElectionModel.seat_method = method
		rng.seed = 7
		var res := ElectionModel.compute(regional, seat_file, voters, 0.0, rng)
		seats_by_method[method] = res["seats"]
		check("%s: butun vekiller dagitildi" % method, int(sum_values(res["seats"])) == cm.TOTAL_SEATS, str(res["seats"]))
	ElectionModel.seat_method = "dhondt"
	check("ayni oylar farkli sayim yontemlerinde farkli vekil dagilimi verir",
		str(seats_by_method["dhondt"]) != str(seats_by_method["wta"]) or str(seats_by_method["hare"]) != str(seats_by_method["wta"]), str(seats_by_method))

	print("")
	print("=== 3b) MITING: YEREL + NUFUSLA ORANTILI HITAP, ODAK, SECMEN CALMA ===")
	new_game({1: groups(["isci", "dindar"]), 2: groups(["isveren", "ilerici"])})
	var mid: String = game_map.ids[0]
	var mid_profile: Dictionary = cm.province_profiles[mid].duplicate(true)
	for pair in {"emek": 80, "kusak": 50, "inanc": 30, "yonetim": 50}:
		VoterGroups.set_percent(mid_profile, VoterGroups.PAIRS[pair][0], {"emek": 80, "kusak": 50, "inanc": 30, "yonetim": 50}[pair])
	mid_profile.erase("_counts")
	cm.province_profiles[mid] = mid_profile
	var profile_before := str(cm.province_profiles[mid])
	cm.organizations[mid] = {1: 1}
	cm.funds[1] = 500
	cm.current_turn_index = 0
	# Provokasyonu dışarıda bırak: ildeki seçmene yeterince hitap eden partide risk 0.
	pm.parties[1]["groups"]["isci"] = 40.0
	pm.parties[2]["groups"]["emekli"] = 20.0
	var g_before: Dictionary = pm.parties[1]["groups"].duplicate()
	var rival_before: Dictionary = pm.parties[2]["groups"].duplicate()
	var nat_before: float = cm.national_of(1)
	var loc_before: float = cm.local_of(mid, 1)
	check("uyumlu ilde provokasyon riski yok", near(cm.miting_risk(1, mid), 0.0), "%.2f" % cm.miting_risk(1, mid))
	check("miting teskilat istemez", cm.can_miting(1, game_map.ids[4]) and cm.organization_level(game_map.ids[4], 1) == 0)
	var g0 := float(cm.miting_group_gains(1, game_map.ids[4])[0]["gain"])
	cm.organizations[game_map.ids[4]] = {1: 1}
	var g1 := float(cm.miting_group_gains(1, game_map.ids[4])[0]["gain"])
	cm.organizations[game_map.ids[4]] = {1: 2}
	var g2 := float(cm.miting_group_gains(1, game_map.ids[4])[0]["gain"])
	cm.organizations.erase(game_map.ids[4])
	check("teskilat 0 / 1 / 2: etki 1x / 2x / 3x", g0 > 0.0 and near(g1, 2.0 * g0) and near(g2, 3.0 * g0), "%.3f / %.3f / %.3f" % [g0, g1, g2])
	check("odak sayisi = teskilat seviyesi", cm.miting_focus_slots(1, mid) == 1 and cm.miting_focus_slots(1, game_map.ids[4]) == 0)
	check("fazla odak kirpilir", cm._clean_focus(1, mid, ["emekli", "genc", "emekli"]) == ["emekli"])
	var plain_emekli := 0.0
	for effect in cm.miting_group_gains(1, mid):
		if effect["group"] == "emekli":
			plain_emekli = float(effect["gain"])
	cm._apply_miting_move(1, mid, 0.0, ["emekli"])
	var d_isci := float(pm.parties[1]["groups"]["isci"]) - float(g_before["isci"])
	var d_isveren := float(pm.parties[1]["groups"]["isveren"]) - float(g_before["isveren"])
	var d_emekli := float(pm.parties[1]["groups"]["emekli"]) - float(g_before["emekli"])
	var d_genc := float(pm.parties[1]["groups"]["genc"]) - float(g_before["genc"])
	check("yerel: il aktivitesi MITING_LOCAL x teskilat carpani artar", near(cm.local_of(mid, 1) - loc_before, PublicOpinion.MITING_LOCAL * 2.0))
	check("ildeki her gruptan kazanir (kalabalik grupta daha cok)", d_isci > 0.0 and d_isveren > 0.0 and d_isci > d_isveren, "%.3f / %.3f" % [d_isci, d_isveren])
	check("odak grup (emekli) odaksiz mitingin %s kati getirir" % PublicOpinion.MITING_FOCUS_MULT,
		near(d_emekli, plain_emekli * PublicOpinion.MITING_FOCUS_MULT, 0.01) and d_genc > 0.0, "%.3f / %.3f" % [d_emekli, plain_emekli])
	check("secmen calma: rakibin emekli hitabi azaldi", float(pm.parties[2]["groups"]["emekli"]) < float(rival_before["emekli"]),
		"%.3f -> %.3f" % [float(rival_before["emekli"]), float(pm.parties[2]["groups"]["emekli"])])
	var hitap_total := 0.0
	for pid in [1, 2]:
		hitap_total += float(pm.parties[pid]["groups"]["emekli"])
	check("hitap toplami 100'u asmaz", hitap_total <= 100.0 + 0.001)
	check("miting ayrica genel ulusal puan yazmaz (cift sayim yok)", near(cm.national_of(1), nat_before))
	# KÜÇÜK İL: 3 vekil, %95 emekli; 2. seviye teşkilat + emekli odağı bile ~%1-2 getirir.
	var tiny: String = game_map.ids[6]
	var tiny_profile: Dictionary = cm.province_profiles[tiny].duplicate(true)
	VoterGroups.set_percent(tiny_profile, "emekli", 95)
	tiny_profile.erase("_counts")
	tiny_profile["_electorate"] = 3 * HexGridGenerator.VOTERS_PER_SEAT
	cm.province_profiles[tiny] = tiny_profile
	cm.organizations[tiny] = {2: 2}
	var tiny_gain := 0.0
	for effect in cm.miting_group_gains(2, tiny, ["emekli"]):
		if effect["group"] == "emekli":
			tiny_gain = float(effect["gain"])
	check("kucuk il (%95 emekli, 3 vekil): odakli miting emeklide en cok ~%2", tiny_gain > 0.3 and tiny_gain <= 2.5, "%.2f" % tiny_gain)
	cm.organizations.erase(tiny)
	check("miting il profilini degistirmez", str(cm.province_profiles[mid]) == profile_before)
	var g_mid: Dictionary = pm.parties[1]["groups"].duplicate()
	cm._apply_miting_move(1, mid)
	var d_isci2 := float(pm.parties[1]["groups"]["isci"]) - float(g_mid["isci"])
	check("art arda miting neredeyse ayni getirir (yorgunluk cok kisik)", d_isci2 < d_isci and d_isci2 > d_isci * 0.95, "%.3f -> %.3f" % [d_isci, d_isci2])
	for i in 40:
		cm._apply_miting_move(1, mid)
		cm.local_support = {}
	check("sinirsiz miting bile destegi 100'e tasimaz", float(pm.parties[1]["groups"]["isci"]) < 100.0 \
		and float(pm.parties[1]["groups"]["isci"]) >= 0.0, "%.1f" % float(pm.parties[1]["groups"]["isci"]))
	var fat: float = float(cm.miting_fatigue[1]["isci"])
	cm._decay_opinion()
	check("miting yorgunlugu tur sonunda soner", float(cm.miting_fatigue.get(1, {}).get("isci", 0.0)) < fat)

	print("")
	print("=== 3c) YATIRIM: SADECE YEREL MEMNUNIYET ===")
	new_game({1: groups(["isci", "dindar"]), 2: groups(["isveren", "ilerici"])})
	var inv: String = game_map.ids[1]
	cm.funds[1] = 500
	cm.current_turn_index = 0
	gm.government = {"pm": 1}
	gm.main_gov_peer_id = 1
	var gi: Dictionary = pm.parties[1]["groups"].duplicate()
	var prof_inv := str(cm.province_profiles[inv])
	cm._apply_invest_move(1, inv)
	check("yatirim il aktivitesini artirir (hemen gelen pay)", near(cm.local_of(inv, 1), minf(PublicOpinion.LIMIT, PublicOpinion.INVEST_LOCAL * Economy.INVEST_IMMEDIATE)))
	check("yatirim ildeki gruplardan hitap kazandirir", float(pm.parties[1]["groups"]["isveren"]) > float(gi["isveren"]))
	# ÜST ÜSTE YATIRIM: aynı ile ikinci yatırım da birincisi kadar işe yarar
	# (il puanı LIMIT'e takılmaz, INVEST_LIMIT'e kadar çıkar; hitap kazancı da aynı).
	new_game({1: groups(["isci", "dindar"]), 2: groups(["isveren", "ilerici"])})
	prof_inv = str(cm.province_profiles[inv])  # yeni oyun: yeni ülke
	cm.funds[1] = 500
	cm.current_turn_index = 0
	gm.government = {"pm": 1}
	gm.main_gov_peer_id = 1
	cm.economy["treasury"] = 1000.0
	var l0: float = cm.local_of(inv, 1)
	var h0: float = float(pm.parties[1]["groups"]["isveren"])
	cm._apply_invest_move(1, inv)
	var l1: float = cm.local_of(inv, 1)
	var h1: float = float(pm.parties[1]["groups"]["isveren"])
	cm._apply_invest_move(1, inv)
	var l2: float = cm.local_of(inv, 1)
	var h2: float = float(pm.parties[1]["groups"]["isveren"])
	check("ikinci yatirim il puanina birincisi kadar ekler (tavana takilmaz)", near(l2 - l1, l1 - l0) and l2 > PublicOpinion.LIMIT,
		"%.2f -> %.2f -> %.2f" % [l0, l1, l2])
	check("ikinci yatirim hitapta birincisi kadar kazandirir", h2 - h1 > (h1 - h0) * 0.97, "%.3f / %.3f" % [h1 - h0, h2 - h1])
	cm._apply_miting_move(1, inv)
	check("miting yatirimin tavan ustu puanini kirpmaz", cm.local_of(inv, 1) >= l2 - 0.001, "%.2f" % cm.local_of(inv, 1))
	gm.government = {"pm": 1}
	gi = pm.parties[1]["groups"].duplicate()
	check("yatirim il profilini degistirmez", str(cm.province_profiles[inv]) == prof_inv)
	check("yatirim grup hitabini (kendi kazanci disinda) degistirmez", str(pm.parties[1]["groups"]) == str(gi))
	cm._apply_invest_move(1, inv)
	check("yatirim il puani INVEST_LIMIT'i asmaz", cm.local_of(inv, 1) <= PublicOpinion.INVEST_LIMIT + 0.001)
	gm.government = {}
	gm.main_gov_peer_id = -1

	print("")
	print("=== 3d) YASA: ETKI OYLAMA SONUCUNDA ===")
	new_game({1: groups(["isci", "dindar"]), 2: groups(["isveren", "ilerici"])})
	var cp = root.get_node("CardPresets")
	cm.last_seats = {1: 260, 2: 240}
	cm.election_seats = cm.last_seats.duplicate()
	cm.agenda = {"type": "gundem_isci", "until": cm.round_number + 1}
	cm.funds[1] = 100
	cm.current_turn_index = 0
	var gl: Dictionary = pm.parties[1]["groups"].duplicate()
	cm._apply_law(1, cp.law_type("isci"))
	check("yasa sunuldu, oylama acik, grup destegi henuz degismedi", gm.phase == gm.Phase.VOTING and str(pm.parties[1]["groups"]) == str(gl))
	gm._apply_vote(2, gm.VOTE_NO)
	check("oylama bitince hedef grupta destek artti", float(pm.parties[1]["groups"]["isci"]) > float(gl["isci"]),
		"%.1f -> %.1f" % [float(gl["isci"]), float(pm.parties[1]["groups"]["isci"])])
	check("gorusune aykiri yasa ek bedel istemez", cm.law_funds_cost(1, cp.law_type("isveren")) == GameRules.LAW_FUNDS_COST)

	print("")
	print("=== 5) ANAYASA (2/3 YA DA RET) ===")
	var votes3 := {1: 0.47, 2: 0.33, 3: 0.20}
	check("D'Hondt", str(ElectionModel.dhondt(votes3, [1, 2, 3], 7)) == str({1: 4, 2: 2, 3: 1}))
	check("Hare kotasi + en buyuk kalan", str(ElectionModel.hare(votes3, [1, 2, 3], 7)) == str({1: 3, 2: 2, 3: 2}))
	check("kazanan hepsini alir", str(ElectionModel.winner_takes_all(votes3, [1, 2, 3], 7)) == str({1: 7, 2: 0, 3: 0}))
	ElectionModel.seat_method = "wta"
	check("wta'da ulusal liste D'Hondt kalir", str(ElectionModel.allocate(votes3, [1, 2, 3], 7, true)) == str({1: 4, 2: 2, 3: 1}))
	mm.reset_seat_method()
	check("varsayilan sayim D'Hondt", ElectionModel.seat_method == "dhondt")
	check("yasa: basit cogunluk (251-249 gecer, 250-250 gecmez)", gm.law_passes(251, 249) and not gm.law_passes(250, 250))
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"]), 3: groups(["genc", "milliyetci"])})
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.election_seats = cm.last_seats.duplicate()
	cm.round_number = 5
	cm.last_election_round = 4
	cm.current_turn_index = 0
	check("anayasa 2/3 = 334", gm.constitution_threshold_seats() == 334 and not gm.has_method("referendum_threshold_seats"))
	var change := {"threshold": 5.0, "interval": 3, "seat_method": "hare"}
	cm._apply_constitution_proposal(1, change)
	gm._apply_vote(2, gm.VOTE_NO)
	gm._apply_vote(3, gm.VOTE_YES)
	check("300 EVET (2/3 alti): REDDEDILIR, referandum yok", is_equal_approx(mm.election_threshold, 0.0)
		and gm.last_resolution_reason.find("REDDEDİLDİ") != -1 and not "referendum" in cm, gm.last_resolution_reason)
	cm.law_rounds = {}
	cm.constitution_rounds = {}
	cm.funds[1] = 20.0
	cm._apply_constitution_proposal(1, change)
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(3, gm.VOTE_YES)
	check("2/3 EVET: hemen yururluge girer", is_equal_approx(mm.election_threshold, 5.0) and mm.election_interval == 3
		and mm.seat_method == "hare" and ElectionModel.seat_method == "hare", gm.last_resolution_reason)
	mm.election_threshold = 0.0
	mm.reset_seat_method()
	cm.law_rounds = {}
	cm.constitution_rounds = {}
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)  # önceki turlarda seçim/kurma açılmış olabilir
	cm.last_seats = {1: 150, 2: 200, 3: 150}
	cm.current_turn_index = 0
	cm._apply_constitution_proposal(1, {"threshold": 0.0, "interval": 2, "seat_method": "wta"})
	gm._apply_vote(2, gm.VOTE_YES)
	gm._apply_vote(3, gm.VOTE_YES)
	check("2/3 ile sayim 'kazanan hepsini alir' olur", mm.seat_method == "wta" and ElectionModel.seat_method == "wta", gm.last_resolution_reason)
	cm.law_rounds = {}
	cm.constitution_rounds = {}
	cm._apply_constitution_proposal(1, {"threshold": 0.0, "interval": 2, "seat_method": "yok"})
	check("gecersiz sayim yontemi reddedilir", gm.proposal_kind == "")
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"])})
	check("yeni oyunda sayim D'Hondt'a doner", mm.seat_method == "dhondt" and ElectionModel.seat_method == "dhondt")

	print("")
	print("=== 4) OLAY LOGU ===")
	cm.clear_event_log()
	cm.log_event("deneme", 1, mid, "miting")
	check("log kaydi tutulur", cm.event_log.size() == 1 and cm.event_log[0]["province"] == mid)
	for i in cm.EVENT_LOG_LIMIT + 10:
		cm.log_event("kayit %d" % i)
	check("log siniri asilmaz", cm.event_log.size() == cm.EVENT_LOG_LIMIT)

	print("")
	print("=== 6) GRUP TOPLANTISI: GECICI VE AZALAN DESTEK ===")
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"]), 3: groups(["genc", "milliyetci"])})
	cm.speech_required = true
	cm.speech_done = false
	cm.crisis = {}
	cm.funds[1] = 100.0
	var org_pid: String = game_map.ids[2]
	cm.organizations[org_pid] = {1: 1}
	cm.last_election_round = 1  # toplantı ilk seçimden sonra
	check("sira gelince toplanti hakki var", cm.needs_speech(1) and not cm.needs_speech(2))
	check("toplantisiz da hamle yapilabilir", cm.can_choose_main_action(1) and cm.can_miting(1, org_pid) \
		and cm.can_play_card(1, "bagis_kampanyasi"))
	cm._apply_speech(2, "isci")
	check("sirasi olmayan toplanamaz", not cm.speech_done)
	var permanent: Dictionary = pm.parties[1]["groups"].duplicate()
	var r0: int = cm.round_number
	cm._apply_speech(1, "emekli")
	check("toplanti bu tur +%s gecici destek" % PublicOpinion.MEETING_BONUS[0], cm.speech_done and near(float(cm.effective_groups(1)["emekli"]), float(permanent["emekli"]) + PublicOpinion.MEETING_BONUS[0]))
	check("kalici destek degismez", str(pm.parties[1]["groups"]) == str(permanent))
	check("bedel %d para" % GameRules.SPEECH_FUNDS_COST, near(cm.funds_of(1), 100.0 - GameRules.SPEECH_FUNDS_COST))
	cm._apply_speech(1, "genc")
	check("turda tek toplanti", cm.meeting_bonuses(1).size() == 1)
	check("sonraki turlarda azalir, sonra 0", near(float(cm.meeting_bonuses(1, r0 + 1).get("emekli", 0.0)), PublicOpinion.MEETING_BONUS[1]) \
		and near(float(cm.meeting_bonuses(1, r0 + 2).get("emekli", 0.0)), PublicOpinion.MEETING_BONUS[2]) and cm.meeting_bonuses(1, r0 + 3).is_empty())
	var nat1: float = cm.national_of(1)
	cm._apply_pass(1, true)
	check("toplanan partiye ceza yok", near(cm.national_of(1), nat1))
	check("siradaki oyuncu toplanabilir", cm.current_turn_peer_id() == 2 and cm.needs_speech(2))
	var nat2: float = cm.national_of(2)
	cm._apply_pass(2, true)
	check("toplanti yapmamak ulusal ceza getirmez", near(cm.national_of(2), nat2))
	# Ardışık turlarda aynı gruba toplantı bonusu biriktirmez.
	cm.group_meetings[1] = {"emekli": r0 + 1}
	check("ardisik toplanti bonusu toplamaz", near(float(cm.meeting_bonuses(1, r0 + 1).get("emekli", 0.0)), PublicOpinion.MEETING_BONUS[0]))
	cm.group_meetings[1] = {"emekli": r0}
	cm._decay_group_effects(r0 + 3)
	check("suresi dolan toplanti kaydi silinir", not cm.group_meetings.has(1))
	cm.round_number = r0
	cm.agenda = {"type": "gundem_emekli", "until": r0 + 1}
	cm.speech_rounds = {}
	cm.current_turn_index = cm.turn_order.find(3)
	var nat3: float = cm.national_of(3)
	cm.funds[3] = 50.0
	cm._apply_speech(3, "emekli")
	check("gundemin grubuyla toplanti ulusal destek getirir", near(cm.national_of(3) - nat3, PublicOpinion.CRISIS_RESPONSE_NATIONAL))
	cm.speech_required = false
	cm.crisis = {}

	print("")
	print("=== 7) TOPLANTI SECIM ANINDA SAYILIR ===")
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isveren", "dindar"])})
	var finished: int = cm.round_number
	cm.group_meetings[1] = {"emekli": finished}
	var at_election: Dictionary = cm._group_profiles(finished)
	check("secim turunda yapilan toplanti secim hesabina tam girer", near(float(at_election[1]["emekli"]) - float(at_election[2]["emekli"]), PublicOpinion.MEETING_BONUS[0]))

	print("")
	print("=== 9) KARISIKLIK, BOLUNME VE GERI DONUS ===")
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"]), 3: groups(["genc", "milliyetci"])})
	mm.players[2]["bot"] = true
	cm.last_seats = {1: 200, 2: 150, 3: 150}
	cm.election_seats = cm.last_seats.duplicate()
	cm.national_list = {1: 80, 2: 60, 3: 60}
	cm.last_election_round = 4
	cm.round_number = 5
	var kid: String = game_map.ids[5]
	cm.organizations[kid] = {1: 2}
	cm._apply_card_effect(2, "isyan", 1)
	check("tek ic karisiklik bolmez", cm.turmoil_of(1) < PublicOpinion.SPLIT_TURMOIL)
	cm._apply_card_effect(2, "isyan", 1)
	var turn_size: int = cm.turn_order.size()
	cm.current_turn_index = 0
	gm.government = {"pm": 3}  # hükümet var: tur sonunda erken seçim olmasın
	gm.main_gov_peer_id = 3
	gm._set_phase(gm.Phase.GOVERNING)
	GameRules.configure(2, 8)
	GameRules.set_election_anchor(0)
	cm.round_number = 5  # seçim turu değil
	cm._finish_round()
	check("karisiklik esigi asildi: parti bolundu", cm.splinters.size() == 1 and cm.turn_order.size() == turn_size + 1,
		str(cm.splinters))
	var sid: int = int(cm.splinters.keys()[0]) if not cm.splinters.is_empty() else -1
	check("ayrilan parti yapay zeka, ayni grup yakinliklari, benzer renk", mm.is_bot(sid) \
		and str(pm.parties[sid]["groups"]) == str(pm.parties[1]["groups"]) \
		and not Color(pm.parties[sid]["bg_color"]).is_equal_approx(Color(pm.parties[1]["bg_color"])))
	var split_seats := int(cm.last_seats.get(sid, 0))
	check("vekillerin ciddi bolumu gecti", split_seats >= int(200 * PublicOpinion.SPLIT_SEAT_SHARE_MIN) - 1 \
		and cm.last_seats[1] + split_seats == 200, "%d / %d" % [split_seats, cm.last_seats[1]])
	check("ayrilan parti bir daha bolunemez", true)
	cm.turmoil[sid] = 99.0
	cm._check_splits()
	check("ayrilan parti tekrar bolunmez", cm.splinters.size() == 1)
	cm.turmoil[1] = 99.0
	cm._check_splits()
	check("ana partinin ayni anda ikinci ayriligi yok", cm.splinters.size() == 1)
	cm.organizations[kid][sid] = 2
	cm.organizations[kid][1] = 1
	cm.turmoil[1] = 0.5
	cm._check_reunions()
	check("secim atlatmadan geri donmez", cm.splinters.has(sid))
	cm.splinters[sid]["elections"] = 1
	cm.turmoil[1] = 5.0
	cm._check_reunions()
	check("karisiklik surerken 1 secimden sonra donmez", cm.splinters.has(sid))
	gm.scores[sid] = 7
	gm.scores[1] = 3
	cm.splinters[sid]["elections"] = PublicOpinion.SPLIT_MAX_ELECTIONS
	cm._check_reunions()
	check("en gec 4 secimden sonra doner", not cm.splinters.has(sid) and not cm.turn_order.has(sid) and not pm.parties.has(sid))
	check("vekilleri ve teskilatlariyla doner, puan birlesir", cm.last_seats[1] == 200 and cm.organization_level(kid, 1) == 2 \
		and gm.score_of(1) == 10, "%d mv, puan %d" % [cm.last_seats[1], gm.score_of(1)])

	print("")
	print("=== 10) YENI KARTLAR VE KURALLAR ===")
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"])})
	check("tur basina para 30 (hukumet 40)", GameRules.FUNDS_PER_ROUND == 30 and GameRules.FUNDS_PER_ROUND_GOVERNMENT == 40)
	check("yasa gecirmek +5 puan", cm.law_pass_score(false) == 5 and cm.law_pass_score(true) == 5)
	check("bakanlik +3, yardimcilik +5, basbakanlik +10", GovernmentPresets.MINISTRY_POINTS == 3 \
		and GovernmentPresets.DEPUTY_PM_POINTS == 5 and GovernmentPresets.PM_POINTS == 10)
	cm.funds[1] = 0.0
	cm._apply_card_effect(1, "bagis_kampanyasi_guclu")
	check("guclu bagis kampanyasi +60", near(cm.funds_of(1), cm.funds_bonus_amount(1, true)) and GameRules.FUNDS_BONUS_STRONG == 60)
	cm.inventories[1] = []
	cm._apply_card_effect(1, "bonus_kart")
	check("bonus kart 2 kart ceker", cm.inventories[1].size() == 2, str(cm.inventories[1]))
	var bonus_from_bonus := 0
	for i in 200:
		cm.inventories[1] = []
		cm._apply_card_effect(1, "bonus_kart")
		bonus_from_bonus += cm.inventories[1].count("bonus_kart")
	check("bonus karttan bonus kart cikmaz", bonus_from_bonus == 0, str(bonus_from_bonus))
	cm.inventories[2] = ["karalama"]
	cm._apply_card_effect(1, "kart_calma", 2)
	check("kart calma: rakibin kartini alir", cm.inventories[2].is_empty() and cm.inventories[1].size() == 3)
	cm._apply_card_effect(1, "kart_calma", 2)
	check("eli bossa kart bosa gider", cm.inventories[1].size() == 3)
	var bot_name_lengths := {}
	var name_ok := true
	for i in 40:
		var n: String = pm._bot_party_name([])
		bot_name_lengths[n.length()] = true
		if not n.ends_with("P") or n.length() < 2 or n.length() > 3:
			name_ok = false
	check("bot adlari XP bicimi (1-2 harf + P)", name_ok and bot_name_lengths.has(2) and bot_name_lengths.has(3), str(bot_name_lengths.keys()))
	check("parti adi 1-15 karakter", pm.NAME_MAX_LENGTH == 15 and pm.is_valid_name("A") and pm.is_valid_name("123456789012345") \
		and not pm.is_valid_name("1234567890123456"))
	mm.players = {10: {"name": "insan"}, 11: {"name": "", "bot": true}, 12: {"name": "", "bot": true}}
	pm.parties = {10: {"name": "Insan", "bg_color": Color("22A9D6")}}
	pm.add_bot_party(11)
	pm.add_bot_party(12)
	var close_pair := false
	var colors: Array = [Color("22A9D6"), Color(pm.parties[11]["bg_color"]), Color(pm.parties[12]["bg_color"])]
	for ci in colors.size():
		for cj in range(ci + 1, colors.size()):
			if pm.color_distance(colors[ci], colors[cj]) < pm.BOT_COLOR_MIN_DISTANCE:
				close_pair = true
	check("bot renkleri oyunculara ve birbirine cok yakin degil", not close_pair, str(colors))
	pm._apply_color(10, colors[1].lightened(0.05))
	check("oyuncu botun rengine YAKIN renk secince bot rengini degistirmez",
		Color(pm.parties[11]["bg_color"]).is_equal_approx(colors[1]))
	pm._apply_color(10, colors[1])
	var moved: Color = Color(pm.parties[11]["bg_color"])
	check("oyuncu botun AYNI rengini alinca bot baska renge gecer", Color(pm.parties[10]["bg_color"]).is_equal_approx(colors[1]) \
		and not moved.is_equal_approx(colors[1]))
	check("botun yeni rengi diger partilere yakin degil",
		pm.color_distance(moved, colors[1]) >= pm.BOT_COLOR_MIN_DISTANCE \
		and pm.color_distance(moved, Color(pm.parties[12]["bg_color"])) >= pm.BOT_COLOR_MIN_DISTANCE, str(moved))
	var keep_owner: int = mm.owner_id
	mm.owner_id = mm.multiplayer.get_unique_id()
	var keep_bg: String = String(pm.politicians[11]["background"])
	pm.set_bot_politician_name(11, "ayşe", "yılmaz")
	check("oda sahibi bot adini degistirir", String(pm.politicians[11]["first_name"]) == "Ayşe" \
		and String(pm.politicians[11]["surname"]) == "Yılmaz" and String(pm.politicians[11]["background"]) == keep_bg,
		str(pm.politicians[11]))
	pm.set_bot_politician_name(11, "", "Kaya")
	check("bos ad reddedilir", String(pm.politicians[11]["first_name"]) == "Ayşe")
	mm.owner_id = keep_owner

	print("")
	print("=== 11) BOTLAR ANAYASA DEGISIKLIGI ONERIR ===")
	var brain = load("res://scripts/bot_brain.gd")
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"]), 3: groups(["genc", "milliyetci"])})
	for id in [1, 2, 3]:
		mm.players[id]["bot"] = true
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)
	mm.election_threshold = 7.0
	cm.last_seats = {1: 30, 2: 300, 3: 170}
	cm.last_vote_shares = {1: 6.0, 2: 60.0, 3: 8.0}
	cm.current_turn_index = 0
	cm.round_number = 9
	brain._constitution_rounds = {}
	var plan: Dictionary = brain._best_constitution(1)
	check("buyukler istemezse baraj teklifi cogunluk bulamaz, teklif yok", plan.is_empty(), str(plan))
	cm.last_seats = {1: 160, 2: 160, 3: 180}  # zorlananlar birlikte 2/3'ü bulur
	plan = brain._best_constitution(1)
	check("barajda zorlanan bot (ve zorlanan ortagi) barajin dusmesini onerir", not plan.is_empty()
		and float(plan["payload"]["threshold"]) < 7.0, str(plan))
	# Yasa da bedelsiz ve her gruba açık: bot geçen dönem yasa sundu sayılır ki
	# anayasa yasa hakkıyla yarışsın (yasa sıklığı sınırı).
	cm.law_rounds[1] = cm.round_number - 1
	# Miting artık teşkilat istemiyor: anayasa kararı ölçülsün diye mitinge para yetmesin.
	cm.funds[1] = GameRules.MITING_FUNDS_COST - 1
	var action: Dictionary = brain.choose_action(1)
	check("bot hamlesi anayasa teklifi", String(action.get("type", "")) == "constitution", str(action))
	root.get_node("BotManager").do_action(1)
	check("teklif meclise geldi, bot not aldi", gm.proposal_kind == gm.KIND_CONSTITUTION
		and brain._best_constitution(1).is_empty())
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)
	mm.election_threshold = 0.0

	print("")
	print("=== 12) DUSMANCA BARAJ VE KAZANAN HEPSINI ALIR ===")
	new_game({1: groups(["isveren", "dindar"]), 2: groups(["isci", "ilerici"]), 3: groups(["genc", "milliyetci"])})
	for id in [1, 2, 3]:
		mm.players[id]["bot"] = true
	gm._clear_proposal()
	gm._set_phase(gm.Phase.IDLE)
	mm.election_threshold = 0.0
	cm.last_seats = {1: 260, 2: 230, 3: 10}
	cm.last_vote_shares = {1: 50.0, 2: 47.5, 3: 2.5}
	cm.last_province_results = {}
	brain._constitution_rounds = {}
	var hostile: Dictionary = brain._best_constitution(1)
	check("barajda zorlanan rakibi gorunce bot barajı yukseltmeyi onerir", not hostile.is_empty()
		and float(hostile["payload"]["threshold"]) >= 3.0, str(hostile))
	check("zorlanan parti yukselen baraja HAYIR der", brain._constitution_vote(3, {"threshold": 3.0}) == gm.VOTE_NO)
	check("guvendeki buyuk parti yukselen baraja EVET der", brain._constitution_vote(2, {"threshold": 3.0}) == gm.VOTE_YES)
	# Kazanan hepsini alır: 1 birçok ilde birinci, 2 hiçbirinde.
	var ids: Array = game_map.ids
	for i in ids.size():
		var n: int = game_map.seats_of(ids[i])
		var a_seats: int = n / 2 + 1 if i % 4 != 0 else n / 2
		cm.last_province_results[ids[i]] = {1: {"percent": 52.0 if i % 4 != 0 else 40.0, "seats": a_seats},
			2: {"percent": 45.0 if i % 4 != 0 else 55.0, "seats": n - a_seats}}
	check("cok ilde birinci partiye WTA vekil kazandirir", brain.wta_seat_gain(1) > 10 and brain.wta_seat_gain(2) < 0,
		"%d / %d" % [brain.wta_seat_gain(1), brain.wta_seat_gain(2)])
	mm.election_threshold = 3.0  # baraj zaten rakibi disarida birakiyor
	cm.last_seats = {1: 340, 2: 150, 3: 10}  # teklif sahibi tek başına 2/3
	brain._constitution_rounds = {}
	var wta_plan: Dictionary = brain._best_constitution(1)
	check("bot kazanan hepsini alir sayimini onerir", not wta_plan.is_empty()
		and String(wta_plan["payload"]["seat_method"]) == "wta", str(wta_plan))
	check("az ilde birinci rakip WTA'ya HAYIR der", brain._constitution_vote(2, {"seat_method": "wta"}) == gm.VOTE_NO)
	mm.election_threshold = 0.0
	cm.last_province_results = {}

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit(1 if fails > 0 else 0)
