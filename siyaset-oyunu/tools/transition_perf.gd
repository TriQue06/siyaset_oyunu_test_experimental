extends SceneTree
## GEÇİŞ AKICILIĞI (0.0.267): harita katman kaydırması ve oylama sırasında
## harita / meclis yer değiştirmesi boyunca kare sürelerini ölçer.
##   godot --path . --script res://tools/transition_perf.gd

var _times: Array = []
var _last := 0

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _measure(seconds: float) -> Dictionary:
	_times.clear()
	_last = Time.get_ticks_usec()
	var end := Time.get_ticks_usec() + int(seconds * 1e6)
	var proc: Array = []
	while Time.get_ticks_usec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		_times.append((now - _last) / 1000.0)
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_last = now
	var worst := 0.0
	var sum := 0.0
	for t in _times:
		worst = maxf(worst, t)
		sum += t
	var pw := 0.0
	for p in proc:
		pw = maxf(pw, p)
	return {"frames": _times.size(), "avg": sum / maxf(1, _times.size()), "worst": worst, "proc_worst": pw,
		"list": _times.slice(0, 12).map(func(x): return snappedf(x, 0.1))}

func _initialize() -> void:
	await process_frame
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	root.get_node("BotManager").set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 4:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _wait(1.5)
	scene._event_fx.skip_all()
	scene._turn_intro.set_process(false)
	await _wait(1.0)
	print("bos: ", _strip(await _measure(1.0)))
	if OS.get_environment("PERF_SHOT") != "":
		scene._set_map_layer(1)
		await _wait(0.2)
		root.get_texture().get_image().save_png(OS.get_environment("PERF_SHOT"))
		await _wait(0.6)
	for layer in [1, 2, 3, 0]:
		scene._set_map_layer(layer)
		print("katman %d: " % layer, _strip(await _measure(0.6)))
		await _wait(0.3)
	gm._set_phase(gm.Phase.VOTING)
	print("oylama gecisi: ", _strip(await _measure(1.0)))
	gm._set_phase(gm.Phase.GOVERNING)
	print("geri donus: ", _strip(await _measure(2.5)))
	quit()

func _strip(r: Dictionary) -> String:
	return "kare %d ort %.2f ms en kotu %.2f ms islem %.2f ms ilk %s" % [r["frames"], r["avg"], r["worst"], r["proc_worst"], str(r["list"])]
