extends SceneTree
## Synthetic viewport input test; supports headless and rendered backends.
var _fails := 0
var _scene
var _pointer := Vector2.ZERO

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_fails += 1

func _frames(count: int = 3) -> void:
	for i in count:
		await process_frame

func _move(position: Vector2) -> void:
	_pointer = position
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = Vector2.ZERO
	root.push_input(event, true)
	_scene._update_live_province(position)
	await _frames()

func _button(button: MouseButton, pressed: bool = true, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.position = _pointer
	event.global_position = event.position
	event.button_index = button
	event.pressed = pressed
	event.factor = factor
	root.push_input(event, true)
	await _frames()

func _overflow(scroll: ScrollContainer) -> void:
	var body := scroll.get_child(0) as Control
	body.custom_minimum_size.y = scroll.size.y + 1200.0
	await _frames()
	scroll.scroll_vertical = 0

func _exercise(scroll: ScrollContainer, source: Vector2, label: String) -> void:
	await _overflow(scroll)
	var board_before: int = _scene._board_scroll.scroll_vertical
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	_check(scroll.scroll_vertical > 0, label + ": wheel down scrolls inspector")
	_check(_scene._board_scroll.scroll_vertical == board_before, label + ": source party list stays still")
	await _button(MOUSE_BUTTON_WHEEL_UP)
	_check(scroll.scroll_vertical == 0, label + ": wheel up scrolls back")
	await _button(MOUSE_BUTTON_WHEEL_DOWN, true, 0.5)
	_check(scroll.scroll_vertical > 0, label + ": fractional wheel factor works")
	scroll.scroll_vertical = 0
	await _button(MOUSE_BUTTON_MIDDLE)
	var motion := InputEventMouseMotion.new()
	motion.position = source - Vector2(0, 65)
	motion.global_position = motion.position
	motion.relative = Vector2(0, -65)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion, true)
	_scene._update_live_province(motion.position)
	await _frames()
	_check(scroll.scroll_vertical == 65, label + ": middle drag follows vertical movement (%d)" % scroll.scroll_vertical)
	_check(_scene._hover_info_drag_scroll == scroll, label + ": drag retains original inspector")
	await _button(MOUSE_BUTTON_MIDDLE, false)
	_check(_scene._hover_info_drag_scroll == null, label + ": middle release ends drag")
	await _move(source)
	var bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(bar.max_value - bar.page)
	var bottom := scroll.scroll_vertical
	await _button(MOUSE_BUTTON_WHEEL_DOWN)
	_check(scroll.scroll_vertical == bottom, label + ": scroll clamps at bottom")
	await _button(MOUSE_BUTTON_WHEEL_UP)
	_check(scroll.scroll_vertical < bottom, label + ": scrolling reverses at bottom")

func _initialize() -> void:
	await process_frame
	seed(4242)
	var mm = root.get_node("MultiplayerManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var pm = root.get_node("PartyManager")
	root.get_node("BotManager").set_process(false)
	cm.set_process(false)
	gm.set_process(false)
	root.get_node("GameSettings").province_view = 0
	cm.fixed_map_seed = 1950
	cm.set_rng_seed(4242)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 7:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm._hold_election(1, false)
	gm.phase = gm.Phase.IDLE
	_scene = load("res://scenes/GameScreen.tscn").instantiate()
	root.add_child(_scene)
	_scene.set_process(false)
	await _frames(30)
	_scene._event_fx.skip_all()
	var map = root.get_node("GameMap")
	var province_position := Vector2.ZERO
	for id in map.province_ids():
		var center: Vector2 = map.center_of(id)
		if _scene.map_holder.get_province_id_at(center) == id:
			province_position = _scene.map_holder.to_global(center)
			break
	await _move(province_position)
	var province_scroll: ScrollContainer = _scene._hover_info_scroll_target(province_position)
	_check(province_scroll != null, "province hover resolves inspector scroll")
	if province_scroll != null:
		await _exercise(province_scroll, province_position, "province")
	var plaque: Control = _scene.player_panel_list.get_child(0)
	var party_position := plaque.get_global_rect().get_center()
	await _move(party_position)
	var party_scroll: ScrollContainer = _scene._hover_info_scroll_target(party_position)
	_check(party_scroll != null and party_scroll == _scene._profile_scroll, "party hover resolves inspector scroll")
	if party_scroll != null:
		await _exercise(party_scroll, party_position, "party")
		party_scroll.scroll_vertical = 0
		await _move(party_scroll.get_global_rect().get_center())
		await _button(MOUSE_BUTTON_WHEEL_DOWN)
		_check(party_scroll.scroll_vertical > 0, "native wheel inside inspector still works")
		await _move(party_position)
		var overlay := Panel.new()
		overlay.position = party_position - Vector2(40, 40)
		overlay.size = Vector2(80, 80)
		overlay.z_index = 1000
		_scene.add_child(overlay)
		await _frames()
		await _move(party_position + Vector2(1, 1))
		var previous := party_scroll.scroll_vertical
		await _button(MOUSE_BUTTON_WHEEL_DOWN)
		_check(party_scroll.scroll_vertical == previous, "covering overlay blocks forwarded scrolling")
		overlay.queue_free()
		await _frames()
		await _move(party_position)
		await _button(MOUSE_BUTTON_MIDDLE)
		_scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		_check(_scene._hover_info_drag_scroll == null, "losing focus cancels middle drag")
		_scene._pinned = true
		var other_party: Control = _scene.player_panel_list.get_child(1)
		_check(_scene._hover_info_scroll_target(other_party.get_global_rect().get_center()) == null, "pinned inspector does not scroll for another party")
		_scene._pinned = false
		_scene._pending_org = true
		_check(_scene._hover_info_scroll_target(party_position) == null, "action targeting keeps its existing input behavior")
		_scene._pending_org = false
		root.get_node("GameSettings").province_view = 1
		_check(_scene._hover_info_scroll_target(party_position) == null, "window mode keeps its existing input behavior")
		root.get_node("GameSettings").province_view = 0
	print("HOVER SCROLL TEST: %s" % ("PASS" if _fails == 0 else "FAIL"))
	root.remove_child(_scene)
	_scene.queue_free()
	await _frames()
	quit(1 if _fails else 0)
