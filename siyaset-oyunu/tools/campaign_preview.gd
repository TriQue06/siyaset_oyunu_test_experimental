extends SceneTree
## Kampanya dönemi (meclis yok) oyun ekranı önizlemesi: nötr partiler, mana,
## hamle butonları, açık yasa tasarlama paneli, gözcü + anket bilgisi ve il
## başkanlıkları. Ekran görüntüleri user:// altına kaydedilir.
##   godot --resolution 1600x900 --script res://tools/campaign_preview.gd

const PARTIES := [
	["Yeni Yol", "Sen", "F20C1F", 0],
	["Halkçı", "Bot Ayşe", "1C48C9", 5],
	["Millet", "Bot Mehmet", "F2920C", 12],
	["Özgürlük", "Bot Deniz", "8C21C2", 20],
	["Yeşiller", "Bot Can", "29A33D", 6],
	["Anadolu", "Bot Elif", "13DBED", 30],
]

func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path := "%s/%s.png" % [OS.get_user_data_dir(), file_name]
	root.get_texture().get_image().save_png(path)
	print("screenshot: ", path)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var cp = root.get_node("CardPresets")
	root.get_node("BotManager").set_process(false)
	mm.room_code = ""
	mm.election_threshold = 7.0
	mm.players = {}
	pm.parties = {}
	var me: int = root.multiplayer.get_unique_id()
	var ids: Array = [me, 2, 3, 4, 5, 6]
	for i in PARTIES.size():
		var p: Array = PARTIES[i]
		mm.players[ids[i]] = {"name": p[1], "bot": i > 0}
		pm.parties[ids[i]] = {
			"name": p[0], "icon_index": p[3], "icon_color": Color.WHITE,
			"bg_color": Color(p[2]), "ideology": {"economic": 0, "social": 0, "administrative": 0}, "ready": true,
		}
	cm.set_rng_seed(2026)
	cm.init_game()
	cm.turn_order = ids.duplicate()
	cm.current_turn_index = 0
	# Biraz geçmiş: rakip il başkanlıkları, bir vaat, benim istihbaratım.
	cm.organizations = {"istanbul": {2: 2, me: 1}, "ankara": {3: 1}, "izmir": {4: 3}}
	cm._add_local("istanbul", me, 3.0)
	cm.mana[me] = 4
	cm.inventories[me] = ["miting", "anket", "gozcu", "karalama"]
	cm._apply_poll(me, "istanbul")
	cm._apply_scout(me, "istanbul")
	cm._push_state({"type": "full"}, true)

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(20)
	_shot("campaign_turn")
	scene._on_law_button_pressed()
	await _frames(10)
	_shot("campaign_law_designer")
	scene._law_designer.hide()
	var pixel_center: Vector2 = scene.map_holder.get_province_centroid("istanbul")
	scene._on_province_clicked("istanbul")
	await _frames(10)
	_shot("campaign_province_panel")
	print("scout istanbul: ", cm.has_scouted(me, "istanbul"), " center ", pixel_center)
	print("=== PREVIEW DONE ===")
	quit()
