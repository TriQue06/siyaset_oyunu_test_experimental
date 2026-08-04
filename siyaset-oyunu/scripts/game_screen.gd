extends Control
## Taslak/placeholder oyun ekranı. Parti Kurulum süresi bitince buraya
## geçilir. Gerçek oyun döngüsü (dönemler, kart oynama vb.) henüz burada
## değil — harita + sağdaki oyuncu paneli var, geçişin doğru sahneye
## ulaştığını doğrulamak ve parti verisinin oyunda da göründüğünü göstermek
## için.
##
## Sağ kenardaki oyuncu paneli: her partinin yuvarlak logosu (arka plan
## rengi + ikon). Üzerine gelince (hover) o partinin ideolojisi CANLI olarak
## gösterilir — PartyManager.parties_updated her tetiklendiğinde güncellenir,
## yani bir parti ideolojisi oyun içinde değişirse (ileride kartlarla) açık
## tooltip de anında yenilenir.

const MAP_SCALE := 1.05
# Sağda oyuncu daireleri için ayrılan, PANELSİZ (tamamen boş) şerit genişliği.
# Harita bu şeridin üstüne hiç taşmasın diye ortalama hesabına dahil edilir.
const PLAYER_STRIP_WIDTH := 120.0
const AVATAR_SIZE := 56.0
const AVATAR_ICON_PIXEL_SIZE := 96

@onready var map_holder: Node2D = %MapHolder
@onready var player_panel_list: VBoxContainer = %PlayerPanelList
@onready var hover_tooltip: PanelContainer = %HoverTooltip
@onready var hover_tooltip_title: Label = %HoverTooltipTitle
@onready var hover_tooltip_axes: VBoxContainer = %HoverTooltipAxes

var _hovered_peer_id: int = -1

func _ready() -> void:
	map_holder.scale = Vector2(MAP_SCALE, MAP_SCALE)
	await get_tree().process_frame
	var viewport_size := get_viewport_rect().size
	var map_native_size := Vector2(1024, 500)
	# Sadece SOL bölgeye (sağdaki boş oyuncu şeridi hariç) göre ortala, ki
	# harita o alana hiç taşmasın.
	var available_width := viewport_size.x - PLAYER_STRIP_WIDTH
	map_holder.position = Vector2(
		available_width * 0.5 - map_native_size.x * 0.5 * MAP_SCALE,
		viewport_size.y * 0.5 - map_native_size.y * 0.5 * MAP_SCALE
	)

	hover_tooltip.hide()
	PartyManager.parties_updated.connect(_on_parties_updated)
	_rebuild_player_panel()

func _on_parties_updated() -> void:
	_rebuild_player_panel()
	if _hovered_peer_id != -1:
		_show_tooltip_for(_hovered_peer_id)

func _rebuild_player_panel() -> void:
	for child in player_panel_list.get_children():
		child.queue_free()

	for peer_id in MultiplayerManager.players.keys():
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var avatar := _build_avatar(peer_id, party)
		player_panel_list.add_child(avatar)

func _build_avatar(peer_id: int, party: Dictionary) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	# VBoxContainer içindeki çocukları yatayda gerebilir; bu olmadan daire
	# oval'a dönüşürdü. SHRINK_CENTER ile hep AVATAR_SIZE genişliğinde,
	# sütunda ortalanmış kalır.
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg_color: Color = party.get("bg_color", Color(0.3, 0.3, 0.3))
	var circle := Panel.new()
	circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(int(AVATAR_SIZE / 2.0))
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(1, 1, 1, 0.5)
	circle.add_theme_stylebox_override("panel", style)
	wrap.add_child(circle)

	if party.has("icon_index"):
		var icon := TextureRect.new()
		icon.texture = PartyPresets.get_icon_texture(party["icon_index"], AVATAR_ICON_PIXEL_SIZE)
		icon.modulate = party.get("icon_color", Color.WHITE)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		var margin := AVATAR_SIZE * 0.22
		icon.offset_left = margin
		icon.offset_top = margin
		icon.offset_right = -margin
		icon.offset_bottom = -margin
		wrap.add_child(icon)

	wrap.mouse_entered.connect(_on_avatar_hovered.bind(peer_id))
	wrap.mouse_exited.connect(_on_avatar_unhovered.bind(peer_id))
	return wrap

func _on_avatar_hovered(peer_id: int) -> void:
	_hovered_peer_id = peer_id
	_show_tooltip_for(peer_id)

func _on_avatar_unhovered(peer_id: int) -> void:
	if _hovered_peer_id == peer_id:
		_hovered_peer_id = -1
		hover_tooltip.hide()

func _show_tooltip_for(peer_id: int) -> void:
	var party: Dictionary = PartyManager.parties.get(peer_id, {})
	var pname: String = MultiplayerManager.players.get(peer_id, {}).get("name", "?")
	hover_tooltip_title.text = party.get("name", pname)

	for child in hover_tooltip_axes.get_children():
		child.queue_free()

	var ideology: Dictionary = party.get("ideology", IdeologyAxes.default_values())
	for axis in IdeologyAxes.AXES:
		var value: int = ideology.get(axis, 0)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var label := Label.new()
		label.text = "%s: %+d" % [_axis_title(axis), value]
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)

		var bar := TextureRect.new()
		bar.texture = AxisVisual.get_axis_texture(axis, value)
		bar.custom_minimum_size = Vector2(154, 22)
		row.add_child(bar)

		hover_tooltip_axes.add_child(row)

	# Tooltip'i, hover edilen avatarın hemen soluna yerleştir.
	var avatar_index := MultiplayerManager.players.keys().find(peer_id)
	if avatar_index != -1 and avatar_index < player_panel_list.get_child_count():
		var avatar: Control = player_panel_list.get_child(avatar_index)
		var avatar_global_pos := avatar.global_position
		hover_tooltip.show()
		await get_tree().process_frame
		var tooltip_size := hover_tooltip.size
		hover_tooltip.global_position = avatar_global_pos - Vector2(tooltip_size.x + 12, 0)
	else:
		hover_tooltip.show()

func _axis_title(axis: String) -> String:
	match axis:
		"economic":
			return "Ekonomi"
		"social":
			return "Toplum"
		"administrative":
			return "İdare"
		_:
			return axis
