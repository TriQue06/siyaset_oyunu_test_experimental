class_name FoundPartyDialog
extends Control
## OYUN İÇİNDE PARTİ KURMA penceresi (parti kurulum ekranının küçük hâli):
## ad, logo ve renk seçilir, bedel ödenip parti kurulur. Bağımsız siyasetçi
## kurar (CardManager.FOUND_PARTY_COST) ya da yardımcı partisinden ayrılıp
## kurar (leaving = true, CardManager.LEAVE_PARTY_COST). Seçmen grubu
## yakınlıkları siyasetçinin mevcut yakınlıklarıdır; siyasetçi profili aynen devam eder.

const WIDTH := 560.0
const ICON_SIZE := 30.0
const SWATCH := 26.0

## true: yardımcı partisinden ayrılıp kuruyor.
var leaving := false

var _name_edit: LineEdit
var _icon_grid: GridContainer
var _color_row: HFlowContainer
var _found_button: Button
var _preview: Control
var _icon_index := 0
var _color := Color.TRANSPARENT

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 110
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var built := PopupKit.frame(WIDTH, UiTheme.GOLD)
	center.add_child(built[0])
	var body: VBoxContainer = built[1]
	var cost := CardManager.FOUND_PARTY_COST
	body.add_child(PopupKit.header("YENİ PARTİ KUR" if not leaving else "AYRIL VE PARTİ KUR",
		"Bedel: %s · seçmen gruplarındaki desteğin aynen devam eder" % GameRules.cost_text(cost), null, queue_free))
	if leaving:
		body.add_child(PopupKit.note("Katkına göre (biraz da şansla) vekillerin, teşkilatların ve desteğin bir kısmını götürürsün; memleketindeki teşkilat seninle gelir. Seçime yaklaştıkça ayrılık iki partiye de daha çok oy kaybettirir.", UiTheme.TEXT_MUTED))
	else:
		body.add_child(PopupKit.note("Bağımsızken topladığın destek yeni partine geçer; memleketinden kazandığın sandalye de partinin olur.", UiTheme.TEXT_MUTED))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(64, 64)
	top.add_child(_preview)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_box)
	name_box.add_child(PopupKit.label("Parti adı", PopupKit.FS_SMALL, UiTheme.TEXT_MUTED))
	_name_edit = LineEdit.new()
	_name_edit.max_length = PartyManager.NAME_MAX_LENGTH
	_name_edit.placeholder_text = "Parti adını yaz"
	_name_edit.text_changed.connect(func(_t): _refresh())
	name_box.add_child(_name_edit)

	body.add_child(PopupKit.section("Logo"))
	_icon_grid = GridContainer.new()
	_icon_grid.columns = 13
	_icon_grid.add_theme_constant_override("h_separation", 6)
	_icon_grid.add_theme_constant_override("v_separation", 6)
	body.add_child(_icon_grid)
	for i in PartyPresets.icon_count():
		var button := TextureButton.new()
		button.texture_normal = PartyPresets.get_icon_texture(i, 60)
		button.ignore_texture_size = true
		button.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.pressed.connect(func():
			_icon_index = i
			_refresh())
		_icon_grid.add_child(button)

	body.add_child(PopupKit.section("Renk", "başka partinin rengi seçilemez"))
	_color_row = HFlowContainer.new()
	_color_row.add_theme_constant_override("h_separation", 4)
	_color_row.add_theme_constant_override("v_separation", 4)
	body.add_child(_color_row)
	for color in PartyPresets.COLORS:
		if color.is_equal_approx(Color.WHITE):
			continue
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.set_meta("color", color)
		var taken := PartyManager.color_owner(color, multiplayer.get_unique_id()) != -1
		swatch.disabled = taken
		swatch.pressed.connect(func():
			_color = color
			_refresh())
		_color_row.add_child(swatch)
		if not taken and _color.a <= 0.0:
			_color = color
	_icon_index = randi() % maxi(1, PartyPresets.icon_count())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Vazgeç"
	cancel.custom_minimum_size = Vector2(120, 40)
	UiSkin.skin_button(cancel)
	cancel.pressed.connect(queue_free)
	buttons.add_child(cancel)
	_found_button = Button.new()
	_found_button.text = "Partiyi Kur · %s" % GameRules.cost_text(cost)
	_found_button.custom_minimum_size = Vector2(200, 40)
	UiSkin.skin_color_button(_found_button, UiTheme.GREEN_DARK)
	_found_button.pressed.connect(_on_found)
	buttons.add_child(_found_button)
	_refresh()
	_name_edit.grab_focus.call_deferred()

func _refresh() -> void:
	for i in _icon_grid.get_child_count():
		(_icon_grid.get_child(i) as TextureButton).self_modulate = UiTheme.GOLD if i == _icon_index else Color.WHITE
	for swatch in _color_row.get_children():
		var color: Color = swatch.get_meta("color")
		var selected := color.is_equal_approx(_color)
		var style := UiSkin.color_box(color if not swatch.disabled else color.darkened(0.6),
			UiSkin.BUTTON_TINT_HOVER if selected else UiSkin.BUTTON_TINT_NORMAL)
		for state in ["normal", "hover", "pressed", "disabled"]:
			swatch.add_theme_stylebox_override(state, style)
		swatch.text = "✕" if swatch.disabled else ("●" if selected else "")
	for child in _preview.get_children():
		child.queue_free()
	var badge := PartyBadge.build({"bg_color": _color, "icon_index": _icon_index, "icon_color": Color.WHITE}, Vector2(64, 64), 128)
	_preview.add_child(badge)
	var me := multiplayer.get_unique_id()
	var allowed := CardManager.can_found_party(me)
	_found_button.disabled = not allowed or not PartyManager.is_valid_name(_name_edit.text.strip_edges()) or _color.a <= 0.0

func _on_found() -> void:
	CardManager.found_party({"name": _name_edit.text.strip_edges(), "icon_index": _icon_index, "bg_color": _color})
	queue_free()
