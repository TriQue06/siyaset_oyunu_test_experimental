extends SceneTree
## AFET ÖNİZLEMESİ: tur başında çıkan depremin gazetesi, haritadaki afet
## bölgesi, YARDIM hamlesi butonu ve yardım paneli, yardım sonrası. Ayrıca
## sağ sütunun kaydırılabilir olduğu ve sekmelerin üstte kaldığı kontrol edilir.
##   PREVIEW_SIZE=1920x1080 godot --path . --script res://tools/disaster_preview.gd

var fails := 0

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), name])
	print("screenshot: " + name)

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	if OS.get_environment("PREVIEW_LANG") != "":
		root.get_node("GameSettings").language = OS.get_environment("PREVIEW_LANG")
		TranslationServer.set_locale(OS.get_environment("PREVIEW_LANG"))
	var forced := OS.get_environment("PREVIEW_SIZE")
	if forced != "":
		var parts := forced.split("x")
		for i in 3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
			await process_frame
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 5:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	var me: int = mm.owner_id
	var partner: int = int(mm.bot_ids()[0])
	gm.government = {"pm": me, "deputy_pm": partner}
	gm.main_gov_peer_id = me
	gm._set_phase(gm.Phase.GOVERNING)
	cm.current_turn_index = cm.turn_order.find(me)
	cm.funds[me] = 120.0
	cm.agenda = {}
	cm.crisis = {}

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	Input.warp_mouse(Vector2(2, 2))
	await _frames(30)
	# Afet tur başında çıkar: durum yayınlanınca gazete oynar.
	var region: Array = cm.start_disaster("deprem")
	cm._push_state({"type": "round"})
	await create_timer(1.3).timeout
	_shot("disaster_paper")
	check("afet gazetesi oynuyor", scene._event_fx.is_playing())
	scene._event_fx.skip_all()
	await _frames(20)
	_shot("disaster_map")
	check("harita afet bölgesini işaretliyor", scene.map_holder._disaster_ids == region, str(region))
	var grid: GridContainer = scene._action_grid
	print("GRID size %s min %s parent %s" % [grid.size, grid.get_combined_minimum_size(), (grid.get_parent() as Control).size])
	for b in grid.get_children():
		print("  %s min %s size %s" % [(b as Button).text.replace("
", " "), (b as Control).get_combined_minimum_size(), (b as Control).size])
	# 0.0.231: yardım tur başındaki afet sahnesinde; panel burada doğrudan açılır.
	scene._aid_panel.open(me)
	scene._place_aid_panel()
	await _frames(10)
	_shot("disaster_aid_panel")
	check("yardım paneli açıldı", scene._aid_panel.visible)
	var panel = scene._aid_panel
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	check("panel ekrana sığıyor", view.encloses(panel.get_global_rect()), str(panel.get_global_rect()))
	var before: float = cm.local_of(String(region[0]), me)
	panel._party_slider.value = 20.0
	await _frames(3)
	_shot("disaster_aid_amount")
	panel._confirm.pressed.emit()
	await _frames(20)
	check("yardım uygulandı", cm.disaster_aid_of(me) == 20.0 and cm.local_of(String(region[0]), me) > before,
		"%.1f milyon, il %.2f -> %.2f" % [cm.disaster_aid_of(me), before, cm.local_of(String(region[0]), me)])
	_shot("disaster_after")
	# Sağ sütun: sekmeler panelin üstünde kalır, içerik kaydırılabilir.
	var tabs: Control = scene._side_tabs
	var left: Control = scene.left_panel
	var scroll := left.get_node_or_null("LeftMargin/LeftScroll") as ScrollContainer
	check("sağ sütun kaydırma kutusunda", scroll != null)
	check("sekmeler panelin içinde ve üstte", tabs.get_global_rect().position.y >= left.get_global_rect().position.y - 1.0,
		"%s / %s" % [str(tabs.get_global_rect().position.y), str(left.get_global_rect().position.y)])
	# Dil değişince ayarlar paneli açık kalır, yazıları yeni dilde kurulur.
	var so = root.get_node("SettingsOverlay")
	so.open()
	await _frames(3)
	var target := "en" if TranslationServer.get_locale().begins_with("tr") else "tr"
	var lang_button: Button = null
	for node in so._dynamic:
		if node is HBoxContainer:
			for b in node.get_children():
				if b is Button and (b as Button).text == String(L.LOCALE_NAMES[target]):
					lang_button = b
	check("dil düğmesi bulundu", lang_button != null)
	if lang_button != null:
		lang_button.pressed.emit()
		await _frames(12)
		check("dil değişince ayarlar paneli açık kalır", so.panel.visible)
		var titles: Array = []
		for node in so._dynamic:
			if is_instance_valid(node) and node is Label:
				titles.append((node as Label).text)
		check("panel yeni dilde kuruldu", str(titles).contains(L.t("Dil").to_upper()), str(titles))
		_shot("settings_after_language")
		so.close()
	print("")
	print("AFET ÖNİZLEMESİ: %s" % ("HEPSİ GEÇTİ" if fails == 0 else "%d HATA" % fails))
	quit(1 if fails > 0 else 0)
