class_name GameOverOverlay
extends Control
## Oyun bitince (CardManager.game_over) oyun ekranının üstüne açılan sonuç
## ekranı: perde yavaşça kararır, kazanan belirir, sonra sıralama satır satır
## gelir (puan, eşitlikte milletvekili). Sıralama CardManager.final_ranking'den
## okunur — ayrılan oyuncuların parti verisi silinmiş olsa bile isimler oyun
## bitişinde oraya yazıldığı için doğru görünür.

const FADE_SECONDS := 0.9
const ROW_DELAY := 0.12
const ROW_FADE_SECONDS := 0.35
const GOLD := UiTheme.GOLD
const DIM := UiTheme.TEXT_MUTED

var _reveal: Array = []  # sırayla beliren düğümler

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.95)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.add_theme_constant_override("separation", 5)
	center.add_child(vbox)

	var ranking: Array = CardManager.final_ranking
	var over := _label("OYUN BİTTİ", 16, DIM)
	vbox.add_child(over)
	_reveal.append(over)

	if not ranking.is_empty():
		var winner: Dictionary = ranking[0]
		var winner_box := VBoxContainer.new()
		winner_box.add_theme_constant_override("separation", 2)
		var badge := PartyBadge.build(_party_for(winner), Vector2(64, 64), 128)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		winner_box.add_child(badge)
		winner_box.add_child(_label("KAZANAN", 13, DIM))
		winner_box.add_child(_label(String(winner.get("name", "?")), 30, Color(winner.get("color", Color.WHITE)).lightened(0.35)))
		winner_box.add_child(_label("%s  ·  %d puan" % [winner.get("leader", "?"), int(winner.get("score", 0))], 15, GOLD))
		vbox.add_child(winner_box)
		_reveal.append(winner_box)

	var reason := _label(CardManager.game_end_reason, 13, DIM)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(reason)
	_reveal.append(reason)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(gap)

	var my_id := multiplayer.get_unique_id()
	for i in ranking.size():
		var row := _ranking_row(i, ranking[i], int(ranking[i].get("peer_id", -1)) == my_id)
		vbox.add_child(row)
		_reveal.append(row)

	var button := Button.new()
	button.text = "Ana Menüye Dön"
	button.custom_minimum_size = Vector2(220, 44)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiSkin.skin_button(button)
	button.pressed.connect(_on_back_pressed)
	vbox.add_child(button)
	_reveal.append(button)

	_play_intro(backdrop)

## Perde kararır, sonra her parça sırayla belirir.
func _play_intro(backdrop: ColorRect) -> void:
	backdrop.modulate.a = 0.0
	for node in _reveal:
		(node as CanvasItem).modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(backdrop, "modulate:a", 1.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE)
	for node in _reveal:
		tween.tween_property(node, "modulate:a", 1.0, ROW_FADE_SECONDS)
		tween.tween_interval(ROW_DELAY)

func _ranking_row(index: int, entry: Dictionary, is_me: bool) -> Control:
	var color: Color = entry.get("color", Color(0.5, 0.5, 0.5))
	var panel := PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL_DARK)
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	# Solda parti renginde şerit; kazanan/kendi satırın altın renkli olur.
	row.add_child(UiTheme.stripe(GOLD if is_me else color))
	var rank := _label("%d." % (index + 1), 18, GOLD if index == 0 else Color.WHITE)
	rank.custom_minimum_size = Vector2(34, 0)
	row.add_child(rank)
	var badge := PartyBadge.build(_party_for(entry), Vector2(30, 30), 64)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var names := HBoxContainer.new()
	names.add_theme_constant_override("separation", 8)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var party_name := _label(String(entry.get("name", "?")), 17, GOLD if is_me else Color.WHITE)
	names.add_child(party_name)
	var leader := _label(String(entry.get("leader", "?")) + ("  (sen)" if is_me else ""), 12, DIM)
	names.add_child(leader)
	row.add_child(names)
	var seats := _label("%d mv" % int(entry.get("seats", 0)), 13, DIM)
	seats.custom_minimum_size = Vector2(56, 0)
	seats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(seats)
	var score := _label("%d" % int(entry.get("score", 0)), 20, Color.WHITE)
	score.custom_minimum_size = Vector2(56, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(score)
	row.add_child(_label("puan", 11, DIM))
	return panel

## Rozet için parti verisi: oyuncu ayrıldıysa sıralamadaki renkle yedek.
func _party_for(entry: Dictionary) -> Dictionary:
	var party: Dictionary = PartyManager.parties.get(int(entry.get("peer_id", -1)), {})
	if party.is_empty():
		party = {"name": entry.get("name", "?"), "icon_index": 0, "icon_color": Color.WHITE, "bg_color": entry.get("color", Color.GRAY)}
	return party

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _on_back_pressed() -> void:
	MultiplayerManager.leave_room()
	SceneTransition.fade_to_scene("res://scenes/Lobby.tscn")
