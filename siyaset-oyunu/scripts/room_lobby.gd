extends Control

const SETTINGS_SHIFT := 150.0
const SLIDE_DURATION := 0.2

@onready var code_label: Label = %CodeLabel
@onready var copy_code_button: Button = %CopyCodeButton
@onready var player_list_box: VBoxContainer = %PlayerListBox
@onready var settings_button: Button = %SettingsButton
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton
@onready var info_label: Label = %InfoLabel
@onready var threshold_label: Label = %ThresholdLabel
@onready var center_box: VBoxContainer = %CenterBox

@onready var settings_side_panel: Control = %SettingsSidePanel
@onready var threshold_slider: HSlider = %ThresholdSlider
@onready var threshold_value_label: Label = %ThresholdValueLabel
@onready var party_duration_slider: HSlider = %PartyDurationSlider
@onready var party_duration_value_label: Label = %PartyDurationValueLabel
@onready var side_close_button: Button = %SideCloseButton

@onready var axis_start_slider: HSlider = %AxisStartSlider
@onready var axis_start_value_label: Label = %AxisStartValueLabel
@onready var axis_increment_slider: HSlider = %AxisIncrementSlider
@onready var axis_increment_value_label: Label = %AxisIncrementValueLabel
@onready var axis_max_enabled_check: CheckButton = %AxisMaxEnabledCheck
@onready var axis_max_value_row: HBoxContainer = %AxisMaxValueRow
@onready var axis_max_value_slider: HSlider = %AxisMaxValueSlider
@onready var axis_max_value_value_label: Label = %AxisMaxValueValueLabel

var _settings_open: bool = false
var _center_base_x: float = 0.0

