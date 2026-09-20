extends SceneTree
## Seçim gecesi canlı sayım simülasyonu testi.
##   godot --headless --script res://tools/smoke_test_election_night.gd

var _fails := 0

func _check(ok: bool, text: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + text)
	if not ok:
		_fails += 1

func _initialize() -> void:
	var sim_script = load("res://scripts/election_night_sim.gd")
	var model = load("res://scripts/election_model.gd")
	var seats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/province_seats.json"))
	var parties := {
		1: {"economic": 1, "social": 1, "administrative": 2},
		2: {"economic": -2, "social": -1, "administrative": 1},
		3: {"economic": 1, "social": 2, "administrative": 2},
		4: {"economic": 2, "social": -2, "administrative": -1},
		5: {"economic": -1, "social": -2, "administrative": -2},
		6: {"economic": -1, "social": 2, "administrative": -2},
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var res: Dictionary = model.compute(parties, seats, model.load_province_voters(), 7.0, 1.0, rng)
	var sim = sim_script.new()
	sim.setup(res["province_results"], res["vote_shares"], res["seats"], res["passed_threshold"], 7.0, 12345, 45.0)

	print("--- sayım ---")
	_check(float(sim.sample(0.0)["counted"]) == 0.0, "başta hiç sandık açık değil")
	var prev := -1.0
	var monotonic := true
	var sums_ok := true
	for i in 91:
		var s: Dictionary = sim.sample(i * 0.5)
		var counted := float(s["counted"])
		if counted + 0.0001 < prev:
			monotonic = false
		prev = counted
		if counted > 0.0:
			var total := 0.0
			for v in s["national"].values():
				total += float(v)
			if absf(total - 100.0) > 0.01:
				sums_ok = false
	_check(monotonic, "açılan sandık oranı hiç geri gitmiyor")
	_check(sums_ok, "ulusal oranların toplamı her karede 100")
	var mid: Dictionary = sim.sample(20.0)
	_check(float(mid["counted"]) > 10.0 and float(mid["counted"]) < 90.0, "20. saniyede sayım yarıda (%.1f)" % float(mid["counted"]))

	# Açılmış ama bitmemiş bir il, sonraki anlarda değişmeye devam etmeli.
	var moving := false
	for province_id in sim.province_ids:
		var c := float(sim.progress(province_id, 15.0))
		if c > 0.0 and c < 0.9:
			var a: Dictionary = sim.province_shares(province_id, 15.0, c)
			var b: Dictionary = sim.province_shares(province_id, 16.0, float(sim.progress(province_id, 16.0)))
			for peer_id in a.keys():
				if absf(float(a[peer_id]) - float(b[peer_id])) > 0.05:
					moving = true
	_check(moving, "açılmış iller sayım sürerken değişmeye devam ediyor")

	print("--- kesin sonuç ---")
	var near: Dictionary = sim.sample(44.99)
	var final: Dictionary = sim.sample(45.0)
	var seats_match := true
	var near_match := true
	for peer_id in res["seats"].keys():
		if int(final["seats"][peer_id]) != int(res["seats"][peer_id]):
			seats_match = false
		if int(near["seats"][peer_id]) != int(res["seats"][peer_id]):
			near_match = false
	_check(seats_match, "son karede vekiller kesin sonuçla aynı")
	_check(near_match, "son kareden hemen önce de aynı (atlama yok)")
	_check(float(near["counted"]) > 99.99, "süre bitmeden tüm sandıklar açılmış")

	var sim2 = sim_script.new()
	sim2.setup(res["province_results"], res["vote_shares"], res["seats"], res["passed_threshold"], 7.0, 12345, 45.0)
	_check(str(sim2.sample(20.0)["national"]) == str(mid["national"]), "aynı tohum her istemcide aynı geceyi üretir")

	print("=== ELECTION NIGHT TEST: %s ===" % ("PASS" if _fails == 0 else "%d FAIL" % _fails))
	quit(1 if _fails > 0 else 0)
