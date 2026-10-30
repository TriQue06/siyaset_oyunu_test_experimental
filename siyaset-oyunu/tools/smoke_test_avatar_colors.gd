extends SceneTree
## GPU regression checks: defaults, feature isolation and unchanged alpha.
var failures := 0
var viewport: SubViewport
var layer: TextureRect
func check(label: String, ok: bool) -> void:
	print("[OK] " if ok else "[FAIL] ", label)
	if not ok: failures += 1
func capture(mat: Material) -> Image:
	layer.material = mat
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func _initialize() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		push_error("This test requires a real GPU renderer")
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.size = Vector2i(1254, 1254)
	root.add_child(viewport)
	layer = TextureRect.new()
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.size = Vector2(1254, 1254)
	viewport.add_child(layer)
	for face: String in AvatarCatalog.data().faces:
		var gender: String = AvatarCatalog.data().assets[face].gender
		var value := AvatarCatalog.clean({"face": face}, gender)
		layer.texture = AvatarCatalog.texture(face)
		var original: Image = await capture(null)
		var defaults: Image = await capture(AvatarColors.material_for(face, "face", value))
		check(face + " original default pixels unchanged", original.get_data() == defaults.get_data())
		value.skin_color = "deep"
		var skin: Image = await capture(AvatarColors.material_for(face, "face", value))
		value.skin_color = "natural"
		value.lip_color = "wine" if gender == "f" else "brown"
		var lips: Image = await capture(AvatarColors.material_for(face, "face", value))
		var mask: Image = load(AvatarCatalog.ROOT + "color_masks/" + face + ".png").get_image()
		var skin_safe := true
		var lip_safe := true
		var alpha_safe := true
		var lip_changed := 0
		var skin_changed := 0
		for y in range(1, 1254, 3):
			for x in range(1, 1254, 3):
				var old := original.get_pixel(x, y)
				var s := skin.get_pixel(x, y)
				var l := lips.get_pixel(x, y)
				var m := mask.get_pixel(x, y)
				alpha_safe = alpha_safe and absf(s.a - old.a) < 0.005 and absf(l.a - old.a) < 0.005
				if old.a < 0.99: continue
				var sd := Vector3(s.r - old.r, s.g - old.g, s.b - old.b).length()
				var ld := Vector3(l.r - old.r, l.g - old.g, l.b - old.b).length()
				if m.r < 0.001 and sd > 0.015: skin_safe = false
				if m.g < 0.001 and ld > 0.015: lip_safe = false
				if ld > 0.05: lip_changed += 1
				if sd > 0.1: skin_changed += 1
		check(face + " skin never paints eyes or lips", skin_safe and skin_changed > 10000)
		check(face + " lip color never paints surrounding skin", lip_safe and lip_changed > 500)
		check(face + " transparency unchanged", alpha_safe)
		lips.save_png("res://../build/avatar-review/colors/" + face + "_lip_check.png")
	for id: String in AvatarCatalog.data().assets:
		var asset: Dictionary = AvatarCatalog.data().assets[id]
		if asset.category in ["face", "iris"]: continue
		var appearance := AvatarCatalog.clean({}, asset.gender)
		layer.texture = AvatarCatalog.texture(id)
		layer.size = layer.texture.get_size()
		viewport.size = Vector2i(layer.size)
		var original: Image = await capture(null)
		var defaults: Image = await capture(AvatarColors.material_for(id, asset.category, appearance))
		check(id + " default colors unchanged", original.get_data() == defaults.get_data())
		var field: String = "eyebrow_color" if asset.category == "eyebrows" else String(asset.category) + "_color"
		appearance[field] = "white"
		var white: Image = await capture(AvatarColors.material_for(id, asset.category, appearance))
		var low := 1.0
		var high := 0.0
		var same_alpha := true
		for y in range(0, white.get_height(), 5):
			for x in range(0, white.get_width(), 5):
				var a := original.get_pixel(x, y)
				var b := white.get_pixel(x, y)
				same_alpha = same_alpha and absf(a.a - b.a) < 0.005
				if a.a > 0.95:
					low = minf(low, b.get_luminance())
					high = maxf(high, b.get_luminance())
		check(id + " white retains tonal detail and alpha", high - low > 0.12 and same_alpha)
	# Both transparent openings and white reflections survive iris recoloring.
	var iris := AvatarCatalog.texture("iris_03")
	layer.texture = iris
	layer.size = iris.get_size()
	viewport.size = Vector2i(iris.get_size())
	var before: Image = await capture(null)
	var eye_value := AvatarCatalog.clean({"iris_color": "blue"}, "m")
	var after: Image = await capture(AvatarColors.material_for("iris_03", "iris", eye_value))
	var whites := 0
	var whites_safe := true
	var alpha_safe := true
	for y in before.get_height():
		for x in before.get_width():
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			alpha_safe = alpha_safe and absf(a.a - b.a) < 0.005
			if minf(a.r, minf(a.g, a.b)) > 0.97 and a.a > 0.99:
				whites += 1
				whites_safe = whites_safe and Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length() < 0.02
	check("iris white reflections remain white", whites > 50 and whites_safe)
	check("iris exterior and pupil opening alpha unchanged", alpha_safe)
	print("AVATAR COLOR GPU FAILURES: ", failures)
	quit(1 if failures else 0)
