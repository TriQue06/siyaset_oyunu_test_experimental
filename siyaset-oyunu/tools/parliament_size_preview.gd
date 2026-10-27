extends SceneTree
## MECLİS PENCERESİ BOYU ve ÜST BANT (0.0.260): meclis penceresinin her sekmede
## ve her yasa sayfasında aynı boyda kaldığını ölçer; üst bant (kriz, sıra,
## Menü), YARDIM düğmesi ve yardım paneli için ekran görüntüleri alır
## (user:// içine parl_*.png).
##   godot --resolution 1920x957 --path . --script res://tools/parliament_size_preview.gd

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/parl_%s.png" % [OS.get_user_data_dir(), name])

func _initialize() -> void:
	await process_frame
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	var gp = root.get_node("GovernmentPresets")
	root.get_node("GameMap").generate_new(4242)
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
		posts[post["id"]] = me
	gm.government = posts
	gm.main_gov_peer_id = me
	gm._set_phase(gm.Phase.GOVERNING)
	gm.formed_round = -5
	cm.funds[me] = 150.0
	cm.agenda = {"type": "kriz_isveren", "until": cm.round_number + 1}
	cm.current_turn_index = cm.turn_order.find(me)
	cm._grant_turn_income()
	cm._push_state({"type": "timer"})
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	Input.warp_mouse(Vector2(2, 2))
	await _wait(1.0)
	scene._event_fx.skip_all()
	await _wait(0.5)
	cm.draw_turn_card()
	await _wait(3.0)
	for child in scene._turn_intro._layer.get_children():
		if child is Button:
			(child as Button).pressed.emit()
	await _wait(0.5)
	_shot("game")

	print("=== ÜST BANT ===")
	var menu: Rect2 = scene._menu_button_rect()
	var turn: Rect2 = scene._band_turn.get_global_rect()
	var crisis: Rect2 = scene._band_crisis.get_global_rect()
	var band: Rect2 = scene._strip_bg.get_global_rect()
	var top_gap := menu.position.y - band.position.y
	var bottom_gap := band.end.y - menu.end.y
	print("  menu %s  turn %s  crisis %s  band %s" % [menu, turn, crisis, band])
	check("sıra–Menü boşluğu Menü'nün üst/alt boşluğu kadar", absf((menu.position.x - turn.end.x) - (top_gap + bottom_gap) * 0.5) <= 1.0,
		"%.1f / üst %.1f alt %.1f" % [menu.position.x - turn.end.x, top_gap, bottom_gap])
	check("kriz–sıra boşluğu aynı", absf((turn.position.x - crisis.end.x) - (menu.position.x - turn.end.x)) <= 1.0,
		"%.1f" % (turn.position.x - crisis.end.x))
	check("üç kutu aynı yükseklikte", absf(turn.size.y - menu.size.y) <= 1.0 and absf(crisis.size.y - menu.size.y) <= 1.0)
	check("para levhasının üstünde sıra yazısı yok", not (scene._desk_labels["turn"] as Label).visible)
	check("KONGRE düğmesi yok, YARDIM var", scene._congress_button == null and scene._aid_button != null and scene._aid_button.is_visible_in_tree())

	print("=== MECLİS PENCERESİ ===")
	var flow = scene._parliament_flow
	var sizes := {}
	flow.open_flow()
	await _wait(0.4)
	for tab in ["censure", "law"]:
		flow._tab = tab
		flow._law_page = false
		flow._shown_key = "x"
		flow._build()
		await _wait(0.3)
		sizes[tab] = flow._panel.size
		print("  %s: boy %s, içerik %s" % [tab, flow._panel.size, flow._panel.get_combined_minimum_size()])
		_shot("tab_%s" % tab)
	for page in [0, 1, 2]:
		flow.open_law_page(page)
		await _wait(0.4)
		sizes["law%d" % page] = flow._panel.size
		print("  yasa sayfası %d: boy %s, içerik %s" % [page, flow._panel.size, flow._panel.get_combined_minimum_size()])
		_shot("law_%d" % page)
		flow.leave_law_page()
		await _wait(0.2)
	var first: Vector2 = sizes.values()[0]
	var same := true
	for v in sizes.values():
		if (v as Vector2).distance_to(first) > 1.0:
			same = false
	check("meclis penceresi her sayfada aynı boyda", same, str(sizes))
	flow.close_flow()
	await _wait(0.2)

	print("=== AFET VE YARDIM ===")
	cm.last_election_round = maxi(1, cm.last_election_round)
	cm.start_disaster("deprem")
	cm._push_state({"type": "timer"})
	await _wait(0.4)
	check("afet varken yardım düğmesi açık", cm.can_aid(me))
	scene._on_aid_button_pressed()
	await _wait(0.4)
	_shot("aid_panel")
	check("YARDIM düğmesi yardım panelini açar", scene._aid_panel.visible)
	var funds_before: float = cm.funds_of(me)
	cm.aid(10.0, 0.0)
	await _wait(0.2)
	check("ilk yardım yapıldı", cm.funds_of(me) < funds_before)
	check("aynı sırada yardım yeniden yapılabilir", cm.can_aid(me), cm.aid_block_reason(me))
	var funds_mid: float = cm.funds_of(me)
	cm.aid(10.0, 0.0)
	check("üst üste ikinci yardım yapıldı", cm.funds_of(me) < funds_mid)
	print("=== %s ===" % ("HEPSİ GEÇTİ" if fails == 0 else "%d HATA" % fails))
	quit(1 if fails > 0 else 0)
