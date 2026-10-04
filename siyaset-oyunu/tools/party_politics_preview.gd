extends SceneTree
## PARTİ SİYASETİ ÖNİZLEMESİ: birleşmiş iki kişilik parti, feshedip bağımsız
## kalmış bir bot, gelen bir başvuru; profil kartındaki parti işlemleri ve
## parti kurma penceresi.
##   godot --resolution 1600x900 --path . --script res://tools/party_politics_preview.gd

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), name])
	print("screenshot: " + name)

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	bm.set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 4:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"),
		{"economic": 1.5, "social": -1.5, "administrative": 1.5}, true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	gm._set_phase(gm.Phase.IDLE)
	var me: int = mm.owner_id
	var bots: Array = mm.bot_ids()
	# Bot 0 benim partime katılsın (birleşme).
	pm.parties[bots[0]]["ideology"] = pm.parties[me]["ideology"].duplicate()
	cm.current_turn_index = cm.turn_order.find(me)
	cm.send_offer(int(bots[0]), "invite")
	# Bot 1 partisini feshetsin (bağımsız kalır).
	cm.current_turn_index = cm.turn_order.find(int(bots[1]))
	cm._apply_dissolve(int(bots[1]))
	# Bot 2'den bana bir başvuru (birleşme önerisi) gelmiş olsun.
	cm.offers.append({"id": 99, "from": int(bots[2]), "to": int(bots[3]), "kind": "apply"})
	cm.current_turn_index = cm.turn_order.find(me)
	cm.mana[me] = 9.0
	cm._push_state({"type": "timer"})
	print("parti: %s, yardımcı %d, bağımsız %s" % [pm.parties[me]["name"], pm.deputy_of(me), str(pm.is_independent(int(bots[1])))])

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(30)
	_shot("party_politics_board")
	# Profilim: parti işlemleri.
	scene._toggle_profile(me)
	await _frames(10)
	_shot("party_politics_profile_me")
	# Bağımsızın profili: davet düğmesi.
	scene._toggle_profile(int(bots[1]))
	await _frames(10)
	_shot("party_politics_profile_independent")
	scene._hide_profile()
	# Gelen teklif şeridi (bana gelsin).
	cm.offers.append({"id": 100, "from": int(bots[1]), "to": me, "kind": "apply"})
	scene._refresh_offer_bar()
	await _frames(5)
	_shot("party_politics_offer")
	# Parti kurma penceresi.
	var dialog: Control = load("res://scripts/found_party_dialog.gd").new()
	scene.add_child(dialog)
	await _frames(10)
	_shot("party_politics_found")
	quit(0)
