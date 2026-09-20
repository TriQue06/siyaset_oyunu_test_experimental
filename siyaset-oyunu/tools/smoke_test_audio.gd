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
	print("=== 5) OYUN OLAYLARI ===")
	var gm = root.get_node("GovernmentManager")
	var cm = root.get_node("CardManager")
	var heard := func(sound: String) -> bool:
		return am._last_played.has(sound)
	am._last_played.clear()
	gm.proposal_kind = gm.KIND_CENSURE
	gm.proposal_peer_id = 1
	gm.phase = gm.Phase.VOTING
	gm.votes = {}
	gm.proposal_changed.emit()
	check("gensoru oylamasi acilinca ses caldi", heard.call("censure_open"))
	gm.votes = {1: gm.VOTE_YES, 2: gm.VOTE_NO, 3: gm.VOTE_ABSTAIN}
	gm.proposal_changed.emit()
	check("evet/hayir/cekimser seslendi", heard.call("vote_yes") and heard.call("vote_no") and heard.call("vote_abstain"))
	am._last_played.erase("vote_yes")
	gm.proposal_changed.emit()
	check("ayni oy ikinci kez seslenmez", not heard.call("vote_yes"))
	am._last_played.clear()
	gm.proposal_resolved.emit(true, gm.KIND_LAW, 1)
	check("yasa gecti sesi", heard.call("law_passed"))
	am._last_played.clear()
	gm.proposal_resolved.emit(false, gm.KIND_LAW, 1)
	check("yasa reddedildi sesi", heard.call("law_rejected"))
	am._last_played.clear()
	gm.proposal_resolved.emit(true, gm.KIND_CENSURE, 1)
	check("gensoru sonucu yasa sesi calmaz", not heard.call("law_passed"))
	am._last_played.clear()
	cm.card_played.emit(999, "karalama")
	check("baskasinin oynadigi karti da duyariz", heard.call("card_played"))
	am._last_played.clear()
	cm.card_drawn.emit(999, "karalama")
	check("baskasinin kart cekmesi duyulmaz", not heard.call("card_drawn"))
	cm.card_drawn.emit(root.multiplayer.get_unique_id(), "karalama")
	check("kendi kart cekisimiz duyulur", heard.call("card_drawn"))
	gm.proposal_kind = ""
	gm.votes = {}

	print("")
	print("=== TUM TESTLER GECTI ===" if _failed == 0 else "=== %d TEST BASARISIZ ===" % _failed)
	quit(1 if _failed > 0 else 0)
