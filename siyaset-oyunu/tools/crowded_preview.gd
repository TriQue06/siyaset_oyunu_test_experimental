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
