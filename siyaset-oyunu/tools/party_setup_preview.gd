extends SceneTree
## Parti kurulum önizlemesi: soldaki oyuncu paneli ve renk kilidi.
## Başka oyuncunun rengi seçilemez; botun rengini oyuncu alırsa bot başka renge geçer.
##   godot --resolution 1600x900 --script res://tools/party_setup_preview.gd

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var colors: Array = load("res://scripts/party_presets.gd").COLORS
	var me: int = root.multiplayer.get_unique_id()
	mm.room_code = ""
	mm.players = {me: {"name": "Barış"}, 77: {"name": "Ayşe"}}
	pm.parties = {77: {"name": "Yeşiller", "icon_index": 2, "icon_color": Color.WHITE, "bg_color": colors[0], "ideology": {}, "ready": true}}
	for i in 3:
		var id: int = mm.BOT_ID_BASE - i
		mm.players[id] = {"name": "Bot %d" % i, "bot": true}
		pm.add_bot_party(id)
		check("bot %d oyuncunun rengini almadi" % i, not Color(pm.parties[id]["bg_color"]).is_equal_approx(colors[0]))

	var scene: Node = (load("res://scenes/PartySetup.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	check("benim rengim Ayse'ninkinden farkli", not Color(pm.parties[me]["bg_color"]).is_equal_approx(colors[0]))
	check("panelde 5 oyuncu", scene._players_list.get_child_count() == 5, str(scene._players_list.get_child_count()))

	pm.set_my_party("Deneme", 1, Color.WHITE, colors[0], scene._ideology)
	check("baskasinin rengi reddedildi", not Color(pm.parties[me]["bg_color"]).is_equal_approx(colors[0]))

	var bot: int = mm.BOT_ID_BASE
	var bot_color: Color = pm.parties[bot]["bg_color"]
	pm.set_my_party("Deneme", 1, Color.WHITE, bot_color, scene._ideology)
	check("botun rengini aldim", Color(pm.parties[me]["bg_color"]).is_equal_approx(bot_color))
	check("bot baska renge gecti", not Color(pm.parties[bot]["bg_color"]).is_equal_approx(bot_color))
	scene._selected_bg_color = bot_color
	scene._update_preview()
	pm.parties_updated.emit()
	for i in 5:
		await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/party_setup.png" % OS.get_user_data_dir())
	# İkon kategorileri: Kurgusal / Türkiye.
	var presets = root.get_node("PartyPresets")
	check("16 parti rengi", colors.size() == 16)
	check("27 Turkiye ikonu yuklendi", presets.icon_indices(1).size() == 27, str(presets.icon_indices(1).size()))
	var turkiye_tab: Button = scene._icon_tabs.get_child(1)
	turkiye_tab.pressed.emit()
	await process_frame
	var visible := 0
	for btn in scene.icon_grid.get_children():
		if btn.visible:
			visible += 1
	check("Turkiye sekmesi sadece Turkiye ikonlarini gosterir", visible == 27, str(visible))
	var first_tr: int = presets.icon_indices(1)[0]
	check("Turkiye ikonu rasterize edilir", presets.get_icon_texture(first_tr, 64) != null)
	scene._on_icon_selected(first_tr + 6)
	for i in 5:
		await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/party_setup_turkiye.png" % OS.get_user_data_dir())
	print("=== PARTY SETUP PREVIEW: %s ===" % ("PASS" if fails == 0 else "%d HATA" % fails))
	quit()
