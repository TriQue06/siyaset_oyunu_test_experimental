extends SceneTree
## İnceleme kartı önizlemesi (il ve parti; anket kartı verisiyle).

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	root.get_node("BotManager").set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 3:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm.set_rng_seed(4242)
	root.get_node("GovernmentManager").result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	var me: int = mm.owner_id
	cm.round_number += 2
	cm.polls[me] = {"round": cm.round_number, "parties": cm.national_poll_snapshot(me)}
	var province: String = String(cm._province_ids[3])
	cm.organizations[province] = {me: 1}
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	Input.warp_mouse(Vector2(2, 2))
	await _wait(1.0)
	scene._event_fx.skip_all()
	scene._turn_intro.set_process(false)
	scene._turn_intro.hide()
	scene._parliament_flow.close_flow()
	await _wait(0.5)
	scene._pinned = false
	scene._show_province_info(province)
	scene._pinned = true
	await _wait(0.6)
	_shot("insp_il")
	scene._toggle_profile(me)
	await _wait(0.6)
	_shot("insp_parti")
	scene._toggle_profile(int(mm.bot_ids()[0]))
	await _wait(0.6)
	_shot("insp_bot")
	quit()
