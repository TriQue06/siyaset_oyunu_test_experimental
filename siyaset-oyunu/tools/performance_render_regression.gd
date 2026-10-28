extends SceneTree
## Verifies the optimized mesh attributes against the engine's original packing.
## PERF_RENDER_DIR optionally saves deterministic map images for visual comparison.
var _fails := 0

func _initialize() -> void:
	await process_frame
	root.get_node("BotManager").set_process(false)
	root.get_node("CardManager").set_process(false)
	root.get_node("GovernmentManager").set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73617
	for mode in ["random"]:
		root.get_node("GameMap").generate_new(1950)
		var map = load("res://scenes/Map.tscn").instantiate()
		root.add_child(map)
		map.scale = Vector2(0.7, 0.7)
		map.position = Vector2(20, 20)
		for frame in 4:
			var colors := {}
			for id in map.ids:
				colors[id] = Color(rng.randf_range(-0.1, 1.1), rng.randf(), rng.randf(), rng.randf())
			map.clear_overlay()
			map.set_province_colors(colors)
			map._update_land_colors()
			var reference := ArrayMesh.new()
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = map._land_vertices
			var vertex_colors := PackedColorArray()
			for index in map._land_vertex_region:
				vertex_colors.append(colors[map.ids[index]])
			arrays[Mesh.ARRAY_COLOR] = vertex_colors
			reference.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var expected: Dictionary = RenderingServer.mesh_get_surface(reference.get_rid(), 0)
			var actual: Dictionary = RenderingServer.mesh_get_surface(map._land_mesh.get_rid(), 0)
			var same: bool = expected["vertex_data"] == actual["vertex_data"] and expected["attribute_data"] == actual["attribute_data"]
			print(("PASS " if same else "FAIL ") + "%s frame %d mesh matches original vertex/color bytes" % [mode, frame])
			if not same:
				_fails += 1
		await process_frame
		await process_frame
		var output := OS.get_environment("PERF_RENDER_DIR")
		if output != "" and DisplayServer.get_name() != "headless":
			root.get_texture().get_image().save_png(output.path_join(mode + ".png"))
		root.remove_child(map)
		map.queue_free()
	print("RENDER REGRESSION: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(1 if _fails else 0)
