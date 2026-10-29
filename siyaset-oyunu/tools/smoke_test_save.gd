extends SceneTree
## YEREL KAYIT / YÜKLEME testi: botlu bir çevrim dışı oyun birkaç tur oynanır,
## kaydedilir, ilerletilir, kayıt yüklenir; durum kayıttakiyle birebir aynı
## olmalı ve oyun yüklendikten sonra hatasız devam etmeli. Bozuk, daha yeni
## biçimli ve çevrim içi durumdaki kayıt denemeleri anlaşılır hatayla reddedilir.
##   godot --headless --script res://tools/smoke_test_save.gd

var mm
var pm
var cm
var gm
var bm
var brain
var save_game
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _play(rounds: int) -> void:
	var target: int = cm.round_number + rounds
	var steps := 0
	var turn_actions := 0
	var last_bot := -1
	while steps < 3000 and not cm.game_finished and cm.round_number < target:
		steps += 1
		if cm.congress_active:
			cm.tick(30.0)
			continue
		if gm.phase == gm.Phase.VOTING:
			for bot in gm.eligible_voter_ids():
				if not gm.has_voted(bot):
					gm._apply_vote(bot, brain.choose_vote(bot))
					break
			continue
		if gm.phase == gm.Phase.FORMING:
			var holder: int = gm.mandate_peer_id()
			gm._apply_government_proposal(holder, brain.build_government(holder))
			if gm.phase == gm.Phase.FORMING:
				gm.tick(GameRules.FORMATION_TIMEOUT + 100.0)
			continue
		var bot: int = cm.current_turn_peer_id()
		if bot != last_bot:
			last_bot = bot
			turn_actions = 0
		var done: Dictionary = bm.do_action(bot) if turn_actions < 12 else {}
		turn_actions += 1
		if done.is_empty():
			cm._apply_pass(bot, true)
			turn_actions = 0

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	bm = root.get_node("BotManager")
	bm.set_process(false)
	brain = load("res://scripts/bot_brain.gd")
	save_game = load("res://scripts/save_game.gd")
	cm.allow_temporary_parties = false
	cm.set_rng_seed(424242)
	seed(424242)
	gm.result_hold_seconds = 0.0

	print("=== 1) ÇEVRİM İÇİ / OYUN DIŞI KAYIT ENGELİ ===")
	mm.offline_mode = false
	check("çevrim içi oyunda kayıt yapılmaz", save_game.save("test") != "")

	print("=== 2) KAYDET, İLERLET, YÜKLE ===")
	mm.start_offline("Test")
	mm.players = {}
	pm.parties = {}
	mm.stage = mm.Stage.PARTY_SETUP
	root.get_node("GameMap").generate_new(1950)
	mm.game_map_seed = 1950
	cm._load_province_seat_counts()
	for i in 6:
		var id: int = mm.BOT_ID_BASE - i
		mm.players[id] = {"name": "Bot %d" % i, "bot": true}
		pm.add_bot_party(id)
		var politician: Dictionary = pm.politicians[id].duplicate(true)
		var look := AvatarCatalog.clean({}, String(politician.gender))
		look.hair = AvatarCatalog.options("hair", String(politician.gender))[0]
		politician["appearance"] = look
		pm.set_politician_host(id, politician)
	cm.init_game()
	mm.stage = mm.Stage.IN_GAME
	_play(6)
	check("oyun ilerledi", cm.round_number >= 6, "tur %d" % cm.round_number)
	var err: String = save_game.save("test")
	check("kayıt yazıldı", err == "" and save_game.exists("test"), err)
	check("geçici dosya kalmadı", not FileAccess.file_exists(save_game.path_of("test") + ".tmp"))
	var before: Dictionary = cm._pack_state(true).duplicate(true)
	var gm_before: Dictionary = gm._pack_state().duplicate(true)
	var parties_before: Dictionary = pm.parties.duplicate(true)
	var politicians_before: Dictionary = pm.politicians.duplicate(true)
	var turmoil_before: Dictionary = cm.turmoil.duplicate(true)
	var rng_before: int = cm._rng.state
	_play(4)
	check("kayıttan sonra oyun değişti", cm.round_number != int(before["round"]))
	var data: Dictionary = save_game._read("test")
	check("kayıt okunuyor ve doğrulanıyor", not data.has("error"), str(data.get("error", "")))
	save_game.apply(data)
	var after: Dictionary = cm._pack_state(true)
	var same := true
	var diff_keys := []
	for key in before.keys():
		if key == "version" or key == "turn_time_left":
			continue
		if str(before[key]) != str(after.get(key)):
			same = false
			diff_keys.append(key)
	check("CardManager durumu birebir geri geldi", same, str(diff_keys))
	var gm_after: Dictionary = gm._pack_state()
	var gm_same := true
	for key in gm_before.keys():
		if key in ["version", "phase_time_left"]:
			continue
		if str(gm_before[key]) != str(gm_after.get(key)):
			gm_same = false
	check("hükümet durumu ve puanlar geri geldi", gm_same)
	check("partiler (seçmen grupları dahil) geri geldi", str(parties_before) == str(pm.parties))
	check("siyasetçi avatar seçimleri geri geldi", politicians_before == pm.politicians)
	check("parti içi karışıklık geri geldi", str(turmoil_before) == str(cm.turmoil))
	check("rastgele sayı üreteci durumu geri geldi", cm._rng.state == rng_before)
	check("aşama oyun içi, çevrim dışı", mm.stage == mm.Stage.IN_GAME and mm.offline_mode)
	var round_loaded: int = cm.round_number
	_play(6)
	check("yüklenen oyun hatasız devam ediyor", cm.round_number > round_loaded or cm.game_finished, "tur %d" % cm.round_number)

	print("=== 3) BOZUK VE YENİ BİÇİMLİ KAYIT ===")
	var f := FileAccess.open(save_game.path_of("bozuk"), FileAccess.WRITE)
	f.store_string("bu bir kayıt değil")
	f.close()
	var round_now: int = cm.round_number
	var bad: Dictionary = save_game._read("bozuk")
	check("bozuk kayıt anlaşılır hatayla reddedilir", bad.has("error"), str(bad.get("error", "")))
	check("hata durumunda oyun durumu bozulmaz", cm.round_number == round_now)
	var newer: Dictionary = save_game._collect()
	newer["format"] = save_game.FORMAT_VERSION + 1
	f = FileAccess.open(save_game.path_of("yeni"), FileAccess.WRITE)
	f.store_var(newer, false)
	f.close()
	check("daha yeni biçimli kayıt reddedilir", save_game._read("yeni").has("error"))
	var partial: Dictionary = save_game._collect()
	partial.erase("gm")
	f = FileAccess.open(save_game.path_of("eksik"), FileAccess.WRITE)
	f.store_var(partial, false)
	f.close()
	check("eksik alanlı kayıt reddedilir", save_game._read("eksik").has("error"))
	var unsupported: Dictionary = save_game._collect()
	unsupported["cm"]["map"] = {"kind": "obsolete"}
	f = FileAccess.open(save_game.path_of("harita"), FileAccess.WRITE)
	f.store_var(unsupported, false)
	f.close()
	check("desteklenmeyen haritalı kayıt reddedilir", save_game._read("harita").has("error"))
	check("geçersiz harita mevcut oyunu değiştirmez", cm.round_number == round_now and not root.get_node("GameMap").country.is_empty())
	check("kayıt yoksa anlaşılır hata", save_game._read("olmayan").has("error"))
	check("kayıt özeti okunuyor", not save_game.summary("test").is_empty())
	for slot in ["test", "bozuk", "yeni", "eksik", "harita"]:
		DirAccess.remove_absolute(save_game.path_of(slot))

	print("")
	print("=== TUM TESTLER GECTI ===" if fails == 0 else "=== %d TEST BASARISIZ ===" % fails)
	quit(1 if fails > 0 else 0)
