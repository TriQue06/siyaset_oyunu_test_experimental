extends Node
## Autoload. Hükümet kurma görevi, meclis teklifleri ve oylama.
##
## AKIŞ
##   1) Seçim sonuçlanır  -> start_formation() (host çağırır)
##   2) En çok MİLLETVEKİLİ olan parti hükümet kurma görevini alır
##      (oy oranına göre DEĞİL — bkz. _build_mandate_order).
##   3) Görevli, GovernmentFormation sahnesinde 10 görevi paylaştırıp teklif
##      eder -> submit_government_proposal(). Süresi GameRules.FORMATION_TIMEOUT.
##   4) Teklif meclise gelir, tüm partiler evet/hayır oylar
##      (GameRules.VOTE_TIMEOUT; oy vermeyen ÇEKİMSER sayılır).
##      REDDEDİLME KOŞULLARI:
##        - HAYIR oylarının milletvekili toplamı salt çoğunluğu (%50 + 1)
##          geçerse (hükümet salt çoğunluğu OLMADAN da güvenoyu alabilir), ya da
##        - KOALİSYON RIZASI: kendisine görev önerilen bir ORTAK açıkça EVET
##          demezse. Kimse rızası olmadan hükümete sokulamaz.
##      Sonuç kesinleştiği an (kalan oylar değiştiremeyecekse) beklemeden açıklanır.
##   5) Reddedilirse ya da süre dolarsa aynı partinin MAX_ATTEMPTS hakkı vardır;
##      hepsi biterse görev bir sonraki en büyük partiye geçer. Kimse kuramazsa
##      faz IDLE olur ve tur sonunda ERKEN SEÇİM yapılır (bkz. CardManager).
##
## GENSORU: Hükümetin toplam milletvekili salt çoğunluğun altına düşerse
## gensoru kartı desteye girer. Kabul edilirse hükümet düşer ve kurma aşaması
## baştan başlar.

signal phase_changed
signal government_changed
signal proposal_changed
signal proposal_resolved(accepted: bool, kind: String, proposer_id: int)
signal scores_changed

enum Phase { IDLE, FORMING, VOTING, GOVERNING }

const KIND_GOVERNMENT := "government"
const KIND_CENSURE := "censure"
## Bir partinin hükümet kurma hakkı (3. teklif de geçmezse sıra devreder).
const MAX_ATTEMPTS := 3

var phase: int = Phase.IDLE
## Koltuk sayısına göre BÜYÜKTEN KÜÇÜĞE sıralı peer_id listesi.
var mandate_order: Array = []
var mandate_index: int = 0
var attempts_used: int = 0

# --- Aktif meclis teklifi ---
var proposal_kind: String = ""
var proposal_peer_id: int = -1
var proposal_assignments: Dictionary = {}  # post_id -> peer_id
var votes: Dictionary = {}                 # peer_id -> bool (true = evet)
## Son teklif/süre sonucunun okunabilir açıklaması (UI'da gösterilir).
var last_resolution_reason: String = ""

# --- Kurulu hükümet ---
var government: Dictionary = {}            # post_id -> peer_id
var main_gov_peer_id: int = -1             # başbakanlığı tutan parti
var scores: Dictionary = {}                # peer_id -> int (biriken puan)

var state_version: int = 0

var _phase_time_left: float = 0.0
var _phase_deadline_ms: int = 0
var _last_blocked: bool = false

func _process(delta: float) -> void:
	if MultiplayerManager.room_code == "" or not MultiplayerManager.is_host:
		return
	tick(delta)

func _is_local_only() -> bool:
	return MultiplayerManager.room_code == ""

func _is_authority() -> bool:
	return _is_local_only() or MultiplayerManager.is_host

## Host: kurma/oylama süre sınırları. _process çağırır; testler doğrudan çağırabilir.
func tick(delta: float) -> void:
	if not _is_authority():
		return
	if phase != Phase.FORMING and phase != Phase.VOTING:
		return
	_phase_time_left -= delta
	if _phase_time_left > 0.0:
		return
	if phase == Phase.FORMING:
		last_resolution_reason = "%s hükümet kurma süresini doldurdu." % _party_name(mandate_peer_id())
		_fail_attempt()
		_push_state()
	else:
		_resolve_proposal()

# --- Sorgular ---------------------------------------------------------------

