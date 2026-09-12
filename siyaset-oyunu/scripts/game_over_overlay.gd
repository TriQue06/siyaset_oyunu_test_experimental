class_name GameOverOverlay
extends Control
## Oyun bitince (CardManager.game_over) oyun ekranının üstüne açılan sonuç
## perdesi: sıralama (puan, eşitlikte milletvekili) ve ana menüye dönüş.
## Sıralama CardManager.final_ranking'den okunur — ayrılan oyuncuların parti
## verisi silinmiş olsa bile isimler oyun bitişinde oraya yazıldığı için doğru
## görünür.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150

	var backdrop := UiSkin.panel_background(UiSkin.PANEL_DARK)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.modulate = Color(1, 1, 1, 0.96)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(520, 0)
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var ranking: Array = CardManager.final_ranking
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	if ranking.is_empty():
		title.text = "OYUN BİTTİ"
	else:
		title.text = "KAZANAN: %s" % ranking[0].get("name", "?")
		title.modulate = Color(ranking[0].get("color", Color.WHITE)).lightened(0.3)
	vbox.add_child(title)

	var reason := Label.new()
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason.modulate = Color(1, 1, 1, 0.7)
	reason.text = CardManager.game_end_reason
	vbox.add_child(reason)

	var my_id := multiplayer.get_unique_id()
	for i in ranking.size():
		var entry: Dictionary = ranking[i]
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 18)
		row.text = "%d.  %s (%s) — %d puan, %d milletvekili" % [
			i + 1, entry.get("name", "?"), entry.get("leader", "?"),
			int(entry.get("score", 0)), int(entry.get("seats", 0)),
		]
		row.modulate = Color(1.0, 0.85, 0.35) if int(entry.get("peer_id", -1)) == my_id else Color.WHITE
		vbox.add_child(row)

	var button := Button.new()
	button.text = "Ana Menüye Dön"
	button.custom_minimum_size = Vector2(220, 44)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiSkin.skin_button(button)
	button.pressed.connect(_on_back_pressed)
	vbox.add_child(button)

func _on_back_pressed() -> void:
	MultiplayerManager.leave_room()
	SceneTransition.fade_to_scene("res://scenes/Lobby.tscn")
