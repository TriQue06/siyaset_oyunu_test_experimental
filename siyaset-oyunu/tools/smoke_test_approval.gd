extends SceneTree
## HÜKÜMET ONAYI testleri (0.0.282, yerel mod): başlangıç değeri (oy oranı ×
## bakanlık payı), yalnız tur sonunda güncellenmesi, afet yardımı karşılaştırması,
## kriz yasası (geçme / hükümet HAYIR'ı / hükümet oylarıyla düşme), %50'den
## uzaklığın seçim çarpanına bakanlık payıyla yazılması, durum kaydı.
##   godot --headless --path . --script res://tools/smoke_test_approval.gd

var mm
var pm
var cm
var gm
var cp
var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["[OK] " if ok else "[HATA]", label, ("  -> " + detail) if detail != "" else ""])

func near(a: float, b: float, eps: float = 0.05) -> bool:
	return absf(a - b) < eps

## 1 başbakan, 2 ortak, 3 muhalefet.
## requests: false ise yatırım istekleri silinir (diğer bölümleri etkilemesin).
func new_game(requests: bool = false) -> void:
	mm.players = {}
	pm.parties = {}
	var cores := {1: ["isveren", "dindar"], 2: ["isci", "milliyetci"], 3: ["genc", "ilerici"]}
	for peer_id in cores.keys():
		mm.players[peer_id] = {"name": "Lider%d" % peer_id}
		pm.parties[peer_id] = {
			"name": "Parti%d" % peer_id, "icon_index": 0, "icon_color": Color.WHITE,
			"bg_color": Color(0.3, 0.5, 0.7), "groups": VoterGroups.start_affinities(cores[peer_id]), "ready": true,
		}
	cm.init_game()
	cm.turn_order = [1, 2, 3]
	cm.current_turn_index = 0
	cm.last_seats = {1: 250, 2: 100, 3: 150}
	cm.last_vote_shares = {1: 40.0, 2: 20.0, 3: 40.0}
	cm.election_seats = cm.last_seats.duplicate()
	cm.last_election_round = 1
	gm.government = {"pm": 1, "deputy_pm": 2}
	gm.main_gov_peer_id = 1
	gm._set_phase(gm.Phase.GOVERNING)
	cm.funds = {1: 500.0, 2: 500.0, 3: 500.0}
	cm.agenda = {}
	cm.crisis = {}
	cm.start_approval()
	if not requests:
		cm.invest_requests = {}

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	cm.enforce_turn_flow = false
	gm = root.get_node("GovernmentManager")
	cp = root.get_node("CardPresets")
	cm.allow_temporary_parties = false
	cm.fixed_map_seed = 1950
	mm.room_code = ""
	gm.result_hold_seconds = 0.0
	GameRules.configure(8, 12)

	print("=== 1) BAŞLANGIÇ ===")
	new_game()
	var s1: float = cm.quota_share(1)
	var s2: float = cm.quota_share(2)
	check("bakanlık payları toplamı 1", near(s1 + s2, 1.0, 0.001), "%.2f + %.2f" % [s1, s2])
	check("başlangıç = oy oranı × bakanlık payı toplamı", near(cm.approval_value(), 40.0 * s1 + 20.0 * s2, 0.06),
		"%.1f" % cm.approval_value())
	gm.government = {"pm": 1}
	cm.last_vote_shares = {1: 50.0, 2: 20.0, 3: 30.0}
	cm.start_approval()
	check("%50 oyla tek başına iktidar %50'den başlar", near(cm.approval_value(), 50.0, 0.001))
	gm.government = {}
	gm.main_gov_peer_id = -1
	check("hükümet yokken onay yok", not cm.has_approval())

	print("=== 2) TUR SONU ===")
	new_game()
	var start: float = cm.approval_value()
	cm.start_disaster("deprem", [cm._province_ids[0]])
	cm.disaster["active"]["aid"] = {1: 20.0, 3: 10.0}
	check("tur içinde değer değişmez", near(cm.approval_value(), start, 0.001))
	cm._finish_round()
	check("afet: hükümet daha çok yardım etti, tur sonunda +4",
		near(cm.approval_value(), start + PublicOpinion.APPROVAL_DISASTER_MORE), "%.1f -> %.1f" % [start, cm.approval_value()])
	check("değişim etiketi tur sonu farkı", near(cm.approval_delta(), PublicOpinion.APPROVAL_DISASTER_MORE))
	check("geçmiş tur tur birikir", (cm.approval["history"] as Array).size() == 2)
	var mid: float = cm.approval_value()
	cm.start_disaster("deprem", [cm._province_ids[0]])
	cm.disaster["active"]["aid"] = {3: 10.0}
	cm.invest_requests = {}
	cm._finish_round()
	check("afet: muhalefet daha çok yardım etti, düşer", near(cm.approval_value(), mid + PublicOpinion.APPROVAL_DISASTER_LESS))
	mid = cm.approval_value()
	cm.invest_requests = {}
	cm._finish_round()
	check("olaysız tur: değişmez, fark 0", near(cm.approval_value(), mid) and near(cm.approval_delta(), 0.0))

	print("=== 3) KRİZ YASASI ===")
	new_game()
	cm.agenda = {"type": "kriz_isci", "until": cm.round_number + 1}
	var law: String = cp.law_type("isci")
	cm.approval["value"] = 62.0
	cm.apply_law_result(3, law, {1: -1, 2: -1, 3: 1}, false, [1, 2])
	cm._finish_round()
	check("hükümet krizli grubun yasasına HAYIR: %62 -> ~%35",
		cm.approval_value() <= 36.0 and cm.approval_value() >= 33.0, "%.1f" % cm.approval_value())
	new_game()
	cm.agenda = {"type": "kriz_isci", "until": cm.round_number + 1}
	var before: float = cm.approval_value()
	cm.apply_law_result(3, law, {1: 1, 2: 1, 3: 1}, true, [1, 2])
	cm._finish_round()
	check("kriz yasası geçti: artar", near(cm.approval_value(), before + PublicOpinion.APPROVAL_CRISIS_LAW_PASSED))
	new_game()
	cm.agenda = {"type": "kriz_isci", "until": cm.round_number + 1}
	before = cm.approval_value()
	cm.apply_law_result(3, law, {1: 1, 2: -1, 3: 1}, true, [1, 2])
	cm._finish_round()
	check("yalnız ortak HAYIR: bakanlık payı kadar düşer",
		near(cm.approval_value(), before + PublicOpinion.APPROVAL_CRISIS_LAW_PASSED + PublicOpinion.APPROVAL_CRISIS_LAW_NO * cm.quota_share(2)),
		"%.1f" % cm.approval_value())
	new_game()
	cm.agenda = {}
	before = cm.approval_value()
	cm.apply_law_result(3, cp.law_type("ilerici"), {1: -1, 2: -1, 3: 1}, false, [1, 2])
	cm._finish_round()
	check("gündem dışı yasa onayı etkilemez", near(cm.approval_value(), before))

	print("=== 4) OYA ETKİSİ (seçmen) ===")
	new_game()
	cm.approval["value"] = 50.0
	check("%50 nötr: seçmen etkisi yok", near(cm.approval_national(1), 0.0, 0.001) and near(cm.approval_national(2), 0.0, 0.001))
	cm.approval["value"] = 100.0
	check("%100: ortaklara bakanlık payıyla bölünmüş tam etki",
		near(cm.approval_national(1), PublicOpinion.APPROVAL_NATIONAL_MAX * cm.quota_share(1), 0.001)
		and near(cm.approval_national(2), PublicOpinion.APPROVAL_NATIONAL_MAX * cm.quota_share(2), 0.001))
	var v1: float = cm.voter_total(1)
	var v3: float = cm.voter_total(3)
	cm._finish_round()
	check("yüksek onay: tur sonunda hükümet partisi seçmen kazanır", cm.voter_total(1) > v1, "%.1f -> %.1f" % [v1, cm.voter_total(1)])
	check("muhalefet seçmeni etkilenmez", near(cm.voter_total(3), v3, 0.01))
	cm.approval["value"] = 20.0
	v1 = cm.voter_total(1)
	cm.invest_requests = {}
	cm._finish_round()
	check("düşük onay: hükümet partisi seçmen kaybeder", cm.voter_total(1) < v1, "%.1f -> %.1f" % [v1, cm.voter_total(1)])
	check("muhalefet etkilenmez", near(cm.approval_national(3), 0.0, 0.001))

	print("=== 5) YATIRIM İSTEKLERİ ===")
	new_game(true)
	var want := maxi(PublicOpinion.REQUEST_MIN, int(roundf(float(cm._province_ids.size()) / float(PublicOpinion.REQUEST_PROVINCES_PER))))
	check("hükümet kurulunca istekler seçilir", cm.invest_requests.size() == want, "%d il" % cm.invest_requests.size())
	var turns: Vector2i = cm.request_turns()
	check("pasta dilimi = oyuncu sayısı, tur başında hepsi dolu", turns == Vector2i(3, 3))
	cm.current_turn_index = 2
	check("son sırada tek dilim kalır", cm.request_turns() == Vector2i(1, 3))
	cm.current_turn_index = 0
	var ids: Array = cm.invest_requests.keys()
	var done_id: String = ids[0]
	var miss_id: String = ids[1]
	before = cm.approval_value()
	var local_before: float = cm.voter_total(1, miss_id)
	cm._fulfil_invest_request(done_id, float(cm.invest_requests[done_id]["amount"]) - 10.0)
	check("istenenden az yatırım isteği karşılamaz", not bool(cm.invest_requests[done_id]["done"]))
	cm._fulfil_invest_request(done_id, 150.0)
	check("yatırım isteği karşılandı", bool(cm.invest_requests[done_id]["done"]))
	check("onay tur içinde değişmez", near(cm.approval_value(), before, 0.001))
	cm._finish_round()
	var expected: float = before + PublicOpinion.APPROVAL_REQUEST_DONE + PublicOpinion.APPROVAL_REQUEST_MISSED * float(want - 1)
	check("tur sonu: karşılanan +, karşılanmayan − (hepsi toplanır)", near(cm.approval_value(), expected), "%.1f -> %.1f (beklenen %.1f)" % [before, cm.approval_value(), expected])
	check("karşılanmayan ilde hükümet partisi seçmen kaybeder", cm.voter_total(1, miss_id) < local_before * 0.97,
		"%.2f -> %.2f" % [local_before, cm.voter_total(1, miss_id)])
	check("yeni tur için yeni istekler", cm.invest_requests.size() == want and not cm.invest_requests.values().any(func(r): return bool(r["done"])))
	gm.government = {}
	gm.main_gov_peer_id = -1
	cm._finish_round()
	check("hükümet yokken istek yok", cm.invest_requests.is_empty())

	print("=== 6) KAYIT ===")
	new_game()
	cm.approval["value"] = 57.0
	var packed: Dictionary = cm._pack_state(true)
	cm.approval = {}
	var req_before: Dictionary = cm.invest_requests.duplicate(true)
	cm.invest_requests = {}
	cm._apply_state(packed)
	check("onay durumla taşınır", near(cm.approval_value(), 57.0, 0.001))
	check("istekler durumla taşınır", cm.invest_requests == req_before)

	print("SONUC: %s (%d hata)" % ["TAMAM" if fails == 0 else "HATA", fails])
	quit(1 if fails > 0 else 0)
