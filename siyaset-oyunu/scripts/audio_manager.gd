extends Node
## Autoload. Oyundaki TÜM ses tek yerden çalar.
##
## KURGU
##   - Ses yolları (bus): Master > Muzik + Efekt. Ses seviyeleri GameSettings'te
##     saklanır (user://settings.cfg), burada bus'lara uygulanır.
##   - Efektler bir OYNATICI HAVUZUNDAN çalar: her seste yeni node yaratmak
##     (özellikle Android'de) takılmaya yol açıyor. Havuz sırayla kullanılır.
##   - Aynı ses REPEAT_GUARD saniye içinde ikinci kez çalmaz: botlar arka arkaya
##     hamle yaptığında sesler üst üste binmesin.
##
## BUTON SESİ EVRENSELDİR: tek tek butonlara bağlanmaz. Sahneye giren her Button
## otomatik yakalanır (bkz. _on_node_added), böylece sonradan eklenen butonlar
## da kendiliğinden seslenir.

const BUS_MUSIC := "Muzik"
const BUS_SFX := "Efekt"

## Ses adı -> dosya. Yeni ses eklemek için buraya bir satır yeter.
const SOUNDS := {
	"ui_click": "res://assets/audio/ui/ui_click.ogg",
	## Sıra sana geldiğinde çalar (tabletten oynarken dikkat çeksin diye cıngıl).
	"turn_start": "res://assets/audio/ui/turn_start.ogg",
	## Gensoru oylaması açıldı — herkes duyar.
	"censure_open": "res://assets/audio/ui/censure_open.ogg",
	## Verilen oylar (açık oylama: her oy herkeste seslenir).
	"vote_yes": "res://assets/audio/ui/vote_yes.ogg",
	"vote_no": "res://assets/audio/ui/vote_no.ogg",
	"vote_abstain": "res://assets/audio/ui/vote_abstain.ogg",
	## Yasa sonucu.
	"law_passed": "res://assets/audio/ui/law_passed.ogg",
	"law_rejected": "res://assets/audio/ui/law_rejected.ogg",
	## Kartlar: oynanan kartı herkes duyar, çekme sesi sadece çekene çalar.
	"card_played": "res://assets/audio/ui/card_played.ogg",
	"card_drawn": "res://assets/audio/ui/card_drawn.ogg",
}

const POOL_SIZE := 8
const REPEAT_GUARD := 0.05

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_played: Dictionary = {}
## Hangi oylamayı ve hangi oyları seslendirdik (tekrar çalmamak için).
var _proposal_key := ""
var _heard_votes: Dictionary = {}

func _ready() -> void:
	# Menü/duraklama sırasında da ses çalsın.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_streams()
	_build_pool()
	apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	# Diğer autoload'lar bu node'dan SONRA hazırlanıyor; sinyallere bir kare
	# sonra bağlanıyoruz.
	_connect_game_signals.call_deferred()
	# Autoload sırası yüzünden zaten sahnede olan butonlar varsa onları da bağla.
	_hook_existing(get_tree().root)

## OYUN OLAYLARI: sesi tek tek ekran kodlarına serpiştirmek yerine merkezi
## sinyallere bağlıyoruz. Böylece host ve istemci aynı anda aynı sesi duyar.
func _connect_game_signals() -> void:
	CardManager.card_played.connect(func(_peer_id: int, _card: String): play("card_played"))
	CardManager.card_drawn.connect(_on_card_drawn)
	GovernmentManager.proposal_changed.connect(_on_proposal_changed)
	GovernmentManager.proposal_resolved.connect(_on_proposal_resolved)

func _on_card_drawn(peer_id: int, _card_type: String) -> void:
	# Kart çekme sesi sadece çeken oyuncuya.
	if peer_id == multiplayer.get_unique_id():
		play("card_drawn")

## Yeni bir oylama açıldığında ve her yeni oy geldiğinde çalar. Oylar durum
## senkronuyla geldiği için istemcide de aynı yerden yakalanır.
func _on_proposal_changed() -> void:
	var key := "%s:%d:%d" % [GovernmentManager.proposal_kind, GovernmentManager.proposal_peer_id,
		GovernmentManager.phase]
	if key != _proposal_key:
		_proposal_key = key
		_heard_votes.clear()
		if GovernmentManager.phase == GovernmentManager.Phase.VOTING 				and GovernmentManager.proposal_kind == GovernmentManager.KIND_CENSURE:
			play("censure_open")
	for voter in GovernmentManager.votes:
		var id := int(voter)
		if _heard_votes.has(id):
			continue
		_heard_votes[id] = true
		match int(GovernmentManager.votes[voter]):
			GovernmentManager.VOTE_YES: play("vote_yes")
			GovernmentManager.VOTE_NO: play("vote_no")
			_: play("vote_abstain")

func _on_proposal_resolved(accepted: bool, kind: String, _proposer_id: int) -> void:
	if kind == GovernmentManager.KIND_LAW:
		play("law_passed" if accepted else "law_rejected")

## Bir ses efekti çalar. Bilinmeyen ad sessizce yok sayılır (ses dosyası
## eksikken oyun çalışmaya devam etsin).
func play(sound: String) -> void:
	if not _streams.has(sound) or _players.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -99.0)) < REPEAT_GUARD:
		return
	_last_played[sound] = now
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[sound]
	player.play()

## GameSettings'teki seviyeleri bus'lara uygular.
func apply_volumes() -> void:
	_set_bus_volume("Master", GameSettings.master_volume)
	_set_bus_volume(BUS_MUSIC, GameSettings.music_volume)
	_set_bus_volume(BUS_SFX, GameSettings.sfx_volume)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, linear <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))

## Bus'ları kod içinde kurarız: ayrı bir bus layout dosyası tutmaya gerek yok.
func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")

func _load_streams() -> void:
	for sound in SOUNDS:
		var path: String = SOUNDS[sound]
		if ResourceLoader.exists(path):
			_streams[sound] = load(path)
		else:
			push_warning("Ses dosyası yok: %s" % path)

func _build_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_players.append(player)

func _on_node_added(node: Node) -> void:
	if node is Button:
		_hook_button(node)

func _hook_existing(node: Node) -> void:
	if node is Button:
		_hook_button(node)
	for child in node.get_children():
		_hook_existing(child)

## Butonun kendi sinyaline bağlanır. İki kez bağlanmaz; ses istemeyen bir buton
## olursa node'a "sessiz" meta'sı konarak muaf tutulabilir.
func _hook_button(button: Button) -> void:
	if bool(button.get_meta("sessiz", false)):
		return
	if button.pressed.is_connected(_on_button_pressed):
		return
	button.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	play("ui_click")
