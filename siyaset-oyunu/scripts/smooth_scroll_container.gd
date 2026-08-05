class_name SmoothScrollContainer
extends ScrollContainer
## Godot'un varsayılan ScrollContainer'ında ORTA FARE TUŞUYLA sürükleyerek
## kaydırma YOKTUR ve fare tekerleği sabit adımlarla ANİDEN zıplar. Bu script
## ikisini de düzeltir:
##   - Orta tuşa basılı tutup sürükleyince içerik fareyi 1:1 takip eder,
##     bırakınca sürtünmeli bir "momentum" ile yumuşakça yavaşlayarak durur.
##   - Fare tekerleği artık ani zıplama yerine hedefe doğru yumuşak (eased)
##     kayar.
## Herhangi bir ScrollContainer'a bu script'i atamak yeterli, başka kurulum
## gerekmez.

const FRICTION := 7.0             # yüksek = momentum daha çabuk söner
const MIN_VELOCITY := 6.0         # bu hızın altında momentum durdurulur
const VELOCITY_SMOOTHING := 18.0  # sürükleme sırasında hız ölçümü yumuşatma
const WHEEL_STEP := 100.0         # tekerlek "tık" başına hedef kayma miktarı
const WHEEL_EASE_SPEED := 16.0    # tekerlek hedefine yaklaşma hızı

var _dragging := false
var _last_drag_pos := Vector2.ZERO
var _velocity := Vector2.ZERO
var _wheel_target := Vector2.ZERO
var _wheel_active := false # tekerlek hedefine dogru yumusak yaklasma su an aktif mi
var _internal_update := false # scroll_horizontal/vertical'i BIZ yaziyoruz, disaridan degil

func _ready() -> void:
	_wheel_target = Vector2(scroll_horizontal, scroll_vertical)
	gui_input.connect(_on_gui_input)
	# Scrollbar'lari dogrudan fareyle surukleme, gui_input'tan degil bu
	# sinyalden gecer; _wheel_target'i onunla senkron tutmazsak, kullanicinin
	# scrollbar'i surukleyisiyle bizim eski hedefe "yumusak yaklasma" mantigimiz
	# birbiriyle cekisip titremeye/bug'a yol aciyordu.
	var h_bar := get_h_scroll_bar()
	var v_bar := get_v_scroll_bar()
	if h_bar != null:
		h_bar.value_changed.connect(_on_scrollbar_value_changed)
	if v_bar != null:
		v_bar.value_changed.connect(_on_scrollbar_value_changed)
	set_process(true)

func _on_scrollbar_value_changed(_value: float) -> void:
	if _internal_update or _dragging:
		return
	# Kullanici scrollbar'i dogrudan surukluyor (ya da tikladi): bizim
	# hedefimizi ve momentum hizimizi anlik konuma senkronla ki cekismesin.
	_wheel_active = false
	_velocity = Vector2.ZERO
	_wheel_target = Vector2(scroll_horizontal, scroll_vertical)

func _get_max_scroll() -> Vector2:
	var h_bar := get_h_scroll_bar()
	var v_bar := get_v_scroll_bar()
	var max_h := 0.0
	var max_v := 0.0
	if h_bar != null:
		max_h = maxf(0.0, h_bar.max_value - h_bar.page)
	if v_bar != null:
		max_v = maxf(0.0, v_bar.max_value - v_bar.page)
	return Vector2(max_h, max_v)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_dragging = true
			_wheel_active = false
			_last_drag_pos = event.global_position
			_velocity = Vector2.ZERO
			_wheel_target = Vector2(scroll_horizontal, scroll_vertical)
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_wheel_active = true
		_wheel_target.y = clampf(_wheel_target.y - WHEEL_STEP, 0.0, _get_max_scroll().y)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_wheel_active = true
		_wheel_target.y = clampf(_wheel_target.y + WHEEL_STEP, 0.0, _get_max_scroll().y)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var delta: Vector2 = motion.global_position - _last_drag_pos
		_last_drag_pos = motion.global_position
		var max_scroll := _get_max_scroll()
		_internal_update = true
		scroll_horizontal = clampi(scroll_horizontal - int(delta.x), 0, int(max_scroll.x))
		scroll_vertical = clampi(scroll_vertical - int(delta.y), 0, int(max_scroll.y))
		_internal_update = false
		_wheel_target = Vector2(scroll_horizontal, scroll_vertical)
		var dt := maxf(get_process_delta_time(), 0.0001)
		var target_velocity: Vector2 = -delta / dt
		_velocity = _velocity.lerp(target_velocity, minf(1.0, VELOCITY_SMOOTHING * dt))
		accept_event()

func _process(delta: float) -> void:
	var max_scroll := _get_max_scroll()

	if _dragging:
		return

	# Tekerlek hedefine yumuşak yaklaşma (kullanıcı tekerlek çevirdiyse).
	# Sadece _wheel_active iken calisir; kullanici scrollbar'i dogrudan
	# surukluyorsa _on_scrollbar_value_changed bunu kapatir, cekisme olmaz.
	if _wheel_active:
		var current := Vector2(scroll_horizontal, scroll_vertical)
		if current.distance_to(_wheel_target) > 0.5:
			var eased := current.lerp(_wheel_target, minf(1.0, WHEEL_EASE_SPEED * delta))
			_internal_update = true
			scroll_horizontal = int(round(eased.x))
			scroll_vertical = int(round(eased.y))
			_internal_update = false
			return
		else:
			_wheel_active = false

	# Bırakınca momentum: sürtünmeyle yavaşlayarak kaymaya devam eder.
	if _velocity.length() > MIN_VELOCITY:
		var new_scroll := Vector2(scroll_horizontal, scroll_vertical) + _velocity * delta
		_internal_update = true
		scroll_horizontal = clampi(int(round(new_scroll.x)), 0, int(max_scroll.x))
		scroll_vertical = clampi(int(round(new_scroll.y)), 0, int(max_scroll.y))
		_internal_update = false
		_wheel_target = Vector2(scroll_horizontal, scroll_vertical)
		_velocity = _velocity.lerp(Vector2.ZERO, minf(1.0, FRICTION * delta))
		# Kenara çarpınca momentum'u kes (zıplamasın).
		if scroll_horizontal <= 0 or scroll_horizontal >= int(max_scroll.x):
			_velocity.x = 0.0
		if scroll_vertical <= 0 or scroll_vertical >= int(max_scroll.y):
			_velocity.y = 0.0
