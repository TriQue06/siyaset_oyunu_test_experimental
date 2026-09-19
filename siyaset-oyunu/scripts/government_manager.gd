extends Node
## Autoload. Hükümet kurma görevi, meclis teklifleri (hükümet, gensoru, YASA)
## ve oylama.
##
## AKIŞ
##   1) Seçim sonuçlanır  -> start_formation() (host çağırır)
##   2) En çok MİLLETVEKİLİ olan parti hükümet kurma görevini alır
##      (oy oranına göre DEĞİL — bkz. _build_mandate_order).
##   3) Görevli, GovernmentFormation sahnesinde görevleri paylaştırıp teklif
##      eder -> submit_government_proposal(). Süresi GameRules.FORMATION_TIMEOUT.
##   4) Teklif İKİ AŞAMADA oylanır. Teklif sahibinin oyu baştan EVET'tir.
##      1. KOALİSYON GÖRÜŞMESİ: sadece görev önerilen ORTAKLAR oy verir. Biri
##         bile EVET demezse (çekimser/süre dolması dahil) teklif reddedilir ve
##         bir teklif hakkı yanar. Ortak yoksa (tek parti) bu aşama atlanır.
##      2. MECLİS OYLAMASI: tüm partiler EVET / ÇEKİMSER / HAYIR oylar (ortakların
##         oyu 1. aşamadan EVET gelir). HAYIR oylarının milletvekili toplamı
##         salt çoğunluğu (%50 + 1) geçerse reddedilir — hükümet salt çoğunluğu
##         OLMADAN da güvenoyu alabilir.
##      Her aşama HERKES oy verene kadar (ya da GameRules.VOTE_TIMEOUT dolana
##      kadar; oy vermeyen ÇEKİMSER sayılır) sürer, erken bitmez.
##   5) Reddedilirse ya da süre dolarsa aynı partinin MAX_ATTEMPTS hakkı vardır;
##      hepsi biterse görev bir sonraki en büyük partiye geçer. Kimse kuramazsa
##      faz IDLE olur ve tur sonunda ERKEN SEÇİM yapılır (bkz. CardManager).
##
## GENSORU: Hükümetin toplam milletvekili salt çoğunluğun altına düşerse muhalefet
## gensoru hamlesi yapabilir. Gensoruyu verenin oyu baştan EVET'tir. EVET vekilleri HAYIR'dan fazlaysa kabul edilir (çekimserler
## sayılmaz), hükümet düşer ve kurma aşaması
## baştan başlar.
##
## YASA: Yasa kartı oynanınca meclise gelir (hükümet olsun olmasın, kurma
## aşaması dışında). EVET milletvekilleri HAYIR'dan fazlaysa geçer (çekimserler
## sayılmaz). Kamuoyu sonuçlarını CardManager.apply_law_result uygular.

signal phase_changed
signal government_changed
signal proposal_changed
signal proposal_resolved(accepted: bool, kind: String, proposer_id: int)
signal scores_changed
## Koalisyondan çekilme gibi herkese duyurulacak olaylar.
signal coalition_changed(text: String)

enum Phase { IDLE, FORMING, VOTING, GOVERNING }

const KIND_GOVERNMENT := "government"
const KIND_CENSURE := "censure"
const KIND_LAW := "law"
## Bir partinin hükümet kurma hakkı (3. teklif de geçmezse sıra devreder).
const MAX_ATTEMPTS := 3
## Hükümet teklifinin oylama aşamaları (bkz. AKIŞ 4).
const STAGE_COALITION := 1
const STAGE_PARLIAMENT := 2

## Oy değerleri (votes sözlüğünde saklanan).
const VOTE_YES := 1
const VOTE_ABSTAIN := 0
const VOTE_NO := -1

## bool (eski çağrılar: true = evet) ya da int oy değerini VOTE_* değerine çevirir.
static func normalize_vote(value) -> int:
	if value is bool:
		return VOTE_YES if value else VOTE_NO
	return clampi(int(value), VOTE_NO, VOTE_YES)

static func vote_text(value) -> String:
	match normalize_vote(value):
		VOTE_YES:
			return "EVET"
		VOTE_NO:
			return "HAYIR"
	return "ÇEKİMSER"

var phase: int = Phase.IDLE
## Koltuk sayısına göre BÜYÜKTEN KÜÇÜĞE sıralı peer_id listesi.
var mandate_order: Array = []
var mandate_index: int = 0
var attempts_used: int = 0

