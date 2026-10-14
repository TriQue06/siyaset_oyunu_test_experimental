extends SceneTree
## TÜM PARTİ İKONLARININ ÖNİZLEME SAYFASI: her ikon, numarasıyla, parti
## renklerinden birinin üstünde. user://icon_sheet.png olarak kaydeder.
##   godot --path . --script res://tools/icon_sheet.gd

const CELL := 96
const COLS := 10

func _initialize() -> void:
	await process_frame
	var presets = root.get_node("PartyPresets")
	var count: int = presets.icon_count()
	var rows := int(ceil(count / float(COLS)))
	var sheet := Image.create(COLS * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1a1530"))
	for i in count:
		var cell := Vector2i((i % COLS) * CELL, (i / COLS) * CELL)
		var bg: Color = presets.COLORS[i % presets.COLORS.size()]
		sheet.fill_rect(Rect2i(cell + Vector2i(8, 8), Vector2i(CELL - 16, CELL - 16)), bg)
		var tex: Texture2D = presets.get_icon_texture(i, 64)
		if tex == null:
			print("HATA: ikon %d yuklenemedi: %s" % [i, presets.icon_paths[i]])
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), cell + Vector2i(16, 16))
	var path := OS.get_user_data_dir() + "/icon_sheet.png"
	sheet.save_png(path)
	print("ikon sayisi: %d  ->  %s" % [count, path])
	quit()
