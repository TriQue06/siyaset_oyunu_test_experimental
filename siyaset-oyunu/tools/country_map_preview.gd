extends SceneTree
## ÜLKE HARİTASI ÖNİZLEMESİ (0.0.261): CountryGenerator'ın birkaç tohumla
## ürettiği ülkeleri oyundan bağımsız çizer (il renkleri, sınırlar, kıyı, il
## adları) ve süreleri yazar. Ayrıca yapboz denetimi: her il bağlı mı, komşuluk
## simetrik mi, vekil toplamı doğru mu.
## Ekran görüntüleri user:// içine country_<tohum>.png.
##   godot --resolution 1920x957 --path . --script res://tools/country_map_preview.gd

const SEEDS := [1950, 7, 42, 2024, 31337, 555]
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	var canvas := Node2D.new()
	root.add_child(canvas)
	var bg := ColorRect.new()
	bg.color = Color("0b0a1a")
	bg.size = Vector2(4000, 4000)
	bg.z_index = -10
	canvas.add_child(bg)
	var current := {}
	canvas.draw.connect(func():
		if current.is_empty():
			return
		var geo: Dictionary = current["geo"]
		var data: Dictionary = current["data"]
		var view := root.get_visible_rect().size
		var map_size := Vector2(float(data["width"]), float(data["height"]))
		var scale := minf((view.x - 40.0) / map_size.x, (view.y - 80.0) / map_size.y)
		var origin := (view - map_size * scale) * 0.5 + Vector2(0, 20)
		canvas.draw_set_transform(origin, 0.0, Vector2(scale, scale))
		canvas.draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.14, 0.17, 0.27))
		var regions: Array = data["regions"]
		for r in regions.size():
			var tris: PackedVector2Array = geo["tris"][r]
			var hue := fmod(float(r) * 0.618034, 1.0)
			var color := Color.from_hsv(hue, 0.55, 0.78 + 0.12 * float(int(regions[r]["seats"]) > 8))
			var indices := PackedInt32Array()
			indices.resize(tris.size())
			for i in tris.size():
				indices[i] = i
			var colors := PackedColorArray()
			colors.resize(tris.size())
			colors.fill(color)
			RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, tris, colors)
		for seg in geo["segments"]:
			var coast: bool = int(seg[3]) < 0
			# Referans seçim haritaları gibi: il sınırı ince beyaz, kıyı ince koyu.
			canvas.draw_line(seg[0], seg[1], Color(0.04, 0.04, 0.08) if coast else Color(1, 1, 1, 0.95), (1.4 if coast else 1.0) / scale, true)
		var font := ThemeDB.fallback_font
		for r in regions.size():
			var c: Vector2 = geo["centers"][r]
			canvas.draw_circle(c, 2.0, Color.BLACK)
			canvas.draw_string(font, c + Vector2(-30, -4), String(regions[r]["name"]), HORIZONTAL_ALIGNMENT_CENTER, 60, 7, Color(0, 0, 0, 0.85))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		canvas.draw_string(font, Vector2(20, 24), "tohum %d · %d il · üretim %d ms · geometri %d ms" % [int(data["seed"]), regions.size(),
			int(current["gen_ms"]), int(current["geo_ms"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE))
	for seed_value in SEEDS:
		print("=== tohum %d ===" % seed_value)
		var t0 := Time.get_ticks_msec()
		var data := CountryGenerator.generate(seed_value)
		var t1 := Time.get_ticks_msec()
		var geo := CountryGenerator.geometry(data)
		var t2 := Time.get_ticks_msec()
		current["data"] = data
		current["geo"] = geo
		current["gen_ms"] = t1 - t0
		current["geo_ms"] = t2 - t1
		var regions: Array = data["regions"]
		print("  %d il, üretim %d ms, geometri %d ms, %d nokta" % [regions.size(), t1 - t0, t2 - t1, (data["points"] as Array).size() / 2])
		var seat_sum := 0
		var min_seats := 999
		for r in regions:
			seat_sum += int(r["seats"])
			min_seats = mini(min_seats, int(r["seats"]))
		check("vekil toplamı 300", seat_sum == 300, str(seat_sum))
		check("il sayısı makul", regions.size() >= 35 and regions.size() <= 60, str(regions.size()))
		var symmetric := true
		var lonely := 0
		for r in regions.size():
			var nbs: Array = geo["neighbors"][r]
			if nbs.is_empty():
				lonely += 1
			for o in nbs:
				if not (geo["neighbors"][int(o)] as Array).has(r):
					symmetric = false
		check("komşuluk simetrik", symmetric)
		print("  komşusuz il (ada): %d, en az vekil %d" % [lonely, min_seats])
		# Her ilin ana karası tek parça mı? (Bağlı adalar ayrı parça sayılmaz.)
		var labels: PackedInt32Array = geo["labels"]
		var topo := CountryGenerator.topology(geo["points"])
		var broken := 0
		for r in regions.size():
			if CountryGenerator.mainland_parts(labels, topo, r) > 1:
				broken += 1
		check("her ilin ana karası tek parça", broken == 0, "%d parçalı il" % broken)
		canvas.queue_redraw()
		await process_frame
		await process_frame
		await process_frame
		if DisplayServer.get_name() != "headless":
			root.get_texture().get_image().save_png("%s/country_%d.png" % [OS.get_user_data_dir(), seed_value])
	print("=== %s ===" % ("HEPSİ GEÇTİ" if fails == 0 else "%d HATA" % fails))
	quit(1 if fails > 0 else 0)
