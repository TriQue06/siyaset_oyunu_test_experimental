extends SceneTree
## SEÇMEN GRUPLARI ÖNİZLEMESİ: il paneli (seçmen profili), parti kartı (grup
## destekleri), yasa paneli (8 grup + etki önizlemesi), grup toplantısı paneli ve
## haritanın "Seçmen" katmanı. Ekran görüntüleri kullanıcı veri klasörüne yazılır.
##   godot --resolution 1600x900 --path . --script res://tools/voter_groups_preview.gd

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
	for i in 5:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isci", "ilerici"], true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	gm._set_phase(gm.Phase.IDLE)
	var me: int = mm.owner_id
	cm.current_turn_index = cm.turn_order.find(me)
	cm.funds[me] = 120.0
	cm.speech_rounds = {}
	cm.agenda = {"type": "gundem_isci", "until": cm.round_number + 1}
	cm.crisis = {"type": "kriz_isveren", "until": cm.round_number + 1}
	cm.group_meetings[me] = {"emekli": cm.round_number}
	pm.apply_group_deltas([{"peer": me, "group": "isci", "amount": 6.0}])
	cm._push_state({"type": "timer"})

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(30)
	_shot("vg_board")
	var province: String = String(cm._province_ids[5])
	cm.organizations[province] = {me: 2}
	scene._on_province_clicked(province)
	await _frames(10)
	_shot("vg_province_top")
	var panel: Node = scene._province_panel
	if panel != null and panel._scroll != null:
		panel._scroll.scroll_vertical = 420
		await _frames(5)
		_shot("vg_province_mid")
		# Başkası hamle yapınca panel tazelenir: kaydırılan yer korunmalı.
		var before: int = panel._scroll.scroll_vertical
		cm._add_local(province, me, 1.0)
		cm.opinion_changed.emit()
		scene._on_opinion_changed()
		await _frames(5)
		print("KAYDIRMA KORUNDU: %s (%d -> %d)" % [str(before > 0 and panel._scroll.scroll_vertical == before), before, panel._scroll.scroll_vertical])
		panel._scroll.scroll_vertical = 900
		await _frames(5)
		_shot("vg_province_bottom")
	scene._province_panel.hide()
	scene._toggle_profile(me)
	await _frames(10)
	_shot("vg_profile_me")
	scene._hide_profile()
	await _frames(3)
	scene._on_law_button_pressed()
	await _frames(10)
	_shot("vg_law_designer")
	scene._law_designer.hide()
	scene._on_speech_button_pressed()
	await _frames(10)
	_shot("vg_meeting_panel")
	scene._speech_panel.hide()
	scene._speech_open_key = ""
	for group in ["isci", "dindar", "ozerkci"]:
		scene._map_group = group
		scene._set_map_layer(3, false)
		scene._refresh_layer_bar()
		scene._apply_map_layer_colors()
		await _frames(12)
		_shot("vg_map_%s" % group)
	quit()
