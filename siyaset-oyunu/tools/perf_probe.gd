extends SceneTree
## Oyun ekranının sinyal işleyicilerinin süresi (ms): hangisi pahalı?
##   godot --path . --script res://tools/perf_probe.gd

func _t(label: String, f: Callable, n: int = 5) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call()
	print("%-34s %7.2f ms" % [label, (Time.get_ticks_usec() - t0) / 1000.0 / n])

func _initialize() -> void:
	await process_frame
	var mm = root.get_node("MultiplayerManager")
	var pm = root.get_node("PartyManager")
	var cm = root.get_node("CardManager")
	var gm = root.get_node("GovernmentManager")
	root.get_node("BotManager").set_process(false)
	cm.allow_temporary_parties = false
	mm.start_offline("Barış")
	for i in 7:
		mm.add_bot()
	mm.start_game()
	pm.set_party_and_ready("Yeni Yol", 0, Color.WHITE, Color("F20C1F"), ["isveren", "dindar"], true)
	cm.set_rng_seed(4242)
	gm.result_hold_seconds = 0.0
	cm._hold_election(cm.round_number, false)
	var scene: Node = (load("res://scenes/GameScreen.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	_t("_on_opinion_changed", scene._on_opinion_changed)
	_t("  _refresh_disaster", scene._refresh_disaster)
	_t("  _refresh_economy", scene._refresh_economy)
	_t("  _refresh_score_panel", scene._refresh_score_panel)
	_t("  _refresh_agenda_banner", scene._refresh_agenda_banner)
	_t("  _apply_map_layer_colors", scene._apply_map_layer_colors)
	for sig in ["phase_changed", "government_changed", "proposal_changed", "scores_changed"]:
		for c in gm.get_signal_connection_list(sig):
			var cb: Callable = c["callable"]
			_t("  GM %s -> %s" % [sig, cb.get_method()], func(): cb.call() if cb.get_argument_count() == 0 else null)
	for sig in ["turn_changed", "inventories_updated", "opinion_changed", "seats_changed"]:
		for c in cm.get_signal_connection_list(sig):
			var cb2: Callable = c["callable"]
			print("  CM %s -> %s.%s" % [sig, cb2.get_object(), cb2.get_method()])
	_t("_rebuild_player_panel", scene._rebuild_player_panel)
	_t("_on_turn_changed", func(): scene._on_turn_changed(cm.current_turn_peer_id()))
	_t("_rebuild_hand", scene._rebuild_hand)
	_t("_on_parties_updated", scene._on_parties_updated)
	_t("_refresh_results_panels", scene._refresh_results_panels)
	_t("_refresh_action_buttons", scene._refresh_action_buttons)
	_t("push_state opinion (tümü)", func(): cm._push_state({"type": "opinion"}))
	_t("GM _emit_all", gm._emit_all)
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await process_frame
	print("ortalama kare (boşta) %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / 60))
	quit()
