extends SceneTree
## Kongre sonu ölçümü: gösteri biterken kare süreleri ve gazete oynuyor mu.
##   godot --path . --script res://tools/congress_end_probe.gd

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	root.get_node("BotManager").set_process(OS.get_environment("PROBE_BOTS_ON") != "")
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
	cm.current_turn_index = cm.turn_order.find(me)
	cm.funds[me] = 120.0
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var who: int = int(mm.bot_ids()[0]) if OS.get_environment("PROBE_BOT") != "" else me
	cm._run_congress(who, "voluntary")
	var t0 := Time.get_ticks_msec()
	var last := t0
	var view: Node = null
	var paper_seen := false
	while Time.get_ticks_msec() - t0 < 25000:
		await process_frame
		var now := Time.get_ticks_msec()
		if now - last > 60:
			print("YAVAŞ KARE %d ms @ %.2f s  congress_active=%s" % [now - last, (now - t0) / 1000.0, cm.congress_active])
		last = now
		if view == null:
			for c in scene.get_children():
				if c.get_script() != null and String(c.get_script().resource_path).ends_with("congress_show.gd"):
					view = c
		if view != null and is_instance_valid(view) and view._paper_started and view._event_fx.is_playing() and not paper_seen:
			paper_seen = true
			print("GAZETE OYNUYOR @ %.2f s" % ((now - t0) / 1000.0))
			await create_timer(1.2).timeout
			var fx = view._event_fx
			print("drawn %d" % Engine.get_frames_drawn()); print("mod %s %s %s self %s" % [fx._holder.modulate, fx.modulate, view.modulate, fx.self_modulate]); print("holder %s pos %s vis %s fxvis %s fxsize %s tween %s z %d/%d" % [fx._holder, fx._holder.global_position if fx._holder else Vector2.ZERO, fx._holder.is_visible_in_tree() if fx._holder else false, fx.visible, fx.size, fx._tween.is_running() if fx._tween else null, fx.z_index, view.z_index])
			root.get_texture().get_image().save_png(OS.get_user_data_dir() + "/congress_paper.png")
			var cr := ColorRect.new(); cr.color = Color.GREEN; cr.size = Vector2(200, 200); cr.position = Vector2(50, 600); root.add_child(cr)
			fx.z_index = int(OS.get_environment("PROBE_Z")) if OS.get_environment("PROBE_Z") != "" else fx.z_index
			await create_timer(1.5).timeout
			print("drawn2 %d" % Engine.get_frames_drawn())
			root.get_texture().get_image().save_png(OS.get_user_data_dir() + "/congress_paper2.png")
		if view != null and not is_instance_valid(view):
			print("GÖSTERİ KAPANDI @ %.2f s, congress_active=%s" % [(now - t0) / 1000.0, cm.congress_active])
			break
	print("gazete görüldü: %s" % paper_seen)
	quit()
