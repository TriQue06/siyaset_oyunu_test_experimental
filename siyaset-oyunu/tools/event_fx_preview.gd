extends SceneTree
## OLAY GAZETESİ testi ve ekran görüntüleri (EventFx, 0.0.179).
## Gerçek oyun ekranında, GERÇEK oyun hamleleriyle (kaset ve iç karışıklık
## kartı oynanır, gensoru oylanır) gazeteyi tetikler; ayrıca kongre ve seçim
## manşetlerini, tekrar engelini, kuyruğu, geçmeyi ve temizliği denetler.
##   godot --path . --script res://tools/event_fx_preview.gd
##   (PREVIEW_SIZE=1280x720, PREVIEW_LANG=en desteklenir; görüntüler
##   kullanıcı veri klasörüne fx_*.png olarak yazılır)

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s]  %s%s" % ["OK" if ok else "HATA", label, ("  -> " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _seconds(s: float) -> void:
	await create_timer(s).timeout

func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s/fx_%s.png" % [OS.get_user_data_dir(), name])

func _initialize() -> void:
	await process_frame
	if OS.get_environment("PREVIEW_LANG") != "":
		root.get_node("GameSettings").language = OS.get_environment("PREVIEW_LANG")
		TranslationServer.set_locale(OS.get_environment("PREVIEW_LANG"))
	var forced := OS.get_environment("PREVIEW_SIZE")
	if forced != "":
		var parts := forced.split("x")
		for i in 3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
			await process_frame
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	var gs = root.get_node("GameSettings")
	gs.event_fx = true
	bm.set_process(false)
	mm.start_offline("Barış")
	for i in 4:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "ilerici"], true)
	cm.set_rng_seed(777)
	bm._rng.seed = 777
	gm.result_hold_seconds = 0.2
	var now := 0.0
	while now < 4000.0 and not (gm.has_government() and cm.round_number >= 5):
		now += 0.2
		cm.tick(0.2)
		gm.tick(0.2)
		bm.step(now)
		if gm.phase == gm.Phase.VOTING and gm.eligible_voter_ids().has(mm.owner_id) and not gm.has_voted(mm.owner_id):
			gm._apply_vote(mm.owner_id, gm.VOTE_YES)
	var me: int = mm.owner_id
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(30)
	var fx = scene._event_fx
	check("oyun ekranında EventFx var", fx != null)

	# 1) KASET: gerçek kart oynanır (host mantığı uygular, gazete sunar).
	var target := -1
	for pid in cm.party_ids():
		if int(pid) != me and cm.has_seats(int(pid)):
			target = int(pid)
			break
	cm.current_turn_index = cm.turn_order.find(me)
	cm.funds[me] = 500.0
	cm.inventories[me] = ["kaset", "isyan"]
	cm._apply_play(me, 0, target)
	await _frames(2)
	check("kaset oynandı (elden çıktı)", not cm.inventories[me].has("kaset"), str(cm.inventories[me]))
	check("kaset gazetesi oynuyor", fx.is_playing())
	await _seconds(0.25)
	_shot("kaset_ucus")
	await _seconds(0.6)
	_shot("kaset")
	# 2) İÇ KARIŞIKLIK: kuyruğa girer, kaset bitince oynar (üst üste binmez).
	cm._apply_play(me, 0, target)
	await _frames(2)
	check("aynı anda tek gazete (ikincisi kuyrukta)", fx._queue.size() == 1 and fx.get_child_count() == 1,
		"kuyruk %d, çocuk %d" % [fx._queue.size(), fx.get_child_count()])
	await _seconds(3.4)
	_shot("isyan")
	await _seconds(1.5)
	_shot("isyan_bolunme")
	await _seconds(1.5)
	check("ikisi de bitti, ekranda gazete kalmadı", not fx.is_playing() and fx.get_child_count() == 0,
		"çocuk %d" % fx.get_child_count())

	# 3) TEKRAR ENGELİ: aynı olay (aynı sürüm) ikinci kez oynamaz.
	var dup := {"type": "played", "card": "kaset", "target": target, "message": "x"}
	cm.event_presented.emit(dup, 990001)
	await _frames(2)
	var first_played: bool = fx.is_playing()
	fx.skip()
	await _frames(2)
	cm.event_presented.emit(dup, 990001)
	await _frames(2)
	check("aynı olay iki kez gösterilmez", first_played and not fx.is_playing())

	# 4) GEÇME: Boşluk gazeteyi hemen kaldırır, ekran etkileşimli kalır.
	fx.present("test|skip", {"headline": "TEST", "accent": Color.GOLD})
	await _seconds(0.5)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.push_input(key)
	await _frames(3)
	check("Boşluk ile geçildi, temizlendi", not fx.is_playing() and fx.get_child_count() == 0)

	# 5) GENSORU: gerçek önerge ve oylama; sonuç oyun mantığında, gazete sonra.
	var gov_before: bool = gm.has_government()
	cm.current_turn_index = cm.turn_order.find(me)
	var censure_ok: bool = cm.can_censure(me)
	if censure_ok:
		cm._apply_censure_move(me)
		for voter in gm.eligible_voter_ids():
			if not gm.has_voted(voter):
				gm._apply_vote(voter, gm.VOTE_NO if gm.government_party_ids().has(cm.party_of(voter)) else gm.VOTE_YES)
		gm.result_hold_seconds = 0.0
		for i in 20:
			gm.tick(0.2)
		await _frames(2)
		await _seconds(1.0)
		_shot("gensoru")
		var shown := false
		for k in fx.get_script()._seen:
			if String(k).begins_with("gm|censure"):
				shown = true
		check("gensoru sonucu gazete manşeti oldu", shown, str(fx.get_script()._seen.slice(-3)))
		print("  gensoru: hükümet önce %s, sonra %s" % [str(gov_before), str(gm.has_government())])
		fx.skip_all()
	else:
		print("  (gensoru şartı yok, atlandı)")

	# 6) KONGRE ve SEÇİM manşetleri (oyunun gerçek verisiyle).
	await _frames(5)
	scene._headline_for_congress({"pid": me, "party": "Yeni Yol", "color": Color("F20C1F"),
		"candidates": [{"name": "Barış", "incumbent": true}, {"name": "Deniz Kaya", "incumbent": false}],
		"round1": [700, 500], "round2": [], "winner": 0})
	await _seconds(0.9)
	_shot("kongre")
	fx.skip_all()
	await _frames(3)
	scene._headline_for_election()
	await _seconds(0.9)
	_shot("secim")
	check("seçim manşeti oynuyor", fx.is_playing())

	# 6b) Koalisyondan çekilme metni tanınır (TR ve EN kalıp), "ortaklar anlaştı" tanınmaz.
	var tr_text := "%s koalisyondan çekildi: %s.%s%s%s" % ["ABC", "hafif destek kaybı", "", "", ""]
	var en_text := TranslationServer.get_translation_object("en").get_message("%s koalisyondan çekildi: %s.%s%s%s") % ["ABC", "x", "", "", ""]
	check("çekilme metni tanınır (TR)", scene._is_withdrawal_text(tr_text), tr_text)
	check("çekilme metni tanınır (EN)", scene._is_withdrawal_text(en_text), en_text)
	check("ortaklık metni çekilme sayılmaz", not scene._is_withdrawal_text("Ortaklar anlaştı: ABC hükümeti meclis oylamasında."))
	# 6c) Gensoru sonucu manşeti (oyunun son oylama gerekçesiyle).
	fx.skip_all()
	await _frames(2)
	scene._headline_for_proposal(false, gm.KIND_CENSURE, me)
	await _seconds(0.9)
	_shot("gensoru_ret")
	check("gensoru reddi manşeti oynuyor", fx.is_playing())
	fx.skip_all()
	# 7) KAPALI AYAR: hiçbir şey oynamaz.
	fx.skip_all()
	gs.event_fx = false
	check("ayar kapalıyken oynamaz", not fx.present("test|off", {"headline": "X"}) and not fx.is_playing())
	gs.event_fx = true
	print("=== EVENT FX: %s ===" % ("PASS" if fails == 0 else "%d HATA" % fails))
	quit()
