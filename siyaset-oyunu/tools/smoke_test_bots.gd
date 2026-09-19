extends SceneTree
## 6 botlu hızlandırılmış oyun: BotBrain kararları beklemesiz uygulanır.
## Çalışma hatası çıkmamalı, oyun ilerlemeli, hükümet kurulmalı, botlar
## farklı türde hamleler (kart, yasa, il başkanlığı) yapmalı.
##   godot --headless --script res://tools/smoke_test_bots.gd

var mm
var pm
var cm
var gm
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	# Test betiği autoload'lardan önce derlendiği için sınıf çalışma anında yüklenir.
	var brain = load("res://scripts/bot_brain.gd")
	var bm = root.get_node("BotManager")
	bm.set_process(false)  # zamanlamasız sürüyoruz
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	mm.election_threshold = 3.0
	mm.axis_sharpness_start = 1.0
	mm.axis_sharpness_increment = 0.1
	mm.players = {}
	pm.parties = {}
	mm.stage = mm.Stage.PARTY_SETUP
	for i in 6:
		var id: int = mm.BOT_ID_BASE - i
		mm.players[id] = {"name": "Bot %d" % i, "bot": true}
		pm.add_bot_party(id)
	check("6 bot partisi olustu, isimler benzersiz", pm.parties.size() == 6)
	cm.init_game()

	var played := {}
	var governments := 0
	var votes := 0
	var steps := 0
	var was_governing := false
	var turn_actions := 0
	var max_actions := 0
	var last_bot := -1
	while steps < 4000 and not cm.game_finished and cm.round_number <= 14:
		steps += 1
		if gm.phase == gm.Phase.VOTING:
			for bot in gm.eligible_voter_ids():
				if not gm.has_voted(bot):
					gm._apply_vote(bot, brain.choose_vote(bot))
					votes += 1
					break
		elif gm.phase == gm.Phase.FORMING:
			var holder: int = gm.mandate_peer_id()
			gm._apply_government_proposal(holder, brain.build_government(holder))
			if gm.phase == gm.Phase.FORMING:
				gm.tick(GameRules.FORMATION_TIMEOUT + 100.0)  # geçersiz teklif: süre dolsun
		else:
			# Hamle sınırı yok: bot turu bitirene kadar (en çok 12) hamle yapar.
			var bot: int = cm.current_turn_peer_id()
			if bot != last_bot:
				last_bot = bot
				turn_actions = 0
			var done: Dictionary = bm.do_action(bot) if turn_actions < 12 else {}
			turn_actions += 1
			if done.is_empty():
				cm._apply_pass(bot, true)
				played["turu_bitir"] = int(played.get("turu_bitir", 0)) + 1
				max_actions = maxi(max_actions, turn_actions - 1)
				turn_actions = 0
			else:
				var kind := String(done["type"])
				if kind == "card":
					kind = String(done["card"])
				elif kind == "law":
					kind = "law"
				elif kind == "organization":
					kind = "teskilat"
				played[kind] = int(played.get(kind, 0)) + 1
		var governing: bool = gm.phase == gm.Phase.GOVERNING
		if governing and not was_governing:
			governments += 1
		was_governing = governing

	print("  adim %d, tur %d, hukumet %d, oy %d, hamleler %s" % [steps, cm.round_number, governments, votes, str(played)])
	check("oyun ilerledi (en az 10 tur)", cm.round_number >= 10 or cm.game_finished, "tur %d" % cm.round_number)
	check("en az bir hukumet kuruldu", governments >= 1)
	check("botlar oy verdi", votes > 0)
	check("botlar yasa sundu", int(played.get("law", 0)) > 0)
	check("botlar teskilat kurdu", int(played.get("teskilat", 0)) > 0)
	check("botlar miting yapti", int(played.get("miting", 0)) > 0)
	check("botlar kart oynadi", int(played.get("karalama", 0)) + int(played.get("anket", 0)) + int(played.get("steal_weak", 0)) \
		+ int(played.get("steal_medium", 0)) + int(played.get("steal_strong", 0)) > 0)
	var dealt := 0
	for id in cm.turn_order:
		dealt += cm.inventories.get(id, []).size()
	check("botlara her sira otomatik kart verildi (kart oynandi ya da elde)", dealt > 0 or int(played.get("karalama", 0)) > 0)
	check("bir turda birden cok hamle yapildi", max_actions >= 2, str(max_actions))
	# Yarım adım kaymasının kendisi smoke_test_rules'ta; burada değerlerin geçerliliği.
	var valid := true
	for peer_id in pm.parties.keys():
		for axis in pm.parties[peer_id]["ideology"].keys():
			var v := float(pm.parties[peer_id]["ideology"][axis])
			if absf(v) > 3.0 or not is_equal_approx(v * 2.0, roundf(v * 2.0)):
				valid = false
				print("  gecersiz ideoloji degeri: ", v)
	check("ideolojiler [-3, 3] ve 0.5 adimli", valid)
	# Bilgi kısıtı: gözcü gönderilmemiş il bot için nötrdür.
	var bot0: int = cm.turn_order[0]
	var known: Dictionary = brain._known_centers(bot0)
	var unknown_ok := true
	for province_id in known.keys():
		if not cm.knows_leaning(bot0, province_id) and not (known[province_id] as Dictionary).is_empty():
			unknown_ok = false
	check("bot teskilati olmayan ilin gorusunu bilmez", unknown_ok)
	check("botlar farkli hamle turleri yapti", played.size() >= 5, str(played))
	var mana_ok := true
	for peer_id in cm.mana.keys():
		if cm.mana_of(peer_id) < 0:
			mana_ok = false
	check("mana hic eksiye dusmedi", mana_ok, str(cm.mana))

	print("")
	print("=== BOT BLOGU ===")
	# Senaryo: "insan" (ilk parti) tek başına hükümet, 5 bot muhalefette.
	var human: int = cm.turn_order[0]
	mm.players[human]["bot"] = false
	var ids: Array = cm.turn_order.duplicate()
	cm.last_seats = {}
	cm.last_seats[human] = 210
	for i in range(1, ids.size()):
		cm.last_seats[ids[i]] = 38
	cm.last_seats[ids[1]] = 60
	var gov := {}
	for post in load("res://scripts/government_presets.gd").POSTS:
		gov[post["id"]] = human
	gm.government = gov
	gm.main_gov_peer_id = human
	gm.formed_round = cm.round_number - 5
	gm.censure_round = -1
	check("insan hukumeti varken blok aktif", brain.bloc_active() and brain.bloc_members().size() == ids.size() - 1)
	check("blok lideri en buyuk bot", brain.bloc_leader() == ids[1])
	var st: Dictionary = brain._eval_steal(ids[2], "steal_strong")
	check("blok uyesi insanin partisinden calar", int(st.get("peer", -1)) == human, str(st))
	check("blok gensoruyu gecer sayar (5 bot 212 > 210)", brain._censure_worth_it(ids[2]))
	gm.proposal_kind = gm.KIND_CENSURE
	gm.proposal_peer_id = ids[2]
	check("blok botu gensoruya evet der", brain.choose_vote(ids[3]) == gm.VOTE_YES)
	gm.government = {}
	gm.main_gov_peer_id = -1
	var plan: Dictionary = brain.build_government(ids[1])
	var partners := {}
	for post in plan.keys():
		partners[plan[post]] = true
	check("gensoru sonrasi blok lideri ortak olarak botlari secer", not partners.has(human), str(partners.keys()))
	mm.players[human]["bot"] = true

	print("")
	print("=== MUHALEFETTEKI BOT GENSORUYU DESTEKLER ===")
	# 3 kisilik senaryo: bot azinlik hukumeti, insan gensoru veriyor, ucuncu
	# parti (bot) muhalefette. Bot, hukumet cok yakin degilse EVET demeli.
	var gov_bot: int = ids[1]
	var other_bot: int = ids[2]
	pm.parties[gov_bot]["ideology"] = {"economic": 3, "social": 3, "administrative": 3}
	pm.parties[other_bot]["ideology"] = {"economic": -2, "social": 0, "administrative": -1}
	pm.parties[human]["ideology"] = {"economic": 0, "social": 0, "administrative": 0}
	cm.last_seats = {human: 150, gov_bot: 160, other_bot: 90}
	var gov2 := {}
	for post in load("res://scripts/government_presets.gd").POSTS:
		gov2[post["id"]] = gov_bot
	gm.government = gov2
	gm.main_gov_peer_id = gov_bot
	gm.proposal_kind = gm.KIND_CENSURE
	gm.proposal_peer_id = human
	check("muhalefet botu gensoruya evet", brain.choose_vote(other_bot) == gm.VOTE_YES)
	pm.parties[other_bot]["ideology"] = {"economic": 3, "social": 3, "administrative": 2.5}
	check("hukumete cok yakin bot cekimser kalir", brain.choose_vote(other_bot) == gm.VOTE_ABSTAIN)
	check("hukumet partisi hayir der", brain.choose_vote(gov_bot) == gm.VOTE_NO)
	gm.government = {}
	gm.main_gov_peer_id = -1

	print("")
	if fails == 0:
		print("=== TUM TESTLER GECTI ===")
	else:
		print("=== %d TEST BASARISIZ ===" % fails)
	quit()
