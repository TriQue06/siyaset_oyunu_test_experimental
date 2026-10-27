extends SceneTree
## ANKET KARTI (0.0.272): ilk turda ve seçimden sonraki ilk turda desteye
## girmez; çekilince yalnız çekenin anketi dolar; seçimde sıfırlanır.

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	root.get_node("BotManager").set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 3:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	root.get_node("GovernmentManager").result_hold_seconds = 0.0
	var me: int = mm.owner_id
	cm.round_number = 1
	check("ilk turda anket desteye girmez", not cm._draw_weights(me).has("anket"))
	cm.round_number = 3
	cm.last_election_round = 0
	check("sonraki turlarda girer", cm._draw_weights(me).has("anket"))
	cm._hold_election(3, false)
	cm.round_number = 4
	check("secimden sonraki ilk turda girmez", not cm._draw_weights(me).has("anket"))
	cm.round_number = 5
	check("bir tur sonra yine girer", cm._draw_weights(me).has("anket"))
	var entry := {}
	cm._apply_instant(me, "anket", entry)
	var poll: Dictionary = cm.my_poll(me)
	var total := 0.0
	for pid in poll.get("parties", {}).keys():
		total += float(poll["parties"][pid]["percent"])
	check("anket cekenin: oy oranlari toplam ~%100", absf(total - 100.0) < 1.0, "%.1f" % total)
	check("baskasinin anketi yok", cm.my_poll(int(mm.bot_ids()[0])).is_empty())
	check("aninda etkili kart", cm.is_instant_card("anket"))
	cm._hold_election(5, false)
	check("secimde anket sifirlanir", cm.my_poll(me).is_empty())
	print("=== %s ===" % ("HEPSİ GEÇTİ" if fails == 0 else "%d HATA" % fails))
	quit(1 if fails > 0 else 0)
