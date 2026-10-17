extends SceneTree
## Siyasetçi profili ekranının görüntüsü: boş hâli ve geçmiş + memleket seçili hâli.
##   godot --resolution 1600x900 --path . --script res://tools/politician_setup_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await process_frame
	root.get_node("GameMap").generate_new(4242)
	var scene: Node = (load("res://scenes/PoliticianSetup.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(8)
	root.get_texture().get_image().save_png("%s/politician_setup_empty.png" % OS.get_user_data_dir())
	scene._on_background_pressed("belediye_baskani")
	scene._on_trait_pressed("hatip")
	var ids: Array = root.get_node("GameMap").province_ids()
	scene._on_province_clicked(String(ids[ids.size() / 2]))
	await _frames(8)
	root.get_texture().get_image().save_png("%s/politician_setup.png" % OS.get_user_data_dir())
	print("kaydedildi")
	quit(0)
