class_name SaveGame
extends RefCounted
## YEREL KAYIT / DEVAM: çevrim dışı oyunun tam durumu bu cihaza yazılır ve
## sonra kaldığı yerden yüklenir. Çevrim içi oyunda kullanılmaz (orada durumun
## sahibi host'tur; yerel dosya otoriter durumla karışmasın).
##
## İçerik: CardManager (_pack_state(true) + paketlenmeyen host alanları: parti
## içi karışıklık, rastgele sayı üreteçlerinin durumu, tur sonu bekleyişi ...),
## GovernmentManager, PartyManager (partiler, siyasetçiler), MultiplayerManager
## ayarları (oyuncular, baraj, takvim, sayım, harita tohumu ...), bot becerileri.
## Biçim: Godot'nun tip koruyan ikili Variant'ı (JSON tamsayı anahtarları
## metne çevirdiği için kullanılmaz). Yazma ATOMİKTİR: önce geçici dosyaya
## yazılır, tamamlanınca asıl dosyanın yerine taşınır; yarım kayıt kalmaz.
##
## SÜRÜMLEME: FORMAT_VERSION kayıt biçiminin sürümüdür. Daha yeni biçimli kayıt
## açılmaz (anlaşılır hata); eski biçim gerekiyorsa _migrate'te yükseltilir.

const FORMAT_VERSION := 1
const SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := "autosave"
const MANUAL_SLOT := "kayit"

static func path_of(slot: String) -> String:
	return "%s/%s.save" % [SAVE_DIR, slot]

## Şu an kaydedilebilir mi? ("" = evet, değilse oyuncuya gösterilecek neden.)
static func block_reason() -> String:
	if not MultiplayerManager.offline_mode:
		return L.t("Kayıt sadece çevrim dışı oyunda yapılır.")
	if MultiplayerManager.stage != MultiplayerManager.Stage.IN_GAME:
		return L.t("Oyun başlamadan kayıt yapılamaz.")
	if CardManager.game_finished:
		return L.t("Oyun bitti.")
	return ""

static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_of(slot))

## Kayıt özeti (menüde göstermek için): {"version", "saved_at", "period", "party"} ya da {}.
static func summary(slot: String) -> Dictionary:
	var data := _read(slot)
	if data.is_empty() or data.has("error"):
		return {}
	return data.get("summary", {})

## Oyunu kaydeder. Dönüş: "" başarı, değilse hata metni.
static func save(slot: String = MANUAL_SLOT) -> String:
	var reason := block_reason()
	if reason != "":
		return reason
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := _collect()
	var tmp := path_of(slot) + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return L.t("Kayıt dosyası açılamadı (%s).") % error_string(FileAccess.get_open_error())
	file.store_var(data, false)
	file.close()
	var final_path := path_of(slot)
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var err := DirAccess.rename_absolute(tmp, final_path)
	if err != OK:
		return L.t("Kayıt tamamlanamadı (%s).") % error_string(err)
	return ""

static func _collect() -> Dictionary:
	var mm := MultiplayerManager
	var cm := CardManager
	var me := mm.owner_id
	return {
		"format": FORMAT_VERSION,
		"game_version": MultiplayerManager.game_version(),
		"summary": {
			"saved_at": Time.get_datetime_string_from_system(false, true),
			"period": GameRules.period_label(cm.round_number),
			"party": String(PartyManager.data_of(me).get("name", "")),
			"version": MultiplayerManager.game_version(),
		},
		"mm": {
			"players": mm.players, "owner_id": me, "local_player_name": mm.local_player_name,
			"election_threshold": mm.election_threshold, "election_interval": mm.election_interval,
			"world_settings": mm.world_settings, "vote_timeout": mm.vote_timeout, "election_count": mm.election_count, "map_seed": mm.map_seed, "game_map_seed": mm.game_map_seed,
			"random_parties": mm.random_parties, "away_mode": mm.away_mode,
			"bot_funds_penalty": mm.bot_funds_penalty, "seat_method": mm.seat_method,
		},
		"rules": {"election_anchor": GameRules.ELECTION_ANCHOR},
		"pm": {"parties": PartyManager.parties, "politicians": PartyManager.politicians,
			"my_politician": PartyManager.my_politician},
		"cm": cm._pack_state(true),
		"cm_host": {
			"secret_news": cm._secret_news,
			"turmoil": cm.turmoil, "final_election_pending": cm.final_election_pending,
			"round_end_pending": cm._round_end_pending, "last_agenda_pair": cm._last_agenda_pair,
			"rng_state": cm._rng.state, "rng_seed": cm._rng.seed,
			"crisis_rng_state": cm._crisis_rng.state, "crisis_rng_seed": cm._crisis_rng.seed,
			"congress_time_left": cm._congress_time_left,
			"allow_temporary_parties": cm.allow_temporary_parties, "event_log": cm.event_log,
		},
		"gm": GovernmentManager._pack_state(),
		"gm_host": {"formed_round": GovernmentManager.formed_round, "censure_round": GovernmentManager.censure_round,
			"resolve_left": GovernmentManager._resolve_left},
		"bots": {"skills": BotBrain._skills},
	}

