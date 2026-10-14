class_name FundingSlider
extends Control
## FİNANSMAN ÇİZGİSİ: bir hamlenin bedelinin PARTİ KASASI (sol uç) ile DEVLET
## HAZİNESİ (sağ uç) arasında nasıl bölüneceğini seçen sürüklenebilir nokta.
## share = devletin payı (0: tamamı parti, 1: tamamı devlet); nokta hangi uca
## yakınsa o kaynak daha çok öder. İzin verilmeyen aralık (kasası yetmeyen
## taraf) taralı ve sönük çizilir, nokta oraya giremez. %5 adımlarla durur;
## fare, dokunma ve klavye (← →, Home/End) ile kullanılır. Görünen nokta
## hedefe yumuşakça kayar (ölçülü hareket).

signal share_changed(share: float)

const PARTY_COLOR := UiTheme.BLUE
const STATE_COLOR := UiTheme.GOLD
const TRACK_H := 6.0
const THUMB_R := 10.0
const PAD := 14.0

var share: float = 1.0
var min_share: float = 0.0
var max_share: float = 1.0
var _shown: float = 1.0
var _dragging := false
var _hover := false

func _init() -> void:
	custom_minimum_size = Vector2(0, 34)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))

func _set_hover(value: bool) -> void:
	_hover = value
	queue_redraw()

## Aralığı ve başlangıç değerini kurar (animasyonsuz).
func setup(value: float, lo: float, hi: float) -> void:
	min_share = lo
	max_share = hi
	share = _clamp(value)
	_shown = share
	queue_redraw()

func set_share(value: float) -> void:
	var next := _clamp(value)
	if is_equal_approx(next, share):
		return
	share = next
	share_changed.emit(share)
	queue_redraw()

func _clamp(value: float) -> float:
	var s := Economy.snap_share(value)
	if min_share > max_share:
		return s
	return clampf(s, min_share, max_share)

func _process(delta: float) -> void:
	if not is_equal_approx(_shown, share):
		_shown = move_toward(_shown, share, maxf(0.02, absf(share - _shown) * 14.0 * delta))
		queue_redraw()

func _x_of(value: float) -> float:
	return PAD + value * (size.x - 2.0 * PAD)

func _value_at(x: float) -> float:
	return (x - PAD) / maxf(1.0, size.x - 2.0 * PAD)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			grab_focus()
			set_share(_value_at(event.position.x))
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		set_share(_value_at(event.position.x))
		accept_event()
	elif event is InputEventScreenTouch:
		_dragging = event.pressed
		if event.pressed:
			set_share(_value_at(event.position.x))
		accept_event()
	elif event is InputEventScreenDrag:
		set_share(_value_at(event.position.x))
		accept_event()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT:
				set_share(share - Economy.FUND_STEP)
			KEY_RIGHT:
				set_share(share + Economy.FUND_STEP)
			KEY_HOME:
				set_share(0.0)
			KEY_END:
				set_share(1.0)
			_:
				return
		accept_event()

func _draw() -> void:
	var y := size.y * 0.5
	var left := _x_of(0.0)
	var right := _x_of(1.0)
	# Ray: partinin rengi soldan devletin rengine doğru (iki kaynak tek çizgide).
	var steps := 24
	for i in steps:
		var a := float(i) / steps
		var b := float(i + 1) / steps
		var color := PARTY_COLOR.lerp(STATE_COLOR, (a + b) * 0.5).darkened(0.35)
		draw_rect(Rect2(lerpf(left, right, a), y - TRACK_H * 0.5, (right - left) / steps + 0.5, TRACK_H), color, true)
	# Çeyrek işaretleri (%0, 25, 50, 75, 100).
	for q in 5:
		var x := lerpf(left, right, q / 4.0)
		draw_line(Vector2(x, y + TRACK_H * 0.5 + 2.0), Vector2(x, y + TRACK_H * 0.5 + 6.0), UiTheme.TEXT_DIM, 1.0)
	# İzin verilmeyen bölgeler: taralı, sönük.
	if min_share > max_share:
		_draw_blocked(left, right, y)
	else:
		if min_share > 0.0:
			_draw_blocked(left, _x_of(min_share), y)
		if max_share < 1.0:
			_draw_blocked(_x_of(max_share), right, y)
	# Nokta: rengi paylaşıma göre karışır; seçiliyken/üstündeyken halkası parlar.
	if min_share <= max_share:
		var cx := _x_of(_shown)
		var tint := PARTY_COLOR.lerp(STATE_COLOR, _shown)
		var active := _dragging or has_focus() or _hover
		draw_circle(Vector2(cx, y + 2.0), THUMB_R, Color(UiTheme.INK, 0.6))
		draw_circle(Vector2(cx, y), THUMB_R, UiTheme.INK)
		draw_circle(Vector2(cx, y), THUMB_R - 2.5, tint)
		draw_arc(Vector2(cx, y), THUMB_R + (2.5 if active else 0.5), 0.0, TAU, 28,
			Color(UiTheme.TEXT, 0.95 if active else 0.55), 2.0 if active else 1.2, true)
		draw_circle(Vector2(cx, y), 2.5, UiTheme.TEXT)

func _draw_blocked(from: float, to: float, y: float) -> void:
	if to - from < 1.0:
		return
	var rect := Rect2(from, y - TRACK_H, to - from, TRACK_H * 2.0)
	draw_rect(rect, Color(UiTheme.INK, 0.75), true)
	var x := from
	while x < to:
		draw_line(Vector2(x, y + TRACK_H), Vector2(minf(x + TRACK_H * 2.0, to), y - TRACK_H), Color(UiTheme.RED, 0.55), 1.0)
		x += 6.0
