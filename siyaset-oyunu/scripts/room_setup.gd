extends Control
## Oyuncu adı artık ana menüde (Lobby.tscn) bir kere girilir ve
## PlayerProfile'da tutulur; burada tekrar sorulmaz.
##
## Bağlantı, internete açık bir röle sunucusu üzerinden kurulur (bkz.
## multiplayer_manager.gd, RELAY_URL). Oyuncular hiçbir IP/port bilgisi
## girmez; sadece oda kurulunca üretilen 5 haneli kod yeterlidir.

@onready var create_button: Button = %CreateButton
@onready var code_edit: LineEdit = %CodeEdit
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var back_button: Button = %BackButton

func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	code_edit.text_changed.connect(_on_code_text_changed)
	code_edit.secret_character = "•"
	code_edit.secret = GameSettings.streamer_mode
	GameSettings.streamer_mode_changed.connect(_on_streamer_mode_changed)
	MultiplayerManager.room_created.connect(_on_room_created)
	MultiplayerManager.connection_error.connect(_on_connection_error)
	MultiplayerManager.join_failed.connect(_on_join_failed)
	MultiplayerManager.join_succeeded.connect(_on_join_succeeded)
	MultiplayerManager.connection_status.connect(_on_connection_status)
	gui_input.connect(_on_background_gui_input)
	# Oda (oyun ortasında bile) kapandıysa buraya sebebiyle birlikte dönülür.
	if MultiplayerManager.last_close_reason != "":
		status_label.text = MultiplayerManager.last_close_reason
		MultiplayerManager.last_close_reason = ""

func _on_connection_status(text: String) -> void:
	status_label.text = text

## Yayıncı modu açıkken kod kutusu, elle yazılsa da yapıştırılsa da
## noktalarla gizlenir (LineEdit.secret zaten girişin kaynağına bakmaz,
## sadece görüntüyü maskeler).
func _on_streamer_mode_changed(enabled: bool) -> void:
	code_edit.secret = enabled

## Boş bir yere tıklanınca yazı imleci kod kutusunda takılı kalmasın.
func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

func _on_code_text_changed(new_text: String) -> void:
	# Kod sadece büyük İngilizce harflerden oluşur (A-Z), rakam/sembol yok.
	var filtered := ""
	for c in new_text.to_upper():
		if c >= "A" and c <= "Z":
			filtered += c
	if filtered != new_text:
		code_edit.text = filtered
		code_edit.caret_column = filtered.length()

func _on_create_pressed() -> void:
	create_button.disabled = true
	status_label.text = "Oda kuruluyor..."
	MultiplayerManager.create_room(PlayerProfile.player_name)

func _on_room_created(_code: String) -> void:
	get_tree().change_scene_to_file("res://scenes/RoomLobby.tscn")

func _on_connection_error(reason: String) -> void:
	status_label.text = reason
	create_button.disabled = false
	join_button.disabled = false

func _on_join_pressed() -> void:
	var code := code_edit.text.strip_edges()
	if code.length() != 5:
		status_label.text = "Kod 5 haneli olmalı."
		return
	status_label.text = "Bağlanılıyor..."
	join_button.disabled = true
	MultiplayerManager.join_room(code, PlayerProfile.player_name)

func _on_join_failed(reason: String) -> void:
	status_label.text = reason
	join_button.disabled = false

func _on_join_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/RoomLobby.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
