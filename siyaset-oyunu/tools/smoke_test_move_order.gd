extends SceneTree
## HAMLE SIRASI TESTİ (0.0.187): seçimden önceki son turda miting
## ve kaset hamlelerinin sırası sonucu değiştiriyor mu? Her senaryo aynı
## başlangıçtan (aynı tohum) kurulur, hamleler GERÇEK oyun kodundan
## (_apply_miting_move, _apply_play) uygulanır, sonra tur biter ve seçim yapılır.
##   godot --headless --path . --script res://tools/smoke_test_move_order.gd

var mm
var pm
var cm
var gm
var P := ""      # mitinglerin yapıldığı il
const A := 1
const B := 2
const C := 3

func new_game(seed_value: int) -> void:
	mm.players = {}
	pm.parties = {}
	var cores := {A: ["emekli", "dindar"], B: ["genc", "ilerici"], C: ["isci", "milliyetci"]}
	for peer_id in cores.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%s" % ["", "A", "B", "C"][peer_id], "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.3, 0.5, 0.7), "groups": VoterGroups.start_affinities(cores[peer_id]), "ready": true,
		}
	# Tohum init_game'den ÖNCE: il seçmen profilleri _rng ile üretilir.
	cm.set_rng_seed(seed_value)
	cm.init_game()
	cm.set_rng_seed(seed_value)
	cm.turn_order = [A, B, C]
	cm.current_turn_index = 0
	GameRules.configure(2, 5)           # seçim turları 4, 8, ...
	cm.round_number = 8                 # bu turun SONUNDA seçim var
	cm.last_election_round = 4
	cm.last_seats = {A: 170, B: 170, C: 160}
	cm.election_seats = cm.last_seats.duplicate()
	gm.government = {"pm": A, "deputy_pm": C}
	gm.main_gov_peer_id = A
	gm._set_phase(gm.Phase.GOVERNING)
	cm.funds = {A: 200.0, B: 200.0, C: 200.0}
	cm.agenda = {}
	cm.crisis = {}
	for pid in [A, B, C]:
		cm.organizations[P] = cm.organizations.get(P, {})
		cm.organizations[P][pid] = 2
		cm.inventories[pid] = [CardPresets.REPUTATION_CARD_TYPE, CardPresets.REPUTATION_CARD_TYPE]

func act(step: Array) -> void:
	var who: int = step[1]
	cm.current_turn_index = cm.turn_order.find(who)
	match String(step[0]):
		"miting":
			cm._apply_miting_move(who, P)
		"kaset":
			cm._apply_play(who, 0, int(step[2]))
		"teskilat":
			cm._apply_organization(who, String(step[2]))

func snapshot() -> Dictionary:
	var s := {}
	for pid in [A, B, C]:
		s[pid] = {"nat": cm.voter_total(pid), "loc": cm.voter_total(pid, P), "turmoil": cm.turmoil_of(pid),
			"groups": (pm.parties[pid]["groups"] as Dictionary).duplicate(), "funds": cm.funds_of(pid)}
	s["rng"] = cm._rng.state
	return s

## Senaryoyu çalıştırır: hamleler → (seçim öncesi) anlık durum → tur sonu ve seçim.
func run(label: String, steps: Array, setup: Callable = Callable(), seed_value: int = 777) -> Dictionary:
	new_game(seed_value)
	if setup.is_valid():
		setup.call()
	for step in steps:
		act(step)
	var pre := snapshot()
	var parties_before: int = cm.party_ids().size()
	cm._finish_round()
	var out := {"label": label, "pre": pre, "votes": cm.last_vote_shares.duplicate(), "seats": cm.last_seats.duplicate(),
		"split": cm.party_ids().size() != parties_before, "turmoil_after": {A: cm.turmoil_of(A), B: cm.turmoil_of(B), C: cm.turmoil_of(C)}}
	return out

