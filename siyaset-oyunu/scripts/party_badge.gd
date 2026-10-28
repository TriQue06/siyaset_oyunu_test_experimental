class_name PartyBadge
extends RefCounted
## Parti rengi ve simgesinden güncel yuvarlak pulu üretir.
## Kendi partisi hardal kenarla vurgulanır.

static func build(party: Dictionary, size: Vector2, icon_pixel_size: int, is_self: bool = false) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = size
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP

	# MASA OYUNU PULU: parti renginde yuvarlak pul, altında koyu kalınlık;
	# kendi partinde dışta hardal halka.
	var color: Color = party.get("bg_color", UiTheme.PANEL_LIGHT)
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Konsept .pico: tepesi açık (beyazla %40) renge geçen pul, altta iç
	# koyuluk, koyu kalınlık ve yumuşak gölge; kendi partinde hardal halka.
	var style := BoardBox.new()
	style.fill = color.lerp(Color.WHITE, 0.4)
	style.fill_bottom = color
	style.set_radius(size.y * 0.5)
	style.shade_size = size.y * 0.087
	style.shade_color = Color(0, 0, 0, 0.22)
	style.lips = [[size.y * 0.087, color.lerp(Color.BLACK, 0.45)]]
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_offset = Vector2(0, size.y * 0.13)
	style.shadow_size = size.y * 0.09
	if is_self:
		style.rings = [[0.0, maxf(1.5, size.y * 0.06), UiTheme.GOLD]]
	disc.add_theme_stylebox_override("panel", style)
	disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(disc)

	if party.has("icon_index"):
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = PartyPresets.get_icon_texture(party["icon_index"], icon_pixel_size)
		icon.modulate = party.get("icon_color", Color.WHITE)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		# 0.0.268: ikon %7,5 büyük (pay 0,24 -> 0,22).
		var margin := size.y * 0.22
		icon.offset_left = margin
		icon.offset_top = margin - size.y * 0.03
		icon.offset_right = -margin
		icon.offset_bottom = -margin - size.y * 0.03
		wrap.add_child(icon)

	return wrap
