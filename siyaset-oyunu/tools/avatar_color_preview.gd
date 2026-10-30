extends SceneTree
func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = Vector2i(1600, 1000)
	var surface := Control.new()
	root.add_child(surface)
	var bg := ColorRect.new()
	bg.color = Color("F7EED8")
	bg.size = Vector2(1600, 1000)
	surface.add_child(bg)
	var groups: Array = []
	for face: String in AvatarCatalog.data().faces:
		var gender: String = AvatarCatalog.data().assets[face].gender
		var samples: Array = []
		for tone: Array in AvatarColors.SKIN:
			var value := AvatarCatalog.clean({}, gender)
			value.face = face
			value.skin_color = tone[0]
			samples.append([face + " / " + tone[0], value])
		groups.append([face + "_skin", samples])
	for gender: String in ["m", "f"]:
		var samples: Array = []
		for lip: Array in AvatarColors.palette("lip_color", gender):
			var value := AvatarCatalog.clean({}, gender)
			value.lip_color = lip[0]
			samples.append([gender + " / " + lip[0], value])
		groups.append([gender + "_lips", samples])
		for page in 3:
			samples = []
			for i in range(page * 6, mini(page * 6 + 6, AvatarColors.HAIR.size())):
				var value := AvatarCatalog.clean({}, gender)
				value.hair = AvatarCatalog.options("hair", gender)[i % AvatarCatalog.options("hair", gender).size()]
				value.hair_color = AvatarColors.HAIR[i][0]
				value.eyebrow_color = AvatarColors.HAIR[i][0]
				value.skin_color = "deep" if i % 3 == 0 else "natural"
				if gender == "m":
					value.beard = AvatarCatalog.options("beard", gender)[i % 5]
					value.moustache = AvatarCatalog.options("moustache", gender)[i % 5]
					value.beard_color = AvatarColors.HAIR[(i + 5) % 17][0]
					value.moustache_color = AvatarColors.HAIR[(i + 10) % 17][0]
				samples.append([value.hair + " / " + value.hair_color, value])
			groups.append([gender + "_hair_%d" % page, samples])
	var eyes: Array = []
	for eye: Array in AvatarColors.EYES:
		var value := AvatarCatalog.clean({}, "f")
		value.iris_color = eye[0]
		eyes.append([eye[0], value])
	groups.append(["iris", eyes])
	for group in groups:
		for page in ceili(group[1].size() / 8.0):
			var nodes: Array = []
			for i in mini(8, group[1].size() - page * 8):
				var sample: Array = group[1][page * 8 + i]
				var p := AvatarPortrait.new()
				p.position = Vector2((i % 4) * 400, (i / 4) * 500)
				p.size = Vector2(400, 465)
				p.set_appearance(sample[1])
				surface.add_child(p)
				nodes.append(p)
				var label := Label.new()
				label.text = sample[0]
				label.position = p.position + Vector2(45, 465)
				label.add_theme_color_override("font_color", Color.BLACK)
				surface.add_child(label)
				nodes.append(label)
			for f in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../build/avatar-review/colors/" + group[0] + "_%d.png" % page)
			for n in nodes: n.free()
	quit()
