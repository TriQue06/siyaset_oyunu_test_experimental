extends SceneTree
## Ses altyapısı: bus'lar kuruldu mu, buton sesi evrensel bağlanıyor mu?
## `godot --headless --path . --script res://tools/smoke_test_audio.gd`

var _failed := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failed += 1
	print("  [%s]  %s%s" % ["OK" if ok else "HATA", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	var am = root.get_node("AudioManager")
	var gs = root.get_node("GameSettings")

	print("=== 1) BUS'LAR ===")
	check("Muzik bus'i var", AudioServer.get_bus_index(am.BUS_MUSIC) != -1)
	check("Efekt bus'i var", AudioServer.get_bus_index(am.BUS_SFX) != -1)
	check("Efekt bus'i Master'a gider", AudioServer.get_bus_send(AudioServer.get_bus_index(am.BUS_SFX)) == "Master")

	print("")
	print("=== 2) SES DOSYALARI VE HAVUZ ===")
	check("ui_click yuklendi", am._streams.has("ui_click"))
	check("oynatici havuzu hazir", am._players.size() == am.POOL_SIZE)
	for sound in am.SOUNDS:
		check("dosya var: %s" % sound, ResourceLoader.exists(String(am.SOUNDS[sound])))

	print("")
	print("=== 3) BUTON SESI EVRENSEL ===")
	var button := Button.new()
	root.add_child(button)
	await process_frame
	check("sahneye giren buton otomatik baglandi", button.pressed.is_connected(am._on_button_pressed))
	button.emit_signal("pressed")
	check("basinca ses caldi", am._last_played.has("ui_click"))
	var muted := Button.new()
	muted.set_meta("sessiz", true)
	root.add_child(muted)
	await process_frame
	check("sessiz meta'li buton baglanmaz", not muted.pressed.is_connected(am._on_button_pressed))

	print("")
	print("=== 4) SES SEVIYESI AYARI ===")
	gs.set_volume("sfx", 0.5)
	var sfx_index := AudioServer.get_bus_index(am.BUS_SFX)
	check("seviye bus'a uygulandi", is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(sfx_index)), 0.5),
		str(db_to_linear(AudioServer.get_bus_volume_db(sfx_index))))
	gs.set_volume("sfx", 0.0)
	check("sifir seviye = susturur", AudioServer.is_bus_mute(sfx_index))
	gs.set_volume("sfx", gs.DEFAULT_SFX_VOLUME)

	print("")
	print("=== TUM TESTLER GECTI ===" if _failed == 0 else "=== %d TEST BASARISIZ ===" % _failed)
	quit(1 if _failed > 0 else 0)
