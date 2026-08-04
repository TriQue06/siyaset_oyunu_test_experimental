extends Control
## Parti Kurulum ekranı — HER OYUNCUYA ÖZEL, tam ekran, harita YOK. Solda
## partinin kocaman bir önizlemesi, sağda ayar paneli (isim, ikon, renkler,
## ideoloji).
##
## İDEOLOJİ KURALI: kuruluşta her eksen (economic/social/administrative)
## SADECE {-2,-1,1,2} değerlerinden biri olabilir — uç (-3/+3) ve nötr (0)
## YASAK (bkz. IdeologyAxes). Bu yüzden kaydırıcılar 0-3 ARASI İNDEKS
## seçtirir, doğrudan değer değil; olası tek değer seti zaten bu dörtlü.
## Uç/nötre ancak oyun içi ideoloji kartlarıyla ulaşılabilir.
##
## Süre (lobi ayarından gelen party_setup_duration; 0 = SINIRSIZ) dolunca
## HOST otomatik olarak herkesi Oyun Ekranı'na geçirir. Bir oyuncu
## "Kilitle ve Hazır Ver"e basarsa seçimleri kilitlenir ve hazır olarak
## işaretlenir; HERKES hazır olursa süre dolmamış olsa bile oyun hemen
## başlar. İptal ederse tekrar düzenleyebilir.
##
## Görsel yerleşim (panel/konteynerler) sahnede editörle düzenlenebilir;
## ikon/renk butonları ile eksen satırları, veri kataloğuna bağlı olduğundan
## çalışma zamanında üretilir.

const SWATCH_SIZE := 24.0
const ICON_BUTTON_SIZE := 30.0
const GRID_ICON_PIXEL_SIZE := 60       # ızgaradaki küçük ikonlar için raster boyutu
const PREVIEW_ICON_PIXEL_SIZE := 480   # kocaman önizleme için raster boyutu

# Eksen başına görünen başlık + uç etiketleri (- ve + yönü).
const AXIS_LABELS := {
	"economic": {"title": "Ekonomi", "neg": "Devletçi", "pos": "Piyasacı"},
	"social": {"title": "Toplum", "neg": "İlerici", "pos": "Muhafazakâr"},
	"administrative": {"title": "İdare", "neg": "Federal / Çoğulcu", "pos": "Üniter / Milliyetçi"},
}

@onready var countdown_label: Label = %CountdownLabel
@onready var ready_count_label: Label = %ReadyCountLabel
@onready var preview_bg: ColorRect = %PreviewBg
@onready var preview_icon: TextureRect = %PreviewIcon
@onready var name_edit: LineEdit = %NameEdit
@onready var name_hint_label: Label = %NameHintLabel
@onready var icon_grid: GridContainer = %IconGrid
@onready var icon_color_row: HFlowContainer = %IconColorRow
@onready var bg_color_row: HFlowContainer = %BgColorRow
@onready var ideology_container: VBoxContainer = %IdeologyContainer
@onready var random_button: Button = %RandomButton
@onready var ready_button: Button = %ReadyButton

var _party_name: String = ""
var _selected_icon_index: int = 0
var _selected_icon_color: Color = PartyPresets.COLORS[21]  # beyaz
var _selected_bg_color: Color = PartyPresets.COLORS[0]     # kırmızı
var _ideology: Dictionary = {}
var _ideology_sliders: Dictionary = {}   # axis -> HSlider
var _ideology_value_labels: Dictionary = {}  # axis -> Label

var _time_left: float = 60.0
var _unlimited_time: bool = false
var _is_locked: bool = false

