extends SceneTree
## assets/icons/mana.png beyaz arka planlı (alfa yok). Kenarlardan başlayan
## flood fill ile dıştaki beyazı şeffaf yapar (damla içindeki beyaz şerit kalır),
## 256 px'e küçültüp assets/icons/mana_icon.png olarak kaydeder.
##   godot --headless --script res://tools/make_mana_icon.gd

func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/icons/mana.png"))
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if seen[i] == 1:
			continue
		seen[i] = 1
		var x := i % w
		var y := i / w
		var c := img.get_pixel(x, y)
		var lightness := minf(c.r, minf(c.g, c.b))
		if lightness < 0.75:
			continue
		# Açık renkli kenar pikselleri yumuşak geçişle saydamlaşır.
		img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf((1.0 - lightness) / 0.25, 0.0, 1.0) if lightness < 0.92 else 0.0))
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path("res://assets/icons/mana_icon.png"))
	print("mana_icon.png yazildi")
	quit()