# --- Aktif meclis teklifi ---
var proposal_kind: String = ""
var proposal_peer_id: int = -1
var proposal_assignments: Dictionary = {}  # post_id -> peer_id
var votes: Dictionary = {}                 # peer_id -> VOTE_YES / VOTE_ABSTAIN / VOTE_NO
## Yasa teklifinde: yasa kartı türü ve teklif geldiği andaki hükümet partileri.
var proposal_law: String = ""
var proposal_gov_ids: Array = []
## Hükümet teklifinin aşaması (STAGE_*); diğer tekliflerde 0.
var proposal_stage: int = 0
## Son teklif/süre sonucunun okunabilir açıklaması (UI'da gösterilir).
var last_resolution_reason: String = ""

# --- Kurulu hükümet ---
var government: Dictionary = {}            # post_id -> peer_id
var main_gov_peer_id: int = -1             # başbakanlığı tutan parti
var scores: Dictionary = {}                # peer_id -> int (biriken puan)
## Bir ortak çekildi ve ana iktidar partisi yalnız kalabilir (bkz. ABANDONED_FALL_PENALTY).
var abandoned: bool = false
## Sadece host (botların kararı için): mevcut hükümetin kurulduğu ve son
## gensorunun verildiği tur.
var formed_round: int = 0
var censure_round: int = 0

var state_version: int = 0

var _phase_time_left: float = 0.0
var _phase_deadline_ms: int = 0
var _last_blocked: bool = false
## Herkes oy verince sonuç bu kadar saniye bekletilir: kimin ne verdiği mecliste
## (koltuk renkleri, profil etiketleri) görünsün. Testler 0 yapar.
var result_hold_seconds: float = 2.5
var _resolving: bool = false
var _resolve_left: float = 0.0

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
	if _resolving:
		_resolve_left -= delta
		if _resolve_left <= 0.0:
			_resolving = false
			_resolve_proposal()
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

## Hükümet teklifi koalisyon görüşmesi (1. aşama) aşamasında mı?
func is_coalition_stage() -> bool:
	return phase == Phase.VOTING and proposal_kind == KIND_GOVERNMENT and proposal_stage == STAGE_COALITION

## Açık oylamada şu an oy verebilecek partiler: koalisyon görüşmesinde sadece
## ortaklar, diğer her durumda meclisteki herkes.
func eligible_voter_ids() -> Array:
	if proposal_kind == KIND_GOVERNMENT and proposal_stage == STAGE_COALITION:
		return proposal_partner_ids()
	return voter_ids()

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

## Şu an bir yasa meclise getirilebilir mi? (Meclis oluşmuş, kurma/oylama yok.)
func can_submit_law() -> bool:
	return (phase == Phase.GOVERNING or phase == Phase.IDLE) and not voter_ids().is_empty()

## Kurma/oylama aşamasında kalan süre (saniye); diğer aşamalarda 0.
func phase_seconds_left() -> float:
	if phase != Phase.FORMING and phase != Phase.VOTING:
		return 0.0
	if _is_authority():
		return maxf(0.0, _phase_time_left)
	return maxf(0.0, float(_phase_deadline_ms - Time.get_ticks_msec()) / 1000.0)

func _party_name(peer_id: int) -> String:
	return PartyManager.parties.get(peer_id, {}).get("name", "?")

## Aktif oylamadaki EVET ve HAYIR milletvekili toplamları (çekimserler hariç).
func vote_seat_totals() -> Vector2i:
	var yes := 0
	var no := 0
	for peer_id in votes.keys():
		match int(votes[peer_id]):
			VOTE_YES:
				yes += seats_of(peer_id)
			VOTE_NO:
				no += seats_of(peer_id)
	return Vector2i(yes, no)

func abstain_seats() -> int:
	var total := 0
	for peer_id in votes.keys():
		if int(votes[peer_id]) == VOTE_ABSTAIN:
			total += seats_of(peer_id)
	return total

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
## extra_seconds: kurma süresine eklenir (seçim gecesi yayını izlenirken süre yanmasın).
func start_formation(extra_seconds: float = 0.0) -> void:
	if not _is_authority():
		return
	government.clear()
	main_gov_peer_id = -1
	_build_mandate_order()
	mandate_index = 0
	attempts_used = 0
	_clear_proposal()
	last_resolution_reason = ""
	abandoned = false
	_set_phase(Phase.FORMING if not mandate_order.is_empty() else Phase.IDLE)
	if phase == Phase.FORMING:
		_phase_time_left += extra_seconds
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
	proposal_law = ""
	proposal_gov_ids = []
	proposal_stage = 0
	votes = {}
	_resolving = false

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
	# Gensoruyu veren kendi önergesine EVET demiş sayılır.
	votes = {peer_id: VOTE_YES}
	censure_round = CardManager.round_number
	_set_phase(Phase.VOTING)
	if _all_voted():
		_begin_resolution()
	else:
		_push_state()

