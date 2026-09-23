extends SceneTree
## ÇEVRİM DIŞI LOBİ ÖNİZLEMESİ: oda kodu yok, boş yuvalar "bot ekle" der.
##   godot --path . --script res://tools/offline_lobby_preview.gd

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	mm.start_offline("Barış")
	for i in 3:
		mm.add_bot()
	var scene: Node = (load("res://scenes/RoomLobby.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 15:
		await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/offline_lobby.png" % OS.get_user_data_dir())
		print("screenshot: offline_lobby")
	print("=== OFFLINE LOBBY PREVIEW: PASS ===")
	quit()
