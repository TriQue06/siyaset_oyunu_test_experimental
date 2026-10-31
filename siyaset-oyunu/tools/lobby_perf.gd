extends SceneTree
## Ana menüden odaya geçişin kare süreleri (ms): "Botlarla Oyna" donması.
## Menü ile oda arasında birkaç kez gidip gelir; en uzun kareyi yazar.
##   godot --path . --verbose --script res://tools/lobby_perf.gd
## (--verbose olmadan print çıktısı görünmeyebiliyor.)

func _frames_until(cond: Callable, limit: int = 600) -> Array:
	var longest := 0.0
	var t := Time.get_ticks_usec()
	var start := t
	for i in limit:
		await process_frame
		var now := Time.get_ticks_usec()
		longest = maxf(longest, (now - t) / 1000.0)
		t = now
		if cond.call():
			break
	return [longest, (t - start) / 1000.0]

func _initialize() -> void:
	await process_frame
	for round_i in 6:
		change_scene_to_file("res://scenes/Lobby.tscn")
		var r: Array = await _frames_until(func(): return current_scene != null and current_scene.scene_file_path.ends_with("Lobby.tscn") and current_scene.has_method("_on_offline_pressed"))
		for i in 20:
			await process_frame
		var t := Time.get_ticks_usec()
		current_scene._on_offline_pressed()
		var press_ms := (Time.get_ticks_usec() - t) / 1000.0
		r = await _frames_until(func(): return current_scene != null and current_scene.scene_file_path.ends_with("RoomLobby.tscn"))
		var r2: Array = await _frames_until(func(): return false, 30)
		print("tur %d: basış %.1f ms, odaya %.0f ms (en uzun kare %.0f), sonrası en uzun %.0f" % [round_i, press_ms, r[1], r[0], r2[0]])
	quit()
