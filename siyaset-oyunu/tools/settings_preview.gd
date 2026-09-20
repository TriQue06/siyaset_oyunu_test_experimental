extends SceneTree
## Ayarlar panelinin görüntüsü (ses kaydırıcıları dahil).
## `godot --path . --resolution 1280x720 --script res://tools/settings_preview.gd`

func _initialize() -> void:
	await process_frame
	await process_frame
	var overlay = root.get_node("SettingsOverlay")
	overlay.open()
	await process_frame
	await create_timer(0.4).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://settings_panel.png")
	print("kaydedildi: settings_panel.png")
	quit()
