extends SceneTree
## HİÇ PARTİ YOKKEN (ilk seçimden önce) sol panel parlamento diyagramını
## kapatıyor mu? Sol paneldeki hangi çocuğun ne kadar yer kapladığını da yazar.
##   godot --path . --script res://tools/empty_board_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _dump(node: Node, depth: int) -> void:
	if not (node is Control):
		return
	var c := node as Control
	print("%s%s  min=%.0f  genislik=%.0f" % ["  ".repeat(depth), node.name,
		c.get_combined_minimum_size().x, c.size.x])
	if depth >= 3:
		return
	for child in node.get_children():
		_dump(child, depth + 1)

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	root.get_node("BotManager").set_process(false)
	mm.start_offline("Barış")
	for i in 4:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"),
		{"economic": 0, "social": 0, "administrative": 0}, true)
	# İLK SEÇİMDEN ÖNCE: mecliste hiç vekil yok, hükümet yok.
	cm.last_seats = {}
	cm.last_vote_shares = {}
	cm.election_seats = {}

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(25)
	# EN-BOY ORANI DEGISINCE mantiksal genislik de degisiyor (stretch = expand):
	# dar ve genis pencerelerde ayri ayri olc.
	for window_size in [Vector2i(1152, 648), Vector2i(1024, 768), Vector2i(960, 720),
			Vector2i(800, 600), Vector2i(1280, 800), Vector2i(2560, 1080), Vector2i(1280, 1024)]:
		DisplayServer.window_set_size(window_size)
		await _frames(8)
		var l: Control = scene.get_node("LeftPanel")
		var b2: Control = scene.get_node("%ParliamentBoard")
		var lr2 := l.get_global_rect()
		var br3 := b2.get_global_rect()
		print("PENCERE %s -> gorunum %s  sol=%.0f..%.0f  tahta=%.0f..%.0f  %s" % [
			str(window_size), str(root.get_visible_rect().size), lr2.position.x, lr2.end.x,
			br3.position.x, br3.end.x, "CAKISMA VAR" if lr2.intersects(br3) else "temiz"])
	DisplayServer.window_set_size(Vector2i(1152, 648))
	await _frames(8)
	var left: Control = scene.get_node("LeftPanel")
	var board: Control = scene.get_node("%ParliamentBoard")
	var bottom: Control = scene.get_node("%BottomArea")
	var lr := left.get_global_rect()
	var br := board.get_global_rect()
	print("gorunum = %s" % str(root.get_visible_rect().size))
	print("OLCUM  sol=%.0f..%.0f (min %.0f)  alt bolge sol=%.0f  tahta=%.0f..%.0f -> %s" % [
		lr.position.x, lr.end.x, left.get_combined_minimum_size().x,
		bottom.get_global_rect().position.x, br.position.x, br.end.x,
		"CAKISMA VAR" if lr.intersects(br) else "temiz"])
	print("--- sol panel agaci ---")
	_dump(left, 0)
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/empty_board.png" % OS.get_user_data_dir())
		print("screenshot: empty_board")
	quit()
