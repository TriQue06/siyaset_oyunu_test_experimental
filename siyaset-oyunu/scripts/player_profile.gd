extends Node
## Autoload. Oyuncunun görünen adını tutar (oyunun ilk ana ekranında girilir)
## ve sonraki açılışlarda hatırlanması için user:// içine kaydeder.
##
## Aynı isimle birden çok oyuncu oyuna girebilir — bu bir sorun değildir,
## kimlik her zaman ağ peer id'siyle ayrışır (bkz. MultiplayerManager.players).

const CONFIG_PATH := "user://profile.cfg"

var player_name: String = "":
	set(value):
		player_name = value
		_save()

func _ready() -> void:
	_load()
	if player_name == "":
		player_name = "Oyuncu%d" % randi_range(1000, 9999)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		player_name = config.get_value("profile", "player_name", "")

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "player_name", player_name)
	config.save(CONFIG_PATH)