func mandate_peer_id() -> int:
	if mandate_index < 0 or mandate_index >= mandate_order.size():
		return -1
	return mandate_order[mandate_index]

func is_my_mandate() -> bool:
	return mandate_peer_id() == multiplayer.get_unique_id()

func attempts_left() -> int:
	return maxi(0, MAX_ATTEMPTS - attempts_used)

func current_attempt_number() -> int:
	return MAX_ATTEMPTS - attempts_left() + 1

func seats_of(peer_id: int) -> int:
	return int(CardManager.last_seats.get(peer_id, 0))

func total_seats() -> int:
	var total := 0
	for peer_id in CardManager.last_seats.keys():
		total += int(CardManager.last_seats[peer_id])
	return total

## Meclise girmiş (en az 1 vekili olan) partiler — oy kullanabilenler.
func voter_ids() -> Array:
	var ids: Array = []
	for peer_id in CardManager.last_seats.keys():
		if int(CardManager.last_seats[peer_id]) > 0:
			ids.append(peer_id)
	return ids

## Hükümette en az bir görevi olan partiler.
func government_party_ids() -> Array:
	return _unique_values(government)

## Aktif hükümet teklifinde görev önerilen, teklif sahibi DIŞINDAKİ partiler.
func proposal_partner_ids() -> Array:
	var ids := _unique_values(proposal_assignments)
	ids.erase(proposal_peer_id)
	return ids

func _unique_values(assignments: Dictionary) -> Array:
	var ids: Array = []
	for post_id in assignments.keys():
		var peer_id: int = int(assignments[post_id])
		if peer_id != -1 and not ids.has(peer_id):
			ids.append(peer_id)
	return ids

func government_seats() -> int:
	var total := 0
	for peer_id in government_party_ids():
		total += seats_of(peer_id)
	return total

## Hükümet salt çoğunluğa (%50 + 1) sahip mi? Değilse gensoru kartı desteye girer.
func has_majority() -> bool:
	if government.is_empty():
		return false
	return government_seats() * 2 > total_seats()

func has_government() -> bool:
	return not government.is_empty()

## Bu partinin hükümetteki görevlerinden gelen TUR BAŞINA puanı.
func round_points_of(peer_id: int) -> int:
	var points := 0
	for post_id in government.keys():
		if int(government[post_id]) == peer_id:
			points += GovernmentPresets.post_points(post_id)
	return points

func score_of(peer_id: int) -> int:
	return int(scores.get(peer_id, 0))

func is_voting() -> bool:
	return phase == Phase.VOTING

func has_voted(peer_id: int) -> bool:
	return votes.has(peer_id)

func my_vote() -> Variant:
	return votes.get(multiplayer.get_unique_id(), null)

## Kurma/oylama aşamasında kalan süre (saniye); diğer aşamalarda 0.
func phase_seconds_left() -> float:
	if phase != Phase.FORMING and phase != Phase.VOTING:
		return 0.0
	if _is_authority():
		return maxf(0.0, _phase_time_left)
	return maxf(0.0, float(_phase_deadline_ms - Time.get_ticks_msec()) / 1000.0)

func _party_name(peer_id: int) -> String:
	return PartyManager.parties.get(peer_id, {}).get("name", "?")

# --- Host tarafı: aşama yönetimi -------------------------------------------

func _set_phase(new_phase: int) -> void:
	phase = new_phase
	match new_phase:
		Phase.FORMING:
			_phase_time_left = GameRules.FORMATION_TIMEOUT
		Phase.VOTING:
			_phase_time_left = GameRules.VOTE_TIMEOUT
		_:
			_phase_time_left = 0.0

## Seçim sonuçlandığı an host çağırır: görev sırasını kurar ve birinci
## partiye hükümet kurma görevini verir.
func start_formation() -> void:
	if not _is_authority():
		return
	government.clear()
	main_gov_peer_id = -1
	_build_mandate_order()
	mandate_index = 0
	attempts_used = 0
	_clear_proposal()
	last_resolution_reason = ""
	_set_phase(Phase.FORMING if not mandate_order.is_empty() else Phase.IDLE)
	_push_state()

