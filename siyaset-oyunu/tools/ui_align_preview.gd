extends SceneTree
## HİZA DENETİMİ (0.0.238): yan yana duran düğme / kutu / logo gibi öğelerin
## yüksekliği ve üst kenarı aynı mı? Parti kurma ekranı ve oyun ekranının
## birkaç hâlinde (il paneli, miting, yatırım, parti listesi, meclis akışı)
## görünür her HBoxContainer taranır; farklı yükseklikte kutular listelenir.
## Ekran görüntüleri user:// içine align_*.png.
##   godot --resolution 1280x720 --path . --script res://tools/ui_align_preview.gd

const TOLERANCE := 1.0
var problems := 0
var rows_checked := 0

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/align_%s.png" % [OS.get_user_data_dir(), name])

static func _is_box(c: Control) -> bool:
	if c is Label or c is RichTextLabel:
		return false
	if c is BaseButton or c is PanelContainer or c is Panel or c is TextureRect or c is LineEdit or c is ColorRect:
		return true
	return c.custom_minimum_size.y > 0.0 and not (c is Container)

static func _desc(c: Control) -> String:
	var text := ""
	if c is Button:
		text = (c as Button).text.replace("\n", " ")
	elif c.get_child_count() > 0 and c.get_child(0) is Label:
		text = (c.get_child(0) as Label).text
	return "%s'%s'" % [c.get_class(), text.substr(0, 18)]

func audit(node: Node, tag: String) -> void:
	var found: Array = []
	_scan(node, found)
	_neighbors(node, found)
	print("--- %s: %d hiza sorunu (%d satir tarandi)" % [tag, found.size(), rows_checked])
	rows_checked = 0
	for line in found:
		print("   " + line)
	problems += found.size()

## Konumdan bağımsız: ekranda yan yana (dikeyde çakışan, aralarında az boşluk
## olan) iki düğme / kutu üst ve alt kenarı aynı hizada olmalı.
func _neighbors(node: Node, found: Array) -> void:
	var items: Array = []
	_collect(node, items)
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Control = items[i]
			var b: Control = items[j]
			var ra := a.get_global_rect()
			var rb := b.get_global_rect()
			if ra.encloses(rb) or rb.encloses(ra) or a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			# Ancak benzer boydaki öğeler karşılaştırılır (düğmenin yanındaki uzun panel değil).
			if maxf(ra.size.y, rb.size.y) > minf(ra.size.y, rb.size.y) * 1.4:
				continue
			var overlap := minf(ra.end.y, rb.end.y) - maxf(ra.position.y, rb.position.y)
			if overlap < minf(ra.size.y, rb.size.y) * 0.6:
				continue
			var gap := maxf(rb.position.x - ra.end.x, ra.position.x - rb.end.x)
			if gap < -1.0 or gap > 28.0:
				continue
			var dt := absf(ra.position.y - rb.position.y)
			var db := absf(ra.end.y - rb.end.y)
			if dt > TOLERANCE or db > TOLERANCE:
				found.append("YAN YANA %s [%s y%.0f-%.0f] ~ %s [%s y%.0f-%.0f]" % [_desc(a), str(a.get_path()).get_file(), ra.position.y, ra.end.y,
					_desc(b), str(b.get_path()).get_file(), rb.position.y, rb.end.y])

