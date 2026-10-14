extends SceneTree
## ANA EKRAN ÖNİZLEMESİ: çevrim içi / çevrim dışı sekmeleri.
##   godot --path . --script res://tools/main_menu_preview.gd

func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), file_name])
	print("screenshot: ", file_name)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://scenes/Lobby.tscn")
	await _frames(20)
	_shot("main_menu_online")
	var lobby := root.get_child(root.get_child_count() - 1)
	lobby._set_mode(false)
	await _frames(10)
	_shot("main_menu_offline")
	print("=== MAIN MENU PREVIEW: PASS ===")
	quit()
