extends SceneTree
## TUR AKIŞI ÖNİZLEMESİ (0.0.231): KART ÇEK, kart açılışı, afet yardım sahnesi,
## MECLİS akışı (gensoru, toplantı, yasa), il işlem paneli (miting ve karalama,
## yatırım). Ekran görüntüleri user:// içine tf_*.png; ekrana sığma kontrolleri.
##   godot --resolution 1280x720 --path . --script res://tools/turn_flow_preview.gd
##   (PREVIEW_SIZE=900x600 gibi dar ekran da denenebilir)

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), name])

func _inside(control: Control) -> bool:
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	return view.encloses(control.get_global_rect().grow(-1.0))

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
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	var gp = root.get_node("GovernmentPresets")
	bm.set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 3:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	var me: int = mm.owner_id
	var gov: int = int(mm.bot_ids()[0])
	var seats := {}
	for pid in cm.party_ids():
		seats[int(pid)] = 60
	seats[me] = 120
	seats[gov] = 200
	cm.last_seats = seats
	var posts := {}
	for post in gp.POSTS:
		posts[post["id"]] = gov
	gm.government = posts
	gm.main_gov_peer_id = gov
	gm._set_phase(gm.Phase.GOVERNING)
	gm.formed_round = -5
	cm.funds[me] = 150.0
	cm.inventories[me] = ["karalama", "kaset", "steal_weak"]
	cm.start_disaster("sel", [String(cm._province_ids[4])])
	cm.current_turn_index = cm.turn_order.find(me)
	cm._grant_turn_income()
	cm._push_state({"type": "timer"})

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	Input.warp_mouse(Vector2(2, 2))
	await _wait(0.6)
	check("gazete oynarken KART CEK ust uste acilmaz", not scene._event_fx.is_playing() or scene._turn_intro.mode == scene._turn_intro.Mode.NONE)
	await _wait(0.6)
	scene._event_fx.skip_all()
	await _wait(0.8)
	check("sira basinda KART CEK ekrani", scene._turn_intro.mode == scene._turn_intro.Mode.PROMPT)
	_shot("tf_1_draw")
	cm.draw_turn_card()
	await _wait(0.8)
	_shot("tf_2_reveal")
	await _wait(1.5)
	check("sans karti sureyle kapanmaz, ATLA bekler", scene._turn_intro.mode == scene._turn_intro.Mode.REVEAL)
	for child in scene._turn_intro._layer.get_children():
		if child is Button:
			(child as Button).pressed.emit()
	for i in 40:
		if scene._turn_intro.mode == scene._turn_intro.Mode.AID:
			break
		await _wait(0.25)
	await _wait(0.5)
	check("karttan sonra afet yardim sahnesi", scene._turn_intro.mode == scene._turn_intro.Mode.AID)
	_shot("tf_3_aid")
	if scene._turn_intro._aid_box != null:
		check("afet sahnesi ekrana sigiyor", _inside(scene._turn_intro._aid_box), str(scene._turn_intro._aid_box.get_global_rect()))
	scene._turn_intro._aid_panel.cancelled.emit()
	await _wait(0.4)
	check("BU TUR YARDIM YAPMA sonrasi sahne kapandi", not scene._turn_intro.is_busy() and cm.aid_decided(me))
	scene._refresh_turn_flow_ui()
	await _wait(0.3)
	_shot("tf_4_desk")
	check("MECLIS dugmesi gensoruyu gosteriyor", scene._parl_button.text.contains(L.t("gensoru")), scene._parl_button.text)
	scene._on_parliament_button_pressed()
	await _wait(1.0)
	_shot("tf_5_censure")
	check("gensoru asamasi acildi", scene._parliament_flow.visible and cm.parliament_stage(me) == "censure")
	check("meclis paneli ekrana sigiyor", _inside(scene._parliament_flow._panel), str(scene._parliament_flow._panel.get_global_rect()))
	cm.pass_parliament_stage("censure")
	await _wait(0.6)
	_shot("tf_6_speech")
	check("toplanti asamasi", cm.parliament_stage(me) == "speech")
	cm.pass_parliament_stage("speech")
	await _wait(0.6)
	_shot("tf_7_law")
	check("yasa alani", cm.parliament_stage(me) == "law")
	check("yasa paneli ekrana sigiyor", _inside(scene._parliament_flow._panel), str(scene._parliament_flow._panel.get_global_rect()))
	scene._on_flow_law_tab(0)
	await _wait(0.5)
	_shot("tf_8_law_designer")
	scene._law_designer.hide()
	scene._parliament_flow.close_flow()
	await _wait(0.2)
	var province: String = String(cm._province_ids[2])
	cm.organizations[province] = {me: 1}
	scene._on_province_clicked(province)
	await _wait(0.6)
	_shot("tf_9_province")
	check("il paneli acildi", scene._province_actions.visible)
	scene._province_actions.tab = "miting"
	scene._province_actions._smear = -1
	scene._province_actions.refresh()
	await _wait(0.3)
	_shot("tf_10_miting")
	check("karalama secenegi kart eldeyken gorunur", cm.smear_targets(me, province).size() > 0)
	check("il paneli ekrana sigiyor", _inside(scene._province_actions), str(scene._province_actions.get_global_rect()))
	scene._province_actions._scroll.scroll_vertical = 2000
	await _wait(0.2)
	_shot("tf_11_miting_summary")
	var before: float = cm.funds_of(me)
	var smears_before: int = cm.my_inventory().count("karalama")
	scene._province_actions._do_miting(0.0)
	await _wait(0.5)
	check("arayuzden miting yapildi, karalama karti elde kaldi", cm.miting_count(me) == 1 and cm.my_inventory().count("karalama") == smears_before,
		"%.0f -> %.0f" % [before, cm.funds_of(me)])
	scene._province_actions.tab = "invest"
	scene._province_actions.refresh()
	await _wait(0.3)
	_shot("tf_12_invest_opposition")
	scene._province_actions.close()
	await _wait(0.4)
	check("panel kapaninca harita eski olcege doner", is_equal_approx(scene.map_holder.scale.x, scene._map_fit_scale))
	# 0.0.237 KARALAMA: karta dokun → ile dokun → evrensel parti listesi → parti.
	var card_index: int = cm.my_inventory().find("karalama")
	scene._on_hand_card_clicked(card_index)
	await _wait(0.2)
	check("karalama kartina dokununca il secimi bekler", scene._pending_province_hand_index == card_index)
	scene._on_province_clicked(province)
	await _wait(0.4)
	_shot("tf_13_smear_picker")
	var picker = scene._inquiry_picker
	check("ile dokununca parti listesi acildi", picker != null and is_instance_valid(picker) and picker.visible)
	check("il paneli acilmadi (karalama hedefi)", not scene._province_actions.visible)
	var target_button: Button = null
	for node in picker.find_children("*", "Button", true, false):
		if (node as Button).text != "İptal" and target_button == null:
			target_button = node
	var target_local_before: float = cm.local_of(province, int(cm.smear_targets(me, province)[0]))
	target_button.pressed.emit()
	await _wait(0.4)
	check("parti secilince karalama oynandi, kart dustu", cm.my_inventory().count("karalama") == smears_before - 1,
		"hedef il puani %.2f -> %.2f" % [target_local_before, cm.local_of(province, int(cm.smear_targets(me, province)[0]) if not cm.smear_targets(me, province).is_empty() else -1)])
	# Teşkilatsız ile karalama: liste açılmaz.
	cm.inventories[me] = cm.inventories[me] + ["karalama"]
	cm._push_state({"type": "timer"})
	await _wait(0.3)
	var other: String = String(cm._province_ids[30])
	scene._on_hand_card_clicked(cm.my_inventory().find("karalama"))
	scene._on_province_clicked(other)
	await _wait(0.3)
	check("teskilatsiz ilde parti listesi acilmaz", scene._inquiry_picker == null or not is_instance_valid(scene._inquiry_picker))
	# Sürükleme: harita dışına bırakmak iptal, kart elde kalır.
	scene._start_smear_drag(cm.my_inventory().find("karalama"), "karalama", null)
	await _wait(0.1)
	Input.warp_mouse(Vector2(2, 2))
	scene._finish_smear_drag()
	await _wait(0.2)
	check("harita disina birakilan karalama iptal", cm.my_inventory().has("karalama") and scene._smear_ghost == null)
	print("=== TURN FLOW PREVIEW: %s ===" % ("PASS" if fails == 0 else "%d HATA" % fails))
	quit()
