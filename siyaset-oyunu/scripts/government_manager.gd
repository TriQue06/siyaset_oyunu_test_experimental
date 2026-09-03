extends Node
## Autoload. Hükümet kurma görevi, meclis teklifleri ve oylama.
##
## AKIŞ
##   1) Seçim sonuçlanır  -> start_formation() (host çağırır)
##   2) En çok MİLLETVEKİLİ olan parti hükümet kurma görevini alır
##      (oy oranına göre DEĞİL — bkz. _build_mandate_order).
##   3) Görevli oyuncu GovernmentFormation sahnesinde 10 görevi paylaştırıp
##      "teklifte bulun" der -> submit_government_proposal()
##   4) Teklif meclise gelir, tüm partiler evet/hayır oylar.
##      REDDEDİLME KOŞULU: HAYIR oylarının milletvekili toplamı, meclisin
##      salt çoğunluğunu (%50 + 1) geçmelidir. Yani hükümet, salt çoğunluğu
##      OLMADAN da güvenoyu alabilir; muhalefet dağınıksa geçer.
##   5) Reddedilirse aynı partinin MAX_ATTEMPTS hakkı vardır; hepsi biterse
##      görev bir sonraki en büyük partiye geçer.
##
## GENSORU: Hükümetin toplam milletvekili salt çoğunluğun altına düşerse
## (ör. "vekil çalma" kartlarıyla) gensoru kartı desteye girer. Kabul
## edilirse hükümet düşer ve kurma aşaması baştan başlar.

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

# --- Kurulu hükümet ---
var government: Dictionary = {}            # post_id -> peer_id
var main_gov_peer_id: int = -1             # başbakanlığı tutan parti
var scores: Dictionary = {}                # peer_id -> int (biriken puan)

func _is_local_only() -> bool:
	return MultiplayerManager.room_code == ""

func _is_authority() -> bool:
	return _is_local_only() or MultiplayerManager.is_host

# --- Sorgular ---------------------------------------------------------------

func mandate_peer_id() -> int:
	if mandate_index < 0 or mandate_index >= mandate_order.size():
		return -1
	return mandate_order[mandate_index]

func is_my_mandate() -> bool:
	return mandate_peer_id() == multiplayer.get_unique_id()

func attempts_left() -> int:
	return maxi(0, MAX_ATTEMPTS - attempts_used)

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
	var ids: Array = []
	for post_id in government.keys():
		var peer_id: int = government[post_id]
		if peer_id != -1 and not ids.has(peer_id):
			ids.append(peer_id)
	return ids

func government_seats() -> int:
	var total := 0
	for peer_id in government_party_ids():
		total += seats_of(peer_id)
	return total

## Hükümet salt çoğunluğa (%50 + 1) sahip mi? Değilse gensoru kartı desteye
## girer (bkz. CardManager._draw_pool).
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
		if government[post_id] == peer_id:
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

# --- Host tarafı: aşama yönetimi -------------------------------------------

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
	phase = Phase.FORMING if not mandate_order.is_empty() else Phase.IDLE
	_push_state()

## Tur bitiminde host çağırır: görevdeki partilere görev puanlarını yazar.
## Puan BİRİKİR — iktidarda kalmak kazandırır, düşürmek engeller. Oyunun
## "iktidar ayakta kalmaya, muhalefet indirmeye çalışır" gerilimi buradan gelir.
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

# --- Teklifler --------------------------------------------------------------

## Hükümet kurma görevlisi, görev dağılımını meclise sunar.
## assignments: post_id -> peer_id (boş bırakılan görev olmamalı).
func submit_government_proposal(assignments: Dictionary) -> void:
	if _is_local_only():
		_apply_government_proposal(multiplayer.get_unique_id(), assignments)
		return
	if MultiplayerManager.is_host:
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
	phase = Phase.VOTING
	_push_state()

func cast_vote(approve: bool) -> void:
	if _is_local_only():
		_apply_vote(multiplayer.get_unique_id(), approve)
		return
	if MultiplayerManager.is_host:
		_apply_vote(multiplayer.get_unique_id(), approve)
	else:
		_request_vote.rpc_id(1, approve)

# --- Host tarafı: uygulama --------------------------------------------------

func _apply_government_proposal(peer_id: int, assignments: Dictionary) -> void:
	if phase != Phase.FORMING or peer_id != mandate_peer_id():
		return
	if not _is_valid_assignment(assignments):
		return
	proposal_kind = KIND_GOVERNMENT
	proposal_peer_id = peer_id
	proposal_assignments = assignments.duplicate(true)
	votes = {}
	phase = Phase.VOTING
	_push_state()

