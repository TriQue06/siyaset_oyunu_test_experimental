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
## BUTON SESİ EVRENSELDİR: tek tek butonlara bağlanmaz. Sahneye giren her
## BaseButton otomatik yakalanır (bkz. _on_node_added) — Button'ın yanı sıra
## TextureButton (parti ikonları), CheckBox, CheckButton da dahil. Böylece
## sonradan eklenen butonlar da kendiliğinden seslenir.

const BUS_MUSIC := "Muzik"
const BUS_SFX := "Efekt"

## Ses adı -> dosya. Yeni ses eklemek için buraya bir satır yeter.
const SOUNDS := {
	"ui_click": "res://assets/audio/ui/ui_click.ogg",
	## Sıra sana geldiğinde çalar (tabletten oynarken dikkat çeksin diye cıngıl).
	"turn_start": "res://assets/audio/ui/turn_start.ogg",
	## Gensoru oylaması açıldı — herkes duyar.
	"censure_open": "res://assets/audio/ui/censure_open.ogg",
	## Verilen oylar: açık oylama, her oy HERKESTE seslenir.
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

## MÜZİK. Oyuncular Discord'da konuşarak oynadığı için arka plan müziği
## kasıtlı olarak KISIK (gain) çalar. Parçalar dikişsiz döngü için
## hazırlanmadığından döngüyü fade ile kuruyoruz: parça biterken kısılır,
## baştan açılırken yükselir.
const MUSIC := {
	"game": "res://assets/audio/music/game_loop.mp3",
	"election": "res://assets/audio/music/election.mp3",
}
## Parça başına ses kazancı (dB) ve fade süreleri (saniye).
const MUSIC_GAIN := {"game": -10.0, "election": -3.0}
const MUSIC_FADE_IN := {"game": 3.0, "election": 0.35}
const MUSIC_FADE_OUT := {"game": 3.0, "election": 0.4}
## Parçaların ilk saniyesi atlanır (giriş vuruşu/sessizliği istenmiyor).
## Dosyayı kesmiyoruz: çalma bu saniyeden başlıyor, döngüde de öyle.
const MUSIC_START := {"game": 1.0, "election": 1.0}
const MUSIC_SILENT_DB := -60.0

const POOL_SIZE := 8
const REPEAT_GUARD := 0.05

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_played: Dictionary = {}
## Hangi oylamayı ve hangi oyları seslendirdik (tekrar çalmamak için).
var _music_player: AudioStreamPlayer
var _music_streams: Dictionary = {}
var _music_name := ""
## Her müzik başlatmada artar: eski fade zamanlayıcıları kendini iptal etsin.
var _music_generation := 0
var _music_tween: Tween
var _proposal_key := ""
var _heard_votes: Dictionary = {}

func _ready() -> void:
	# Menü/duraklama sırasında da ses çalsın.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_streams()
	_build_pool()
	_build_music()
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

# --- MÜZİK -----------------------------------------------------------------

## Parçayı çalmaya başlar (zaten çalıyorsa bir şey yapmaz). Önceki parça kendi
## fade süresiyle kısılır, yenisi kendi süresiyle açılır.
func play_music(track: String) -> void:
	if _music_name == track:
		return
	if not _music_streams.has(track):
		return
	_music_generation += 1
	if _music_player.playing:
		await _fade_music(MUSIC_SILENT_DB, float(MUSIC_FADE_OUT.get(_music_name, 1.0)))
		_music_player.stop()
	_music_name = track
	_start_music(_music_generation)

## Müziği kısarak durdurur (menüler sessiz).
func stop_music() -> void:
	if _music_name == "":
		return
	_music_generation += 1
	var previous := _music_name
	_music_name = ""
	if _music_player.playing:
		await _fade_music(MUSIC_SILENT_DB, float(MUSIC_FADE_OUT.get(previous, 1.0)))
		_music_player.stop()

func _build_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	_music_player.volume_db = MUSIC_SILENT_DB
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	for track in MUSIC:
		var path: String = MUSIC[track]
		if ResourceLoader.exists(path):
			var stream = load(path)
			# Döngüyü fade ile biz kuruyoruz: motorun kendi döngüsü kapalı olmalı,
			# yoksa "finished" hiç gelmez.
			if "loop" in stream:
				stream.loop = false
			_music_streams[track] = stream
		else:
			push_warning("Müzik dosyası yok: %s" % path)

func _start_music(generation: int) -> void:
	_music_player.stream = _music_streams[_music_name]
	_music_player.volume_db = MUSIC_SILENT_DB
	_music_player.play(float(MUSIC_START.get(_music_name, 0.0)))
	_fade_music(float(MUSIC_GAIN.get(_music_name, -6.0)), float(MUSIC_FADE_IN.get(_music_name, 1.0)))
	_schedule_fade_out(generation)

## Parça bitmeden fade_out kadar önce kısmaya başla.
func _schedule_fade_out(generation: int) -> void:
	var fade_out := float(MUSIC_FADE_OUT.get(_music_name, 1.0))
	var length := _music_player.stream.get_length() - float(MUSIC_START.get(_music_name, 0.0))
	var wait := maxf(0.1, length - fade_out)
	await get_tree().create_timer(wait).timeout
	if generation != _music_generation or not _music_player.playing:
		return
	_fade_music(MUSIC_SILENT_DB, fade_out)

## Parça bitti: aynı parçayı fade ile yeniden başlat (döngü).
func _on_music_finished() -> void:
	if _music_name == "":
		return
	_start_music(_music_generation)

func _fade_music(target_db: float, seconds: float) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", target_db, maxf(0.05, seconds))
	await _music_tween.finished

func _on_card_drawn(peer_id: int, _card_type: String) -> void:
	# Kart çekme sesi sadece çeken oyuncuya.
	if peer_id == multiplayer.get_unique_id():
		play("card_drawn")

## Yeni bir oylama açıldığında ve her yeni oy geldiğinde çalar — kimin oyu
## olursa olsun herkes duyar. Oylar durum senkronuyla geldiği için istemcide de
## aynı yerden yakalanır.
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
	if node is BaseButton:
		_hook_button(node)

func _hook_existing(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node)
	for child in node.get_children():
		_hook_existing(child)

## Butonun kendi sinyaline bağlanır. İki kez bağlanmaz; ses istemeyen bir buton
## olursa node'a "sessiz" meta'sı konarak muaf tutulabilir.
func _hook_button(button: BaseButton) -> void:
	if bool(button.get_meta("sessiz", false)):
		return
	if button.pressed.is_connected(_on_button_pressed):
		return
	button.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	play("ui_click")
