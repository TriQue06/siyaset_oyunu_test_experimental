extends Control

@onready var name_edit: LineEdit = %NameEdit
@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton

func _ready() -> void:
	name_edit.text = PlayerProfile.player_name
	name_edit.text_changed.connect(_on_name_changed)
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	$Background.gui_input.connect(_on_background_gui_input)

## Boş bir yere (kutunun dışına) tıklanınca yazı imleci kutuda takılı kalmasın.
func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

func _on_name_changed(new_text: String) -> void:
	var trimmed := new_text.strip_edges()
	if trimmed != "":
		PlayerProfile.player_name = trimmed

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/RoomSetup.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
