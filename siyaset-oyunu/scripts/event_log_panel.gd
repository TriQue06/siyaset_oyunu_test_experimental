class_name EventLogPanel
extends PanelContainer
## CANLI OLAY LOGU (sol panel, hükümet bilgisi ile sıra göstergesi arası).
## Eski tek satırlık üst bant yazısının yerini aldı: oyundaki her olay burada
## alt alta birikir, en yenisi en altta.
##
## Her satır bağımsız bir HBoxContainer:
##   [parti rozeti] [olay metni .............] [◎ odak düğmesi]
## Odak düğmesi sadece olayın bir ili varsa görünür; basınca focus_requested
## yayınlanır, oyun ekranı haritayı o ile kaydırıp parlatır (bkz. GameScreen).

signal focus_requested(entry: Dictionary)

const BADGE_SIZE := 18.0
const FOCUS_SIZE := 20.0
const FONT_SIZE := 10

var _scroll: ScrollContainer
var _rows: VBoxContainer
var _glow_time := 0.0
var _focus_buttons: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.PANEL_DARK, 0.85)
	style.border_color = UiTheme.PANEL_LIGHT
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 3)
	_scroll.add_child(_rows)
	for entry in CardManager.event_log:
		_add_row(entry)
	CardManager.event_logged.connect(_on_event_logged)
	_scroll_to_end()

func _process(delta: float) -> void:
	# Odak düğmeleri hafifçe parıldar.
	_glow_time += delta
	var a := 0.65 + 0.35 * (sin(_glow_time * 3.2) * 0.5 + 0.5)
	for button in _focus_buttons:
		if is_instance_valid(button):
			button.modulate.a = a

func _on_event_logged(entry: Dictionary) -> void:
	_add_row(entry)
	while _rows.get_child_count() > CardManager.EVENT_LOG_LIMIT:
		var old := _rows.get_child(0)
		_rows.remove_child(old)
		old.queue_free()
	_scroll_to_end()

func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _add_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var peer_id := int(entry.get("peer_id", -1))
	var party: Dictionary = PartyManager.parties.get(peer_id, {})
	if not party.is_empty():
		var badge := PartyBadge.build(party, Vector2(BADGE_SIZE, BADGE_SIZE), 36, peer_id == multiplayer.get_unique_id())
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(badge)
	else:
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(BADGE_SIZE, 6)
		row.add_child(dot)
	var label := Label.new()
	label.text = String(entry.get("text", ""))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", UiTheme.TEXT if not party.is_empty() else UiTheme.TEXT_MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	if String(entry.get("province", "")) != "":
		var focus := FocusButton.new()
		focus.custom_minimum_size = Vector2(FOCUS_SIZE, FOCUS_SIZE)
		focus.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		focus.ring_color = party.get("bg_color", UiTheme.GOLD)
		focus.tooltip_text = "Haritada göster"
		focus.pressed.connect(func(): focus_requested.emit(entry))
		row.add_child(focus)
		_focus_buttons.append(focus)
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(FOCUS_SIZE, 1)
		row.add_child(gap)
	_rows.add_child(row)

## Dairesel "hedef" simgeli odak düğmesi (çizimle; yazı tipi emojisine güvenmez).
class FocusButton extends Button:
	var ring_color := Color.WHITE

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		var hover := is_hovered()
		draw_circle(c, r, Color(UiTheme.INK, 0.9))
		draw_arc(c, r, 0.0, TAU, 24, ring_color.lightened(0.3 if hover else 0.1), 1.6, true)
		draw_arc(c, r * 0.55, 0.0, TAU, 18, Color.WHITE if hover else Color(1, 1, 1, 0.8), 1.3, true)
		draw_circle(c, r * 0.18, Color.WHITE)