func fmt(r: Dictionary) -> String:
	var p: Dictionary = r["pre"]
	var lines := "  %s\n" % r["label"]
	for pid in [A, B, C]:
		var d: Dictionary = p[pid]
		lines += "    %s  ulusal %+6.2f  il %+6.2f  karışıklık %.2f  emekli %.2f genç %.2f  | oy %%%.3f  vekil %d\n" % [
			["", "A", "B", "C"][pid], d["nat"], d["loc"], d["turmoil"], float(d["groups"]["emekli"]), float(d["groups"]["genc"]),
			float(r["votes"].get(pid, 0.0)), int(r["seats"].get(pid, 0))]
	lines += "    bölünme: %s" % r["split"]
	return lines

## 0.0.228 SEÇMEN TABANI: seçmen çalma sıraya bağlıdır (önce gelen kararsızları
## alır), tam eşitlik artık beklenmez. Sıra sonucu KÜÇÜK oynatabilir: oy farkı
## ORDER_VOTE_TOL puandan, vekil farkı ORDER_SEAT_TOL'dan az olmalı;
## karışıklık, kasa ve bölünme birebir aynı.
const ORDER_VOTE_TOL := 0.5
const ORDER_SEAT_TOL := 3
func same(a: Dictionary, b: Dictionary) -> bool:
	for pid in [A, B, C]:
		if absf(float(a["votes"].get(pid, 0.0)) - float(b["votes"].get(pid, 0.0))) > ORDER_VOTE_TOL:
			return false
		if absi(int(a["seats"].get(pid, 0)) - int(b["seats"].get(pid, 0))) > ORDER_SEAT_TOL:
			return false
		var da: Dictionary = a["pre"][pid]
		var db: Dictionary = b["pre"][pid]
		for k in ["turmoil", "funds"]:
			if not is_equal_approx(float(da[k]), float(db[k])):
				return false
		# 0.0.284: seçmen tabanı sıraya duyarlı (kaset o anki seçmenin bir
		# kısmını düşürür); ölçüt sandık sonucu (oy ve vekil toleransı).
	return a.get("split", false) == b.get("split", false)

func diff_line(a: Dictionary, b: Dictionary) -> String:
	var parts: PackedStringArray = []
	for pid in [A, B, C]:
		var da: Dictionary = a["pre"][pid]
		var db: Dictionary = b["pre"][pid]
		for k in ["nat", "loc", "turmoil"]:
			if not is_equal_approx(float(da[k]), float(db[k])):
				parts.append("%s.%s %.3f / %.3f" % [["", "A", "B", "C"][pid], k, da[k], db[k]])
		if str(da["groups"]) != str(db["groups"]):
			parts.append("%s.grup yakınlıkları farklı" % ["", "A", "B", "C"][pid])
		var va := float(a["votes"].get(pid, 0.0))
		var vb := float(b["votes"].get(pid, 0.0))
		if absf(va - vb) > 1e-9:
			parts.append("%s.oy %.4f / %.4f (Δ %.4f)" % [["", "A", "B", "C"][pid], va, vb, vb - va])
		if int(a["seats"].get(pid, 0)) != int(b["seats"].get(pid, 0)):
			parts.append("%s.vekil %d / %d" % [["", "A", "B", "C"][pid], a["seats"].get(pid, 0), b["seats"].get(pid, 0)])
	if a["pre"]["rng"] != b["pre"]["rng"]:
		parts.append("RNG durumu farklı")
	return "BİREBİR AYNI" if parts.is_empty() else ", ".join(parts)

