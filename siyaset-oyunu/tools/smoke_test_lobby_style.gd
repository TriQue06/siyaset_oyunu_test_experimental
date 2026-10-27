extends SceneTree
var fails := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("[OK] " if ok else "[HATA] ") + label)
	if not ok:
		fails += 1
func run() -> void:
	var mm = root.get_node("MultiplayerManager")
	mm.start_offline("UI test")
	mm.add_bot()
	var lobby = load("res://scenes/RoomLobby.tscn").instantiate()
	root.add_child(lobby)
	for i in 5:
		await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/lobby-a.png"))
	check(lobby._setting_sections.size() == 3, "A three setting groups")
	check(lobby.settings_side_panel.visible, "A rules panel always visible")
	check(lobby._lobby_columns.columns == 2, "A desktop columns")
	check(not lobby.world_controls.has("turn_seconds") and lobby.world_choice_buttons["turn_seconds"].size() == 5, "turn duration uses buttons (60-120)")
	check(lobby.world_choice_buttons["action_limit"].size() == 3, "action limit uses buttons (4, 5, 6)")
	var turn_buttons: Array = lobby.world_choice_buttons["turn_seconds"]
	var limit_buttons: Array = lobby.world_choice_buttons["action_limit"]
	check(is_equal_approx(turn_buttons[0].size.y, limit_buttons[0].size.y), "choice buttons share height")
	check(turn_buttons[0].size.x < limit_buttons[0].size.x, "more options -> narrower buttons")
	check(turn_buttons[0].text == "60" and lobby.vote_time_buttons[0].text == "15", "no seconds suffix")
	check(lobby.world_controls["province_seats"] is HSlider, "district seats use slider")
	check(lobby.world_controls["national_seats"] is HSlider, "national seats use slider")
	check(lobby.density_buttons.size() == 3, "density segmented choices")
	var slots = lobby.player_list_box.get_children()
	var common: Vector2 = slots[0].size
	var equal := true
	for slot in slots:
		if not slot.is_queued_for_deletion() and not slot.size.is_equal_approx(common):
			equal = false
	check(equal, "all lobby player slots equal")
	var card_size: Vector2 = (slots[0].get_meta("card") as Control).size
	for slot in slots:
		if not slot.is_queued_for_deletion():
			check((slot.get_meta("card") as Control).size.is_equal_approx(card_size), "visible player frames equal")
	check(lobby._lobby_columns.size.x <= lobby.size.x, "lobby fits viewport horizontally")
	var base_height: float = lobby._lobby_columns.get_child(0).size.y
	for i in 3:
		mm.add_bot()
		for frame in 4:
			await process_frame
		check(is_equal_approx(lobby._lobby_columns.get_child(0).size.y, base_height), "adding bot preserves panel height")
		for slot in lobby.player_list_box.get_children():
			var card: Control = slot.get_meta("card")
			check(is_equal_approx(card.size.y, 77.0), "empty and occupied cards fixed height")
	slots = lobby.player_list_box.get_children()
	(lobby.world_choice_buttons["turn_seconds"][3] as Button).pressed.emit()  # 105
	check(int(mm.world_settings["turn_seconds"]) == 105, "button changes server setting")
	var skin = load("res://scripts/ui_skin.gd")
	var panel := Panel.new()
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color.RED
	flat.content_margin_left = 9
	skin.apply_style(panel, "panel", flat)
	var style = panel.get_theme_stylebox("panel")
	check(style is StyleBoxFlat and style.bg_color == Color.RED and style.corner_radius_top_left > 0, "information rectangle uses rounded board frame")
	check(style.get_content_margin(SIDE_LEFT) == 9, "frame preserves layout margins")
	var outline := StyleBoxFlat.new()
	outline.draw_center = false
	skin.apply_style(panel, "panel", outline)
	check(not (panel.get_theme_stylebox("panel") as StyleBoxFlat).draw_center, "card outline remains transparent")
	for slot in slots:
		if not slot.is_queued_for_deletion():
			var card: Control = slot.get_meta("card")
			check(card.position.y + card.size.y <= slot.size.y + 1.0, "player card bottom border inside slot")
	panel.free()
	mm.owner_id = 99
	lobby._refresh()
	check(not lobby.world_controls["national_seats"].editable and (lobby.world_choice_buttons["turn_seconds"][0] as Button).disabled, "guest sees read-only settings")
	check(lobby.settings_side_panel.visible, "guest sees rules panel")
	lobby.queue_free()
	await process_frame
	quit(1 if fails else 0)
