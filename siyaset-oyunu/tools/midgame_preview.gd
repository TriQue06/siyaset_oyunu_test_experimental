extends SceneTree
## GERÇEK OYUN HÂLİ: birkaç tur botlarla oynanmış, seçim yapılmış, hükümet
## kurulmuş ve ELDE KART olan bir oyunun ekran görüntüsü.
##   godot --path . --script res://tools/midgame_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	# PREVIEW_SIZE=1280x720 gibi: kullanıcının tam ekran ayarına dokunmadan pencere boyutu.
	var forced := OS.get_environment("PREVIEW_SIZE")
	if forced != "":
		var parts := forced.split("x")
		for i in 3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
			await process_frame
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	mm.start_offline("Barış")
	for i in 5:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"),
		["isveren", "ilerici"], true)
	cm.set_rng_seed(4242)
	bm._rng.seed = 4242
	gm.result_hold_seconds = 0.2
	# SEÇİM VE HÜKÜMET OLUŞANA KADAR sanal saatle oynat.
	var now := 0.0
	while now < 4000.0 and not (gm.has_government() and cm.round_number >= 6):
		now += 0.2
		cm.tick(0.2)
		gm.tick(0.2)
		bm.step(now)
		if gm.phase == gm.Phase.VOTING and gm.eligible_voter_ids().has(mm.owner_id) \
				and not gm.has_voted(mm.owner_id):
			gm._apply_vote(mm.owner_id, gm.VOTE_YES)
	print("tur=%d hukumet=%s elde kart=%d" % [cm.round_number, str(gm.has_government()),
		cm.inventories.get(mm.owner_id, []).size()])

	# YASA OYLAMASI AÇIK: teklifi veren parti rozeti bu sırada görünür.
	gm.result_hold_seconds = 999.0
	gm.submit_law(mm.owner_id, "law:isveren")
	print("yasa oylamasi: %s / teklif veren %d" % [gm.proposal_kind, gm.proposal_peer_id])

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(30)
	var left: Control = scene.get_node("LeftPanel")
	var board: Control = scene.get_node("%ParliamentBoard")
	var lr := left.get_global_rect()
	var br := board.get_global_rect()
	print("OLCUM sol=%.0f..%.0f tahta=%.0f..%.0f -> %s" % [lr.position.x, lr.end.x,
		br.position.x, br.end.x, "CAKISMA VAR" if lr.intersects(br) else "temiz"])
	# OY SIRASI SÜTUNA SIĞIYOR MU? Taşarsa sol panelin altına kayıyor.
	var row: Control = scene.get_node("%VoteButtonRow")
	var chamber: Control = scene.get_node("BottomArea/ChamberSplit/ParliamentChamber")
	var rr := row.get_global_rect()
	print("OY SIRASI  asgari=%.0f  sutun=%.0f  satir=%.0f..%.0f  -> %s" % [
		row.get_combined_minimum_size().x, chamber.size.x, rr.position.x, rr.end.x,
		"SOL PANELIN ALTINDA" if rr.position.x < lr.end.x else "temiz"])
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/midgame.png" % OS.get_user_data_dir())
		print("screenshot: midgame")
		var cmx = root.get_node("CardManager")
		var saved_agenda: Dictionary = cmx.agenda
		cmx.agenda = {"type": "gundem_isveren", "until": cmx.round_number + 1, "index": 1}
		scene._refresh_agenda_banner()
		await create_timer(0.2).timeout
		root.get_texture().get_image().save_png("%s/midgame_agenda.png" % OS.get_user_data_dir())
		print("screenshot: midgame_agenda")
		cmx.agenda = saved_agenda
		scene._refresh_agenda_banner()
		scene._on_law_button_pressed()
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("%s/midgame_law.png" % OS.get_user_data_dir())
		print("screenshot: midgame_law")
		scene._on_law_button_pressed()
		scene._set_map_layer(1, false)
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("%s/midgame_org.png" % OS.get_user_data_dir())
		print("screenshot: midgame_org")
		# Güç haritası: teşkilatın olduğu illerde oy bandı (1. seviye yaklaşık, 2. seviye %90).
		var cmp = root.get_node("CardManager")
		for i in 14:
			var org_pid: String = cmp._province_ids[i * 3 % cmp._province_ids.size()]
			var orgs: Dictionary = cmp.organizations.get(org_pid, {})
			orgs[mm.owner_id] = 1 + i % 2
			cmp.organizations[org_pid] = orgs
		scene._set_map_layer(2, false)
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("%s/midgame_power.png" % OS.get_user_data_dir())
		print("screenshot: midgame_power")
		# MECLİS KONUŞMASI: sıra bende, henüz konuşmadım.
		var cms = root.get_node("CardManager")
		cms.current_turn_index = cms.turn_order.find(mm.owner_id)
		cms.speech_done = false
		gm._clear_proposal()
		gm._set_phase(gm.Phase.GOVERNING)
		cms._push_state({"type": "timer"})
		scene._on_speech_button_pressed()
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("%s/midgame_speech.png" % OS.get_user_data_dir())
		print("screenshot: midgame_speech")
		# İkinci konuşma: panel genişlememeli (eski sütunlar hemen kalkmalı).
		var first_width: float = scene._speech_panel.size.x
		cms.speech_done = true
		cms._push_state({"type": "timer"})
		pm.parties[mm.owner_id]["groups"]["isveren"] = 75.0
		cms.speech_done = false
		cms._push_state({"type": "timer"})
		scene._speech_open_key = "%d:%d" % [cms.round_number, cms.current_turn_index]
		scene._refresh_speech_panel()
		await create_timer(0.3).timeout
		print("KONUSMA SERIDI genislik %.0f -> %.0f %s" % [first_width, scene._speech_panel.size.x,
			"AYNI" if absf(first_width - scene._speech_panel.size.x) < 1.0 else "GENISLEDI"])
		scene._speech_panel.hide()
		scene._set_map_layer(0, false)
		await create_timer(0.3).timeout
		# Olay logundaki odak düğmesi: ili olan son kaydı haritada göster.

		# TIKLAMA MENÜLERİ: il paneli (teşkilat 2), parti profili, kart bilgisi.
		var cmq = root.get_node("CardManager")
		var pid: String = cmq._province_ids[0]
		var porgs: Dictionary = cmq.organizations.get(pid, {})
		porgs[mm.owner_id] = 2
		cmq.organizations[pid] = porgs
		scene._on_province_clicked(pid)
		await create_timer(0.4).timeout
		root.get_texture().get_image().save_png("%s/popup_province.png" % OS.get_user_data_dir())
		var pid2: String = cmq._province_ids[5]
		var o2: Dictionary = cmq.organizations.get(pid2, {})
		o2.erase(mm.owner_id)
		cmq.organizations[pid2] = o2
		scene._on_province_clicked(pid2)
		await create_timer(0.4).timeout
		root.get_texture().get_image().save_png("%s/popup_province_noorg.png" % OS.get_user_data_dir())
		scene._province_panel.hide()
		scene._toggle_profile(cmq.turn_order[2])
		await create_timer(0.4).timeout
		root.get_texture().get_image().save_png("%s/popup_party.png" % OS.get_user_data_dir())
		scene._toggle_profile(cmq.turn_order[2])
		if scene.hand_container.get_child_count() > 0:
			scene._show_card_info(String(cmq.my_inventory()[0]), scene.hand_container.get_child(0))
			await create_timer(0.3).timeout
			root.get_texture().get_image().save_png("%s/popup_card.png" % OS.get_user_data_dir())
			scene._card_info.hide()
		scene._show_toast("Bu ilde teşkilatın yok. Önce teşkilatlanmalısın.")
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("%s/popup_toast.png" % OS.get_user_data_dir())
		print("screenshot: popups")
		var focus_entry := {}
		for entry in root.get_node("CardManager").event_log:
			if String(entry.get("province", "")) != "":
				focus_entry = entry
		if not focus_entry.is_empty():
			scene._focus_log_entry(focus_entry)
			await create_timer(0.75).timeout
			root.get_texture().get_image().save_png("%s/midgame_focus.png" % OS.get_user_data_dir())
			print("screenshot: midgame_focus -> %s" % focus_entry["text"])
			await create_timer(1.0).timeout
			print("odak sonrasi harita olcegi geri dondu: %s" % str(scene.map_holder.scale.is_equal_approx(Vector2(scene._map_fit_scale, scene._map_fit_scale))))
	quit()
