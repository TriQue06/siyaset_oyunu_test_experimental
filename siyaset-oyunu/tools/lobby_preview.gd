extends SceneTree
## Oda lobisi önizlemesi: sahip + 2 bot + botlardan SONRA katılan bir insan.
## İnsanların botların önüne dizildiğini, 8 kartı ve sadece ilk boş kartın
## robot butonunun etkin olduğunu kontrol eder; ekran görüntüsü alır.
##   godot --resolution 1600x900 --script res://tools/lobby_preview.gd

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var me: int = root.multiplayer.get_unique_id()
	mm.room_code = "ABCDE"
	mm.is_host = true
	mm.owner_id = me
	mm.stage = mm.Stage.LOBBY
	mm.players = {me: {"name": "Barış"}}
	# add_bot RPC'siz yerel yol için room_code geçici olarak boş.
	mm.room_code = ""
	mm.add_bot()
	mm.add_bot()
	mm.room_code = "ABCDE"
	mm.players[77] = {"name": "Ayşe"}  # botlardan sonra katılan insan
	check("insanlar once, botlar sonra", mm.lobby_order()[1] == 77 and mm.is_bot(mm.lobby_order()[2]), str(mm.lobby_order()))

	var scene: Node = (load("res://scenes/RoomLobby.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 10:
		await process_frame
	var grid: GridContainer = scene.player_list_box
	check("8 kart, 2 sutun", grid.get_child_count() == 8 and grid.columns == 2, str(grid.get_child_count()))
	var enabled := 0
	var disabled := 0
	for slot in grid.get_children():
		for child in slot.get_children():
			if child is Button:
				if child.disabled:
					disabled += 1
				else:
					enabled += 1
	check("sadece ilk bos kartta etkin robot butonu", enabled == 1 and disabled == 3, "etkin %d, pasif %d" % [enabled, disabled])
	var start: Button = scene.start_button
	var bottom: float = start.get_global_rect().end.y
	check("baslat butonu ekranda", start.visible and bottom <= root.get_visible_rect().size.y, "alt kenar %.0f / %.0f" % [bottom, root.get_visible_rect().size.y])

	# Lobi ayarları: oyun süresi (4 turda bir, 7 seçim) ve artırma.
	check("varsayilan: 4 yilda bir, 8 secim, 64 tur (32 yil)", mm.election_interval == 4 and mm.election_count == 8 and GameRules.MAX_ROUNDS == 64)
	scene._on_settings_pressed()
	for i in 20:
		await process_frame
	scene.count_plus.pressed.emit()
	await process_frame
	check("secim sayisi +1 -> 9 secim, 72 tur", mm.election_count == 9 and GameRules.MAX_ROUNDS == 72 and GameRules.is_election_round(72))
	check("ozet yaziyor", String(scene.game_length_summary.text).find("36") != -1, scene.game_length_summary.text)
	root.get_texture().get_image().save_png("%s/lobby_settings.png" % OS.get_user_data_dir())
	scene.count_minus.pressed.emit()
	# Doldur: 8 kart dolunca buton kalmamalı; başlat yine ekranda.
	mm.room_code = ""
	for i in 6:
		mm.add_bot()
	mm.room_code = "ABCDE"
	scene._refresh()
	for i in 5:
		await process_frame
	check("oda dolu (8)", mm.players.size() == 8)
	check("dolu odada baslat butonu yine ekranda", start.get_global_rect().end.y <= root.get_visible_rect().size.y)
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/lobby_full.png" % OS.get_user_data_dir())
	mm.room_code = ""
	mm.remove_bot(mm.bot_ids().back())
	mm.remove_bot(mm.bot_ids().back())
	mm.room_code = "ABCDE"
	scene._refresh()
	for i in 5:
		await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/lobby_partial.png" % OS.get_user_data_dir())
	print("=== LOBBY PREVIEW: %s ===" % ("PASS" if fails == 0 else "%d HATA" % fails))
	quit()
