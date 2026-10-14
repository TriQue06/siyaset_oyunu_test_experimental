extends SceneTree
## Memleket seçimi GERÇEK fare tıklamasıyla çalışıyor mu?
##   godot --resolution 1600x900 --path . --script res://tools/politician_click_test.gd

func _initialize() -> void:
	await process_frame
	root.get_node("GameMap").generate_new(4242)
	var scene: Node = (load("res://scenes/PoliticianSetup.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 8:
		await process_frame
	var gmap = root.get_node("GameMap")
	var target := String(gmap.province_ids()[3])
	var pos: Vector2 = scene._map.get_global_transform() * gmap.center_of(target)
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	root.push_input(move, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev, true)
		await process_frame
	print("TIKLAMA: hedef=%s secilen=%s %s" % [target, scene._hometown, "OK" if scene._hometown == target else "HATA"])
	quit(0)
