extends SceneTree
## Güncel ülke haritasının yüklenmesi, sorguları ve çizimi.
var fails := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	await process_frame
	var gm = root.get_node("GameMap")
	var mm = root.get_node("MultiplayerManager")
	var before: Dictionary = gm.data.duplicate(true)
	check(gm.supports_data(before), "generated country is supported")
	check(not gm.supports_data({"kind": "obsolete"}) and not gm.supports_data(null), "unsupported map data rejected")
	check(not mm.WORLD_DEFAULTS.has("map_mode") and not mm.WORLD_OPTIONS.has("map_mode"), "no obsolete map selector")
	var events := [0]
	gm.map_changed.connect(func(): events[0] += 1)
	gm.set_data(before)
	check(events[0] == 0, "identical map does not rebuild geometry")
	var centers_ok := true
	var neighbors_ok := true
	var links: Dictionary = gm.neighbors()
	for id in gm.province_ids():
		centers_ok = centers_ok and gm.province_at(gm.center_of(id)) == id
		for other in links[id]:
			neighbors_ok = neighbors_ok and (links[other] as Array).has(id)
	check(centers_ok, "province centers resolve to their own province")
	check(neighbors_ok, "province adjacency is symmetric")
	check(gm.province_at(Vector2(-100, -100)) == "", "sea does not resolve to a province")
	var map = load("res://scenes/Map.tscn").instantiate()
	root.add_child(map)
	map.set_dark_borders(true)
	map.set_dark_borders(false)
	map.set_isolated(gm.province_ids()[0])
	map.set_isolated("")
	var colors := {}
	for id in gm.province_ids():
		colors[id] = UiTheme.TEAL
	map.set_province_colors(colors)
	map._update_land_colors()
	check(map._land_mesh.get_surface_count() == 1 and not map._region_tris.is_empty(), "country mesh and region geometry remain available")
	map.queue_free()
	await process_frame
	print("MAP CLEANUP: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