## Tur bitiminde host çağırır: görevdeki partilere görev puanlarını yazar.
## Puan BİRİKİR — iktidarda kalmak kazandırır, düşürmek engeller.
func award_round_scores() -> void:
	if not _is_authority() or government.is_empty():
		return
	for peer_id in government_party_ids():
		scores[peer_id] = score_of(peer_id) + round_points_of(peer_id)
	_push_state()

func _build_mandate_order() -> void:
	mandate_order = voter_ids()
	# Milletvekili sayısına göre azalan; eşitlikte oy oranı, o da eşitse
	# peer_id — sıralama her istemcide AYNI çıksın diye tam deterministik.
	mandate_order.sort_custom(func(a, b):
		var sa := seats_of(a)
		var sb := seats_of(b)
		if sa != sb:
			return sa > sb
		var va: float = float(CardManager.last_vote_shares.get(a, 0.0))
		var vb: float = float(CardManager.last_vote_shares.get(b, 0.0))
		if not is_equal_approx(va, vb):
			return va > vb
		return a < b
	)

func _clear_proposal() -> void:
	proposal_kind = ""
	proposal_peer_id = -1
	proposal_assignments = {}
	votes = {}

## Görevlinin bir teklif hakkı yanar (red ya da süre dolması); haklar biterse
## görev sıradaki partiye geçer.
func _fail_attempt() -> void:
	attempts_used += 1
	if attempts_used >= MAX_ATTEMPTS:
		attempts_used = 0
		mandate_index += 1
	_clear_proposal()
	_set_phase(Phase.FORMING if mandate_index < mandate_order.size() else Phase.IDLE)
	if phase == Phase.IDLE:
		last_resolution_reason += " Hükümet kurulamadı — tur sonunda erken seçim."

## Oyun bittiğinde CardManager çağırır: açık teklif kapanır, hükümet gösterim
## için korunur.
func end_game() -> void:
	if not _is_authority():
		return
	_clear_proposal()
	_set_phase(Phase.IDLE)
	_push_state()

# --- Teklifler --------------------------------------------------------------

## Hükümet kurma görevlisi, görev dağılımını meclise sunar.
## assignments: post_id -> peer_id (boş bırakılan görev olmamalı).
func submit_government_proposal(assignments: Dictionary) -> void:
	if _is_authority():
		_apply_government_proposal(multiplayer.get_unique_id(), assignments)
	else:
		_request_government_proposal.rpc_id(1, assignments)

## Gensoru teklifi (kart oynanınca CardManager çağırır).
func submit_censure(peer_id: int) -> void:
	if not _is_authority():
		return
	if phase != Phase.GOVERNING or government.is_empty():
		return
	proposal_kind = KIND_CENSURE
	proposal_peer_id = peer_id
	proposal_assignments = {}
	votes = {}
	_set_phase(Phase.VOTING)
	_push_state()

func cast_vote(approve: bool) -> void:
	if _is_authority():
		_apply_vote(multiplayer.get_unique_id(), approve)
	else:
		_request_vote.rpc_id(1, approve)

## İstemci: tam durumu host'tan ister (heartbeat sürüm uyuşmazlığında).
func request_full_sync() -> void:
	if _is_authority():
		return
	_request_full_sync.rpc_id(1)

# --- Host tarafı: uygulama --------------------------------------------------

func _apply_government_proposal(peer_id: int, assignments: Dictionary) -> void:
	if CardManager.game_finished or phase != Phase.FORMING or peer_id != mandate_peer_id():
		return
	if not _is_valid_assignment(assignments):
		return
	proposal_kind = KIND_GOVERNMENT
	proposal_peer_id = peer_id
	proposal_assignments = assignments.duplicate(true)
	votes = {}
	_set_phase(Phase.VOTING)
	_push_state()

## Her görev dolu olmalı ve sadece meclise girmiş partilere verilebilmeli.
## Teklif sahibi hükümette olmak zorunda.
func _is_valid_assignment(assignments: Dictionary) -> bool:
	var valid_voters := voter_ids()
	for post in GovernmentPresets.POSTS:
		var post_id: String = post["id"]
		if not assignments.has(post_id):
			return false
		if not valid_voters.has(int(assignments[post_id])):
			return false
	return _unique_values(assignments).has(mandate_peer_id())

func _apply_vote(peer_id: int, approve: bool) -> void:
	if phase != Phase.VOTING:
		return
	if not voter_ids().has(peer_id):
		return
	if votes.has(peer_id):
		return  # oy değiştirilemez
	votes[peer_id] = approve
	if votes.size() >= voter_ids().size() or _outcome_decided():
		_resolve_proposal()
	else:
		_push_state()