func _ready() -> void:
	_unlimited_time = MultiplayerManager.party_setup_duration == MultiplayerManager.PARTY_DURATION_UNLIMITED
	_time_left = float(MultiplayerManager.party_setup_duration)
	_party_name = "Parti%d" % randi_range(1, 99)
	_ideology = IdeologyAxes.random_start_ideology()

	name_edit.text = _party_name
	name_edit.max_length = PartyManager.NAME_MAX_LENGTH
	name_edit.text_changed.connect(_on_name_changed)

	_build_icon_grid()
	_build_color_row(icon_color_row, _on_icon_color_selected)
	_build_color_row(bg_color_row, _on_bg_color_selected)
	_build_ideology_rows()
	random_button.pressed.connect(_on_random_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	MultiplayerManager.party_setup_finished.connect(_on_party_setup_finished)
	PartyManager.parties_updated.connect(_refresh_ready_count)

	_update_preview()
	_update_name_hint()
	_push_party()
	_update_countdown_label()
	_refresh_ready_count()

func _process(delta: float) -> void:
	if _unlimited_time:
		return
	_time_left = max(0.0, _time_left - delta)
	_update_countdown_label()
	if MultiplayerManager.is_host and _time_left <= 0.0:
		set_process(false)
		MultiplayerManager.finish_party_setup()

func _update_countdown_label() -> void:
	if _unlimited_time:
		countdown_label.text = "Süre: Sınırsız"
		return
	var seconds := int(ceil(_time_left))
	countdown_label.text = "Süre: %02d:%02d" % [seconds / 60, seconds % 60]

func _refresh_ready_count() -> void:
	var total := MultiplayerManager.players.size()
	var ready_count := 0
	for peer_id in MultiplayerManager.players.keys():
		if PartyManager.is_ready(peer_id):
			ready_count += 1
	ready_count_label.text = "Hazır: %d / %d" % [ready_count, total]

func _on_name_changed(new_text: String) -> void:
	_party_name = new_text
	_update_name_hint()
	if PartyManager.is_valid_name(_party_name):
		_push_party()

func _update_name_hint() -> void:
	var valid := PartyManager.is_valid_name(_party_name)
	name_hint_label.text = "%d-%d karakter" % [PartyManager.NAME_MIN_LENGTH, PartyManager.NAME_MAX_LENGTH]
	name_hint_label.modulate = Color(1, 1, 1, 0.6) if valid else Color(1, 0.4, 0.4, 1)

func _build_icon_grid() -> void:
	for i in PartyPresets.icon_count():
		var btn := TextureButton.new()
		btn.texture_normal = PartyPresets.get_icon_texture(i, GRID_ICON_PIXEL_SIZE)
		# ÖNEMLİ: ignore_texture_size olmadan TextureButton kendini dokunun
		# GERÇEK piksel boyutuna göre büyütür (custom_minimum_size'ı yok sayar)
		# — bu yüzden ızgara panelin dışına taşıyordu. Bunu kapatınca doku,
		# aşağıdaki sabit kutunun içine (küçülterek) sığdırılıyor.
		btn.ignore_texture_size = true
		btn.custom_minimum_size = Vector2(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.modulate = Color.WHITE
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		btn.pressed.connect(_on_icon_selected.bind(i))
		icon_grid.add_child(btn)
	_refresh_icon_grid_selection()

func _refresh_icon_grid_selection() -> void:
	for i in icon_grid.get_child_count():
		var btn: TextureButton = icon_grid.get_child(i)
		btn.self_modulate = Color(1, 1, 0.4) if i == _selected_icon_index else Color.WHITE

## Bir rengin, DİĞER (karşı) seçim için o an kullanımda olup olmadığını
## döner — ikon rengi ile arka plan rengi ASLA aynı olamaz.
func _is_color_taken_by_other(row: HFlowContainer, color: Color) -> bool:
	if row == icon_color_row:
		return color.is_equal_approx(_selected_bg_color)
	return color.is_equal_approx(_selected_icon_color)

func _build_color_row(row: HFlowContainer, callback: Callable) -> void:
	for child in row.get_children():
		child.queue_free()
	for i in PartyPresets.COLORS.size():
		var color: Color = PartyPresets.COLORS[i]
		var taken := _is_color_taken_by_other(row, color)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		btn.disabled = taken
		btn.modulate = Color(1, 1, 1, 0.35) if taken else Color(1, 1, 1, 1)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(4)
		style.border_width_bottom = 2
		style.border_width_top = 2
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_color = Color(1, 1, 1, 0.9) if _is_selected_color(row, color) else Color(0, 0, 0, 0.4)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("disabled", style)
		if not taken:
			btn.pressed.connect(callback.bind(i))
		row.add_child(btn)

func _is_selected_color(row: HFlowContainer, color: Color) -> bool:
	if row == icon_color_row:
		return color.is_equal_approx(_selected_icon_color)
	return color.is_equal_approx(_selected_bg_color)

func _on_icon_selected(index: int) -> void:
	_selected_icon_index = index
	_refresh_icon_grid_selection()
	_update_preview()
	_push_party()

func _on_icon_color_selected(index: int) -> void:
	_selected_icon_color = PartyPresets.COLORS[index]
	_build_color_row(icon_color_row, _on_icon_color_selected)
	_update_preview()
	_push_party()

func _on_bg_color_selected(index: int) -> void:
	_selected_bg_color = PartyPresets.COLORS[index]
	_build_color_row(bg_color_row, _on_bg_color_selected)
	_update_preview()
	_push_party()

## Her eksen için: başlık + (sol uç etiketi - kaydırıcı - sağ uç etiketi) +
## anlık değer. Kaydırıcı 0-3 İNDEKS tutar; gerçek değer her zaman
## IdeologyAxes.ALLOWED_START_VALUES[indeks] üzerinden okunur, böylece uç/nötr
## seçimi arayüz seviyesinde imkansız kalır.
func _build_ideology_rows() -> void:
	for axis in IdeologyAxes.AXES:
		var info: Dictionary = AXIS_LABELS.get(axis, {"title": axis, "neg": "-", "pos": "+"})

		var title := Label.new()
		title.text = info["title"]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ideology_container.add_child(title)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var neg_label := Label.new()
		neg_label.text = info["neg"]
		neg_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(neg_label)

		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = IdeologyAxes.ALLOWED_START_VALUES.size() - 1
		slider.step = 1
		slider.tick_count = IdeologyAxes.ALLOWED_START_VALUES.size()
		slider.ticks_on_borders = true
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		var start_value: int = _ideology.get(axis, IdeologyAxes.ALLOWED_START_VALUES[0])
		slider.value = IdeologyAxes.ALLOWED_START_VALUES.find(start_value)
		slider.value_changed.connect(_on_ideology_slider_changed.bind(axis))
		row.add_child(slider)

		var pos_label := Label.new()
		pos_label.text = info["pos"]
		pos_label.custom_minimum_size = Vector2(90, 0)
		pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pos_label)

		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.text = "%+d" % start_value
		row.add_child(value_label)

		ideology_container.add_child(row)

		_ideology_sliders[axis] = slider
		_ideology_value_labels[axis] = value_label

func _on_ideology_slider_changed(index: float, axis: String) -> void:
	var value: int = IdeologyAxes.ALLOWED_START_VALUES[int(index)]
	_ideology[axis] = value
	_ideology_value_labels[axis].text = "%+d" % value
	_push_party()

## Sadece ikon ve renkleri rastgeleler — İDEOLOJİYE DOKUNMAZ. İdeoloji daha
## stratejik bir seçim olduğu için kazara "rastgele" ile karışmasın diye
## kasıtlı olarak buraya dahil edilmedi.
func _on_random_pressed() -> void:
	_selected_icon_index = PartyPresets.random_icon_index()
	_selected_icon_color = PartyPresets.random_color()
	_selected_bg_color = PartyPresets.random_color()
	# İkon rengiyle arka plan rengi asla aynı olamaz — çakışırsa arka planı
	# başka bir renkle değiştirene kadar tekrar dene.
	while _selected_bg_color.is_equal_approx(_selected_icon_color):
		_selected_bg_color = PartyPresets.random_color()
	_refresh_icon_grid_selection()
	_build_color_row(icon_color_row, _on_icon_color_selected)
	_build_color_row(bg_color_row, _on_bg_color_selected)
	_update_preview()
	_push_party()

func _update_preview() -> void:
	preview_bg.color = _selected_bg_color
	preview_icon.texture = PartyPresets.get_icon_texture(_selected_icon_index, PREVIEW_ICON_PIXEL_SIZE)
	preview_icon.modulate = _selected_icon_color
	preview_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _push_party() -> void:
	if PartyManager.is_valid_name(_party_name):
		PartyManager.set_my_party(_party_name, _selected_icon_index, _selected_icon_color, _selected_bg_color, _ideology)

## "Kilitle ve Hazır Ver" / iptal: kilitliyken tüm seçim kontrolleri
## devre dışı kalır (yanlışlıkla değiştirilemesin diye), tekrar basınca açılır.
func _on_ready_pressed() -> void:
	_is_locked = not _is_locked
	_set_controls_disabled(_is_locked)
	ready_button.text = "✕ İptal Et" if _is_locked else "🔒 Kilitle ve Hazır Ver"
	PartyManager.set_ready(_is_locked)

func _set_controls_disabled(disabled: bool) -> void:
	name_edit.editable = not disabled
	random_button.disabled = disabled
	for btn in icon_grid.get_children():
		btn.disabled = disabled
	if disabled:
		for btn in icon_color_row.get_children():
			btn.disabled = true
		for btn in bg_color_row.get_children():
			btn.disabled = true
	else:
		# Sadece "disabled=false" yapmak yeterli değil — ikon/arka plan rengi
		# çakışma kısıtını (taken renkler) yeniden hesaplamak için satırları
		# baştan kuruyoruz.
		_build_color_row(icon_color_row, _on_icon_color_selected)
		_build_color_row(bg_color_row, _on_bg_color_selected)
	for axis in _ideology_sliders.keys():
		_ideology_sliders[axis].editable = not disabled

func _on_party_setup_finished() -> void:
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")