func _collect(node: Node, items: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control and (node is BaseButton or node is PanelContainer or node is LineEdit) 			and (node as Control).size.y >= 16.0 and (node as Control).size.x >= 16.0:
		var empty: bool = node is PanelContainer and (node as Control).get_theme_stylebox("panel") is StyleBoxEmpty
		if not empty:
			items.append(node)
	for child in node.get_children():
		_collect(child, items)

func _scan(node: Node, found: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is HBoxContainer:
		var boxes: Array = []
		for child in node.get_children():
			if child is Control and (child as Control).visible and _is_box(child) and (child as Control).size.x > 2.0:
				boxes.append(child)
		if boxes.size() >= 2:
			rows_checked += 1
			var lo := INF
			var hi := -INF
			var top_lo := INF
			var top_hi := -INF
			for b in boxes:
				var r: Rect2 = (b as Control).get_global_rect()
				lo = minf(lo, r.size.y)
				hi = maxf(hi, r.size.y)
				top_lo = minf(top_lo, r.position.y)
				top_hi = maxf(top_hi, r.position.y)
			if hi - lo > TOLERANCE or top_hi - top_lo > TOLERANCE:
				var parts: PackedStringArray = []
				for b in boxes:
					var r: Rect2 = (b as Control).get_global_rect()
					parts.append("%s y%.0f h%.0f" % [_desc(b), r.position.y, r.size.y])
				found.append("%s :: %s" % [str(node.get_path()).replace("/root/", ""), " | ".join(parts)])
	for child in node.get_children():
		_scan(child, found)

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	var gp = root.get_node("GovernmentPresets")

	# 0) ANA MENÜ, AYARLAR, ODA
	var menu: Node = (load("res://scenes/Lobby.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _frames(12)
	_shot("menu_online")
	audit(menu, "ana menu (cevrim ici)")
	menu._set_mode(false)
	await _frames(6)
	_shot("menu_offline")
	audit(menu, "ana menu (cevrim disi)")
	var overlay = root.get_node("SettingsOverlay")
	overlay.open()
	await _wait(0.4)
	_shot("settings")
	audit(overlay, "ayarlar menusu")
	overlay.close() if overlay.has_method("close") else overlay.panel.hide()
	menu.queue_free()
	await _frames(2)
	var me_l: int = root.multiplayer.get_unique_id()
	mm.owner_id = me_l
	mm.stage = mm.Stage.LOBBY
	mm.players = {me_l: {"name": "Barış"}}
	mm.room_code = ""
	mm.add_bot()
	mm.add_bot()
	mm.room_code = "ABCDE"
	var room: Node = (load("res://scenes/RoomLobby.tscn") as PackedScene).instantiate()
	root.add_child(room)
	await _frames(10)
	_shot("room")
	audit(room, "oda lobisi")
	var timing: Control = room._setting_sections["timing"]
	var rules_scroll: ScrollContainer = room.settings_side_panel.find_children("*", "ScrollContainer", true, false)[0]
	rules_scroll.scroll_vertical = int(timing.get_global_rect().position.y - rules_scroll.get_global_rect().position.y)
	await _frames(4)
	_shot("room_timing")
	audit(room, "oda lobisi: sureler")
	room.queue_free()
	await _frames(2)

	# 1) PARTİ KURMA
	var gmap = root.get_node("GameMap")
	gmap.generate_new(4242)
	var me0: int = root.multiplayer.get_unique_id()
	mm.room_code = ""
	mm.owner_id = me0
	mm.players = {me0: {"name": "Barış Tanlık"}}
	pm.parties = {}
	pm.politicians = {}
	pm.my_politician = {}
	var setup: Node = (load("res://scenes/PartySetup.tscn") as PackedScene).instantiate()
	root.add_child(setup)
	await _frames(8)
	_shot("setup_1")
	audit(setup, "parti kurma 1. adim")
	for step in [1, 2, 3, 4]:
		setup._show_step(step)
		await _frames(4)
		_shot("setup_%d" % (step + 1))
		audit(setup, "parti kurma %d. adim" % (step + 1))
	setup.queue_free()
	await _frames(2)

	# 2) OYUN EKRANI
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
	cm.inventories[me] = ["karalama", "kaset", "steal_weak"]
	cm.current_turn_index = cm.turn_order.find(me)
	cm._grant_turn_income()
	cm._push_state({"type": "timer"})
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	Input.warp_mouse(Vector2(2, 2))
	await _wait(1.0)
	scene._event_fx.skip_all()
	await _wait(0.5)
	audit(root, "kart cek ekrani")
	cm.draw_turn_card()
	await _wait(3.0)
	for child in scene._turn_intro._layer.get_children():
		if child is Button:
			(child as Button).pressed.emit()
	await _wait(0.5)
	_shot("game_1")
	audit(root, "oyun ekrani")
	# Vekil haritası: fare bir ilin üstüne gelince ayrı noktalar (geçişli).
	var busiest := ""
	var most := 0
	var markers = scene.map_holder.get_node("SeatMarkers")
	for pid in markers._seats.keys():
		var n: int = (markers._seats[pid] as Array).size()
		if n > most and n <= 30:
			most = n
			busiest = String(pid)
	scene.map_holder.province_hovered.emit(busiest)
	await _wait(0.05)
	_shot("game_hover_mid")
	await _wait(0.3)
	_shot("game_hover")
	scene.map_holder.province_hovered.emit("")
	await _wait(0.2)
	scene._on_layer_button_pressed(3)
	await _wait(0.3)
	_shot("game_voter_layer")
	scene._on_layer_button_pressed(0)
	await _wait(0.2)
	var province: String = String(cm._province_ids[2])
	cm.organizations[province] = {me: 2}
	scene._on_province_clicked(province)
	await _wait(0.6)
	audit(root, "il paneli")
	for tab in ["org", "miting", "invest"]:
		scene._province_actions.tab = tab
		scene._province_actions.refresh()
		await _wait(0.3)
		_shot("game_%s" % tab)
		var pa: Control = scene._province_actions
		print("PANEL %s rect %s panel_width %.0f" % [tab, pa.get_global_rect(), pa.panel_width])
		for c in pa._body.get_children():
			if c is Control and (c as Control).get_combined_minimum_size().x > pa.panel_width - 30.0:
				print("   GENIS %s min %.0f" % [_desc(c), (c as Control).get_combined_minimum_size().x])
				for cc in c.get_children():
					if cc is Control:
						print("      - %s min %.0f" % [_desc(cc), (cc as Control).get_combined_minimum_size().x])
		audit(root, "il paneli: %s" % tab)
	scene._province_actions.close()
	await _wait(0.4)
	scene._show_party_picker("Gülkent: kimi karalayacaksın?", cm.smear_targets(me, province) if not cm.smear_targets(me, province).is_empty() else cm.party_ids().filter(func(p): return int(p) != me), func(_p): pass)
	await _wait(0.3)
	_shot("game_picker")
	audit(root, "parti listesi")
	scene._party_picker.queue_free()
	scene._parliament_flow.open_flow() if scene._parliament_flow.has_method("open_flow") else null
	await _wait(0.5)
	_shot("game_parliament")
	audit(root, "meclis akisi")
	scene._parliament_flow.hide()
	scene._on_alliance_button_pressed()
	await _wait(0.4)
	_shot("game_alliance")
	audit(root, "ittifak paneli")
	print("=== HIZA DENETIMI: %d sorun ===" % problems)
	quit()