func _no_seats() -> int:
	var no_seats := 0
	for peer_id in votes.keys():
		if not bool(votes[peer_id]):
			no_seats += seats_of(peer_id)
	return no_seats

## Kalan oylar sonucu artık değiştiremiyor mu?
func _outcome_decided() -> bool:
	var total := total_seats()
	var no_seats := _no_seats()
	if no_seats * 2 > total:
		return true  # red kesin
	if proposal_kind == KIND_GOVERNMENT:
		for partner in proposal_partner_ids():
			if not votes.has(partner):
				return false  # ortağın rızası bekleniyor
			if not bool(votes[partner]):
				return true  # ortak reddetti
	var undecided := 0
	for peer_id in voter_ids():
		if not votes.has(peer_id):
			undecided += seats_of(peer_id)
	return (no_seats + undecided) * 2 <= total  # kabul kesin

func _resolve_proposal() -> void:
	# Salt çoğunluk = %50 + 1. Bu eşiği AŞAN "hayır" teklifi düşürür; oy
	# vermeyenler çekimser sayılır.
	var rejected: bool = _no_seats() * 2 > total_seats()
	var kind := proposal_kind
	var proposer := proposal_peer_id
	var reason := "Meclis çoğunluğu HAYIR dedi." if rejected else ""
	if kind == KIND_GOVERNMENT and not rejected:
		for partner in proposal_partner_ids():
			if not (votes.has(partner) and bool(votes[partner])):
				rejected = true
				reason = "%s koalisyona girmeyi kabul etmedi." % _party_name(partner)
				break
	var accepted := not rejected

	if kind == KIND_GOVERNMENT:
		if accepted:
			government = proposal_assignments.duplicate(true)
			main_gov_peer_id = int(government.get(GovernmentPresets.POST_PM, -1))
			_clear_proposal()
			_set_phase(Phase.GOVERNING)
			last_resolution_reason = "%s hükümeti güvenoyu aldı." % _party_name(main_gov_peer_id)
		else:
			last_resolution_reason = "Hükümet teklifi reddedildi: " + reason
			_fail_attempt()
	else: # KIND_CENSURE
		if accepted:
			# Hükümet düştü: kurma aşaması baştan başlar.
			government.clear()
			main_gov_peer_id = -1
			_build_mandate_order()
			mandate_index = 0
			attempts_used = 0
			_clear_proposal()
			_set_phase(Phase.FORMING if not mandate_order.is_empty() else Phase.IDLE)
			last_resolution_reason = "Gensoru kabul edildi, hükümet düştü."
		else:
			_clear_proposal()
			_set_phase(Phase.GOVERNING)
			last_resolution_reason = "Gensoru reddedildi, hükümet görevde."

	_push_state()
	if not _is_local_only():
		_notify_resolved.rpc(accepted, kind, proposer)
	proposal_resolved.emit(accepted, kind, proposer)

## Host: oyun sırasında ayrılan oyuncuyu hükümet süreçlerinden çıkarır.
## CardManager.remove_player, oyuncunun vekillerini meclisten sildikten SONRA
## çağırır (voter_ids/total_seats zaten güncel).
func remove_player(peer_id: int) -> void:
	if not _is_authority():
		return
	votes.erase(peer_id)

	# 1) Başbakanlığı tutan parti ayrıldıysa hükümet düşer; diğer görevleri
	#    ana iktidar partisine devredilir.
	if government.values().has(peer_id):
		if main_gov_peer_id == peer_id:
			government.clear()
			main_gov_peer_id = -1
			_clear_proposal()
			_build_mandate_order()
			mandate_index = 0
			attempts_used = 0
			last_resolution_reason = "%s ayrıldı, hükümet düştü." % _party_name(peer_id)
			_set_phase(Phase.FORMING if not mandate_order.is_empty() else Phase.IDLE)
			_push_state()
			return
		for post_id in government.keys():
			if int(government[post_id]) == peer_id:
				government[post_id] = main_gov_peer_id

	# 2) Görev sırası.
	var idx := mandate_order.find(peer_id)
	if idx != -1:
		mandate_order.remove_at(idx)
		if idx < mandate_index:
			mandate_index -= 1
		elif idx == mandate_index:
			attempts_used = 0
			if phase == Phase.FORMING:
				_set_phase(Phase.FORMING)  # yeni görevliye tam süre

	# 3) Açık teklif.
	if phase == Phase.VOTING:
		var broken := proposal_peer_id == peer_id \
			or (proposal_kind == KIND_GOVERNMENT and proposal_assignments.values().has(peer_id))
		if broken:
			var was_government := proposal_kind == KIND_GOVERNMENT
			_clear_proposal()
			if was_government:
				_set_phase(Phase.FORMING if mandate_index < mandate_order.size() else Phase.IDLE)
			else:
				_set_phase(Phase.GOVERNING if has_government() else Phase.IDLE)
			last_resolution_reason = "%s ayrıldığı için teklif düştü." % _party_name(peer_id)
		elif votes.size() >= voter_ids().size() or _outcome_decided():
			_resolve_proposal()
			return
	elif phase == Phase.FORMING and mandate_index >= mandate_order.size():
		_set_phase(Phase.IDLE)

	_push_state()

