extends SceneTree
var fails := 0
func check(ok: bool, text: String) -> void:
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + text)

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	root.get_node("BotManager").set_process(false)
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	for count in [2, 5, 8]:
		mm.players = {}
		pm.parties = {}
		pm.politicians = {}
		mm.room_code = ""
		mm.is_host = true
		mm._apply_world_settings({"province_seats": 300, "national_seats": 100})
		for i in count:
			var pid: int = mm.BOT_ID_BASE - i
			mm.players[pid] = {"name": "Bot %d" % i, "bot": true}
			pm.add_bot_party(pid)
		cm.init_game()
		cm._hold_election(1, false)
		var final_before: Dictionary = cm.last_seats.duplicate(true)
		var screen = load("res://scenes/ElectionResults.tscn").instantiate()
		root.add_child(screen)
		await process_frame
		await process_frame
		screen.set_process(false)
		screen._t = 7.0
		screen._refresh()
		screen._animate(1.0)
		check(screen._bars.rows.size() == count, "%d parties displayed" % count)
		check(screen._parliament._total_seats == 400, "national list included from first frame")
		check(screen._province_cards.size() == 4, "hover card and three largest cards")
		var stable: Array = screen._largest_provinces.duplicate()
		var hovered: String = screen._sim.province_ids[-1]
		screen._map.province_hovered.emit(hovered)
		check(screen._province_cards[0].province_id == hovered, "map hover updates inspected province")
		var motion := InputEventMouseMotion.new()
		var another: String = screen._sim.province_ids[0]
		motion.global_position = screen._map.to_global(root.get_node("GameMap").center_of(another))
		screen._map._unhandled_input(motion)
		check(screen._province_cards[0].province_id == another, "mouse coordinates resolve through scaled election canvas")
		for i in 3:
			check(screen._province_cards[i + 1].province_id == stable[i], "largest province remains fixed")
		var list: Array = stable.duplicate()
		list.sort_custom(func(a, b): return cm.province_seat_count(a) > cm.province_seat_count(b))
		check(list == stable, "largest provinces sorted by seats")
		check(cm.last_seats == final_before, "visual count never changes host result")
		check(not screen._majority_label.visible and screen._section_parliament.text == L.t("Meclis"), "approved simplified headings")
		screen.queue_free()
		await process_frame
	print("ELECTION TABLE: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
