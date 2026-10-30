extends SceneTree

func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1440, 900)
	root.content_scale_size = Vector2i(1440, 900)
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(surface)
	var bg := ColorRect.new()
	bg.color = Color("F7EED8")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_child(bg)
	var groups: Array = []
	for gender in ["m", "f"]:
		for category in ["face", "hair", "eyebrows", "moustache", "beard"]:
			var opts := AvatarCatalog.options(category, gender)
			if opts.is_empty():
				continue
			var samples: Array = []
			for id in opts:
				var value := AvatarCatalog.clean({}, gender)
				value[category] = id
				samples.append([id, value])
			groups.append([gender + "_" + category, samples])
	for gender in ["m", "f"]:
		var samples: Array = []
		var faces := AvatarCatalog.options("face", gender)
		var hairs := AvatarCatalog.options("hair", gender)
		var brows := AvatarCatalog.options("eyebrows", gender)
		for i in 8:
			var value := AvatarCatalog.clean({}, gender)
			value.face = faces[i % faces.size()]
			value.hair = hairs[(i + 2) % hairs.size()]
			value.eyebrows = brows[i % brows.size()]
			if gender == "m":
				value.beard = AvatarCatalog.options("beard", gender)[(i + 1) % 5]
				value.moustache = AvatarCatalog.options("moustache", gender)[i % 5]
			samples.append(["%s / %s" % [value.face, value.hair], value])
		groups.append([gender + "_combinations", samples])
	# Review every female hairstyle on every supplied female face.
	for face in AvatarCatalog.options("face", "f"):
		var samples: Array = []
		for hair in AvatarCatalog.options("hair", "f"):
			var value := AvatarCatalog.clean({}, "f")
			value.face = face
			value.hair = hair
			samples.append([hair + " / " + face, value])
		groups.append(["female_hair_" + face, samples])
	for face in AvatarCatalog.options("face", "m"):
		var samples: Array = []
		for beard in AvatarCatalog.options("beard", "m"):
			var value := AvatarCatalog.clean({}, "m")
			value.face = face
			value.beard = beard
			samples.append([beard + " / " + face, value])
		groups.append(["beards_" + face, samples])
	for face in AvatarCatalog.options("face", "m"):
		var samples: Array = []
		for moustache in AvatarCatalog.options("moustache", "m"):
			var value := AvatarCatalog.clean({}, "m")
			value.face = face
			value.moustache = moustache
			samples.append([moustache + " / " + face, value])
		groups.append(["moustaches_" + face, samples])
	for group in groups:
		var nodes: Array = []
		for i in group[1].size():
			var sample: Array = group[1][i]
			var p := AvatarPortrait.new()
			p.position = Vector2((i % 4) * 350 + 15, (i / 4) * 440 + 20)
			p.size = Vector2(330, 400)
			p.set_appearance(sample[1])
			surface.add_child(p)
			nodes.append(p)
			var label := Label.new()
			label.text = sample[0]
			label.position = p.position + Vector2(80, 400)
			label.add_theme_color_override("font_color", Color.BLACK)
			surface.add_child(label)
			nodes.append(label)
		for f in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/avatar-review/" + group[0] + ".png")
		for n in nodes: n.free()
	quit()
