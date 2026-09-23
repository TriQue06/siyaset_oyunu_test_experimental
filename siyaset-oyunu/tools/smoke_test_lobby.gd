extends SceneTree
## LOBİ TESTİ: çevrim dışı mod ve ADAPTİF BOT ADLANDIRMA.
##   godot --headless --path . --script res://tools/smoke_test_lobby.gd

var _failed := 0
var mm

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failed += 1
	print("  [%s]  %s%s" % ["OK" if ok else "HATA", label, ("  -> " + detail) if detail != "" else ""])

func bot_names() -> Array:
	var names: Array = []
	for peer_id in mm.players.keys():
		if mm.is_bot(peer_id):
			names.append(String(mm.players[peer_id]["name"]))
	return names

func bot_id_of(name: String) -> int:
	for peer_id in mm.players.keys():
		if mm.is_bot(peer_id) and String(mm.players[peer_id]["name"]) == name:
			return int(peer_id)
	return -1

func _initialize() -> void:
	await process_frame
	mm = root.get_node("MultiplayerManager")

	print("=== 1) CEVRIM DISI MOD ===")
	mm.start_offline("Barış")
	check("cevrim disi bayragi", mm.offline_mode)
	check("oda kodu yok", mm.room_code == "", mm.room_code)
	check("kendisi sahip ve host", mm.is_local_owner() and mm.is_host)
	check("listede sadece oyuncunun kendisi var", mm.players.size() == 1, str(mm.players))
	check("oyuncu adi kaydedildi", String(mm.players[mm.owner_id]["name"]) == "Barış")

	print("")
	print("=== 2) BOT EKLEME ===")
	for i in 5:
		mm.add_bot()
	check("5 bot eklendi", bot_names().size() == 5, str(bot_names()))
	check("adlar 1..5", bot_names() == ["Bot 1", "Bot 2", "Bot 3", "Bot 4", "Bot 5"], str(bot_names()))

	print("")
	print("=== 3) ADAPTIF ADLANDIRMA: ARADAN SILINCE NUMARALAR KAYAR ===")
	var bot3 := bot_id_of("Bot 3")
	var bot4 := bot_id_of("Bot 4")
	var bot5 := bot_id_of("Bot 5")
	mm.remove_bot(bot4)
	mm.remove_bot(bot3)
	check("3 bot kaldi", bot_names().size() == 3, str(bot_names()))
	check("adlar tekrar 1..3", bot_names() == ["Bot 1", "Bot 2", "Bot 3"], str(bot_names()))
	# Kullanıcının asıl şikâyeti: "Bot 5" adı 5 olarak kalıyordu.
	check("eski Bot 5 artik Bot 3", String(mm.players[bot5]["name"]) == "Bot 3",
		String(mm.players[bot5]["name"]))

	print("")
	print("=== 4) YENI BOT BOSLUGU DOLDURUR ===")
	mm.add_bot()
	check("adlar 1..4", bot_names() == ["Bot 1", "Bot 2", "Bot 3", "Bot 4"], str(bot_names()))
	mm.remove_bot(bot_id_of("Bot 1"))
	check("bastan silinince de kayar", bot_names() == ["Bot 1", "Bot 2", "Bot 3"], str(bot_names()))

	print("")
	print("=== 5) OYUN BASLATILABILIR ===")
	while mm.players.size() < mm.MIN_PLAYERS_TO_START:
		mm.add_bot()
	mm.start_game()
	check("cevrim disi oyun basladi", mm.stage == mm.Stage.PARTY_SETUP, str(mm.stage))

	print("")
	print("=== TUM TESTLER GECTI ===" if _failed == 0 else "=== %d TEST BASARISIZ ===" % _failed)
	quit(1 if _failed > 0 else 0)
