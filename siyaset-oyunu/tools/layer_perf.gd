extends SceneTree
## Harita katmanı geçişinde kare süreleri (ms): takılma var mı?
##   godot --path . --script res://tools/layer_perf.gd

func _t(label: String, f: Callable, n: int = 5) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call()
	print("%-34s %7.2f ms" % [label, (Time.get_ticks_usec() - t0) / 1000.0 / n])

func _initialize() -> void:
	await process_frame
	seed(4242)
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	root.get_node("BotManager").set_process(false)
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	cm.set_rng_seed(4242)
	mm.start_offline("Barış")
	for i in 7:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 60:
		await process_frame
	for layer in [1, 2, 3, 0, 1, 2, 0]:
		var times := []
		var t := Time.get_ticks_usec()
		var t_call := Time.get_ticks_usec()
		scene._on_layer_button_pressed(layer)
		var call_ms := (Time.get_ticks_usec() - t_call) / 1000.0
		for i in 40:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append(int((now - t) / 1000.0))
			t = now
		times.sort()
		print("katman %d: çağrı %.1f ms, en uzun kareler %s, medyan %d" % [layer, call_ms, str(times.slice(-4)), times[20]])
	quit()