## Bu parti koalisyondan çekilebilir mi? (Hükümette, ana iktidar partisi
## değil, oylama/kurma sürmüyor.)
func can_withdraw(peer_id: int) -> bool:
	return phase == Phase.GOVERNING and peer_id != main_gov_peer_id and government_party_ids().has(peer_id)

## Küçük ortak koalisyondan çekilir: görevleri ana iktidar partisine geçer,
## kendisi WITHDRAW_SCORE_PENALTY puan kaybeder. Hükümet salt çoğunluğu
## kaybederse gensoru desteye girer; ana parti yalnız kalıp gensoruyla düşerse
## ağır ceza alır (bkz. _resolve_proposal).
func withdraw_from_coalition() -> void:
	if _is_authority():
		_apply_withdraw(multiplayer.get_unique_id())
	else:
		_request_withdraw.rpc_id(1)

func _apply_withdraw(peer_id: int) -> void:
	if not can_withdraw(peer_id):
		return
	for post_id in government.keys():
		if int(government[post_id]) == peer_id:
			government[post_id] = main_gov_peer_id
	scores[peer_id] = score_of(peer_id) - GovernmentPresets.WITHDRAW_SCORE_PENALTY
	abandoned = true
	var alone := government_party_ids().size() == 1
	var text := "%s koalisyondan çekildi (−%d puan).%s%s" % [
		_party_name(peer_id), GovernmentPresets.WITHDRAW_SCORE_PENALTY,
		(" %s hükümeti tek başına kaldı." % _party_name(main_gov_peer_id)) if alone else "",
		" Hükümet salt çoğunluğu kaybetti!" if not has_majority() else ""]
	last_resolution_reason = text
	_push_state()
	if not _is_local_only():
		_notify_coalition.rpc(text)
	coalition_changed.emit(text)

@rpc("any_peer", "reliable")
func _request_withdraw() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_withdraw(multiplayer.get_remote_sender_id())

@rpc("authority", "reliable")
func _notify_coalition(text: String) -> void:
	coalition_changed.emit(text)

## Yasa teklifi (yasa kartı oynanınca CardManager çağırır).
func submit_law(peer_id: int, law_type: String) -> bool:
	if not _is_authority() or not can_submit_law() or not CardPresets.is_law_card(law_type):
		return false
	_clear_proposal()
	proposal_kind = KIND_LAW
	proposal_peer_id = peer_id
	proposal_law = law_type
	proposal_gov_ids = government_party_ids()
	# Yasayı getiren kendi yasasına EVET demiş sayılır.
	votes = {peer_id: VOTE_YES}
	_set_phase(Phase.VOTING)
	if _all_voted():
		_begin_resolution()
	else:
		_push_state()
	return true

## choice: VOTE_YES / VOTE_ABSTAIN / VOTE_NO (bool da kabul edilir).
func cast_vote(choice) -> void:
	var value := normalize_vote(choice)
	if _is_authority():
		_apply_vote(multiplayer.get_unique_id(), value)
	else:
		_request_vote.rpc_id(1, value)

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
	# Teklif sahibi kendi hükümetini oylamaz: oyu baştan EVET.
	votes = {peer_id: VOTE_YES}
	proposal_stage = STAGE_COALITION if not proposal_partner_ids().is_empty() else STAGE_PARLIAMENT
	_set_phase(Phase.VOTING)
	if _all_voted():
		_begin_resolution()
	else:
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

## Oylama, sonuç önceden belli olsa bile HERKES oy verene (ya da süre
## dolana) kadar sürer — herkes tavrını ortaya koyabilsin diye.
func _apply_vote(peer_id: int, choice) -> void:
	if phase != Phase.VOTING:
		return
	if not eligible_voter_ids().has(peer_id):
		return
	if votes.has(peer_id):
		return  # oy değiştirilemez
	# Koalisyon görüşmesinde ortak ya EVET ya HAYIR der; çekimser olamaz.
	if is_coalition_stage() and normalize_vote(choice) == VOTE_ABSTAIN:
		return
	votes[peer_id] = normalize_vote(choice)
	if not _all_voted():
		_push_state()
	else:
		_begin_resolution()

