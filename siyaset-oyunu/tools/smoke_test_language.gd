extends SceneTree
## DİL TESTİ: İngilizce dilde botlarla tam bir oyun oynanır, oyun ekranı da
## açık tutulur (bütün çevrilmiş şablonlar gerçek değerlerle biçimlenir).
## Biçimlendirme hatası, çevrilmemiş kritik metin ya da çalışma hatası olmamalı.
##   godot --headless --script res://tools/smoke_test_language.gd

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	root.get_node("GameSettings").language = "en"
	TranslationServer.set_locale("en")
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	var bm = root.get_node("BotManager")
	var brain = load("res://scripts/bot_brain.gd")
	bm.set_process(false)
	cm.allow_temporary_parties = true
	cm.set_rng_seed(777)
	seed(777)
	gm.result_hold_seconds = 0.0
	mm.start_offline("Player")
	for i in 5:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("New Way", 0, Color.WHITE, Color("F20C1F"), ["isci", "ilerici"], true)
	var me: int = mm.owner_id
	check("dil İngilizce", TranslationServer.get_locale() == "en")
	check("çeviri yüklü", L.t("Kapat") == "Close")
	check("yüzde İngilizce biçimde", L.pct(12.3) == "12.3%" and L.thousands(1240) == "1,240", L.pct(12.3))
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var steps := 0
	var turn_actions := 0
	var last_bot := -1
	while steps < 6000 and not cm.game_finished:
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
		if steps % 40 == 0:
			await process_frame  # ekran tazelensin
	check("oyun sona erdi", cm.game_finished, "tur %d" % cm.round_number)
	# Günlükte Türkçeye özgü kalıplar kalmamalı.
	var turkish := 0
	var sample := ""
	for entry in cm.event_log:
		var text := String(entry.get("text", ""))
		if text.contains(" yaptı") or text.contains(" kurdu") or text.contains("seçimi yapıldı") or text.contains("milyon"):
			turkish += 1
			sample = text
	check("olay günlüğü İngilizce", turkish == 0, sample)
	print("=== TUM TESTLER GECTI ===" if fails == 0 else "=== %d TEST BASARISIZ ===" % fails)
	quit(1 if fails > 0 else 0)
