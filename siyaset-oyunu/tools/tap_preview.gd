extends SceneTree
## Dokunma (hover'sız) akışını oyun ekranında adım adım dener, kontrol eder ve
## ekran görüntüsü alır:
##   karta dokun (seç) -> ile dokun (ayrıntı) -> aynı ile dokun (oyna),
##   seçili karta tekrar dokun (iptal), parti kartına dokun (profil aç/kapa).
##   godot --resolution 1600x900 --script res://tools/tap_preview.gd

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), file_name])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	root.get_node("BotManager").set_process(false)
	mm.room_code = ""
	mm.players = {}
	pm.parties = {}
	var me: int = root.multiplayer.get_unique_id()
	var ids: Array = [me, 2, 3]
	var names := ["Yeni Yol", "Halkçı", "Millet"]
	var colors := ["F20C1F", "1C48C9", "F2920C"]
	for i in 3:
		mm.players[ids[i]] = {"name": "Oyuncu %d" % i, "bot": i > 0}
		pm.parties[ids[i]] = {"name": names[i], "icon_index": i * 5, "icon_color": Color.WHITE,
			"bg_color": Color(colors[i]), "ideology": {"economic": 0, "social": 0, "administrative": 0}, "ready": true}
	cm.set_rng_seed(11)
	cm.init_game()
	cm.turn_order = ids.duplicate()
	cm.current_turn_index = 0
	cm.inventories[me] = ["karalama", "karalama", "karalama"]
	cm.mana[me] = 20
	cm._push_state({"type": "full"}, true)

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(20)

	scene._on_hand_card_clicked(0)
	await _frames(15)
	check("karta dokununca secildi ve il secme basladi", scene._selected_hand_index == 0 and scene._pending_province_hand_index == 0)
	check("kart aciklamasi gorunuyor", scene._card_info.visible)
	_shot("tap_card_selected")

	scene._on_province_clicked("ankara")
	await _frames(5)
	check("ile ilk dokunus: sadece secildi, kart oynanmadi", scene._selected_province == "ankara" and cm.inventories[me].size() == 3)
	check("ust yazida il ayrintisi var", String(scene._target_hint.text).find("Ankara") != -1, String(scene._target_hint.text))
	_shot("tap_province_selected")

	scene._on_province_clicked("ankara")
	await _frames(10)
	check("ayni ile ikinci dokunus: karalama hedef menusu acildi", scene._propaganda_menu.visible)
	scene._propaganda_menu.hide()

	cm.current_turn_index = 0
	cm._push_state({"type": "timer"})
	await _frames(10)
	scene._on_hand_card_clicked(0)
	await _frames(5)
	scene._on_hand_card_clicked(0)
	await _frames(5)
	check("secili karta tekrar dokunmak iptal eder", scene._selected_hand_index == -1 and scene._pending_province_hand_index == -1 and not scene._card_info.visible)

	scene._on_target_party_clicked(2)
	await _frames(10)
	check("parti kartina dokununca profil acildi", scene._profile_peer_id == 2 and scene.hover_tooltip.visible)
	_shot("tap_profile")
	scene._on_target_party_clicked(2)
	await _frames(3)
	check("ayni parti kartina tekrar dokununca profil kapandi", scene._profile_peer_id == -1 and not scene.hover_tooltip.visible)

	print("=== TAP PREVIEW: %s ===" % ("PASS" if fails == 0 else "%d HATA" % fails))
	quit()
