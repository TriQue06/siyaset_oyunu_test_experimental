class_name VectorSlider
extends HSlider
## KAYDIRICI (0.0.279, konsept .slider): oyuk krem ray, hardal dolgu ve
## hardal piyon topuz; hepsi vektörle çizilir (her çözünürlükte keskin).
## Godot'nun kendi rayı ve topuzu görünmez kılınır; boş topuz dokusu yalnız
## tıklama hesabı için topuz genişliğini korur. Tekerlek ayarı değiştirmez.

const KNOB := 24.0
const TRACK_H := 8.0

static var _blank: ImageTexture
var _hover := false

func _init() -> void:
	scrollable = false
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = KNOB + 4.0
	if _blank == null:
		var image := Image.create(int(KNOB), int(KNOB), false, Image.FORMAT_RGBA8)
		_blank = ImageTexture.create_from_image(image)
	for icon in ["grabber", "grabber_highlight", "grabber_disabled", "tick"]:
		add_theme_icon_override(icon, _blank)
	for style in ["slider", "grabber_area", "grabber_area_highlight"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	value_changed.connect(func(_v): queue_redraw())
	changed.connect(queue_redraw)
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())

func _draw() -> void:
	var span := max_value - min_value
	var ratio := 0.0 if span <= 0.0 else clampf((value - min_value) / span, 0.0, 1.0)
	var cy := size.y * 0.5
	var knob_x := KNOB * 0.5 + ratio * (size.x - KNOB)
	var track := Rect2(0, cy - TRACK_H * 0.5, size.x, TRACK_H)
	var groove := StyleBoxFlat.new()
	groove.bg_color = UiTheme.SLOT
	groove.set_corner_radius_all(int(TRACK_H * 0.5))
	groove.anti_aliasing = true
	draw_style_box(groove, track)
	draw_rect(Rect2(track.position.x + 4, track.position.y, track.size.x - 8, 2), Color(0, 0, 0, 0.08))
	if ratio > 0.0:
		var fill := groove.duplicate() as StyleBoxFlat
		fill.bg_color = UiTheme.GOLD if editable else UiTheme.GOLD.lerp(UiTheme.PANEL_LIGHT, 0.5)
		draw_style_box(fill, Rect2(track.position, Vector2(maxf(TRACK_H, knob_x), TRACK_H)))
	var r := KNOB * 0.5
	var c := Vector2(knob_x, cy - 1.5)
	var face := UiTheme.GOLD if editable else UiTheme.GOLD.lerp(UiTheme.PANEL_LIGHT, 0.5)
	if editable and _hover:
		face = face.lightened(0.08)
	draw_circle(c + Vector2(0, 4.5), r, Color(0, 0, 0, 0.18), true, -1.0, true)
	draw_circle(c + Vector2(0, 3), r, UiTheme.GOLD_DIM if editable else UiTheme.CARD_LIP, true, -1.0, true)
	draw_circle(c, r, face, true, -1.0, true)
	draw_circle(c + Vector2(-r * 0.12, -r * 0.14), r * 0.72, face.lerp(Color("FFE08A"), 0.55), true, -1.0, true)
	draw_circle(c + Vector2(-r * 0.32, -r * 0.36), r * 0.2, Color(1, 1, 1, 0.55), true, -1.0, true)