## Herkes oy verdi: sonuç result_hold_seconds bekletilip açıklanır.
func _begin_resolution() -> void:
	if result_hold_seconds <= 0.0:
		_resolve_proposal()
	else:
		_resolving = true
		_resolve_left = result_hold_seconds
		_push_state()

## Herkes oy verdi, sonuç birazdan açıklanacak (bkz. result_hold_seconds).
func is_resolving() -> bool:
	return phase == Phase.VOTING and _resolving

func _all_voted() -> bool:
	for peer_id in eligible_voter_ids():
		if not votes.has(peer_id):
			return false
	return true

func _resolve_proposal() -> void:
	var kind := proposal_kind
	var proposer := proposal_peer_id
	var totals := vote_seat_totals()

	if kind == KIND_LAW:
		# Çekimserler sayılmaz: EVET milletvekili HAYIR'dan fazlaysa geçer.
		var passed: bool = totals.x > totals.y
		var law_type := proposal_law
		var gov_ids := proposal_gov_ids.duplicate()
		var votes_copy := votes.duplicate()
		_clear_proposal()
		_set_phase(Phase.GOVERNING if has_government() else Phase.IDLE)
		last_resolution_reason = "%s %s (EVET %d – HAYIR %d)." % [
			CardPresets.card_title(law_type), "kabul edildi" if passed else "reddedildi", totals.x, totals.y]
		if passed:
			# Kabul edilen yasa getirene ciddi puan yazar; hükümetinki daha çok.
			var points: int = CardManager.law_pass_score(gov_ids.has(proposer))
			scores[proposer] = score_of(proposer) + points
			last_resolution_reason += " %s +%d puan." % [_party_name(proposer), points]
		# Kamuoyu sonuçları ÖNCE: fazın açılması ertelenmiş bir tur sonunu (ve
		# seçimi) tetikleyebilir, seçim bu sonuçları görmeli.
		CardManager.apply_law_result(proposer, law_type, votes_copy, passed, gov_ids)
		_push_state()
		if not _is_local_only():
			_notify_resolved.rpc(passed, kind, proposer)
		proposal_resolved.emit(passed, kind, proposer)
		return

	if kind == KIND_GOVERNMENT and proposal_stage == STAGE_COALITION:
		_resolve_coalition_stage()
		return

	# Salt çoğunluk = %50 + 1. Bu eşiği AŞAN "hayır" teklifi düşürür; oy
	# vermeyenler çekimser sayılır.
	var rejected: bool = totals.y * 2 > total_seats()
	var reason := "Meclis çoğunluğu HAYIR dedi." if rejected else ""
	if kind == KIND_CENSURE:
		# Gensoru, EVET veren vekiller HAYIR verenlerden fazlaysa geçer (yasalardaki
		# gibi). Çekimser ve oy vermeyenler sayılmaz; eşitlikte hükümet görevde kalır.
		rejected = not (totals.x > totals.y)
	var accepted := not rejected

	if kind == KIND_GOVERNMENT:
		if accepted:
			government = proposal_assignments.duplicate(true)
			main_gov_peer_id = int(government.get(GovernmentPresets.POST_PM, -1))
			abandoned = false
			_clear_proposal()
			_set_phase(Phase.GOVERNING)
			formed_round = CardManager.round_number
			last_resolution_reason = "%s hükümeti güvenoyu aldı. Hükümet partileri +%d mana." % [
				_party_name(main_gov_peer_id), GameRules.GOVERNMENT_MANA_BONUS]
			CardManager.grant_government_mana(government_party_ids())
		else:
			last_resolution_reason = "Hükümet teklifi reddedildi: " + reason
			_fail_attempt()
	else: # KIND_CENSURE
		if accepted:
			# Hükümet düştü: kurma aşaması baştan başlar. Ortağı çekildiği için
			# tek başına kalıp düşen ana parti ağır puan kaybeder.
			var fall_note := ""
			if abandoned and government_party_ids().size() == 1 and main_gov_peer_id != -1:
				scores[main_gov_peer_id] = score_of(main_gov_peer_id) - GovernmentPresets.ABANDONED_FALL_PENALTY
				fall_note = " Yalnız kalan %s −%d puan." % [_party_name(main_gov_peer_id), GovernmentPresets.ABANDONED_FALL_PENALTY]
			abandoned = false
			government.clear()
			main_gov_peer_id = -1
			_build_mandate_order()
			mandate_index = 0
			attempts_used = 0
			_clear_proposal()
			_set_phase(Phase.FORMING if not mandate_order.is_empty() else Phase.IDLE)
			last_resolution_reason = "Gensoru kabul edildi, hükümet düştü." + fall_note
		else:
			_clear_proposal()
			_set_phase(Phase.GOVERNING)
			# Başarısız gensoru getiren partinin ulusal desteğine eksi yazar (puan tablosuna değil).
			CardManager.apply_censure_rejected(proposer)
			last_resolution_reason = "Gensoru reddedildi, hükümet görevde. %s ulusal destek %.0f." % [
				_party_name(proposer), PublicOpinion.CENSURE_REJECTED_NATIONAL]

	_push_state()
	if not _is_local_only():
		_notify_resolved.rpc(accepted, kind, proposer)
	proposal_resolved.emit(accepted, kind, proposer)

