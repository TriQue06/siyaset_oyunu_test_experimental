class_name TutorialGuide
extends Control
## İLK OYUN REHBERİ: bağlama duyarlı, oyunu DURDURMAYAN kısa ipuçları. Her
## ipucunun bir koşulu (ne zaman anlamlı) ve bir hedefi (ekranda hangi alan)
## vardır; koşul sağlanınca hedef altın, nabız gibi atan bir çerçeveyle
## gösterilir, yanında kısa açıklama ve "Anladım" / "Rehberi kapat" çıkar.
## Aynı anda tek ipucu. Görülen ipuçları ve kapatma tercihi cihazda saklanır
## (user://tutorial.cfg); Oyun Menüsü'nden sıfırlanabilir.

const CONFIG_PATH := "user://tutorial.cfg"
const CHECK_INTERVAL := 0.5
const PANEL_WIDTH := 330.0
## Test / önizleme betikleri rehberi sadece bunu açınca görür.
static var allow_in_scripts := false
## Ayar dosyası (testler geçici bir dosya kullanır).
static var config_path := CONFIG_PATH

## Kayıtlı adımlar: [{"id", "title", "text", "target": Callable -> Rect2, "when": Callable -> bool}]
var _steps: Array = []
var _seen: Dictionary = {}
var _disabled := false
var _current: Dictionary = {}
var _check_left := 0.0
var _pulse := 0.0
var _panel: PanelContainer
var _title: Label
var _text: Label
var _counter: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 140
	_load()
	_build_panel()

static func is_disabled() -> bool:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return false
	return bool(config.get_value("tutorial", "disabled", false))

## Rehberi baştan başlatır (Oyun Menüsü).
static func reset() -> void:
	var config := ConfigFile.new()
	config.set_value("tutorial", "disabled", false)
	config.set_value("tutorial", "seen", [])
	config.save(config_path)

func add_step(id: String, title: String, text: String, target: Callable, when: Callable) -> void:
	_steps.append({"id": id, "title": title, "text": text, "target": target, "when": when})

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	_disabled = bool(config.get_value("tutorial", "disabled", false))
	for id in config.get_value("tutorial", "seen", []):
		_seen[String(id)] = true

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("tutorial", "disabled", _disabled)
	config.set_value("tutorial", "seen", _seen.keys())
	config.save(config_path)

## Menüden sıfırlanınca çalışan rehber de baştan başlar.
func restart() -> void:
	reset()
	_seen.clear()
	_disabled = false
	_hide_current()

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1d1838")
	style.border_color = UiTheme.GOLD
	style.set_border_width_all(2)
	style.border_width_top = 4
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(UiTheme.INK, 0.7)
	style.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.hide()
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = UiTheme.mono_label("", 14, UiTheme.GOLD, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_counter = UiTheme.mono_label("", 10, UiTheme.TEXT_DIM)
	head.add_child(_counter)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(PANEL_WIDTH - 28.0, 0)
	_text.add_theme_font_size_override("font_size", 13)
	_text.add_theme_color_override("font_color", UiTheme.TEXT)
	box.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var ok := Button.new()
	ok.text = L.t("Anladım")
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(110, 30)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiSkin.skin_color_button(ok, UiTheme.GREEN_DARK)
	ok.pressed.connect(_on_ok)
	buttons.add_child(ok)
	var off := Button.new()
	off.text = L.t("Rehberi kapat")
	off.focus_mode = Control.FOCUS_NONE
	off.custom_minimum_size = Vector2(120, 30)
	UiSkin.skin_button(off)
	off.add_theme_font_size_override("font_size", 12)
	off.pressed.connect(_on_disable)
	buttons.add_child(off)

func _on_ok() -> void:
	if not _current.is_empty():
		_seen[String(_current["id"])] = true
		_save()
	_hide_current()
	_check_left = 0.8  # bir sonraki ipucu hemen üst üste binmesin

func _on_disable() -> void:
	_disabled = true
	_save()
	_hide_current()

func _hide_current() -> void:
	_current = {}
	_panel.hide()
	queue_redraw()

func seen_count() -> int:
	var n := 0
	for step in _steps:
		if _seen.has(String(step["id"])):
			n += 1
	return n

func current_id() -> String:
	return String(_current.get("id", ""))

func _process(delta: float) -> void:
	if _disabled:
		return
	_pulse += delta
	if not _current.is_empty():
		_place()
		queue_redraw()
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_INTERVAL
	check_now()

## Sıradaki görülmemiş ve koşulu sağlanan ipucunu açar.
func check_now() -> void:
	if _disabled or not _current.is_empty():
		return
	for step in _steps:
		if _seen.has(String(step["id"])):
			continue
		if bool((step["when"] as Callable).call()):
			_show(step)
			return

func _show(step: Dictionary) -> void:
	_current = step
	_title.text = String(step["title"])
	_text.text = String(step["text"])
	_counter.text = "%d/%d" % [seen_count() + 1, _steps.size()]
	_panel.show()
	_panel.reset_size()
	_place()
	queue_redraw()

func _target_rect() -> Rect2:
	if _current.is_empty():
		return Rect2()
	return (_current["target"] as Callable).call()

## Paneli hedefin altına (yer yoksa üstüne, yoksa yanına) yerleştirir; ekranda kalır.
func _place() -> void:
	var view := get_viewport_rect().size
	var target := _target_rect()
	var size := _panel.get_combined_minimum_size()
	var pos := Vector2(target.position.x, target.end.y + 10.0)
	if pos.y + size.y > view.y - 8.0:
		pos.y = target.position.y - size.y - 10.0
	if pos.y < 8.0:
		pos = Vector2(target.end.x + 10.0, target.position.y)
		if pos.x + size.x > view.x - 8.0:
			pos.x = target.position.x - size.x - 10.0
	pos.x = clampf(pos.x, 8.0, view.x - size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, view.y - size.y - 8.0)
	_panel.position = pos

func _draw() -> void:
	if _current.is_empty():
		return
	var target := _target_rect().grow(4.0)
	var glow := 0.55 + 0.45 * sin(_pulse * 5.0)
	draw_rect(target, Color(UiTheme.GOLD, 0.10 * glow), true)
	draw_rect(target, Color(UiTheme.GOLD, glow), false, 3.0)