## Her görev dolu olmalı ve sadece meclise girmiş partilere verilebilmeli.
func _is_valid_assignment(assignments: Dictionary) -> bool:
	var valid_voters := voter_ids()
	for post in GovernmentPresets.POSTS:
		var post_id: String = post["id"]
		if not assignments.has(post_id):
			return false
		var target: int = int(assignments[post_id])
		if not valid_voters.has(target):
			return false
	return true

func _apply_vote(peer_id: int, approve: bool) -> void:
	if phase != Phase.VOTING:
		return
	if not voter_ids().has(peer_id):
		return
	if votes.has(peer_id):
		return  # oy değiştirilemez
	votes[peer_id] = approve
	# Herkes oyunu kullandıysa sonucu hemen hesapla.
	if votes.size() >= voter_ids().size():
		_resolve_proposal()
	else:
		_push_state()

func _resolve_proposal() -> void:
	var no_seats := 0
	for peer_id in votes.keys():
		if not bool(votes[peer_id]):
			no_seats += seats_of(peer_id)
	# Salt çoğunluk = %50 + 1. Bu eşiği AŞAN "hayır" teklifi düşürür.
	var rejected: bool = no_seats * 2 > total_seats()
	var kind := proposal_kind
	var proposer := proposal_peer_id
	var accepted := not rejected

	if kind == KIND_GOVERNMENT:
		if accepted:
			government = proposal_assignments.duplicate(true)
			main_gov_peer_id = int(government.get(GovernmentPresets.POST_PM, -1))
			phase = Phase.GOVERNING
			_clear_proposal()
		else:
			attempts_used += 1
			if attempts_used >= MAX_ATTEMPTS:
				attempts_used = 0
				mandate_index += 1
			_clear_proposal()
			phase = Phase.FORMING if mandate_index < mandate_order.size() else Phase.IDLE
	else: # KIND_CENSURE
		if accepted:
			# Hükümet düştü: kurma aşaması baştan başlar.
			government.clear()
			main_gov_peer_id = -1
			_build_mandate_order()
			mandate_index = 0
			attempts_used = 0
			_clear_proposal()
			phase = Phase.FORMING if not mandate_order.is_empty() else Phase.IDLE
		else:
			_clear_proposal()
			phase = Phase.GOVERNING

	_push_state()
	_notify_resolved.rpc(accepted, kind, proposer)
	proposal_resolved.emit(accepted, kind, proposer)

# --- Senkronizasyon ---------------------------------------------------------

## Host tarafı: durumu herkese yayınlar VE kendi sinyallerini doğrudan atar
## (PartyManager/CardManager ile aynı desen — .rpc()'nin göndericide de
## çalışacağına güvenmiyoruz, bkz. card_manager.gd'deki not).
func _push_state() -> void:
	if _is_local_only():
		_emit_all()
		return
	_sync_state.rpc(phase, mandate_order, mandate_index, attempts_used,
		proposal_kind, proposal_peer_id, proposal_assignments, votes,
		government, main_gov_peer_id, scores)
	_emit_all()

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

@rpc("authority", "reliable")
func _sync_state(new_phase: int, new_order: Array, new_index: int, new_attempts: int,
		new_kind: String, new_proposer: int, new_assignments: Dictionary, new_votes: Dictionary,
		new_government: Dictionary, new_main: int, new_scores: Dictionary) -> void:
	phase = new_phase
	mandate_order = new_order
	mandate_index = new_index
	attempts_used = new_attempts
	proposal_kind = new_kind
	proposal_peer_id = new_proposer
	proposal_assignments = new_assignments
	votes = new_votes
	government = new_government
	main_gov_peer_id = new_main
	scores = new_scores
	_emit_all()

@rpc("authority", "reliable")
func _notify_resolved(accepted: bool, kind: String, proposer_id: int) -> void:
	proposal_resolved.emit(accepted, kind, proposer_id)

## Oyun yeniden başlarken (yeni oda / yeni oyun) host çağırır.
func reset() -> void:
	if not _is_authority():
		return
	phase = Phase.IDLE
	mandate_order = []
	mandate_index = 0
	attempts_used = 0
	government = {}
	main_gov_peer_id = -1
	scores = {}
	_clear_proposal()
	_push_state()
