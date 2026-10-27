extends SceneTree
## Deterministic output fixture. Run on the reference and optimized projects:
## PERF_FIXTURE=<absolute .save> to write; PERF_COMPARE=<same .save> to compare.
var _fails := 0
var _fixtures: Array = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	await process_frame
	var cm = root.get_node("CardManager")
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var gm = root.get_node("GovernmentManager")
	var brain = load("res://scripts/bot_brain.gd")
	root.get_node("BotManager").set_process(false)
	cm.set_process(false)
	gm.set_process(false)
	brain.skill_variance = false
	for mode in ["random", "turkiye_altigen"]:
		for method in ["dhondt", "hare", "wta"]:
			seed(925731)
			cm.set_rng_seed(925731)
			cm.fixed_map_seed = 1950
			cm.allow_temporary_parties = false
			mm.room_code = ""
			mm.players = {}
			pm.parties = {}
			pm.politicians = {}
			mm.world_settings["map_mode"] = mode
			mm.seat_method = method
			ElectionModel.seat_method = method
			mm.stage = mm.Stage.PARTY_SETUP
			for i in 8:
				var pid: int = mm.BOT_ID_BASE - i
				mm.players[pid] = {"name": "Bot %d" % i, "bot": true}
				pm.add_bot_party(pid)
			cm.init_game()
			var data := {"map": root.get_node("GameMap").data.duplicate(true)}
			var polls := []
			for pid in cm.party_ids():
				for province in cm._province_ids.slice(0, 3):
					cm.organizations[province] = {pid: 2}
					polls.append(cm.province_poll(pid, province))
			data["polls"] = polls
			data["projection"] = cm.projection_all()
			data["voters"] = cm.vb_election_state()
			var actions := []
			for pid in cm.party_ids():
				actions.append(brain.choose_action(pid))
				actions.append(brain.choose_play(pid))
			data["actions"] = actions
			cm._hold_election(1, false)
			data["result"] = [cm.last_vote_shares.duplicate(true), cm.last_seats.duplicate(true), cm.last_province_results.duplicate(true)]
			var sim = load("res://scripts/election_night_sim.gd").new()
			sim.setup(cm.last_province_results, cm.last_vote_shares, cm.last_seats, cm.passed_threshold, mm.election_threshold, 12345, 45.0)
			var samples := []
			for t in [0.0, 0.1, 5.0, 10.0, 20.0, 30.0, 40.0, 44.99, 45.0, 46.0, 15.0, 40.0]:
				samples.append(sim.sample(t).duplicate(true))
			data["samples"] = samples
			_fixtures.append(data)
			if cm.has_method("_state_delta"):
				var before: Dictionary = cm._pack_state(false).duplicate(true)
				cm.state_version += 1
				cm.funds[cm.party_ids()[0]] = 88.0
				var after: Dictionary = cm._pack_state(false).duplicate(true)
				var delta: Dictionary = cm._state_delta(after, before)
				var restored := before.duplicate(true)
				restored.merge(delta, true)
				_check(restored == after, "%s/%s delta reconstructs full state" % [mode, method])
				_check(not delta.has("voter_base") and not delta.has("province_profiles"), "unchanged large fields omitted")
				print("STATE BYTES full=%d delta=%d" % [var_to_bytes(after).size(), var_to_bytes(delta).size()])
	var output := OS.get_environment("PERF_FIXTURE")
	if output != "":
		var f := FileAccess.open(output, FileAccess.WRITE)
		f.store_var(_fixtures)
		f.close()
	var compare := OS.get_environment("PERF_COMPARE")
	if compare != "":
		var f := FileAccess.open(compare, FileAccess.READ)
		var expected: Array = f.get_var()
		f.close()
		_check(expected.size() == _fixtures.size(), "fixture count")
		for i in mini(expected.size(), _fixtures.size()):
			for key in _fixtures[i]:
				_check(expected[i][key] == _fixtures[i][key], "scenario %d: %s unchanged" % [i, key])
	if cm.has_method("_state_delta"):
		var peer = load("res://scripts/relay_multiplayer_peer.gd").new()
		for i in 4096:
			peer._incoming.append({"sender": i + 1, "data": PackedByteArray([i % 256])})
		for i in 4096:
			if peer._get_packet_peer() != i + 1 or peer._get_packet_script() != PackedByteArray([i % 256]):
				_check(false, "packet FIFO at %d" % i)
				break
		_check(peer._get_available_packet_count() == 0 and peer._get_packet_peer() == 0, "4096 relay packets preserve sender and order")
	print("PERFORMANCE REGRESSION: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(1 if _fails else 0)
