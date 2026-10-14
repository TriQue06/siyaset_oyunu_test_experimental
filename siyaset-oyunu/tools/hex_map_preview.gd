extends SceneTree
## ALTIGEN HARİTA ÖNİZLEMESİ: birkaç tohumla harita üretir, bölgeleri rastgele
## parti renklerine boyar, vekil noktalarını koyar ve user://hex_map_<tohum>.png
## kaydeder; bölge/vekil istatistiklerini yazar. Pencereli çalıştır:
##   godot --path . --script res://tools/hex_map_preview.gd

const SEEDS := [1950, 7, 42]

func _initialize() -> void:
	await process_frame
	var game_map = root.get_node("GameMap")
	var presets = root.get_node("PartyPresets")
	root.size = Vector2i(1152, 648)
	for seed_value in SEEDS:
		game_map.generate_new(seed_value)
		var sizes: Array = []
		var seats: Array = []
		for id in game_map.ids:
			sizes.append(game_map.region_cells(id).size())
			seats.append(game_map.seats_of(id))
		var total := 0
		for s in seats:
			total += int(s)
		print("tohum %d: %d bolge, hucre %d-%d, vekil %d-%d (toplam %d)" % [seed_value, game_map.ids.size(),
			sizes.min(), sizes.max(), seats.min(), seats.max(), total])
		var names: Array = []
		for id in game_map.ids.slice(0, 14):
			names.append("%s(%d)" % [game_map.name_of(id), game_map.seats_of(id)])
		print("   " + ", ".join(PackedStringArray(names)))
		var bg := ColorRect.new()
		bg.color = Color("1e2130")
		bg.size = Vector2(1152, 648)
		root.add_child(bg)
		var map: Node2D = (load("res://scenes/Map.tscn") as PackedScene).instantiate()
		root.add_child(map)
		await process_frame
		var native: Vector2 = game_map.map_size()
		var fit := minf(1112.0 / native.x, 608.0 / native.y)
		map.scale = Vector2(fit, fit)
		map.position = (Vector2(1152, 648) - native * fit) * 0.5
		var palette: Array = [presets.COLORS[0], presets.COLORS[6], presets.COLORS[11], presets.COLORS[3]]
		var colors := {}
		var by_province := {}
		var i := 0
		for id in game_map.ids:
			var c: Color = palette[(i * 7 + int(game_map.seats_of(id))) % palette.size()]
			colors[id] = c.darkened(0.25)
			var dots: Array = []
			for k in game_map.seats_of(id):
				dots.append(palette[(i + k) % palette.size()])
			by_province[id] = dots
			i += 1
		map.set_province_colors(colors)
		map.get_node("SeatMarkers").set_all(by_province)
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		var path := OS.get_user_data_dir() + "/hex_map_%d.png" % seed_value
		img.save_png(path)
		print("   -> " + path)
		map.queue_free()
		bg.queue_free()
		await process_frame
	quit()
