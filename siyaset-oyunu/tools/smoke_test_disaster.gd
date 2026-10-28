extends SceneTree
## AFET testleri (yerel mod, RPC yok): bölge büyüklükleri ve komşuluk, tur
## sonunda bitiş, dönem sınırı (en fazla 2), afetsiz dönemden sonra garanti,
## YARDIM GÖTÜR (tutar serbest; devlet payı sadece hükümete, kota ve hazine
## sınırı; hemen gelen yerel ve ulusal etki; grup yakınlığına dokunmama;
## azalan getiri), durum kaydı/yükleme, botun yardım kararı.
##   godot --headless --path . --script res://tools/smoke_test_disaster.gd

var mm
var pm
var cm
var gm
var fails := 0
var D
var BB
var gmap

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

## 1 başbakan, 2 ortak, 3 muhalefet.
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
	cm.last_election_round = 1  # afet ilk seçimden sonra çıkar (kampanya dönemi afetsiz)
	gm.government = {"pm": 1, "deputy_pm": 2}
	gm.main_gov_peer_id = 1
	gm._set_phase(gm.Phase.GOVERNING)
	cm.funds = {1: 200.0, 2: 200.0, 3: 200.0}
	cm.agenda = {}
	cm.crisis = {}

func give_turn(peer_id: int) -> void:
	cm.current_turn_index = cm.turn_order.find(peer_id)

