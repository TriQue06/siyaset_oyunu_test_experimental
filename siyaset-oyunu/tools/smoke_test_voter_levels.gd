extends SceneTree
## SEÇMEN SEVİYELERİ (0.0.228): il × grup × parti × sadakat seviyesi tabanı.
var fails := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String, detail: String = "") -> void:
	if not ok:
		fails += 1
	print(("  [OK]  " if ok else "  [HATA] ") + label + ("  -> " + detail if detail != "" else ""))

var mm
var pm
var cm
var gm

func cell(pid: int, pi: int, group: String) -> Array:
	var arr: PackedFloat32Array = cm.voter_base[pid]
	var i: int = cm._vb_i(pi, VoterGroups.GROUP_IDS.find(group), 0)
	return [arr[i], arr[i + 1], arr[i + 2]]

func total(pid: int, pi: int, group: String) -> float:
	var c := cell(pid, pi, group)
	return float(c[0]) + float(c[1]) + float(c[2])

func setc(pid: int, pi: int, group: String, l1: float, l2: float, l3: float) -> void:
	var arr: PackedFloat32Array = cm.voter_base[pid]
	var i: int = cm._vb_i(pi, VoterGroups.GROUP_IDS.find(group), 0)
	arr[i] = l1
	arr[i + 1] = l2
	arr[i + 2] = l3
	cm.voter_base[pid] = arr

func clear_all() -> void:
	for pid in cm.voter_base.keys():
		var arr: PackedFloat32Array = cm.voter_base[pid]
		arr.fill(0.0)
		cm.voter_base[pid] = arr

