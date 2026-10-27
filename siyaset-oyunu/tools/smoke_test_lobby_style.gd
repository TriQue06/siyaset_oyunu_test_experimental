extends SceneTree
## ODA LOBİSİ (konsept C, komuta panosu): tek ekran, katlanır kurallar,
## eşit oyuncu satırları, solda Başlat / sağda Ayrıl, konuğa salt okunur ayarlar.
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
	check(lobby._sections.size() == 4, "four rule sections")
	var open := 0
	for id in lobby._sections:
		if (lobby._sections[id]["body"] as Control).visible:
			open += 1
	check(open == 1, "only one rule section open")
	lobby._on_section_pressed("timing")
	await process_frame
	check((lobby._sections["timing"]["body"] as Control).visible and not (lobby._sections["map"]["body"] as Control).visible, "accordion switches section")
	check(not lobby.world_controls.has("turn_seconds") and lobby.world_choice_buttons["turn_seconds"].size() == 5, "turn duration uses buttons (60-120)")
	check(lobby.world_choice_buttons["action_limit"].size() == 3, "action limit uses buttons (4, 5, 6)")
	for f in 3:
		await process_frame
	var turn_buttons: Array = lobby.world_choice_buttons["turn_seconds"]
	var limit_buttons: Array = lobby.world_choice_buttons["action_limit"]
	check(is_equal_approx(turn_buttons[0].size.y, limit_buttons[0].size.y), "choice buttons share height")
	check(turn_buttons[0].size.x < limit_buttons[0].size.x, "more options -> narrower buttons")
	check(turn_buttons[0].text == "60" and lobby.vote_time_buttons[0].text == "15", "no seconds suffix")
	check(lobby.world_controls["province_seats"] is HSlider and not (lobby.world_controls["province_seats"] as HSlider).scrollable, "district seats slider ignores wheel")
	check(lobby.world_controls["national_seats"] is HSlider, "national seats use slider")
	check(not lobby.threshold_slider.scrollable, "threshold slider ignores wheel")
	check(lobby.density_buttons.size() == 3, "density segmented choices")
	var rows = lobby.player_list_box.get_children()
	check(rows.size() == 8, "eight player rows")
	var common: float = rows[0].size.y
	var equal := true
	for row in rows:
		if not is_equal_approx(row.size.y, common):
			equal = false
	check(equal, "all lobby player rows equal")
	var start: Button = lobby.start_button
	var leave: Button = lobby.leave_button
	check(leave.get_global_rect().position.x < start.get_global_rect().position.x, "leave on the left, start on the right")
	check(leave.get_global_rect().end.y <= lobby.size.y and leave.get_global_rect().end.x <= lobby.size.x, "lobby fits viewport")
	for i in 3:
		mm.add_bot()
		for frame in 4:
			await process_frame
		equal = true
		for row in lobby.player_list_box.get_children():
			if not row.is_queued_for_deletion() and not is_equal_approx(row.size.y, common):
				equal = false
		check(equal, "adding bot keeps rows equal")
	check(leave.get_global_rect().end.y <= lobby.size.y, "full lobby still fits")
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
	panel.free()
	mm.owner_id = 99
	lobby._refresh()
	check(not lobby.world_controls["national_seats"].editable and (lobby.world_choice_buttons["turn_seconds"][0] as Button).disabled, "guest sees read-only settings")
	check(not start.visible, "guest has no start button")
	lobby.queue_free()
	await process_frame
	quit(1 if fails else 0)