# --- Senkronizasyon ---------------------------------------------------------

func _pack_state() -> Dictionary:
	return {
		"version": state_version,
		"phase": phase,
		"mandate_order": mandate_order,
		"mandate_index": mandate_index,
		"attempts_used": attempts_used,
		"proposal_kind": proposal_kind,
		"proposal_peer_id": proposal_peer_id,
		"proposal_assignments": proposal_assignments,
		"votes": votes,
		"government": government,
		"main_gov_peer_id": main_gov_peer_id,
		"scores": scores,
		"phase_time_left": _phase_time_left,
		"reason": last_resolution_reason,
	}

## Host tarafı: durumu herkese yayınlar VE kendi sinyallerini doğrudan atar.
## Tur akışını engelleyen bir aşamadan çıkıldıysa CardManager'a haber verir.
func _push_state() -> void:
	state_version += 1
	if not _is_local_only():
		_sync_state.rpc(_pack_state())
	_emit_all()
	var blocked := phase == Phase.FORMING or phase == Phase.VOTING
	var was_blocked := _last_blocked
	_last_blocked = blocked
	if was_blocked and not blocked:
		CardManager.on_block_state_changed()

func _emit_all() -> void:
	phase_changed.emit()
	government_changed.emit()
	proposal_changed.emit()
	scores_changed.emit()

@rpc("any_peer", "reliable")
func _request_government_proposal(assignments: Dictionary) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_government_proposal(multiplayer.get_remote_sender_id(), assignments)

@rpc("any_peer", "reliable")
func _request_vote(approve: bool) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_vote(multiplayer.get_remote_sender_id(), approve)

@rpc("any_peer", "reliable")
func _request_full_sync() -> void:
	if not MultiplayerManager.is_host:
		return
	_sync_state.rpc_id(multiplayer.get_remote_sender_id(), _pack_state())

@rpc("authority", "reliable")
func _sync_state(state: Dictionary) -> void:
	state_version = int(state["version"])
	phase = int(state["phase"])
	mandate_order = state["mandate_order"]
	mandate_index = int(state["mandate_index"])
	attempts_used = int(state["attempts_used"])
	proposal_kind = str(state["proposal_kind"])
	proposal_peer_id = int(state["proposal_peer_id"])
	proposal_assignments = state["proposal_assignments"]
	votes = state["votes"]
	government = state["government"]
	main_gov_peer_id = int(state["main_gov_peer_id"])
	scores = state["scores"]
	_phase_deadline_ms = Time.get_ticks_msec() + int(float(state["phase_time_left"]) * 1000.0)
	last_resolution_reason = str(state["reason"])
	_emit_all()

@rpc("authority", "reliable")
func _notify_resolved(accepted: bool, kind: String, proposer_id: int) -> void:
	proposal_resolved.emit(accepted, kind, proposer_id)

## Yeni oyun başlarken host çağırır.
func reset() -> void:
	if not _is_authority():
		return
	_set_phase(Phase.IDLE)
	mandate_order = []
	mandate_index = 0
	attempts_used = 0
	government = {}
	main_gov_peer_id = -1
	scores = {}
	last_resolution_reason = ""
	_last_blocked = false
	_clear_proposal()
	_push_state()