## Dosyayı okur ve doğrular. Dönüş: veri ya da {"error": metin}.
static func _read(slot: String) -> Dictionary:
	if not exists(slot):
		return {"error": L.t("Kayıt bulunamadı.")}
	var file := FileAccess.open(path_of(slot), FileAccess.READ)
	if file == null:
		return {"error": L.t("Kayıt açılamadı (%s).") % error_string(FileAccess.get_open_error())}
	var data: Variant = file.get_var(false)
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": L.t("Kayıt dosyası bozuk.")}
	var dict: Dictionary = data
	var format := int(dict.get("format", 0))
	if format > FORMAT_VERSION:
		return {"error": L.t("Bu kayıt oyunun daha yeni bir sürümüyle yapılmış.")}
	dict = _migrate(dict, format)
	for key in ["mm", "pm", "cm", "cm_host", "gm"]:
		if typeof(dict.get(key)) != TYPE_DICTIONARY:
			return {"error": L.t("Kayıt dosyası eksik ya da bozuk (%s).") % key}
	for key in ["turn_order", "inventories", "funds", "round", "map"]:
		if not (dict["cm"] as Dictionary).has(key):
			return {"error": L.t("Kayıt dosyası eksik ya da bozuk (%s).") % key}
	if not GameMap.supports_data(dict["cm"]["map"]):
		return {"error": L.t("Bu kaydın harita biçimi artık desteklenmiyor. Yeni bir oyun başlatın.")}
	return dict

## Eski biçimleri bugünkü biçime yükseltir (şimdilik tek biçim var).
static func _migrate(data: Dictionary, _from: int) -> Dictionary:
	return data

## Kaydı yükler ve oyun ekranına geçer. Dönüş: "" başarı, değilse hata metni.
## Hata durumunda mevcut oyun durumuna DOKUNULMAZ (önce dosya doğrulanır).
static func load_game(tree: SceneTree, slot: String = MANUAL_SLOT) -> String:
	var data := _read(slot)
	if data.has("error"):
		return String(data["error"])
	apply(data)
	var scene_path := "res://scenes/GameScreen.tscn"
	if ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_LOADED:
		tree.change_scene_to_packed(ResourceLoader.load_threaded_get(scene_path))
	else:
		tree.change_scene_to_file(scene_path)
	return ""

## Doğrulanmış kayıt verisini yöneticilere uygular (sahne değiştirmez; testler
## doğrudan çağırır).
static func apply(data: Dictionary) -> void:
	var mm := MultiplayerManager
	var saved_mm: Dictionary = data["mm"]
	mm.start_offline(String(saved_mm.get("local_player_name", L.t("Oyuncu"))), false)
	mm.players = saved_mm["players"]
	mm.owner_id = int(saved_mm.get("owner_id", mm.owner_id))
	mm.election_threshold = float(saved_mm.get("election_threshold", mm.election_threshold))
	mm.election_interval = GameRules.snap_interval(float(saved_mm.get("election_interval", mm.election_interval)))
	mm._apply_world_settings(saved_mm.get("world_settings", mm.WORLD_DEFAULTS))
	mm.vote_timeout = int(saved_mm.get("vote_timeout", 30))
	mm.election_count = int(saved_mm.get("election_count", mm.election_count))
	mm.map_seed = String(saved_mm.get("map_seed", ""))
	mm.game_map_seed = int(saved_mm.get("game_map_seed", 0))
	mm.random_parties = bool(saved_mm.get("random_parties", true))
	mm.away_mode = String(saved_mm.get("away_mode", mm.away_mode))
	mm.bot_funds_penalty = float(saved_mm.get("bot_funds_penalty", mm.bot_funds_penalty))
	mm.seat_method = String(saved_mm.get("seat_method", mm.seat_method))
	GameRules.configure(mm.election_interval, mm.election_count)
	GameRules.set_election_anchor(int((data.get("rules", {}) as Dictionary).get("election_anchor", 0)))
	mm.stage = mm.Stage.IN_GAME
	var cm_state: Dictionary = data["cm"]
	GameMap.set_data(cm_state["map"])
	CardManager._load_province_seat_counts()
	var pm_state: Dictionary = data["pm"]
	PartyManager.parties = pm_state.get("parties", {})
	PartyManager.politicians = pm_state.get("politicians", {})
	PartyManager.my_politician = pm_state.get("my_politician", {})
	BotBrain._skills = (data.get("bots", {}) as Dictionary).get("skills", {})
	CardManager._apply_state(cm_state)
	var host: Dictionary = data["cm_host"]
	CardManager.turmoil = host.get("turmoil", {})
	CardManager._secret_news = host.get("secret_news", [])
	CardManager.final_election_pending = bool(host.get("final_election_pending", false))
	CardManager._round_end_pending = bool(host.get("round_end_pending", false))
	CardManager._last_agenda_pair = String(host.get("last_agenda_pair", ""))
	CardManager._rng.seed = int(host.get("rng_seed", CardManager._rng.seed))
	CardManager._rng.state = int(host.get("rng_state", CardManager._rng.state))
	CardManager._crisis_rng.seed = int(host.get("crisis_rng_seed", CardManager._crisis_rng.seed))
	CardManager._crisis_rng.state = int(host.get("crisis_rng_state", CardManager._crisis_rng.state))
	CardManager._congress_time_left = float(host.get("congress_time_left", 0.0))
	CardManager.allow_temporary_parties = bool(host.get("allow_temporary_parties", true))
	CardManager.event_log = host.get("event_log", [])
	GovernmentManager._sync_state(data["gm"])
	var gm_host: Dictionary = data.get("gm_host", {})
	GovernmentManager._phase_time_left = float((data["gm"] as Dictionary).get("phase_time_left", 0.0))
	GovernmentManager.formed_round = int(gm_host.get("formed_round", 0))
	GovernmentManager.censure_round = int(gm_host.get("censure_round", 0))
	GovernmentManager._resolve_left = float(gm_host.get("resolve_left", 0.0))
	GovernmentManager._last_blocked = GovernmentManager.phase == GovernmentManager.Phase.FORMING 		or GovernmentManager.phase == GovernmentManager.Phase.VOTING
	PartyManager.broadcast()
	CardManager._push_state({"type": "full"}, true)
