extends SceneTree
## 8 oyunculu oyun ekranı: seçimden önce (boş beyaz meclis) ve sonra.
## Menü butonu / oyuncu kartları / mana çakışmalarını kontrol eder.
##   godot --resolution 1280x720 --script res://tools/crowded_preview.gd

const COLORS := ["F20C1F", "1C48C9", "F2920C", "8C21C2", "29A33D", "13DBED", "E619A8", "59BD28"]
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), name])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	root.get_node("BotManager").set_process(false)
	mm.room_code = ""
	mm.election_threshold = 3.0
	var me: int = root.multiplayer.get_unique_id()
	mm.players = {}
	pm.parties = {}
	for i in 8:
		var id: int = me if i == 0 else 100 + i
		mm.players[id] = {"name": "Oyuncu %d" % i, "bot": i > 0}
		pm.parties[id] = {"name": "Partim%d" % i, "icon_index": i * 3, "icon_color": Color.WHITE,
			"bg_color": Color(COLORS[i]), "ideology": {"economic": 0, "social": 0, "administrative": 0}, "ready": true}
	cm.init_game()
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(20)
	_layout_checks(scene)
	_shot("crowded_before")
	if DisplayServer.get_name() != "headless":
		var img := root.get_texture().get_image()
		var d: ParliamentDiagram = scene.parliament_diagram
		var k: float = float(img.get_width()) / root.get_visible_rect().size.x
		var r := Rect2i(Rect2(d.get_global_rect().position * k, d.get_global_rect().size * k))
		var z := img.get_region(r)
		z.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)
		z.save_png("%s/zoom_parliament.png" % OS.get_user_data_dir())
	cm._hold_election(1, false)
	var gm = root.get_node("GovernmentManager")
	scene.queue_free()
	root.get_node("SceneTransition").queue_free()
	scene = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	gm._set_phase(gm.Phase.IDLE)
	root.add_child(scene)
	await _frames(30)
	if DisplayServer.get_name() != "headless":
		var img := root.get_texture().get_image()
		var d: ParliamentDiagram = scene.parliament_diagram
		var k: float = float(img.get_width()) / root.get_visible_rect().size.x
		var r := Rect2i(Rect2(d.get_global_rect().position * k, d.get_global_rect().size * k))
		var z := img.get_region(r)
		z.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)
		z.save_png("%s/zoom_parliament_after.png" % OS.get_user_data_dir())
	_shot("crowded_after")
	# Harita katmanları: örnek teşkilat, güç ve gözcü verisi.
	cm.organizations = {"istanbul": {me: 3}, "ankara": {me: 2}, "izmir": {me: 1}, "konya": {me: 1}, "bursa": {me: 2}}
	var ids: Array = scene.map_holder.get_all_province_ids()
	for i in ids.size():
		cm.local_support[ids[i]] = {me: sin(i * 0.7) * 5.0}
		if i % 4 == 0:
			cm.intel[me] = cm.intel.get(me, {})
			var scouts: Dictionary = cm.intel[me].get("scouts", {})
			scouts[ids[i]] = cm.round_number + 1 + (i / 4) % 5
			var known: Dictionary = cm.intel[me].get("known", {})
			known[ids[i]] = true
			cm.intel[me]["known"] = known
			cm.intel[me]["scouts"] = scouts
	cm.current_turn_index = 2
	cm._push_state({"type": "timer"})
	await _frames(10)
	for layer in [1, 2, 3, 0]:
		scene._on_layer_button_pressed(layer)
		await create_timer(0.2).timeout
		if layer == 1:
			_shot("layer_sliding")
		await create_timer(0.4).timeout
		_shot("layer_%d" % layer)
		print("layer istendi ", layer, " -> ", scene._map_layer, " switching ", scene._layer_switching, " queued ", scene._queued_layer)
	check("vekil katmaninda vekil daireleri gorunur", scene.map_holder.get_node("SeatMarkers").visible)
	scene._on_layer_button_pressed(2)
	await create_timer(0.6).timeout
	cm.current_turn_index = cm.turn_order.find(me)
	cm.mana[me] = 5
	cm._push_state({"type": "timer"})
	await _frames(5)
	scene._on_scout_button_pressed()
	await create_timer(0.6).timeout
	check("gozcu butonu haritayi gozcu katmanina alir", scene._map_layer == 3)
	_shot("scout_pending")
	scene._on_scout_button_pressed()
	await create_timer(0.6).timeout
	check("iptal: onceki katmana (guc) doner, mana harcanmaz", scene._map_layer == 2 and cm.mana_of(me) == 5)
	scene._on_scout_button_pressed()
	var target := ""
	for id in ids:
		if not cm.has_scouted(me, id) and not cm.knows_leaning(me, id):
			target = id
			break
	scene._on_province_clicked(target)
	scene._on_province_clicked(target)
	check("gozcu gonderildi, 1 mana", cm.has_scouted(me, target) and cm.mana_of(me) == 4)
	await create_timer(0.3).timeout
	check("gonderince bir an gozcu katmaninda kalir", scene._map_layer == 3)
	await create_timer(1.6).timeout
	check("sonra onceki katmana doner", scene._map_layer == 2)
	_shot("my_turn")
	scene._on_miting_button_pressed()
	scene._on_province_clicked("konya")
	await _frames(3)
	_shot("miting_pending")
	check("miting: ilk dokunus riski gosterir", String(scene._target_hint.text).find("provokasyon") != -1)
	scene._on_province_clicked("konya")
	check("miting hamlesi yapildi (3 mana)", cm.mana_of(me) == 1)
	cm.mana[me] = 10
	cm.inventories[me] = ["populizm", "mana_bonusu", "karalama"]
	cm._push_state({"type": "timer"})
	await _frames(5)
	scene._on_hand_card_clicked(0)
	await _frames(3)
	scene._on_hand_card_clicked(0)
	await _frames(5)
	check("populizm karti iki dokunusla kullanildi", cm.populism_rounds_left(me) == GameRules.POPULISM_ROUNDS and cm.mana_of(me) == 8)
	scene._on_censure_button_pressed()
	await _frames(3)
	check("cogunluk yokken bile hukumet yoksa gensoru acilmaz", not scene._pending_censure)
	_shot("bonus_cards")
	# İl paneli: gözcülü ve gözcüsüz il.
	scene._cancel_targeting()
	scene._on_layer_button_pressed(0)
	await create_timer(0.6).timeout
	var scouted := ""
	var plain := ""
	for id in ids:
		if scouted == "" and cm.has_scouted(me, id) and cm.province_seat_count(id) >= 8:
			scouted = id
		if plain == "" and not cm.has_scouted(me, id) and not cm.knows_leaning(me, id):
			plain = id
	scene._on_province_clicked(scouted)
	await _frames(5)
	check("gozculu ilde rapor var", scene._province_panel.visible)
	_shot("panel_scouted")
	scene._on_province_clicked(scouted)
	scene._on_province_clicked(plain)
	await _frames(5)
	_shot("panel_plain")
	scene._province_panel.hide()
	scene._on_layer_button_pressed(3)
	await create_timer(0.6).timeout
	_shot("layer_scout_rounds")
	cm._end_game("32 tur tamamlandı. Son seçimle kurulan Partim3 hükümeti makam puanlarını aldı.")
	await create_timer(0.4).timeout
	_shot("game_over_fading")
	await create_timer(3.0).timeout
	var ov: Control = scene._game_over_overlay
	print("overlay rect ", ov.get_global_rect(), " children ", ov.get_child_count(), " bd mod ", (ov.get_child(0) as CanvasItem).modulate, " bd rect ", (ov.get_child(0) as Control).get_global_rect(), " vp ", root.get_visible_rect())
	await create_timer(4.0).timeout
	_shot("game_over")
	print("=== CROWDED PREVIEW: %s ===" % ("PASS" if fails == 0 else "%d HATA" % fails))
	quit()

func _layout_checks(scene: Node) -> void:
	var list: Control = scene.player_panel_list
	var menu := root.get_node("SettingsOverlay").find_child("OpenSettingsButton", true, false) as Control
	var first: Rect2 = (list.get_child(0) as Control).get_global_rect()
	var last: Rect2 = (list.get_child(list.get_child_count() - 1) as Control).get_global_rect()
	if menu != null:
		check("menu butonu ilk oyuncuyla cakismiyor", not menu.get_global_rect().intersects(first), "%s / %s" % [menu.get_global_rect(), first])
	print("panel ", (list.get_parent() as Control).get_global_rect(), " list ", list.get_global_rect(), " h ", scene._avatar_height)
	var mana: Control = scene._mana_box
	check("mana son oyuncuyla cakismiyor", not mana.get_global_rect().intersects(last), "%s / %s" % [mana.get_global_rect(), last])
