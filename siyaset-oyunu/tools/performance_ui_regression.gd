extends SceneTree
## Compare cached UI with a forced rebuild while all animation clocks are paused.
## Run with --rendering-method gl_compatibility for deterministic pixel comparison.
func _frames(count: int) -> void:
	for i in count:
		await process_frame

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
	var scene = load("res://scenes/GameScreen.tscn").instantiate()
	root.add_child(scene)
	await _frames(30)
	paused = true
	await _frames(3)
	var before: Image = root.get_texture().get_image()
	await _frames(3)
	var unchanged: Image = root.get_texture().get_image()
	print("UI UNCHANGED CAPTURE: %s" % ("PASS" if before.get_data() == unchanged.get_data() else "VARIES"))
	if before.get_data() != unchanged.get_data():
		print("UI PIXEL REGRESSION: SKIP (renderer varies without UI changes; run with --rendering-method gl_compatibility)")
		paused = false
		root.remove_child(scene)
		scene.queue_free()
		await _frames(2)
		quit(0)
		return
	for plaque in scene.player_panel_list.get_children():
		plaque.remove_meta("plaque_key")
	scene._hand_built = false
	scene._economy_panel._styled_tax_level = -1
	for button in scene.find_children("*", "Button", true, false):
		for key in ["action_skin_key", "action_text_key", "game_tab_key"]:
			if button.has_meta(key):
				button.remove_meta(key)
	scene._rebuild_player_panel_now()
	scene._rebuild_hand()
	scene._refresh_action_buttons()
	scene._refresh_economy()
	scene._refresh_pass_button()
	await _frames(3)
	var after: Image = root.get_texture().get_image()
	var same := before.get_data() == after.get_data()
	var output := OS.get_environment("PERF_RENDER_DIR")
	if output != "":
		before.save_png(output.path_join("ui-cached.png"))
		unchanged.save_png(output.path_join("ui-unchanged.png"))
		after.save_png(output.path_join("ui-rebuilt.png"))
	print("UI PIXEL REGRESSION: %s" % ("PASS" if same else "FAIL"))
	paused = false
	root.remove_child(scene)
	scene.queue_free()
	await _frames(2)
	quit(0 if same else 1)
