class_name LobbyPreset
extends RefCounted
## AYAR PAKETİ — ALTYAPI (oyunda henüz arayüzü yok, oyuncuya gösterilmez).
## Lobinin bütün kurallarını tek bir JSON'a yazılabilir sözlükte toplar.
## Oda sahibi uygular (apply); değerler mevcut ayar fonksiyonlarıyla, yani
## mevcut RPC'lerle herkese yayılır: kimse dosya indirmez, mod gerekmez.
## Dosya içeren içerik (logo, portre, harita) ayar paketine GİRMEZ; o
## ContentPacks modlarının işidir. Paket bir mod içeriğine atıf yapıyorsa
## (ör. "requires": ["harita_paketi"]) uygulamadan önce requires_met bakılır.
## Biçim:
##   {"format": FORMAT, "title": "...", "requires": [mod id],
##    "lobby": {threshold, interval, count, vote_seconds, map_seed,
##              random_parties, away_mode, bot_funds_penalty, world: {...}}}
## Bilinmeyen ya da geçersiz alanlar sessizce atlanır (eski/yeni sürüm uyumu).

const FORMAT := 1

## Şu anki lobi ayarlarının paketi.
static func capture(title: String = "") -> Dictionary:
	var mm := MultiplayerManager
	return {"format": FORMAT, "title": title, "requires": [],
		"lobby": {"threshold": mm.election_threshold, "interval": mm.election_interval,
			"count": mm.election_count, "vote_seconds": mm.vote_timeout, "map_seed": mm.map_seed,
			"random_parties": mm.random_parties, "away_mode": mm.away_mode,
			"bot_funds_penalty": mm.bot_funds_penalty, "world": mm.world_settings.duplicate()}}

static func to_json(pack: Dictionary) -> String:
	return JSON.stringify(pack, "\t")

## JSON metninden paket; geçersizse {}.
static func from_json(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary or int(parsed.get("format", 0)) < 1 or int(parsed.get("format", 0)) > FORMAT:
		return {}
	return parsed

## Paketin istediği modlar yüklü mü?
static func requires_met(pack: Dictionary) -> bool:
	var loaded := {}
	for mod in ContentPacks.active_mods():
		loaded[mod["id"]] = true
	for id in pack.get("requires", []):
		if not loaded.has(String(id)):
			return false
	return true

## Oda sahibi: paketi lobiye uygular. Her değer kendi ayar fonksiyonundan
## geçer (doğrulama + yayın orada). Başarılıysa true.
static func apply(pack: Dictionary) -> bool:
	var mm := MultiplayerManager
	if pack.is_empty() or not mm.is_local_owner() or not requires_met(pack):
		return false
	var lobby: Dictionary = pack.get("lobby", {})
	var world: Dictionary = lobby.get("world", {})
	# Yalnız güncel dünya ayarları uygulanır; bilinmeyen anahtarlar yok sayılır.
	for key in world.keys():
		mm.set_world_setting(String(key), _number_like(world[key], mm.WORLD_DEFAULTS.get(key)))
	if lobby.has("threshold"):
		mm.set_election_threshold(float(lobby["threshold"]))
	if lobby.has("interval") or lobby.has("count"):
		mm.set_game_length(float(lobby.get("interval", mm.election_interval)), int(lobby.get("count", mm.election_count)))
	if lobby.has("vote_seconds"):
		mm.set_vote_timeout(int(lobby["vote_seconds"]))
	if lobby.has("map_seed"):
		mm.set_map_seed(String(lobby["map_seed"]))
	if lobby.has("random_parties"):
		mm.set_random_parties(bool(lobby["random_parties"]))
	if lobby.has("away_mode"):
		mm.set_away_mode(String(lobby["away_mode"]))
	if lobby.has("bot_funds_penalty"):
		mm.set_bot_funds_penalty(float(lobby["bot_funds_penalty"]))
	return true

## JSON sayıları float gelir; seçenek listesi int ise int'e çevir (300.0 -> 300).
static func _number_like(value: Variant, sample: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and typeof(sample) == TYPE_INT:
		return int(value)
	return value
