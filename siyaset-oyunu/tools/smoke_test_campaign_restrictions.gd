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
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	mm.room_code = ""
	mm.players = {1: {"name": "Human"}, 2: {"name": "Bot", "bot": true}}
	pm.parties = {1: {"name": "Human", "groups": {}, "ready": true}, 2: {"name": "Bot", "groups": {}, "ready": true}}
	cm.init_game()
	cm.turn_order = [1, 2]
	cm.current_turn_index = 0
	gm.phase = gm.Phase.IDLE
	var province: String = cm._province_ids[0]
	check(cm.start_disaster("deprem", [province]).is_empty(), "campaign disaster cannot start")
	cm.disaster["owed"] = true
	cm._roll_disaster()
	check(not cm.has_disaster(), "campaign random disaster blocked")
	var screen = load("res://scenes/GameScreen.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	var skin = load("res://scripts/ui_skin.gd")
	for button in screen._action_tab_of:
		var style = button.get_theme_stylebox("normal")
		check(style is BoardBox and not (style as BoardBox).lips.is_empty(), "universal action frame (kalınlıklı tombul düğme)")
		check(is_equal_approx(button.modulate.a, 1.0), "action frame stays opaque")
	var markers = screen.map_holder.get_node("SeatMarkers")
	var count := 0
	for id in cm._province_ids:
		var marker_count: int = markers._seats.get(id, []).size()
		check(marker_count == cm._province_seat_counts[id], "pre-election seat markers " + id)
		count += marker_count
	check(count > 0, "campaign seat markers visible")
	screen.queue_free()
	await process_frame
	cm.last_election_round = 1
	check(not cm.start_disaster("deprem", [province]).is_empty(), "disaster available after first election")
	quit(1 if fails else 0)