func run() -> void:
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	root.get_node("BotManager").set_process(false)
	mm.start_offline("Ben")
	for i in 2:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm.set_rng_seed(5)
	var me: int = mm.owner_id
	var ids: Array = cm.party_ids()
	var a: int = me
	var b: int = -1
	for pid in ids:
		if int(pid) != me:
			b = int(pid)
			break
	cm._vb_ensure()

	print("=== baslangic ===")
	var groups: Dictionary = pm.groups_of(a)
	check(absf(float(groups["isveren"]) - 10.0) < 1.5, "cekirdek grup ~%10 ile baslar", "%.2f" % groups["isveren"])

	print("=== miting: toplam sabit, odak bilesimi degistirir ===")
	var province: String = String(cm._province_ids[0])
	var pi: int = cm._vb_index[province]
	clear_all()
	var no_focus: Dictionary = cm._vb_miting(a, province, [], 1.0)
	var sum_plain := 0.0
	for g in no_focus:
		sum_plain += float(no_focus[g])
	clear_all()
	var with_focus: Dictionary = cm._vb_miting(a, province, ["emekli"], 1.0)
	var sum_focus := 0.0
	for g in with_focus:
		sum_focus += float(with_focus[g])
	check(absf(sum_plain - sum_focus) < sum_plain * 0.01, "odakli ve odaksiz mitingte cekilen toplam ayni", "%.0f / %.0f" % [sum_plain, sum_focus])
	check(float(with_focus["emekli"]) > float(no_focus["emekli"]) * 1.5 and float(with_focus["isci"]) < float(no_focus["isci"]), "odak emekliden daha cok, digerlerinden daha az ceker")

	print("=== once kismen kararsiz, sonra rakip ===")
	clear_all()
	var count: float = cm._vb_count(pi, VoterGroups.GROUP_IDS.find("emekli"))
	setc(b, pi, "emekli", count * 0.3, 0.0, 0.0)
	cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("emekli"), count * 0.1, cm.MITING_STEAL, cm.MITING_DEMOTE)
	var b_after := total(b, pi, "emekli")
	check(b_after < count * 0.3 and b_after > count * 0.3 - count * 0.1, "cekilenin bir kismi rakipten, bir kismi kararsizdan", "%.0f -> %.0f" % [count * 0.3, b_after])

	print("=== 3. seviye zor calinir, rakip baskisi seviye dusurur ===")
	clear_all()
	setc(b, pi, "emekli", 0.0, 0.0, count * 0.6)
	cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("emekli"), count * 0.2, cm.MITING_STEAL, cm.MITING_DEMOTE)
	var c3 := cell(b, pi, "emekli")
	check(total(b, pi, "emekli") > count * 0.57, "tek miting 3. seviyeden az secmen calar (cogunu yalniz dusurur)", "%.0f / %.0f / %.0f" % [c3[0], c3[1], c3[2]])
	# Gerçekçi odaklı miting: grubun ~%10'u, birkaç rakipten toplam 8 miting.
	for i in 8:
		cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("emekli"), count * 0.1, cm.MITING_STEAL, cm.MITING_DEMOTE)
	c3 = cell(b, pi, "emekli")
	check(float(c3[2]) < count * 0.2, "rakiplerin birkac mitingi 3. seviyeyi asagi ceker", "%.0f / %.0f / %.0f" % [c3[0], c3[1], c3[2]])
	clear_all()
	setc(b, pi, "emekli", 0.0, count * 0.5, 0.0)
	cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("emekli"), count * 0.2, cm.INVEST_STEAL, cm.INVEST_DEMOTE)
	var after_inv := total(b, pi, "emekli")
	setc(b, pi, "emekli", 0.0, count * 0.5, 0.0)
	setc(a, pi, "emekli", 0.0, 0.0, 0.0)
	cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("emekli"), count * 0.2, cm.MITING_STEAL, cm.MITING_DEMOTE)
	var after_mit := total(b, pi, "emekli")
	check(after_inv < after_mit, "yatirim 2. seviyeyi mitingten kolay calar", "yatirim %.0f, miting %.0f" % [after_inv, after_mit])

	print("=== zit grup ===")
	clear_all()
	setc(a, pi, "isci", count * 0.2, count * 0.2, 0.0)
	var isci_before := cell(a, pi, "isci")
	var got: float = cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("isveren"), count * 0.1, cm.MITING_STEAL, cm.MITING_DEMOTE)
	cm._vb_opposite_loss(a, pi, VoterGroups.GROUP_IDS.find("isveren"), got)
	var isci_after := cell(a, pi, "isci")
	# 0.0.268: seviye toplamı (1×L1 + 2×L2 + 3×L3) kazancın BİREBİR aynısı kadar
	# azalır; il büyüklüğü, teşkilat ve kriz oranı değiştirmez.
	var score_before := float(isci_before[0]) + 2.0 * float(isci_before[1]) + 3.0 * float(isci_before[2])
	var score_after := float(isci_after[0]) + 2.0 * float(isci_after[1]) + 3.0 * float(isci_after[2])
	check(got > 0.0 and absf((score_before - score_after) - got) < got * 0.01,
		"isverene kazanc kadar iscide seviye duser (birebir)", "kazanc %.0f, dusus %.0f" % [got, score_before - score_after])
	check(is_equal_approx(5.0 * cm.OPPOSITE_LOSS, 5.0), "5 isveren kazanilirsa 5 isci kaybedilir")
	# Siyasi kriz isverenin: kayıp yine birebir (istisna yok).
	clear_all()
	setc(a, pi, "isci", count * 0.2, count * 0.2, 0.0)
	cm.agenda = {"type": "kriz_isveren", "until": cm.round_number + 1}
	isci_before = cell(a, pi, "isci")
	got = cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("isveren"), count * 0.1, cm.MITING_STEAL, cm.MITING_DEMOTE)
	cm._vb_opposite_loss(a, pi, VoterGroups.GROUP_IDS.find("isveren"), got)
	isci_after = cell(a, pi, "isci")
	score_before = float(isci_before[0]) + 2.0 * float(isci_before[1]) + 3.0 * float(isci_before[2])
	score_after = float(isci_after[0]) + 2.0 * float(isci_after[1]) + 3.0 * float(isci_after[2])
	check(got > 0.0 and absf((score_before - score_after) - got) < got * 0.01,
		"krizde de zit gruptan kayip birebir", "kazanc %.0f, dusus %.0f" % [got, score_before - score_after])
	# Teşkilatlı ilde de kayıp birebir (kalkan zıt grup kaybına uygulanmaz).
	clear_all()
	cm.agenda = {}
	var prov := String(cm._province_ids[pi])
	var org_before = cm.organizations.get(prov, {}).duplicate()
	cm.organizations[prov] = {a: 2}
	setc(a, pi, "isveren", count * 0.2, count * 0.2, 0.0)
	var isv_before := cell(a, pi, "isveren")
	got = cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("isci"), count * 0.1, cm.MITING_STEAL, cm.MITING_DEMOTE)
	cm._vb_opposite_loss(a, pi, VoterGroups.GROUP_IDS.find("isci"), got)
	var isv_after := cell(a, pi, "isveren")
	var drop_full := (float(isv_before[0]) + 2.0 * float(isv_before[1])) - (float(isv_after[0]) + 2.0 * float(isv_after[1]))
	check(absf(drop_full - got) < got * 0.01, "teskilatli ilde de kayip birebir", "kazanc %.0f, dusus %.0f" % [got, drop_full])
	cm.organizations[prov] = org_before

	print("=== miting odagi ===")
	# Grup seçilse de seçilmese de ildeki seviye atlayan seçmen sayısı aynı
	# (çekilen toplamın aynılığı yukarıda sınanıyor); odak yalnız dağılımı değiştirir.
	clear_all()
	for g in VoterGroups.GROUP_IDS:
		setc(a, pi, g, count * 0.1, count * 0.05, 0.0)
	var promoted := []
	for focus in [[], ["isci"], ["emekli", "genc"]]:
		var shares: Array = cm.miting_promote_shares(a, pi, focus)
		var sum := 0.0
		for level in 2:
			for gi in 8:
				sum += float(cell(a, pi, VoterGroups.GROUP_IDS[gi])[level]) * float(shares[level][gi])
		promoted.append(sum)
	check(absf(promoted[1] - promoted[0]) < promoted[0] * 0.001 and absf(promoted[2] - promoted[0]) < promoted[0] * 0.001,
		"odakli ve odaksiz mitingde seviye atlayan secmen ayni", "odaksiz %.0f, isci %.0f, emekli+genc %.0f" % promoted)
	var focus_shares: Array = cm.miting_promote_shares(a, pi, ["isci"])
	check(float(focus_shares[0][0]) > float(focus_shares[0][1]), "odak grubu daha cok yukselir")

	print("=== il buyuklugu ===")
	var sizes: Array = []
	for i in cm._province_ids.size():
		sizes.append([cm.province_seat_count(String(cm._province_ids[i])), i])
	sizes.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	var small_pi: int = int(sizes[0][1])
	var big_pi: int = int(sizes[-1][1])
	check(cm.vb_size_factor(small_pi) < cm.vb_size_factor(big_pi), "kucuk ilin carpani kucuk, buyugunku buyuk",
		"%.2f / %.2f" % [cm.vb_size_factor(small_pi), cm.vb_size_factor(big_pi)])
	clear_all()
	var small_n: float = cm._vb_count(small_pi, 0)
	var big_n: float = cm._vb_count(big_pi, 0)
	var arr: PackedFloat32Array = cm.voter_base[a]
	arr[cm._vb_i(small_pi, 0, 0)] = small_n * 0.5
	arr[cm._vb_i(big_pi, 0, 0)] = big_n * 0.5
	cm.voter_base[a] = arr
	cm._vb_promote(a, small_pi, 0, 0.2, 0.0)
	cm._vb_promote(a, big_pi, 0, 0.2, 0.0)
	var small_up: float = cm.voter_base[a][cm._vb_i(small_pi, 0, 1)] / (small_n * 0.5)
	var big_up: float = cm.voter_base[a][cm._vb_i(big_pi, 0, 1)] / (big_n * 0.5)
	check(small_up > big_up, "kucuk ilde seviye atlamak daha hizli", "%.3f / %.3f" % [small_up, big_up])
	# Aynı oranda baskı: kalabalık ildeki 2. seviyenin daha büyük kısmı düşer.
	cm._vb_demote_own(a, small_pi, 0, small_n * 0.5 * 0.05, false)
	cm._vb_demote_own(a, big_pi, 0, big_n * 0.5 * 0.05, false)
	var small_ref: float = cm.voter_base[a][cm._vb_i(small_pi, 0, 1)] / (small_n * 0.5)
	var big_ref: float = cm.voter_base[a][cm._vb_i(big_pi, 0, 1)] / (big_n * 0.5)
	cm._vb_demote_own(a, small_pi, 0, small_n * 0.5 * 0.05)
	cm._vb_demote_own(a, big_pi, 0, big_n * 0.5 * 0.05)
	var small_left: float = cm.voter_base[a][cm._vb_i(small_pi, 0, 1)] / (small_n * 0.5)
	var big_left: float = cm.voter_base[a][cm._vb_i(big_pi, 0, 1)] / (big_n * 0.5)
	check((small_ref - small_left) / small_ref < (big_ref - big_left) / big_ref,
		"kalabalik ilde secmen daha kolay duser", "kucuk %.3f->%.3f, buyuk %.3f->%.3f" % [small_ref, small_left, big_ref, big_left])
	clear_all()
	setc(a, pi, "isci", 0.0, 0.0, count * 0.2)
	setc(a, pi, "isveren", 0.0, count * 0.2, 0.0)
	cm._vb_promote(a, pi, VoterGroups.GROUP_IDS.find("isveren"), 0.0, 0.5)
	check(float(cell(a, pi, "isci")[2]) == 0.0 and float(cell(a, pi, "isveren")[2]) > 0.0, "iki zit grupta ayni anda 3. seviye tutulamaz")

	print("=== skandal ===")
	clear_all()
	setc(b, pi, "emekli", count * 0.1, count * 0.1, count * 0.1)
	pm.politicians[b]["background"] = "sendikaci"
	cm._vb_scandal(b)
	var sc := cell(b, pi, "emekli")
	check(is_equal_approx(float(sc[0]), count * 0.1) and is_equal_approx(float(sc[1]), count * 0.1) and is_equal_approx(float(sc[2]), 0.0), "kaset butun secmeni bir seviye dusurur", str(sc))
	var other_pi: int = 1
	setc(b, other_pi, "emekli", count * 0.1, 0.0, 0.0)
	cm._vb_scandal(b, province)
	check(is_equal_approx(float(cell(b, other_pi, "emekli")[0]), count * 0.1), "karalama yalniz hedef ilde")
	clear_all()
	setc(b, pi, "emekli", 0.0, 0.0, count * 0.2)
	cm._vb_scandal(b, "", 0.5)
	check(absf(float(cell(b, pi, "emekli")[2]) - count * 0.1) < 1.0, "yarim skandal secmenin yarisini dusurur")

	print("=== ittifak ===")
	clear_all()
	setc(b, pi, "emekli", count * 0.5, 0.0, 0.0)
	cm.alliances = {1: {"name": "X", "color": Color.RED, "leader": a, "members": [a, b]}}
	cm._vb_pull(a, pi, VoterGroups.GROUP_IDS.find("emekli"), count * 0.2, cm.MITING_STEAL, cm.MITING_DEMOTE)
	check(is_equal_approx(total(b, pi, "emekli"), count * 0.5), "ortaklar birbirinden calmaz")
	cm.alliances = {}

	print("=== secim ===")
	clear_all()
	for g in VoterGroups.GROUP_IDS:
		setc(a, pi, String(g), cm._vb_count(pi, VoterGroups.GROUP_IDS.find(g)) * 0.5, 0.0, 0.0)
	var st: Dictionary = cm.vb_province_state(province)
	var shares: Dictionary = ElectionModel.voter_shares(st, cm._vb_parties(), {})
	check(float(shares[a]) > 0.5, "ildeki seçmenin yarisi bagli parti ilde ilk sirada", "%.2f" % shares[a])

	print("")
	print("SONUC: ", "TUM TESTLER GECTI" if fails == 0 else "%d HATA" % fails)
	quit(1 if fails > 0 else 0)
