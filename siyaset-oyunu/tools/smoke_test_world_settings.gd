extends SceneTree
var fails := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
	print(("[OK] " if ok else "[HATA] ") + label)
func run() -> void:
	var gen = load("res://scripts/country_generator.gd")
	var groups = load("res://scripts/voter_groups.gd")
	var model = load("res://scripts/election_model.gd")
	var mm = root.get_node("MultiplayerManager")
	var totals := [0, 0, 0]
	for seed_value in range(1, 11):
		var counts := []
		for scale in [0.75, 1.0, 1.25]:
			var map: Dictionary = gen.generate(seed_value, scale, 150)
			var seats := 0
			for region in map["regions"]:
				seats += int(region["seats"])
			# 0.0.269: il başına en az 3 vekil; toplam yetmezse il başına 3 verilir.
			var expected := maxi(150, 3 * (map["regions"] as Array).size())
			check(seats == expected, "seat conservation seed %d scale %.2f (%d / %d)" % [seed_value, scale, seats, expected])
			var min_ok := true
			for region in map["regions"]:
				min_ok = min_ok and int(region["seats"]) >= 3
			check(min_ok, "her ilde en az 3 vekil seed %d scale %.2f" % [seed_value, scale])
			counts.append(map["regions"].size())
		for i in 3:
			totals[i] += int(counts[i])
		check(counts[0] < counts[1] and counts[1] < counts[2], "ordered province counts seed %d" % seed_value)
	print("mean province counts: ", totals[0]/10.0, " / ", totals[1]/10.0, " / ", totals[2]/10.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var profiles: Dictionary = groups.generate_profiles(rng, ["small", "metro"], {"small": 3, "metro": 40}, {"small": 300000, "metro": 4000000})
	for id in profiles:
		for pair in groups.PAIR_IDS:
			var pair_groups: Array = groups.PAIRS[pair]
			check(int(profiles[id]["_counts"][pair_groups[0]]) + int(profiles[id]["_counts"][pair_groups[1]]) == int(profiles[id]["_electorate"]), "numeric cohort conservation " + id + ":" + pair)
	var party_groups := {1: groups.start_affinities(["emekli", "dindar"]), 2: groups.neutral_affinities()}
	var affinity := party_groups[1] as Dictionary
	affinity["emekli"] = 90.0
	var votes: Dictionary = model.shares_in_group(party_groups, "emekli")
	check(float(votes[1]) > 0.9, "targeted party captures retired electorate")
	mm._apply_world_settings({"province_scale": 0.75, "province_seats": 150, "national_seats": 0, "turn_seconds": 60})
	var outcome: Dictionary = model.compute(party_groups, {"small": 50, "metro": 100}, profiles, 0.0, rng)
	var seat_sum := 0
	for value in outcome["seats"].values():
		seat_sum += int(value)
	check(seat_sum == 150, "zero national list and total seats")
	check(model.NATIONAL_LIST_SEATS == 0, "national list setting")
	var rules = load("res://scripts/game_rules.gd")
	check(rules.TURN_TIMEOUT == 60.0, "turn timeout setting")
	mm._apply_world_settings({"turn_seconds": 30, "action_limit": 7})
	check(int(mm.world_settings["turn_seconds"]) == 90 and int(mm.world_settings["action_limit"]) == 5, "old out-of-range values fall back to defaults")
	rules.configure(1, 5)
	check(rules.ELECTION_INTERVAL == 3, "0.0.300: elections at least every 1.5 years")
	rules.configure(2.5, 5)
	check(rules.ELECTION_INTERVAL == 5 and rules.MAX_ROUNDS == 25, "half-year election interval (2.5 years = 5 rounds)")
	check(is_equal_approx(rules.snap_interval(2.3), 2.5) and is_equal_approx(rules.snap_interval(0.2), 1.5), "interval snaps to half years")
	rules.configure(1, 5)
	mm._apply_world_settings(mm.WORLD_DEFAULTS)
	quit(1 if fails else 0)
