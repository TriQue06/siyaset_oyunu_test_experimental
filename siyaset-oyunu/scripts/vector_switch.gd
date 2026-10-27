class_name VectorSwitch
extends CheckButton
## ANAHTAR (0.0.279, konsept .sw): oyuk krem ray, açıkken yeşil; krem topuz
## kalınlığıyla sağa kayar. Vektörle çizilir; Godot'nun simgesi görünmez
## (boş doku yalnız yer tutar).

const W := 46.0
const H := 26.0

static var _blank: ImageTexture

func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	if _blank == null:
		var image := Image.create(int(W), int(H), false, Image.FORMAT_RGBA8)
		_blank = ImageTexture.create_from_image(image)
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled",
			"checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored", "unchecked_disabled_mirrored"]:
		add_theme_icon_override(icon, _blank)
	toggled.connect(func(_on): queue_redraw())

func _draw() -> void:
	var pos := Vector2(size.x - W, (size.y - H) * 0.5)
	var on := button_pressed
	var track := StyleBoxFlat.new()
	track.bg_color = UiTheme.GREEN_DARK if on else UiTheme.SLOT
	if disabled:
		track.bg_color = track.bg_color.lerp(UiTheme.PANEL_LIGHT, 0.45)
	track.set_corner_radius_all(int(H * 0.5))
	track.anti_aliasing = true
	draw_style_box(track, Rect2(pos, Vector2(W, H)))
	if not on:
		draw_rect(Rect2(pos + Vector2(H * 0.5, 0), Vector2(W - H, 2)), Color(0, 0, 0, 0.1))
	var r := 10.0
	var c := pos + Vector2(W - 3.0 - r if on else 3.0 + r, H * 0.5)
	draw_circle(c + Vector2(0, 2), r, Color("14603A") if on else UiTheme.CARD_LIP, true, -1.0, true)
	draw_circle(c, r, UiTheme.PANEL_DARK, true, -1.0, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()
