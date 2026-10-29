class_name AvatarEditor
extends Control

signal appearance_changed(value: Dictionary)
const TITLES := {"face": "Yüz", "hair": "Saç", "eyebrows": "Kaş", "iris": "Göz irisi", "moustache": "Bıyık", "beard": "Sakal"}
var appearance: Dictionary = {}
var _gender_drafts: Dictionary = {}
var _category := "face"
var _preview: AvatarPortrait
var _tabs: HFlowContainer
var _grid: GridContainer
var _genders: Dictionary = {}
var _scroll: ScrollContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var built := PopupKit.frame(0, UiTheme.TEAL)
	var panel: PanelContainer = built[0]
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 38
	panel.offset_bottom = -38
	add_child(panel)
	var body: VBoxContainer = built[1]
	body.add_theme_constant_override("separation", 14)
	body.add_child(PopupKit.header(L.t("Siyasetçi Profili"), "", null, queue_free))
	var gender_row := HBoxContainer.new()
	gender_row.add_theme_constant_override("separation", 10)
	body.add_child(gender_row)
	for g: String in ["m", "f"]:
		var button := Button.new()
		button.text = L.t("Erkek" if g == "m" else "Kadın")
		button.custom_minimum_size = Vector2(130, 42)
		button.pressed.connect(_select_gender.bind(g))
		gender_row.add_child(button)
		_genders[g] = button
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 24)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	var portrait_panel := PanelContainer.new()
	portrait_panel.custom_minimum_size.x = 310
	portrait_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_panel.size_flags_stretch_ratio = 0.8
	portrait_panel.add_theme_stylebox_override("panel", UiSkin.card(UiTheme.PANEL, UiTheme.EDGE, UiTheme.EDGE_DARK))
	main.add_child(portrait_panel)
	_preview = AvatarPortrait.new()
	_preview.custom_minimum_size = Vector2(280, 350)
	portrait_panel.add_child(_preview)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 480
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 16)
	main.add_child(controls)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 8)
	_tabs.add_theme_constant_override("v_separation", 8)
	controls.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(_grid)
	var done := Button.new()
	done.text = L.t("Tamam")
	done.custom_minimum_size = Vector2(160, 42)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiSkin.skin_color_button(done, UiTheme.GOLD)
	done.pressed.connect(queue_free)
	body.add_child(done)
	_refresh()

func set_appearance(value: Dictionary) -> void:
	appearance = AvatarCatalog.clean(value, String(value.get("gender", "m")))
	_gender_drafts[appearance.gender] = appearance.duplicate(true)
	if is_node_ready():
		_refresh()

func _select_gender(gender: String) -> void:
	_gender_drafts[appearance.gender] = appearance.duplicate(true)
	appearance = AvatarCatalog.clean(_gender_drafts.get(gender, {}), gender)
	if gender == "f" and _category in ["beard", "moustache"]:
		_category = "face"
	_refresh()
	appearance_changed.emit(appearance.duplicate(true))

func _select(category: String, id: Variant) -> void:
	appearance[category] = id
	_refresh()
	appearance_changed.emit(appearance.duplicate(true))

func _choose_category(category: String) -> void:
	_category = category
	_scroll.scroll_vertical = 0
	_refresh()

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _refresh() -> void:
	_preview.set_appearance(appearance)
	for g: String in _genders:
		UiSkin.skin_color_button(_genders[g], UiTheme.GOLD if g == appearance.gender else UiTheme.PANEL_LIGHT)
	_clear(_tabs)
	for category: String in AvatarCatalog.CATEGORIES:
		if appearance.gender == "f" and category in ["beard", "moustache"]:
			continue
		var tab := Button.new()
		tab.text = L.t(TITLES[category])
		tab.custom_minimum_size = Vector2(76, 36)
		UiSkin.skin_color_button(tab, UiTheme.GOLD if category == _category else UiTheme.PANEL_LIGHT)
		tab.pressed.connect(_choose_category.bind(category))
		_tabs.add_child(tab)
	_clear(_grid)
	var choices: Array = []
	choices.append_array(AvatarCatalog.options(_category, appearance.gender))
	if AvatarCatalog.OPTIONAL.has(_category):
		choices.push_front(null)
	for id: Variant in choices:
		var button := Button.new()
		button.custom_minimum_size = Vector2(106, 150)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected: bool = appearance.get(_category) == id
		var style := UiSkin.card(UiTheme.PANEL_DARK, UiTheme.GOLD if selected else UiTheme.CARD_LIP, UiTheme.EDGE)
		if selected:
			style.rings = [[0.0, UiTheme.d(4), UiTheme.GOLD]]
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", UiSkin.card(UiTheme.PANEL, UiTheme.GOLD, UiTheme.EDGE))
		button.add_theme_stylebox_override("pressed", style)
		button.pressed.connect(_select.bind(_category, id))
		_grid.add_child(button)
		var thumb := AvatarPortrait.new()
		thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = 5
		thumb.offset_right = -5
		thumb.offset_top = 5
		thumb.offset_bottom = -28
		var sample := appearance.duplicate(true)
		sample[_category] = id
		thumb.set_appearance(sample)
		button.add_child(thumb)
		var label := UiTheme.mono_label(L.t("Yok") if id == null else L.t(String(AvatarCatalog.data().assets[id].label)), 13, UiTheme.TEXT)
		label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		label.offset_top = -27
		label.offset_bottom = -6
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
