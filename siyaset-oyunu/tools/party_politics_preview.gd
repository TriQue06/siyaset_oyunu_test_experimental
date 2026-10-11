extends SceneTree
## PARTİ SİYASETİ ÖNİZLEMESİ: birleşmiş iki kişilik parti, feshedip bağımsız
## kalmış bir bot, gelen bir başvuru; profil kartındaki parti işlemleri ve
## parti kurma penceresi.
##   godot --resolution 1600x900 --path . --script res://tools/party_politics_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), name])
	print("screenshot: " + name)

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 7:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"),
		{"economic": 1.5, "social": -1.5, "administrative": 1.5}, true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	gm._set_phase(gm.Phase.IDLE)
	var me: int = mm.owner_id
	var bots: Array = mm.bot_ids()
	# Bot 1 partisini feshetsin (bağımsız kalır).
	cm.current_turn_index = cm.turn_order.find(int(bots[1]))
	cm._apply_dissolve(int(bots[1]))
	cm.current_turn_index = cm.turn_order.find(me)
	cm.mana[me] = 9.0
	cm.inventories[me] = ["kaset", "populizm", "steal_weak", "karalama", "mana_bonusu", "bonus_kart", "steal_strong", "isyan"]
	cm._push_state({"type": "timer"})
	print("parti: %s, bağımsız %s" % [pm.parties[me]["name"], str(pm.is_independent(int(bots[1])))])

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(30)
	_shot("party_politics_board")
	cm.agenda = {"type": "gundem_economic_p", "until": cm.round_number + 1}
	cm.crisis = {"type": "kriz_economic_n", "until": cm.round_number + 1}
	cm._turn_time_left = 40.0
	scene._refresh_agenda_banner()
	await _frames(5)
	_shot("party_politics_crisis")
	cm.crisis = {}
	cm.agenda = {}
	scene._refresh_agenda_banner()
	scene._on_player_tab_pressed(1)
	await _frames(5)
	_shot("party_politics_scores")
	scene._on_player_tab_pressed(0)
	scene._on_side_tab(1)
	await _frames(5)
	_shot("party_politics_log")
	scene._on_side_tab(0)
	var list: Control = scene.player_panel_list
	print("LISTE boy=%s avatar_h=%.1f" % [str(list.size), scene._avatar_height])
	print("VIEWPORT %s  panel=%s" % [str(scene.get_viewport_rect().size), str((scene.get_node("PlayerPanel") as Control).get_global_rect())])
	for child in list.get_children():
		print("  satir %s" % str(child.get_global_rect()))
	# Profilim: parti işlemleri.
	scene._toggle_profile(me)
	await _frames(10)
	_shot("party_politics_profile_me")
	# Bağımsızın profili: davet düğmesi.
	scene._toggle_profile(int(bots[1]))
	await _frames(10)
	_shot("party_politics_profile_independent")
	scene._hide_profile()
	await _frames(5)
	_shot("party_politics_profile_closed")
	scene._on_province_clicked(String(cm._province_ids[0]))
	await _frames(10)
	_shot("party_politics_province_dock")
	scene._province_panel.hide()
	# İl inceleme: PENCERE modu (ayar sonunda geri alınır).
	var gs = root.get_node("GameSettings")
	var old_view: int = gs.province_view
	gs.set_province_view(1)
	await _frames(3)
	scene._on_province_clicked(String(cm._province_ids[3]))
	await _frames(10)
	_shot("party_politics_province_window")
	scene._province_panel.hide()
	scene._toggle_profile(int(bots[2]))
	await _frames(10)
	_shot("party_politics_profile_window")
	scene._hide_profile()
	gs.set_province_view(old_view)
	await _frames(3)
	# Meclis oylaması: stüdyo masasında büyür.
	gm.submit_early_election(me)
	await _frames(10)
	_shot("party_politics_voting")
	gm._set_phase(gm.Phase.IDLE)
	await _frames(3)
	# Kongre gecesi (benim partim, zayıf: dört aday, iki tur).
	cm._congress_info(me)["share"] = float(cm.last_vote_shares.get(me, 0.0)) + 6.0
	cm.turmoil[me] = 4.0
	var shown := false
	for attempt in 20:
		var result: Dictionary = cm._compute_congress(me, "mandatory")
		if (result["candidates"] as Array).size() == 4 and not (result["round2"] as Array).is_empty():
			result["duration"] = 3.0
			scene._on_congress_started(result)
			shown = true
			break
	if shown:
		var show_node: Node = scene.get_child(scene.get_child_count() - 1)
		show_node._t = 0.8
		await _frames(3)
		_shot("party_politics_congress_round1")
		show_node._t = 1.9
		await _frames(3)
		_shot("party_politics_congress_round2")
		show_node._t = 2.6
		await _frames(3)
		_shot("party_politics_congress_result")
	# Parti kurma penceresi.
	var dialog: Control = load("res://scripts/found_party_dialog.gd").new()
	scene.add_child(dialog)
	await _frames(10)
	_shot("party_politics_found")
	quit(0)