## 1. aşama (koalisyon görüşmesi) bitti: ortakların hepsi EVET dediyse teklif
## meclis oylamasına geçer; biri bile EVET demezse teklif hakkı yanar.
func _resolve_coalition_stage() -> void:
	var proposer := proposal_peer_id
	for partner in proposal_partner_ids():
		if int(votes.get(partner, VOTE_ABSTAIN)) != VOTE_YES:
			last_resolution_reason = "Koalisyon görüşmesi başarısız: %s ortak olmayı kabul etmedi." % _party_name(partner)
			_fail_attempt()
			_push_state()
			if not _is_local_only():
				_notify_resolved.rpc(false, KIND_GOVERNMENT, proposer)
			proposal_resolved.emit(false, KIND_GOVERNMENT, proposer)
			return
	proposal_stage = STAGE_PARLIAMENT
	_set_phase(Phase.VOTING)  # meclis oylamasına tam süre
	last_resolution_reason = "Ortaklar anlaştı: %s hükümeti meclis oylamasında." % _party_name(proposer)
	var text := last_resolution_reason
	if _all_voted():
		_begin_resolution()
	else:
		_push_state()
	if not _is_local_only():
		_notify_coalition.rpc(text)
	coalition_changed.emit(text)

## Host: oyun sırasında ayrılan oyuncuyu hükümet süreçlerinden çıkarır.
## CardManager.remove_player, oyuncunun vekillerini meclisten sildikten SONRA
## çağırır (voter_ids/total_seats zaten güncel).
func remove_player(peer_id: int) -> void:
	if not _is_authority():
		return
	votes.erase(peer_id)
	proposal_gov_ids.erase(peer_id)

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
		elif _all_voted():
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
		"proposal_law": proposal_law,
		"proposal_gov_ids": proposal_gov_ids,
		"proposal_stage": proposal_stage,
		"votes": votes,
		"government": government,
		"main_gov_peer_id": main_gov_peer_id,
		"scores": scores,
		"phase_time_left": _phase_time_left,
		"reason": last_resolution_reason,
		"abandoned": abandoned,
		"resolving": _resolving,
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
func _request_vote(choice: int) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_vote(multiplayer.get_remote_sender_id(), choice)

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
	proposal_law = str(state["proposal_law"])
	proposal_gov_ids = state["proposal_gov_ids"]
	proposal_stage = int(state.get("proposal_stage", 0))
	votes = state["votes"]
	government = state["government"]
	main_gov_peer_id = int(state["main_gov_peer_id"])
	scores = state["scores"]
	_phase_deadline_ms = Time.get_ticks_msec() + int(float(state["phase_time_left"]) * 1000.0)
	last_resolution_reason = str(state["reason"])
	abandoned = bool(state.get("abandoned", false))
	_resolving = bool(state.get("resolving", false))
	_emit_all()

@rpc("authority", "reliable")
func _notify_resolved(accepted: bool, kind: String, proposer_id: int) -> void:
	proposal_resolved.emit(accepted, kind, proposer_id)

## Yeni oyun başlarken host çağırır.
func reset() -> void:
	formed_round = 0
	censure_round = 0
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
	abandoned = false
	_last_blocked = false
	_clear_proposal()
	_push_state()
