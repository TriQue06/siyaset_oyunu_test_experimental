extends SceneTree
## EKONOMİ ÖNİZLEMESİ: sağ sütundaki ekonomi kutusu (vergi geçişi sürerken),
## Vergi Politikası paneli (kademe seçili ve kapalı hâli), yatırım önizlemesi
## ve sonrası, sandık öncesi özeti, yasa panelindeki bağlantı. Ekran
## görüntüleri kullanıcı veri klasörüne yazılır; arayüz değerleri gerçek
## durumla da karşılaştırılır.
##   godot --resolution 1600x900 --path . --script res://tools/economy_preview.gd

var fails := 0

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OS.get_user_data_dir(), name])
	print("screenshot: " + name)

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

## Kontrolün ve atalarının ekrandaki dikdörtgeni pencereye sığıyor mu?
func _inside(control: Control) -> bool:
	var rect := control.get_global_rect()
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	return view.encloses(rect.grow(-1.0))

func _initialize() -> void:
	# PREVIEW_SIZE=1280x720 gibi: kullanıcının tam ekran ayarına dokunmadan pencere boyutu.
	await process_frame
	if OS.get_environment("PREVIEW_LANG") != "":
		# Ayar dosyasına yazmadan (GameSettings açılışta dili yükledikten sonra).
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
	var cp = root.get_node("CardPresets")
	bm.set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 5:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	var me: int = mm.owner_id
	var partner: int = int(mm.bot_ids()[0])
	gm.government = {"pm": me, "deputy_pm": partner}
	gm.main_gov_peer_id = me
	gm._set_phase(gm.Phase.GOVERNING)
	cm.current_turn_index = cm.turn_order.find(me)
	cm.funds[me] = 120.0
	cm.agenda = {}
	cm.crisis = {}
	# Yüksek vergiyle birkaç dönem, sonra indirim: geçiş sürüyor.
	cm.economy = Economy.start_state()
	cm.economy["tax"] = Economy.TAX_HIGH
	cm.economy["pressure"] = 0.0
	for i in 3:
		Economy.advance(cm.economy)
	cm.economy["tax_from"] = Economy.TAX_HIGH
	cm.economy["pressure_from"] = float(cm.economy["pressure"])
	cm.economy["tax"] = Economy.TAX_NORMAL
	cm.economy["pressure"] = Economy.pressure_after_change(float(cm.economy["pressure"]), Economy.TAX_NORMAL)
	cm.economy["prev"] = Economy.snapshot(cm.economy)
	cm.economy["prev"]["treasury"] = float(cm.economy["treasury"]) - 140.0
	cm.economy["prev"]["index"] = float(cm.economy["index"]) + 2.0
	cm._push_state({"type": "timer"})

	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	# Fare haritanın üstünde kalırsa il paneli açılır: köşeye çek.
	Input.warp_mouse(Vector2(2, 2))
	await _frames(30)
	scene._on_side_tab(0)
	await _frames(4)
	_shot("econ_board")
	var panel = scene._economy_panel
	check("ekonomi kutusu görünür (Hükümet sekmesi)", panel != null and panel.is_visible_in_tree())
	if panel != null:
		var treasury_text: String = (panel._tiles["treasury"]["value"] as Label).text
		check("hazine kutusu gerçek bakiyeyi gösterir", treasury_text == Economy.money_text(cm.state_treasury()),
			"%s / %s" % [treasury_text, Economy.money_text(cm.state_treasury())])
		check("enflasyon kutusu", (panel._tiles["inflation"]["value"] as Label).text == Economy.percent_text(cm.inflation()))
		check("vergi geçişi gösteriliyor", panel._transition.visible)
		check("ekonomi kutusu ekrana sığıyor", _inside(panel), str(panel.get_global_rect()))
		check("yürürlükteki vergi vurgulu", (panel._tax_buttons[Economy.TAX_NORMAL] as Button).get_theme_color("font_color") == UiTheme.INK)

	# Vergi Politikası paneli.
	scene._open_tax_panel()
	await _frames(6)
	_shot("econ_tax_panel")
	check("vergi paneli ekrana sığıyor", _inside(scene._tax_panel), str(scene._tax_panel.get_global_rect()))
	scene._on_tax_selected(Economy.TAX_LOW)
	await _frames(6)
	_shot("econ_tax_selected")
	check("seçili kademeyle panel ekrana sığıyor", _inside(scene._tax_panel), str(scene._tax_panel.get_global_rect()))
	# Sıra başkasındayken: sunulamaz durumu.
	cm.current_turn_index = cm.turn_order.find(partner)
	scene._fill_tax_panel()
	await _frames(4)
	_shot("econ_tax_blocked")
	cm.current_turn_index = cm.turn_order.find(me)
	scene._tax_panel.hide()

	# Yasa paneli: vergi bağlantısı.
	scene._on_law_button_pressed()
	await _frames(8)
	_shot("econ_law_designer")
	scene._law_designer.hide()

	# Yatırım (0.0.238: tamamı hazineden, finansman paneli yok).
	var province: String = String(cm._province_ids[6])
	var before: float = cm.state_treasury()
	cm._apply_invest_move(me, province)
	await _frames(12)
	_shot("econ_invest_anim")
	await create_timer(1.2).timeout
	check("yatırımdan sonra hazine kutusu güncel", (panel._tiles["treasury"]["value"] as Label).text == Economy.money_text(before - Economy.INVEST_COST))

	# Sandık öncesi özeti (erken seçim kararı).
	cm.early_election_pending = true
	cm._push_state({"type": "opinion"})
	await _frames(8)
	_shot("econ_early_election")
	check("sandık öncesi özeti görünür", panel._summary.visible)
	check("özetle birlikte sağ sütun ekrana sığıyor", _inside(panel), str(panel.get_global_rect()))
	cm.early_election_pending = false

	# Tur sonu: gelir animasyonu.
	var before_round: float = cm.state_treasury()
	var expected_income: float = cm.expected_revenue()
	cm._finish_round()
	check("tur sonu: hazineye tam bir dönem geliri girdi", absf(cm.state_treasury() - before_round - expected_income) < 0.01,
		"%.1f + %.1f -> %.1f" % [before_round, expected_income, cm.state_treasury()])
	await _frames(10)
	_shot("econ_round_revenue")

	# Profil kartı: hükümette ekonomi etkisi.
	scene._toggle_profile(me)
	await _frames(10)
	_shot("econ_profile")
	scene._hide_profile()

	print("ÖNİZLEME KONTROLLERİ: %s" % ("HEPSİ GEÇTİ" if fails == 0 else "%d HATA" % fails))
	quit(1 if fails > 0 else 0)