func _initialize() -> void:
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	root.get_node("BotManager").set_process(false)
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	var ids: Array = root.get_node("GameMap").province_ids()
	# Mitingin yapılacağı il: her üç partinin provokasyon riski 0 olan ilk il.
	new_game(777)
	for id in ids:
		P = String(id)
		new_game(777)
		if cm.miting_risk(A, P) == 0.0 and cm.miting_risk(B, P) == 0.0 and cm.miting_risk(C, P) == 0.0:
			break
	new_game(777)
	print("İl: %s  (provokasyon riski A %.2f, B %.2f, C %.2f)" % [P, cm.miting_risk(A, P), cm.miting_risk(B, P), cm.miting_risk(C, P)])
	print("Sabitler: kaset seviye düşürme %%%.0f + ülke geneli −%.1f puan, karışıklık: kaset +%.1f / miting −%.1f (0'ın altına inmez), bölünme eşiği %.1f" % [
		PublicOpinion.KASET_DEMOTE * 100.0, PublicOpinion.REPUTATION_NATIONAL_DAMAGE, PublicOpinion.TURMOIL_REPUTATION,
		PublicOpinion.TURMOIL_EASE_MITING, PublicOpinion.SPLIT_TURMOIL])

	print("\n=== 0) KONTROL: aynı senaryo üç kez ===")
	for i in 3:
		new_game(777)
		print("  başlangıç: il profili %s, yorgunluk %s, A emekli %.2f, ildeki seçmen %.2f" % [str(cm.province_profile(P)), str(cm.miting_fatigue), float(pm.parties[A]["groups"]["emekli"]), cm.voter_total(A, P)])
		var k := run("kontrol", [["miting", A], ["kaset", B, A]])
		print("  sonuç: A emekli %.3f, A oy %.4f, vekil %s" % [float(k["pre"][A]["groups"]["emekli"]), float(k["votes"][A]), str(k["seats"])])
	print("\n=== 0b) ÇAPRAZ KONTROL: S1, S1', S1, S1' ===")
	var x1 := run("S1", [["miting", A], ["kaset", B, A]])
	var x2 := run("S1'", [["kaset", B, A], ["miting", A]])
	var x3 := run("S1", [["miting", A], ["kaset", B, A]])
	var x4 := run("S1'", [["kaset", B, A], ["miting", A]])
	print("  S1 (1.) / S1 (3.): " + diff_line(x1, x3))
	print("  S1' (2.) / S1' (4.): " + diff_line(x2, x4))
	print("  S1 (3.) / S1' (4.): " + diff_line(x3, x4))
	print("\n=== 1) İSTENEN İKİ SENARYO ===")
	var s1 := run("S1: A miting → B, A'ya kaset", [["miting", A], ["kaset", B, A]])
	var s2 := run("S2: B miting → A, B'ye kaset", [["miting", B], ["kaset", A, B]])
	print(fmt(s1)); print(fmt(s2))
	print("  S1 ile S2 (aynı hamleler, roller ters): " + diff_line(s1, s2))

	print("\n=== 2) AYNI HAMLELER, SIRA TERS ===")
	var s1r := run("S1': B, A'ya kaset → A miting", [["kaset", B, A], ["miting", A]])
	var s2r := run("S2': A, B'ye kaset → B miting", [["kaset", A, B], ["miting", B]])
	print(fmt(s1r)); print(fmt(s2r))
	print("  S1 / S1': " + diff_line(s1, s1r))
	print("  S2 / S2': " + diff_line(s2, s2r))

	var q := String(ids[min(5, ids.size() - 1)])
	var o1 := run("A teşkilat → B, A'ya kaset", [["teskilat", A, q], ["kaset", B, A]])
	var o2 := run("B, A'ya kaset → A teşkilat", [["kaset", B, A], ["teskilat", A, q]])
	print("  teşkilat / kaset, sıra ters: " + diff_line(o1, o2))
	var m1 := run("A miting + teşkilat → kaset", [["miting", A], ["teskilat", A, q], ["kaset", B, A]])
	var m2 := run("kaset → A teşkilat + miting", [["kaset", B, A], ["teskilat", A, q], ["miting", A]])
	print("  miting + teşkilat / kaset, sıra ters: " + diff_line(m1, m2))
	print("\n=== 3) ÜÇ OYUNCU, BÜTÜN SIRALAR (A miting, B→A kaset, C miting) ===")
	var moves := [["miting", A], ["kaset", B, A], ["miting", C]]
	var perms := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	var base := {}
	for perm in perms:
		var steps: Array = []
		var names: PackedStringArray = []
		for i in perm:
			steps.append(moves[i])
			names.append(["A miting", "B→A kaset", "C miting"][i])
		var r := run(" → ".join(names), steps)
		if base.is_empty():
			base = r
			print("  %s (temel)" % r["label"])
		else:
			print("  %s : %s" % [r["label"], diff_line(base, r)])

	print("\n=== 4) UÇ DURUMLAR ===")
	# a) Karışıklık 0'dayken: miting azaltacak bir şey bulamaz.
	var t0a := run("karışıklık 0: A miting → kaset", [["miting", A], ["kaset", B, A]])
	var t0b := run("karışıklık 0: kaset → A miting", [["kaset", B, A], ["miting", A]])
	print("  a) A karışıklığı başta 0:  önce miting %.2f, önce kaset %.2f  → %s" % [
		t0a["pre"][A]["turmoil"], t0b["pre"][A]["turmoil"], diff_line(t0a, t0b)])
	# b) Karışıklık bölünme eşiğinin hemen altında (5,6 + 1,5 = 7,1).
	var near := func(): cm.turmoil[A] = 5.6
	var t1a := run("eşik: A miting → kaset", [["miting", A], ["kaset", B, A]], near)
	var t1b := run("eşik: kaset → A miting", [["kaset", B, A], ["miting", A]], near)
	print("  b) A karışıklığı 5,6 (eşik 7,0):  önce miting → %.2f, bölünme %s;  önce kaset → %.2f, bölünme %s" % [
		t1a["pre"][A]["turmoil"], t1a["split"], t1b["pre"][A]["turmoil"], t1b["split"]])
	print("     " + diff_line(t1a, t1b))
	# e) Provokasyon riski olan il: zarı hangi miting atıyor?
	var risky := ""
	for id in ids:
		new_game(777)
		var r1: float = cm.miting_risk(A, String(id))
		var r2: float = cm.miting_risk(C, String(id))
		if r1 > 0.05:
			risky = String(id)
			break
	if risky != "":
		var keep := P
		P = risky
		new_game(777)
		print("  e) Riskli il %s (A riski %.2f, C riski %.2f): iki miting, sıra ters, birkaç tohum" % [P, cm.miting_risk(A, P), cm.miting_risk(C, P)])
		var differ := 0
		for seed_value in range(1, 41):
			var e1 := run("A → C", [["miting", A], ["miting", C]], Callable(), seed_value)
			var e2 := run("C → A", [["miting", C], ["miting", A]], Callable(), seed_value)
			var line := diff_line(e1, e2)
			if line != "BİREBİR AYNI":
				differ += 1
				if differ <= 3:
					print("     tohum %d: %s" % [seed_value, line])
		print("     40 tohumdan %d tanesinde sonuç sıraya göre değişti" % differ)
		# Aynı risk, kaset araya girince: kaset RNG kullanmaz.
		var k1 := run("A miting → B→A kaset", [["miting", A], ["kaset", B, A]], Callable(), 3)
		var k2 := run("B→A kaset → A miting", [["kaset", B, A], ["miting", A]], Callable(), 3)
		print("     riskli ilde miting+kaset, sıra ters: " + diff_line(k1, k2))
		P = keep
	print("\n=== ÖZET ===")
	var fails := 0
	for pair in [["S1 / S1'", s1, s1r], ["S2 / S2'", s2, s2r], ["teşkilat / kaset", o1, o2], ["miting+teşkilat / kaset", m1, m2],
			["karışıklık 0", t0a, t0b], ["eşik", t1a, t1b]]:
		var ok := same(pair[1], pair[2])
		if not ok:
			fails += 1
		print("  %s hamle sırası sonucu yalnız az oynatır: %s" % ["[OK] " if ok else "[HATA]", pair[0]])
	print("=== TUM TESTLER GECTI ===" if fails == 0 else "=== %d TEST BASARISIZ ===" % fails)
	quit(1 if fails > 0 else 0)