func _ready() -> void:
	_refresh_code_display()
	GameSettings.streamer_mode_changed.connect(_on_streamer_mode_changed)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	side_close_button.pressed.connect(_on_settings_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	threshold_slider.min_value = MultiplayerManager.THRESHOLD_MIN
	threshold_slider.max_value = MultiplayerManager.THRESHOLD_MAX
	threshold_slider.step = MultiplayerManager.THRESHOLD_STEP
	threshold_slider.value_changed.connect(_on_threshold_slider_changed)

	party_duration_slider.min_value = 0
	party_duration_slider.max_value = MultiplayerManager.PARTY_DURATION_OPTIONS.size() - 1
	party_duration_slider.step = 1
	party_duration_slider.value_changed.connect(_on_party_duration_slider_changed)

	axis_start_slider.min_value = MultiplayerManager.AXIS_SHARPNESS_START_MIN
	axis_start_slider.max_value = MultiplayerManager.AXIS_SHARPNESS_START_MAX
	axis_start_slider.step = 0.5
	axis_start_slider.value_changed.connect(_on_axis_start_slider_changed)

	axis_increment_slider.min_value = MultiplayerManager.AXIS_SHARPNESS_INCREMENT_MIN
	axis_increment_slider.max_value = MultiplayerManager.AXIS_SHARPNESS_INCREMENT_MAX
	axis_increment_slider.step = 0.1
	axis_increment_slider.value_changed.connect(_on_axis_increment_slider_changed)

	axis_max_enabled_check.toggled.connect(_on_axis_max_enabled_toggled)

	axis_max_value_slider.min_value = 0
	axis_max_value_slider.max_value = MultiplayerManager.AXIS_SHARPNESS_CAP_OPTIONS.size() - 1
	axis_max_value_slider.step = 1
	axis_max_value_slider.value_changed.connect(_on_axis_max_value_slider_changed)

	MultiplayerManager.player_list_updated.connect(_refresh)
	MultiplayerManager.settings_updated.connect(_refresh_settings_display)
	MultiplayerManager.room_closed.connect(_on_room_closed)
	MultiplayerManager.game_started.connect(_on_game_started)

	# Anchor tabanlı offset'ler ilk layout geçişinden sonra kesinleşir; kaymanın
	# doğru hesaplanması için taban X konumunu bir sonraki frame'de yakalıyoruz.
	await get_tree().process_frame
	_center_base_x = center_box.position.x

	_refresh()
	_refresh_settings_display()

func _refresh() -> void:
	for child in player_list_box.get_children():
		child.queue_free()

	var am_owner := MultiplayerManager.is_local_owner()
	var local_id := multiplayer.get_unique_id()

	for peer_id in MultiplayerManager.players.keys():
		var pdata: Dictionary = MultiplayerManager.players[peer_id]
		var row := HBoxContainer.new()

		var label := Label.new()
		var suffix := ""
		if peer_id == MultiplayerManager.owner_id:
			suffix += "  (Sahip)"
		if peer_id == local_id:
			suffix += "  (Sen)"
		label.text = "%s%s" % [pdata.get("name", "?"), suffix]
		label.custom_minimum_size = Vector2(220, 0)
		row.add_child(label)

		if am_owner and peer_id != local_id:
			var transfer_btn := Button.new()
			transfer_btn.text = "Sahipliği Devret"
			transfer_btn.pressed.connect(func(): MultiplayerManager.transfer_ownership(peer_id))
			row.add_child(transfer_btn)

		player_list_box.add_child(row)

	var count := MultiplayerManager.players.size()
	info_label.text = "Oyuncular: %d / %d  (başlamak için en az %d gerekir)" % [
		count, MultiplayerManager.MAX_PLAYERS, MultiplayerManager.MIN_PLAYERS_TO_START
	]

	settings_button.visible = am_owner
	start_button.visible = am_owner
	start_button.disabled = count < MultiplayerManager.MIN_PLAYERS_TO_START

	if not am_owner and _settings_open:
		_close_settings_panel()

	threshold_slider.editable = am_owner
	party_duration_slider.editable = am_owner
	axis_start_slider.editable = am_owner
	axis_increment_slider.editable = am_owner
	axis_max_enabled_check.disabled = not am_owner
	axis_max_value_slider.editable = am_owner
	_refresh_settings_display()

func _refresh_settings_display() -> void:
	var t := MultiplayerManager.election_threshold
	threshold_label.text = "Seçim Barajı: %%%s" % _format_threshold(t)
	threshold_value_label.text = "%%%s" % _format_threshold(t)
	if not threshold_slider.has_focus():
		threshold_slider.value = t

	var duration := MultiplayerManager.party_setup_duration
	party_duration_value_label.text = _format_party_duration(duration)
	if not party_duration_slider.has_focus():
		var idx := MultiplayerManager.PARTY_DURATION_OPTIONS.find(duration)
		party_duration_slider.value = idx if idx != -1 else 0

	axis_start_value_label.text = "%.1f" % MultiplayerManager.axis_sharpness_start
	if not axis_start_slider.has_focus():
		axis_start_slider.value = MultiplayerManager.axis_sharpness_start

	axis_increment_value_label.text = "%.1f" % MultiplayerManager.axis_sharpness_increment
	if not axis_increment_slider.has_focus():
		axis_increment_slider.value = MultiplayerManager.axis_sharpness_increment

	axis_max_enabled_check.button_pressed = MultiplayerManager.axis_sharpness_max_enabled
	axis_max_value_row.visible = MultiplayerManager.axis_sharpness_max_enabled
	axis_max_value_value_label.text = "%.0f" % MultiplayerManager.axis_sharpness_max_value
	if not axis_max_value_slider.has_focus():
		var cap_idx := MultiplayerManager.AXIS_SHARPNESS_CAP_OPTIONS.find(MultiplayerManager.axis_sharpness_max_value)
		axis_max_value_slider.value = cap_idx if cap_idx != -1 else 0

func _format_party_duration(seconds: int) -> String:
	if seconds == MultiplayerManager.PARTY_DURATION_UNLIMITED:
		return "Sınırsız"
	return "%d sn" % seconds

func _format_threshold(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value

func _on_threshold_slider_changed(value: float) -> void:
	MultiplayerManager.set_election_threshold(value)

func _on_party_duration_slider_changed(index: float) -> void:
	var seconds: int = MultiplayerManager.PARTY_DURATION_OPTIONS[int(index)]
	MultiplayerManager.set_party_setup_duration(seconds)

func _on_axis_start_slider_changed(value: float) -> void:
	MultiplayerManager.set_axis_sharpness_start(value)

func _on_axis_increment_slider_changed(value: float) -> void:
	MultiplayerManager.set_axis_sharpness_increment(value)

func _on_axis_max_enabled_toggled(enabled: bool) -> void:
	axis_max_value_row.visible = enabled
	MultiplayerManager.set_axis_sharpness_max_enabled(enabled)

func _on_axis_max_value_slider_changed(index: float) -> void:
	var value: float = MultiplayerManager.AXIS_SHARPNESS_CAP_OPTIONS[int(index)]
	MultiplayerManager.set_axis_sharpness_max_value(value)

func _refresh_code_display() -> void:
	var shown := "•••••" if GameSettings.streamer_mode else MultiplayerManager.room_code
	code_label.text = "ODA KODU: %s" % shown

func _on_streamer_mode_changed(_enabled: bool) -> void:
	_refresh_code_display()

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(MultiplayerManager.room_code)
	copy_code_button.text = "Kopyalandı!"
	await get_tree().create_timer(1.0).timeout
	copy_code_button.text = "📋 Kopyala"

## Lobi ayarları butonu: panel kapalıysa ekranın sağında açar ve ortadaki
## içeriği hafifçe sola kaydırır; açıksa tersini yapıp kapatır.
func _on_settings_pressed() -> void:
	if _settings_open:
		_close_settings_panel()
	else:
		_open_settings_panel()

func _open_settings_panel() -> void:
	_settings_open = true
	settings_side_panel.show()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(center_box, "position:x", _center_base_x - SETTINGS_SHIFT, SLIDE_DURATION)

func _close_settings_panel() -> void:
	_settings_open = false
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(center_box, "position:x", _center_base_x, SLIDE_DURATION)
	tween.finished.connect(func(): settings_side_panel.hide())

func _on_start_pressed() -> void:
	MultiplayerManager.start_game()

func _on_game_started() -> void:
	SceneTransition.fade_to_scene("res://scenes/PartySetup.tscn")

func _on_leave_pressed() -> void:
	MultiplayerManager.leave_room()
	get_tree().change_scene_to_file("res://scenes/RoomSetup.tscn")

func _on_room_closed(reason: String) -> void:
	info_label.text = reason
	get_tree().change_scene_to_file("res://scenes/RoomSetup.tscn")
