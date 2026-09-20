extends SceneTree
## TAM OYUN TESTİ: botlar oynarken kurallar tutuyor mu?
## Özellikle PUAN TABLOSU: hükümetteki partiler her tur makam puanını
## gerçekten alıyor mu (kullanıcı "bakanlık aldım ama puan gelmedi" dedi).
##   godot --headless --path . --script res://tools/smoke_test_fullgame.gd

var _failed := 0
var cm
var gm
var pm
var mm

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failed += 1
	print("  [%s]  %s%s" % ["OK" if ok else "HATA", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	var gp = load("res://scripts/government_presets.gd")

	mm.room_code = ""
	mm.players = {}
	pm.parties = {}
	var ids := [1, 2, 3]
	for i in ids.size():
		mm.players[ids[i]] = {"name": "Lider %d" % i, "bot": i != 0}
		pm.parties[ids[i]] = {"name": "Parti %d" % i, "icon_index": i, "icon_color": Color.WHITE,
			"bg_color": Color.RED, "ideology": {"economic": 0, "social": 0, "administrative": 0}, "ready": true}
	cm.init_game()
	gm.result_hold_seconds = 0.0
	cm.turn_order = ids.duplicate()
	cm.last_seats = {1: 150, 2: 200, 3: 50}
	cm.last_vote_shares = {1: 37.0, 2: 50.0, 3: 13.0}

	print("=== 1) BAKANLIK ALAN PARTI PUAN ALIR ===")
	gm.start_formation()
	var assignments := {}
	for post in gp.POSTS:
		assignments[post["id"]] = 2
	# İnsan oyuncu (1) iki bakanlık alıyor.
	assignments["ministry_health"] = 1
	assignments["ministry_education"] = 1
	gm._apply_government_proposal(2, assignments)
	# Hükümet teklifi İKİ aşamalı: önce ortaklar anlaşır, sonra meclis oylar.
	check("once koalisyon gorusmesi", gm.is_coalition_stage())
	for voter in gm.eligible_voter_ids():
		gm._apply_vote(int(voter), gm.VOTE_YES)
	check("ikinci asama: meclis oylamasi", gm.proposal_stage == gm.STAGE_PARLIAMENT and gm.is_voting())
	for voter in gm.eligible_voter_ids():
		gm._apply_vote(int(voter), gm.VOTE_YES)
	check("hukumet kuruldu", gm.has_government(), gm.last_resolution_reason)
	check("bakanlik alan parti hukumette", gm.government_party_ids().has(1), str(gm.government_party_ids()))
	var expected_human: int = 2 * gp.MINISTRY_POINTS
	check("tur puani = 2 bakanlik", gm.round_points_of(1) == expected_human, str(gm.round_points_of(1)))
	gm.scores = {}
	cm._finish_round()
	check("tur sonunda puan YAZILDI", gm.score_of(1) == expected_human, "puan %d, beklenen %d" % [gm.score_of(1), expected_human])
	cm._finish_round()
	check("puan birikiyor", gm.score_of(1) == expected_human * 2, str(gm.score_of(1)))
	var pm_party_points: int = gm.round_points_of(2)
	check("basbakanlik + kalan gorevler daha fazla", pm_party_points > expected_human, str(pm_party_points))

	print("")
	print("=== 2) SECIM SONRASI HUKUMET DUSER, PUAN DURUR ===")
	var before: int = gm.score_of(1)
	gm.government.clear()
	cm._finish_round()
	check("hukumet yokken puan yazilmaz", gm.score_of(1) == before, str(gm.score_of(1)))

	print("")
	print("=== TUM TESTLER GECTI ===" if _failed == 0 else "=== %d TEST BASARISIZ ===" % _failed)
	quit(1 if _failed > 0 else 0)
