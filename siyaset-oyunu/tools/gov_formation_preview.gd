extends SceneTree
## Hükümet kurma ekranı: ortak ekle/çıkar sonrası renkler doğru mu?
## `godot --path . --resolution 1280x720 --script res://tools/gov_formation_preview.gd`

func _initialize() -> void:
	await process_frame
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	mm.room_code = ""
	mm.players = {}
	pm.parties = {}
	var colors := [Color("F2132A"), Color("31C440"), Color("FAD028"), Color("244FB3")]
	var me: int = root.multiplayer.get_unique_id()
	var ids := [me, 2, 3, 4]
	for i in ids.size():
		mm.players[ids[i]] = {"name": "Lider %d" % i, "bot": i != 0}
		pm.parties[ids[i]] = {
			"name": "Parti %d" % i, "icon_index": i, "icon_color": Color.WHITE,
			"bg_color": colors[i], "ideology": {"economic": 0, "social": 0, "administrative": 0}, "ready": true,
		}
	cm.init_game()
	cm.last_seats = {me: 150, 2: 110, 3: 80, 4: 60}
	cm.last_vote_shares = {me: 37.0, 2: 27.0, 3: 20.0, 4: 16.0}
	gm.start_formation()

	var screen: Node = (load("res://scenes/GovernmentFormation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	await create_timer(0.4).timeout
	var shot := func(name: String):
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("user://gov_%s.png" % name)
		print("kaydedildi: gov_%s.png" % name)
	# 1) Başlangıç: sadece görevli parti ortak.
	shot.call("1_baslangic")
	# 2) Parti 2 eklendi.
	screen._on_partner_toggled(2)
	await process_frame
	await create_timer(0.3).timeout
	shot.call("2_eklendi")
	print("ortaklar: ", screen._partners)
	# 3) Çıkarıldı.
	screen._on_partner_toggled(2)
	await process_frame
	await create_timer(0.3).timeout
	shot.call("3_cikarildi")
	# 4) Tekrar eklendi: renk orijinaline dönmeli.
	screen._on_partner_toggled(2)
	await process_frame
	await create_timer(0.3).timeout
	shot.call("4_tekrar_eklendi")
	print("ortaklar: ", screen._partners)
	# 5) Dagitim asamasi: ortak cikar/ekle sonrasi renkler
	screen._on_partner_toggled(3)
	screen._step = 1  # Step.DISTRIBUTE
	screen._rebuild()
	await process_frame
	await create_timer(0.3).timeout
	shot.call("5_dagitim")
	screen._on_partner_toggled(3)
	await process_frame
	await create_timer(0.3).timeout
	shot.call("6_dagitim_cikarildi")
	screen._on_partner_toggled(3)
	await process_frame
	await create_timer(0.3).timeout
	shot.call("7_dagitim_tekrar_eklendi")
	quit()
