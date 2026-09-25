extends SceneTree
## SEÇİM GECESİ PERFORMANS ÖLÇÜMÜ. Web'deki gibi Compatibility ile çalıştır:
##   godot --rendering-method gl_compatibility --path . --script res://tools/election_perf.gd
## Parçaları tek tek devre dışı bırakıp hangisinin kare süresini yediğini bulur.

const PARTIES := [
	{"name": "Yeni Yol", "color": "F20C1F", "icon": 0, "ideology": {"economic": 1, "social": 1, "administrative": 2}},
	{"name": "Halkçı", "color": "1C48C9", "icon": 5, "ideology": {"economic": -2, "social": -1, "administrative": 1}},
	{"name": "Millet", "color": "F2920C", "icon": 12, "ideology": {"economic": 1, "social": 2, "administrative": 2}},
	{"name": "Özgürlük", "color": "8C21C2", "icon": 20, "ideology": {"economic": 2, "social": -2, "administrative": -1}},
	{"name": "Yeşiller", "color": "29A33D", "icon": 6, "ideology": {"economic": -1, "social": -2, "administrative": -2}},
	{"name": "Anadolu", "color": "13DBED", "icon": 30, "ideology": {"economic": -1, "social": 2, "administrative": -2}},
]

var _scene: Node

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## n kare boyunca ORTALAMA kare süresi (ms).
func measure(label: String, n: int) -> float:
	await _frames(10)  # ısınma
	var start := Time.get_ticks_usec()
	await _frames(n)
	var total := float(Time.get_ticks_usec() - start) / 1000.0
	var per_frame := total / float(n)
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	print("  %-38s %7.2f ms/kare  (~%3.0f FPS)  cizim_cagrisi=%d  ucgen=%d" % [
		label, per_frame, 1000.0 / maxf(per_frame, 0.01), int(calls), int(prims)])
	return per_frame

func _initialize() -> void:
	await process_frame
	# VSYNC KAPALI: yoksa tüm ölçümler monitör hızına takılıp farkları gizliyor.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	mm.room_code = ""
	mm.election_threshold = 7.0
	mm.players = {}
	pm.parties = {}
	for i in PARTIES.size():
		var p: Dictionary = PARTIES[i]
		mm.players[i + 1] = {"name": "Bot %d" % i, "bot": true}
		pm.parties[i + 1] = {"name": p["name"], "icon_index": p["icon"], "icon_color": Color.WHITE,
			"bg_color": Color(p["color"]), "ideology": p["ideology"].duplicate(), "ready": true}
	cm.init_game()
	cm.turn_order = [1, 2, 3, 4, 5, 6]
	cm._hold_election(1, false)

	_scene = (load("res://scenes/ElectionResults.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	await _frames(20)

	print("=== SECIM GECESI KARE SURESI (render: %s) ===" % RenderingServer.get_video_adapter_api_version())
	var base := await measure("1) her sey acik", 90)

	# 2) Parlamento diyagramini gizle (500 daire cizilmesin)
	_scene._parliament.visible = false
	var no_parliament := await measure("2) parlamento diyagrami KAPALI", 90)
	_scene._parliament.visible = true

	# 3) Harita yenilemeyi durdur (_refresh_map erken doner)
	var map_ref = _scene._map
	_scene._map = null
	var no_map := await measure("3) harita yenileme KAPALI", 90)
	_scene._map = map_ref

	# 4) Ikisi de kapali
	_scene._parliament.visible = false
	_scene._map = null
	var neither := await measure("4) ikisi de KAPALI", 90)
	_scene._parliament.visible = true
	_scene._map = map_ref

	print("")
	print("  parlamento diyagraminin payi : %6.2f ms/kare" % (base - no_parliament))
	print("  harita yenilemenin payi      : %6.2f ms/kare" % (base - no_map))
	print("  ikisi birden                 : %6.2f ms/kare" % (base - neither))
	print("=== OLCUM BITTI ===")
	quit()
