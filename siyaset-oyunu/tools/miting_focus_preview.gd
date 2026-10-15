extends SceneTree
## MİTİNG ODAĞI paneli: 2. seviye teşkilatlı ilde miting seçilince açılan grup
## odağı paneli (bir grup seçili).
##   PREVIEW_SIZE=1920x1080 godot --path . --script res://tools/miting_focus_preview.gd

func _initialize() -> void:
	await process_frame
	var forced := OS.get_environment("PREVIEW_SIZE")
	if forced != "":
		var parts := forced.split("x")
		for i in 3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
			await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	mm.start_offline("Barış")
	for i in 3:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "ilerici"], true)
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var me: int = mm.owner_id
	cm.current_turn_index = cm.turn_order.find(me)
	cm.funds[me] = 200.0
	var province: String = String(cm._province_ids[3])
	cm.organizations[province] = {me: 2}
	scene._on_miting_button_pressed()
	scene._select_target_province(province)
	scene._miting_focus = ["emekli"]
	scene._fill_focus_panel()
	scene._place_focus_panel()
	await create_timer(0.4).timeout
	print("odak paneli: ", scene._focus_panel != null and scene._focus_panel.visible)
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/miting_focus.png" % OS.get_user_data_dir())
		print("screenshot: miting_focus")
	quit()