func connected(region: Array) -> bool:
	var seen := {String(region[0]): true}
	var stack: Array = [String(region[0])]
	var nb: Dictionary = gmap.neighbors()
	while not stack.is_empty():
		var p := String(stack.pop_back())
		for n in nb.get(p, []):
			if region.has(String(n)) and not seen.has(String(n)):
				seen[String(n)] = true
				stack.append(String(n))
	return seen.size() == region.size()

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	D = load("res://scripts/disaster.gd")
	BB = load("res://scripts/bot_brain.gd")
	gmap = root.get_node("GameMap")
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	GameRules.configure(8, 12)

	print("=== 1) BÖLGELER ===")
	new_game()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ids: Array = gmap.province_ids()
	var sizes_ok := true
	var connected_ok := true
	for kind in D.KINDS:
		for i in 40:
			var region: Array = D.pick_region(kind, rng, ids)
			var lim: Array = D.SIZES[kind]
			if region.size() < int(lim[0]) or region.size() > int(lim[1]):
				# Komşusu az bir ilde bölge küçük kalabilir; en az 1 il şart.
				if region.is_empty() or region.size() > int(lim[1]):
					sizes_ok = false
			if not connected(region):
				connected_ok = false
	check("bölge büyüklükleri (sel/kayma/çığ 1, yangın 2-3, deprem 3-5)", sizes_ok)
	check("bölgeler komşu illerden oluşur", connected_ok)
	var quake_sizes := {}
	for i in 60:
		quake_sizes[D.pick_region("deprem", rng, ids).size()] = true
	check("deprem çoğunlukla birkaç il", quake_sizes.has(3) or quake_sizes.has(4) or quake_sizes.has(5), str(quake_sizes.keys()))

	print("=== 2) YARDIM ===")
	new_game()
	give_turn(3)
	check("afet yokken yardım yapılamaz", not cm.can_aid(3))
	var region: Array = cm.start_disaster("deprem")
	check("afet başladı", cm.has_disaster() and region.size() >= 1, str(region))
	check("afet logu ve gazete bilgisi hazır", not cm._pending_disaster_fx.is_empty())
	check("muhalefet devletten ödeyemez", not cm.can_aid(3, 0.0, 20.0)
		and cm.aid_block_reason(3, 0.0, 20.0).contains("kasa"))
	check("en az 5 milyon", not cm.can_aid(3, 0.0, 0.0) and not cm.can_aid(3, 3.0, 0.0))
	check("5 milyon adımı", not cm.can_aid(3, 12.0, 0.0))
	var before_by: Dictionary = {}
	for province_id in region:
		before_by[province_id] = cm.voter_total(3, String(province_id))
	var outside: String = ""
	for province_id in cm._province_ids:
		if not region.has(province_id):
			outside = String(province_id)
			break
	var outside_before: float = cm.voter_total(3, outside)
	cm._apply_aid_move(3, 40.0, 0.0)
	var gain: float = cm.voter_total(3, String(region[0])) - float(before_by[region[0]])
	check("yardım kasadan düşer", is_equal_approx(cm.funds_of(3), 160.0), str(cm.funds_of(3)))
	check("afetteki ilde seçmen hemen artar", gain > 0.0, "+%.2f" % gain)
	var all_up := true
	for province_id in region:
		if cm.voter_total(3, String(province_id)) <= float(before_by[province_id]):
			all_up = false
	check("bütün afet illerine düşer", all_up)
	check("ülke genelinde de seçmen kazanır", cm.voter_total(3, outside) > outside_before)
	var first_points: float = D.local_gain(0.0, 40.0, region.size())
	var second: float = D.local_gain(40.0, 80.0, region.size())
	check("aynı afete ikinci yardım daha az getirir", second < first_points, "%.2f < %.2f" % [second, first_points])
	give_turn(1)
	var treasury: float = cm.state_treasury()
	var quota: float = cm.state_quota(1)
	check("hükümet de devletten ödeyemez (0.0.238: hazine yalnız yatırım)", not cm.can_aid(1, 0.0, 30.0))
	cm._apply_aid_move(1, 0.0, 30.0)
	check("devletten yardım denemesi hazineye ve kotaya dokunmaz", is_equal_approx(cm.state_treasury(), treasury) and is_equal_approx(cm.state_quota(1), quota))
	give_turn(2)
	check("sıra başkasındayken yardım yok", not cm.can_aid(3, 10.0, 0.0))

	print("=== 3) KAYIT ===")
	var packed: Dictionary = cm._pack_state(false)
	var aid_before: Dictionary = (cm.active_disaster()["aid"] as Dictionary).duplicate()
	cm.disaster = {}
	cm._apply_state(packed)
	check("afet ve yardımlar durumla taşınır", cm.has_disaster() and cm.active_disaster()["aid"] == aid_before)

	print("=== 4) TUR SONU VE DÖNEM ===")
	cm._end_disaster()
	check("tur bitince afet sona erer", not cm.has_disaster())
	# Dönem sınırı: 2 afetten sonra zar atılmaz.
	cm.disaster["term_count"] = 2
	var spawned := false
	for i in 50:
		cm._roll_disaster()
		if cm.has_disaster():
			spawned = true
			break
	check("dönemde en fazla 2 afet", not spawned)
	# Afetsiz dönem → sonraki dönem garanti (son turda kesin).
	cm.disaster = {"term_count": 0}
	cm._disaster_new_term()
	check("afetsiz dönemden sonra borç", bool(cm.disaster.get("owed", false)))
	var last_round := 1
	while not GameRules.is_election_round(last_round):
		last_round += 1
	cm.round_number = last_round
	var old_chance: float = D.ROUND_CHANCE
	cm._rng.seed = 7
	# Şans ne olursa olsun son turda çıkar: 30 kez dene, hepsi çıkmalı.
	var forced_ok := true
	for i in 30:
		cm.disaster = {"term_count": 0, "owed": true}
		cm._roll_disaster()
		if not cm.has_disaster():
			forced_ok = false
	check("garanti: dönemin son turunda afet kesin çıkar", forced_ok)
	cm.disaster = {"term_count": 1, "owed": false}
	cm._disaster_new_term()
	check("afetli dönemden sonra borç yok", not bool(cm.disaster.get("owed", true)))
	# Sıklık: 4 turluk 2000 dönemde ortalama ~1, hiçbiri 2'yi aşmaz.
	var total := 0
	var over := false
	var sim := RandomNumberGenerator.new()
	sim.seed = 99
	for term in 2000:
		var n := 0
		for r in 4:
			if n < D.TERM_MAX and sim.randf() < D.ROUND_CHANCE:
				n += 1
		total += n
		over = over or n > D.TERM_MAX
	check("dönem başına ortalama ~1 afet (4 turluk dönem)", total / 2000.0 > 0.7 and total / 2000.0 < 1.2, "%.2f" % (total / 2000.0))
	check("hiçbir dönem 2'yi aşmaz", not over)
	print("  (ROUND_CHANCE %.2f)" % old_chance)

	print("=== 5) BOT ===")
	new_game()
	cm.start_disaster("sel")
	give_turn(3)
	var plan: Dictionary = BB.eval_aid(3)
	check("bot yardım planı yapar", not plan.is_empty() and float(plan["party"]) + float(plan["state"]) >= D.AID_MIN, str(plan))
	give_turn(1)
	var gov_plan: Dictionary = BB.eval_aid(1)
	check("hükümetteki bot da yalnız kasadan öder", not gov_plan.is_empty() and is_equal_approx(float(gov_plan["state"]), 0.0), str(gov_plan))
	cm._apply_aid_move(1, float(gov_plan["party"]), float(gov_plan["state"]))
	check("aynı afete ikinci kez plan yapmaz", BB.eval_aid(1).is_empty())

	print("")
	if fails == 0:
		print("AFET TESTLERİ: HEPSİ GEÇTİ")
	else:
		print("AFET TESTLERİ: %d HATA" % fails)
	quit(1 if fails > 0 else 0)
