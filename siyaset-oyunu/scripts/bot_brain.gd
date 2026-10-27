class_name BotBrain
extends RefCounted
## Botların KARARLARI (zamanlaması BotManager'da). Basit fayda puanı: her olası
## hamle oyunun kendi formülleriyle (grup uyumu, il gücü, miting riski, yasanın
## grup etkileri...) kabaca puanlanır, en yükseği seçilir.
##
## SEÇMEN GRUPLARI: botlar insanlarla AYNI açık bilgiyi kullanır (illerin
## seçmen grubu dağılımı herkese açık, kendi grup yakınlıkları). Bir hamlenin
## değeri çoğunlukla "ülke genelinde (vekil ağırlıklı) grup uyumum ne kadar
## artar" sorusudur (bkz. _appeal_gain): yasa ve miting yakınlıkları kalıcı
## değiştirir, toplantı seçime yakın turlarda değerlidir. Gizli bonus yok.
##
## HAMLE SINIRI YOK: BotManager, choose_action "pass" (turu bitir) diyene kadar
## hamle yaptırır. Her seçeneğin puanından para bedeli × FUNDS_VALUE düşülür;
## böylece bot ucuz ama değersiz hamlelere kasasını dağıtmaz, biriktirir.

## En iyi kartın puanı bunun altındaysa bot kart oynamaz (el doluysa oynar).
const PASS_THRESHOLD := 0.4
## Ana hamlelerin taban puanları.
const PASS_ACTION_SCORE := 0.7
## 1 milyon ¤ bedelin puan karşılığı (hamle puanından bedel × bu değer düşülür).
const FUNDS_VALUE := 0.03
## Grup uyumundaki 1 puanlık ülke geneli artışın ulusal puan karşılığı
## (SHARPNESS / EFFECT_PER_POINT: ikisi de oy ağırlığını aynı ölçüde büyütür).
const APPEAL_TO_POINTS := 1.4
## Yasa ve mitingin grup kazancı KALICIDIR (ulusal puan gibi her tur sönmez):
## bot onu birkaç turluk etki olarak değerlendirir.
const PERMANENT_GAIN_VALUE := 3.0
## Grup toplantısı puanı: uyum kazancı × bu + kriz grubuysa CRISIS_MEETING_BONUS.
const MEETING_VALUE := 1.5
const CRISIS_MEETING_BONUS := 1.2
## Yasanın taban puanı: yasa her tur meclisi durdurur, bot onu sadece gerçekten
## işe yarayacaksa sunsun (miting / il başkanlığı / kartlar öne geçebilsin).
const LAW_BASE_SCORE := 1.0
## Bot bir yasayı en fazla bu kadar turda bir sunar.
const LAW_EVERY_ROUNDS := 2
## Muhalefetteki bot, hükümete bu mesafeden yakınsa gensoruda çekimser kalır
## (mesafe: VoterGroups.party_distance, grup yakınlıkları arasında).
const CENSURE_LOYALTY_DISTANCE := 1.2
## Erken seçime EVET demek için gereken ulusal kamuoyu eşiği.
const EARLY_ELECTION_SUPPORT := 1.0
## Koalisyon ortağı, sandalye payına düşen makam puanının en az bu oranını ister.
const COALITION_FAIR_SHARE := 0.75
## Ortak olacak parti en az bu kadar makam puanı ister (1 bakanlık yetmez).
const COALITION_MIN_POINTS := 2
## Hükümete alınmayan bot, azınlık hükümetine ancak bu mesafeden yakınsa güvenoyu verir.
const MINORITY_TRUST_DISTANCE := 1.0

# --- BOT BECERİSİ ---------------------------------------------------------------
## Her bot farklı oynar: oyun başında bir BECERİ (0..1) alır.
##   %25 zayıf (0,10–0,45): sık sık yanlış/kısmen yanlış hamle, il seçimi kötü,
##   %50 orta (0,60–0,80), %25 usta (0,85–1,00): neredeyse kusursuz.
## Beceri düşükse her seçeneğin puanına gürültü eklenir (yanlış il, yanlış
## hamle sırası), ara sıra en iyi yerine rastgele geçerli bir hamle seçilir ya da
## yapacak iş varken tur boşa geçirilir. Testler `skill_variance = false` ile kapatır.
static var skill_variance := true
static var _skills: Dictionary = {}
const WEAK_BOT_CHANCE := 0.25
const STRONG_BOT_CHANCE := 0.25
const SKILL_NOISE := 1.6
const SKILL_BLUNDER := 0.45
const SKILL_IDLE := 0.5

static func skill(bot: int) -> float:
	if not skill_variance:
		return 1.0
	if not _skills.has(bot):
		var roll := randf()
		if roll < WEAK_BOT_CHANCE:
			_skills[bot] = randf_range(0.1, 0.45)
		elif roll < 1.0 - STRONG_BOT_CHANCE:
			_skills[bot] = randf_range(0.6, 0.8)
		else:
			_skills[bot] = randf_range(0.85, 1.0)
	return float(_skills[bot])

## Yeni oyunda beceriler yeniden dağıtılır.
static func reset_skills() -> void:
	_skills.clear()

## Beceriye göre puan gürültüsü (usta bot ~0).
static func _jitter(bot: int, scale: float = 1.0) -> float:
	var miss := 1.0 - skill(bot)
	if miss <= 0.0:
		return 0.0
	return randf_range(-1.0, 1.0) * miss * SKILL_NOISE * scale

# --- BOT BLOĞU ------------------------------------------------------------------
## Hükümeti bir İNSAN partisi kurduysa muhalefetteki botlar birleşir:
##   1. Hepsi vekil çalma kartlarını hükümetin ana partisine yöneltir; bloğun
##      en büyük botunu birinci parti yapmak (hükümet kurma yetkisi sırası
##      sandalyeye göre) ve hükümeti azınlığa düşürmek ek puan kazandırır.
##   2. Gensoruyu blok olarak hesaplar ve oylar (grup yakınlığı fark etmez).
##   3. Gensoru geçince kurulacak hükümette bloğun botları birbirini destekler
##      ve ortak olarak önce birbirini seçer.
## Blokta gensoru ile düşen hükümetin ardından kurma süreci işaretlenir.
const BLOC_STEAL_BONUS := 2.5
const BLOC_OVERTAKE_BONUS := 3.0
static var _bloc_forming := false

## Blok şu an hedefte mi (insan hükümeti var)?
static func bloc_active() -> bool:
	if not GovernmentManager.has_government():
		return false
	var main := GovernmentManager.main_gov_peer_id
	return main != -1 and not MultiplayerManager.is_bot(main)

## Muhalefetteki (vekili olan) botlar.
static func bloc_members() -> Array:
	var members: Array = []
	for peer_id in GovernmentManager.seated_party_ids():
		if MultiplayerManager.is_bot(peer_id) and not CardManager.is_government_party(peer_id):
			members.append(peer_id)
	return members

## Bloğun en büyük botu: gensorudan sonra hükümeti kuracak aday.
static func bloc_leader() -> int:
	var leader := -1
	for peer_id in bloc_members():
		if leader == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(leader):
			leader = peer_id
	return leader

## Gensoru sonrası kurma sürecinde blok dayanışması sürüyor mu?
static func _bloc_solidarity() -> bool:
	if GovernmentManager.has_government() or CardManager.round_number <= 1:
		_bloc_forming = false
	return _bloc_forming

## DOST mu? Aynı partideki ortak ya da KARDEŞ PARTİ (birlikte büyüyüp ayrılan
## bot partileri bir süre birbirine saldırmaz, birbirini destekler).
static func is_ally(bot: int, other: int) -> bool:
	if other == -1:
		return false
	return PartyManager.same_party(bot, other)

static func _groups(peer_id: int) -> Dictionary:
	return PartyManager.groups_of(CardManager.party_of(peer_id))

## İki partinin seçmen grubu profilleri arasındaki mesafe.
static func _distance(a: int, b: int) -> float:
	return VoterGroups.party_distance(_groups(a), _groups(b))

## İTTİFAK DOSTLUĞU (0.0.227): şu anki ya da son seçimdeki ittifak ortağı
## seçmen grupları açısından olduğundan YAKIN görülür (koalisyon, güvenoyu).
const FORMER_ALLY_DISTANCE_MULT := 0.6
static func _friend_distance(a: int, b: int) -> float:
	var d := _distance(a, b)
	if CardManager.are_allies(a, b) or CardManager.were_allies(a, b):
		d *= FORMER_ALLY_DISTANCE_MULT
	return d

static func _seats() -> Dictionary:
	return CardManager._province_seat_counts

static func _total_seats() -> float:
	return float(maxi(1, CardManager.TOTAL_SEATS))

## Partinin ülke geneli (vekil ağırlıklı) grup uyumu (0..100). Uyum her çiftte
## doğrusal olduğu için illerin ortalaması = ülkenin vekil ağırlıklı ortalama
## profiliyle hesaplanan uyum: iller tek tek dolaşılmaz (bot hızlı düşünür).
static func _national_appeal(affinities: Dictionary) -> float:
	var shares := _national_shares()
	var sum := 0.0
	for pair in VoterGroups.PAIR_IDS:
		var groups: Array = VoterGroups.PAIRS[pair]
		var s := float(shares.get(pair, 0.5))
		sum += s * float(affinities.get(groups[0], VoterGroups.AFFINITY_NEUTRAL)) \
			+ (1.0 - s) * float(affinities.get(groups[1], VoterGroups.AFFINITY_NEUTRAL))
	return sum / VoterGroups.PAIR_IDS.size()

## Çift -> ilk grubun ülke geneli (vekil ağırlıklı) payı. İl profilleri oyun
## boyunca sabit olduğu için profil tablosu değişene kadar önbellekte kalır.
static var _shares_cache: Dictionary = {}
static var _shares_key: Variant = null
static func _national_shares() -> Dictionary:
	var profiles := CardManager.province_voters()
	if is_same(profiles, _shares_key) and not _shares_cache.is_empty():
		return _shares_cache
	var seats := _seats()
	var result := {}
	for pair in VoterGroups.PAIR_IDS:
		result[pair] = VoterGroups.national_share(profiles, seats, VoterGroups.PAIRS[pair][0])
	_shares_cache = result
	_shares_key = profiles
	return result

## Kalıcı grup değişikliklerinin ([{"group", "amount"}]) partinin ülke geneli
## uyumuna etkisi (azalan getiri dahil, gerçek kuralla).
static func _appeal_gain(bot: int, changes: Array) -> float:
	var before := _groups(bot)
	var after := before.duplicate()
	var core: Array = PartyManager.data_of(CardManager.party_of(bot)).get("core", [])
	for change in changes:
		VoterGroups.apply_delta(after, String(change["group"]), float(change["amount"]), core)
	return _national_appeal(after) - _national_appeal(before)

static func _election_soon() -> bool:
	var next := GameRules.next_election_round(CardManager.round_number)
	return next != -1 and next - CardManager.round_number <= 1

# --- Ana hamle ------------------------------------------------------------------

## Kasası bol olan bot için para ucuzdur (birikip boşa durmasın), azsa değerlidir.
static func _funds_value(bot: int) -> float:
	return FUNDS_VALUE * clampf(40.0 / maxf(10.0, float(CardManager.funds_of(bot))), 0.2, 1.5)

## Dönüş: {"type": "card"} | {"type": "law", "law"} | {"type": "organization",
## "province"} | {"type": "miting", "province"} | {"type": "speech", "group"} |
## {"type": "pass"}
static func choose_action(bot: int) -> Dictionary:
	# MECLİS AKIŞI (0.0.231): açık aşama sırayla ya yapılır ya geçilir.
	var stage := CardManager.parliament_stage(bot)
	if stage != "":
		return _choose_parliament(bot, stage)
	# GRUP TOPLANTISI isteğe bağlı: değerliyse (seçime yakın / kriz) önce yapılır.
	if CardManager.needs_speech(bot):
		var meeting := choose_speech(bot)
		if not meeting.is_empty() and float(meeting["score"]) - GameRules.SPEECH_FUNDS_COST * _funds_value(bot) > PASS_ACTION_SCORE:
			return {"type": "speech", "group": meeting["group"]}
	# SEÇİMDEN OLUMLU ÇIKAN BOT KONGREYE GİDER (iktidarını tazeler).
	var pid := CardManager.party_of(bot)
	if CardManager.can_hold_congress(bot) and CardManager.bot_congress_due(pid):
		return {"type": "congress"}
	var candidates: Array = []
	var best := _choose_action_best(bot, candidates)
	var miss := 1.0 - skill(bot)
	if miss > 0.0 and not candidates.is_empty():
		# HATA: ara sıra en iyisi yerine rastgele geçerli bir hamle...
		if randf() < miss * SKILL_BLUNDER:
			return candidates[randi() % candidates.size()]
		# ...ya da yapacak iş varken turu boşa geçirmek.
		if String(best.get("type", "")) != "pass" and randf() < miss * SKILL_IDLE:
			return {"type": "pass"}
	return best

## MECLİS AŞAMASI KARARI: aşamanın hamlesi değerliyse yapılır, değilse aşama
## geçilir ({"type": "parl_pass", "stage"}). Yasa aşamasında grup yasası,
## vergi, anayasa ve erken seçim birbiriyle yarışır.
static func _choose_parliament(bot: int, stage: String) -> Dictionary:
	var skip := {"type": "parl_pass", "stage": stage}
	var funds_value := _funds_value(bot)
	match stage:
		"censure":
			if CardManager.can_censure(bot) and _censure_worth_it(bot):
				_bloc_forming = bloc_active()
				return {"type": "censure"}
		"speech":
			var meeting := choose_speech(bot)
			if not meeting.is_empty() and float(meeting["score"]) - GameRules.SPEECH_FUNDS_COST * funds_value > PASS_ACTION_SCORE:
				return {"type": "speech", "group": meeting["group"]}
		"law":
			var best := {}
			var best_score := PASS_ACTION_SCORE
			if CardManager.can_propose_law(bot):
				var law := _best_law(bot)
				var rested: bool = CardManager.round_number - int(CardManager.law_rounds.get(bot, -99)) >= LAW_EVERY_ROUNDS
				if rested and not law.is_empty() and CardManager.can_propose_law(bot, String(law["law"])):
					var score := float(law["score"]) - CardManager.law_funds_cost(bot, String(law["law"])) * funds_value + _jitter(bot)
					if score > best_score:
						best = {"type": "law", "law": law["law"]}
						best_score = score
			var tax := _best_tax_law(bot)
			if not tax.is_empty():
				var tax_score := float(tax["score"]) - GameRules.LAW_FUNDS_COST * funds_value + _jitter(bot)
				if tax_score > best_score:
					best = {"type": "law", "law": tax["law"]}
					best_score = tax_score
			var constitution := _best_constitution(bot)
			if not constitution.is_empty() and float(constitution["score"]) > best_score:
				best = {"type": "constitution", "payload": constitution["payload"]}
				best_score = float(constitution["score"])
			if CardManager.can_early_election(bot) and not CardManager.is_government_party(bot) \
					and CardManager.national_of(bot) > EARLY_ELECTION_SUPPORT:
				var early_score := 1.0 + CardManager.national_of(bot) * 0.8 - GameRules.EARLY_ELECTION_FUNDS_COST * funds_value + _jitter(bot)
				if early_score > best_score:
					best = {"type": "early_election"}
			if not best.is_empty():
				return best
	return skip

## AFET KARARI: değerli bir yardım varsa yapılır ({"party", "state"}), yoksa boş
## (bu tur yardım yapma).
static func choose_aid(bot: int) -> Dictionary:
	var aid := eval_aid(bot)
	if aid.is_empty() or float(aid["score"]) - float(aid["party"]) * _funds_value(bot) <= PASS_ACTION_SCORE:
		return {}
	return aid

## MİTİNG BÜTÇESİ: kasa darsa küçük, seçim yakın ve kasa bolsa büyük, yoksa orta.
static func miting_tier(bot: int) -> int:
	var funds := CardManager.funds_of(bot)
	if funds < CardManager.miting_tier_cost(1) * 2.0:
		return 0
	if _election_soon() and funds > CardManager.miting_tier_cost(2) * 3.0:
		return 2
	return CardManager.DEFAULT_TIER

## Mitingte karalanacak parti (-1 = kart yok ya da değmez): en büyük rakibin
## bu ildeki gücünü kıracak hedef (eski karalama değerlendirmesiyle aynı ölçek).
static func miting_smear(bot: int, province_id: String) -> int:
	var best := -1
	var best_value := 0.6
	var org_level := CardManager.organization_level(province_id, bot)
	var seats := float(CardManager.province_seat_count(province_id)) * PublicOpinion.org_action_mult(org_level)
	var gain := PublicOpinion.propaganda_gain(CardManager.party_strength(province_id, bot))
	for target in CardManager.smear_targets(bot, province_id):
		if is_ally(bot, int(target)):
			continue
		var damage := PublicOpinion.propaganda_damage(CardManager.party_strength(province_id, target))
		var rival := 0.3 + float(GovernmentManager.seats_of(target)) / _total_seats() * 4.0
		var value := (gain + damage * 0.6 * rival) * seats / 6.0 * 0.45
		if value > best_value:
			best_value = value
			best = int(target)
	return best

## KARALAMA KARTI (0.0.237, yine ayrı kart): teşkilatlı illerde en değerli
## il + rakip; ölçek miting_smear ile aynı.
static func _eval_propaganda(bot: int) -> Dictionary:
	var best := {}
	var best_value := -INF
	for province_id in _seats().keys():
		var target := miting_smear(bot, String(province_id))
		if target == -1:
			continue
		var org_level := CardManager.organization_level(String(province_id), bot)
		var seats := float(CardManager.province_seat_count(province_id)) * PublicOpinion.org_action_mult(org_level)
		var gain := PublicOpinion.propaganda_gain(CardManager.party_strength(province_id, bot))
		var damage := PublicOpinion.propaganda_damage(CardManager.party_strength(province_id, target))
		var rival := 0.3 + float(GovernmentManager.seats_of(target)) / _total_seats() * 4.0
		var value := (gain + damage * 0.6 * rival) * seats / 6.0
		if value > best_value:
			best_value = value
			best = {"peer": target, "province": province_id}
	if best.is_empty():
		return {}
	best["score"] = best_value * 0.45
	return best

## İTTİFAK BAŞVURUSUNA YANIT (0.0.225). Davet edilen bot: barajda zorlanıyorsa
## neredeyse her zaman, ortak oy barajı aşıyorsa çoğunlukla kabul eder.
## Oylayan üye bot: ittifakı barajdan kurtaracak ya da güçlendirecek partiyi
## çoğunlukla onaylar; eski ortağa daha sıcak bakar.
static func alliance_answer(bot: int, request_id: int) -> bool:
	var req: Dictionary = CardManager.alliance_requests.get(request_id, {})
	if req.is_empty():
		return false
	var pid := CardManager.party_of(bot)
	var alliance_id := int(req["alliance"])
	var threshold := MultiplayerManager.election_threshold
	if String(req["kind"]) == "invite" and int(req["party"]) == pid:
		var own_share := _vote_share(pid)
		var struggling := threshold > 0.0 and own_share < threshold + 2.0
		var helps := threshold > 0.0 and own_share + _alliance_share(alliance_id) >= threshold
		return struggling or (helps and randf() < 0.65) or (CardManager.were_allies(pid, int(req["party"])) and randf() < 0.5)
	var candidate := int(req["party"])
	var pooled := _alliance_share(alliance_id)
	# 0.0.254: seçmeni uzak partiyi onaylamaz; ittifak 3 partiyi geçmez (ortak
	# oy hâlâ barajın altındaysa hariç).
	if _friend_distance(bot, candidate) >= ALLIANCE_PARTNER_DISTANCE and not CardManager.were_allies(pid, candidate):
		return false
	var size: int = (CardManager.alliances.get(alliance_id, {}).get("members", []) as Array).size()
	if size >= ALLIANCE_MAX_BOT_SIZE and (threshold <= 0.0 or pooled >= threshold):
		return false
	var chance := 0.6
	if threshold > 0.0 and pooled < threshold:
		chance = 0.9
	if CardManager.were_allies(pid, candidate):
		chance += 0.15
	return randf() < chance

## Bot kendi sırasında katılma isteği gönderir mi? (Barajda zorlanıyor ve ortak
## oy barajı aşıyorsa.) İttifak kimliği ya da -1.
static func choose_alliance_request(bot: int) -> int:
	if not CardManager.can_manage_alliance(bot) or CardManager.alliance_of(bot) >= 0:
		return -1
	var pid := CardManager.party_of(bot)
	var threshold := MultiplayerManager.election_threshold
	var own_share := _vote_share(pid)
	if threshold <= 0.0 or own_share >= threshold + 2.0:
		return -1
	var best_id := -1
	var best_share := own_share
	for alliance_id in CardManager.alliances:
		if CardManager.pending_alliance_request(int(alliance_id), pid) >= 0:
			return -1
		if CardManager.recently_refused(int(alliance_id), pid):
			continue
		var combined := own_share + _alliance_share(int(alliance_id))
		if combined >= threshold and combined > best_share:
			best_id = int(alliance_id)
			best_share = combined
	return best_id

## BOTUN İTTİFAK HAMLESİ (0.0.227), kendi sırasında, öncelik sırasıyla:
##   ayrıl  : ortakları önergelerine HAYIR dediyse (küskünlük) ve seçim turu
##            değilse (seçim turunda ayrılmak cezalı).
##   iste   : barajda zorlanıyor ve bir ittifak onu barajın üstüne çıkarıyor.
##   davet  : liderse ve ittifak barajın yakınındaysa ya da küçükse, seçmen
##            grupları yakın (ideoloji karışımı çekirdeğini sulandırmayan)
##            partileri davet eder.
##   kur    : barajda zorlanıyor, katılacak ittifak yok, yakın bir parti var.
## 0.0.254: 3.0 → 1.5. Parti çiftlerinin uzaklığı pratikte 0–1,8 arası: 3.0 hiç
## kimseyi elemiyordu (bütün botlar tek ittifakta toplanıyordu).
const ALLIANCE_PARTNER_DISTANCE := 1.5
## Botların kendi isteğiyle büyüttüğü ittifakın en fazla parti sayısı.
const ALLIANCE_MAX_BOT_SIZE := 3
const ALLIANCE_NAMES := [["Halk Cephesi", "People's Front"], ["Ulusal Birlik", "National Union"],
	["Demokrasi Bloku", "Democracy Bloc"], ["Emek Birliği", "Labour Union"], ["Ortak Gelecek", "Common Future"],
	["Anadolu Birliği", "Anatolian Union"], ["Özgürlük Cephesi", "Freedom Front"], ["Yeni Başlangıç", "New Beginning"]]

static func choose_alliance_move(bot: int) -> Dictionary:
	if not CardManager.can_manage_alliance(bot):
		return {}
	# 0.0.254: ilk seçimden önce kimse kimsenin gücünü bilmez: bot ittifak
	# kurmaz, davet etmez, başvurmaz (gelen daveti yine yanıtlar).
	if CardManager.last_seats.is_empty():
		return {}
	var pid := CardManager.party_of(bot)
	var alliance_id := CardManager.alliance_of(bot)
	if alliance_id >= 0:
		if CardManager.alliance_grievance(pid) >= CardManager.ALLIANCE_GRIEVANCE_LEAVE and not CardManager.election_this_round():
			return {"type": "leave"}
		if CardManager.alliance_leader(alliance_id) == pid:
			var target := _alliance_invite_target(bot, alliance_id)
			if target >= 0:
				return {"type": "invite", "alliance_id": alliance_id, "party": target}
		return {}
	var join := choose_alliance_request(bot)
	if join >= 0:
		return {"type": "request", "alliance_id": join}
	var threshold := MultiplayerManager.election_threshold
	if threshold <= 0.0 or _vote_share(pid) >= threshold + 2.0 or not CardManager.alliances_enabled:
		return {}
	for other in CardManager.party_ids():
		if _alliance_candidate(bot, int(other)):
			var name := _free_alliance_name()
			var color := _free_alliance_color()
			if name != "" and color != Color.TRANSPARENT:
				return {"type": "create", "name": name, "color": color}
			break
	return {}

static func _alliance_candidate(bot: int, other: int) -> bool:
	return other != CardManager.party_of(bot) and CardManager.party_ids().has(other) 		and not PartyManager.is_independent(other) and CardManager.alliance_of(other) < 0 		and _friend_distance(bot, other) < ALLIANCE_PARTNER_DISTANCE

## Lider bot kimi davet eder? İttifak barajın 3 puan yakınındaysa ya da 3'ten az
## üyeliyse, en yakın uygun parti (açık başvurusu olmayan).
static func _alliance_invite_target(bot: int, alliance_id: int) -> int:
	var members: Array = CardManager.alliances[alliance_id].get("members", [])
	var threshold := MultiplayerManager.election_threshold
	if members.size() >= ALLIANCE_MAX_BOT_SIZE or (members.size() >= 2 and _alliance_share(alliance_id) >= threshold + 3.0):
		return -1
	var best := -1
	var best_d := INF
	for other in CardManager.party_ids():
		if not _alliance_candidate(bot, int(other)) or CardManager.pending_alliance_request(alliance_id, int(other)) >= 0 				or CardManager.recently_refused(alliance_id, int(other)):
			continue
		var d := _friend_distance(bot, int(other))
		if d < best_d:
			best_d = d
			best = int(other)
	return best

static func _free_alliance_name() -> String:
	var used := {}
	for alliance in CardManager.alliances.values():
		used[String(alliance.get("name", ""))] = true
	for pair in ALLIANCE_NAMES:
		var name: String = pair[1] if L.is_en() else pair[0]
		if not used.has(name):
			return name
	return ""

static func _free_alliance_color() -> Color:
	for color in PartyPresets.COLORS:
		var taken := false
		for alliance in CardManager.alliances.values():
			if Color(alliance.get("color", Color.WHITE)).is_equal_approx(color):
				taken = true
		if not taken:
			return color
	return Color.TRANSPARENT

## Partinin oy oranı (%): son seçim; seçim yoksa (ilk seçimden önce ya da
## yeni parti) "şimdi seçim olsa" beklenen ulusal oy. Eskiden kamuoyu puanına
## düşüyordu (~0): her bot kendini barajın altında sanıp ittifaka koşuyordu.
static func _vote_share(pid: int) -> float:
	if CardManager.last_vote_shares.has(pid):
		return float(CardManager.last_vote_shares[pid])
	var expected: Dictionary = CardManager._expected_national(CardManager.election_modifiers(true))
	return float(expected.get(pid, 0.0)) * 100.0

static func _alliance_share(alliance_id: int) -> float:
	var alliance: Dictionary = CardManager.alliances.get(alliance_id, {})
	var total := 0.0
	for member in alliance.get("members", []):
		total += _vote_share(int(member))
	return total

## En iyi hamle (gürültülü puanlarla). Geçerli seçenekler candidates'e eklenir.
static func _choose_action_best(bot: int, candidates: Array) -> Dictionary:
	var best := {"type": "pass"}
	var best_score := PASS_ACTION_SCORE
	var funds_value := _funds_value(bot)

	var hand: Array = CardManager.inventories.get(bot, [])
	var play := choose_play(bot)
	if not play.is_empty():
		var card_score := float(play["score"]) + _jitter(bot)
		candidates.append({"type": "card"})
		if card_score > best_score:
			best = {"type": "card"}
			best_score = card_score

	if CardManager.can_propose_law(bot):
		var law := _best_law(bot)
		# Yasa sıklığı sınırı (her gündem turunda herkes yasa sunup meclisi kilitlemesin).
		var rested: bool = CardManager.round_number - int(CardManager.law_rounds.get(bot, -99)) >= LAW_EVERY_ROUNDS
		if not rested:
			law = {}
		var law_cost: int = CardManager.law_funds_cost(bot, String(law.get("law", "")))
		var law_noise := _jitter(bot)
		if not law.is_empty() and CardManager.can_propose_law(bot, String(law["law"])):
			candidates.append({"type": "law", "law": law["law"]})
		if not law.is_empty() and CardManager.can_propose_law(bot, String(law["law"])) and float(law["score"]) - law_cost * funds_value + law_noise > best_score:
			best = {"type": "law", "law": law["law"]}
			best_score = float(law["score"]) - law_cost * funds_value + law_noise

	# VERGİ YASASI (sadece başbakanın partisi): aynı yasa hakkını kullanır.
	var tax := _best_tax_law(bot)
	if not tax.is_empty():
		var tax_score := float(tax["score"]) - GameRules.LAW_FUNDS_COST * funds_value + _jitter(bot)
		candidates.append({"type": "law", "law": tax["law"]})
		if tax_score > best_score:
			best = {"type": "law", "law": tax["law"]}
			best_score = tax_score

	# Anayasa teklifi yasa hakkını kullanır; o yüzden yasayla yarışır.
	var constitution := _best_constitution(bot)
	if not constitution.is_empty() and float(constitution["score"]) > best_score:
		best = {"type": "constitution", "payload": constitution["payload"]}
		best_score = float(constitution["score"])

	var org := _best_organization(bot)
	var org_cost := CardManager.org_cost_for(bot, String(org.get("province", ""))) if not org.is_empty() else 0.0
	var org_noise := _jitter(bot)
	if not org.is_empty():
		candidates.append({"type": "organization", "province": org["province"]})
	if not org.is_empty() and float(org["score"]) - org_cost * funds_value + org_noise > best_score:
		best = {"type": "organization", "province": org["province"]}
		best_score = float(org["score"]) - org_cost * funds_value + org_noise

	if CardManager.can_invest(bot):
		var invest := _eval_investment(bot)
		var invest_noise := _jitter(bot)
		if not invest.is_empty():
			candidates.append({"type": "invest", "province": invest["province"], "tier": CardManager.DEFAULT_TIER})
		if not invest.is_empty() and float(invest["score"]) - GameRules.INVEST_FUNDS_COST * funds_value + invest_noise > best_score:
			best = {"type": "invest", "province": invest["province"], "tier": CardManager.DEFAULT_TIER}
			best_score = float(invest["score"]) - GameRules.INVEST_FUNDS_COST * funds_value + invest_noise

	var aid := eval_aid(bot)
	if not aid.is_empty():
		var aid_score := float(aid["score"]) - float(aid["party"]) * funds_value + _jitter(bot)
		candidates.append({"type": "aid", "party": aid["party"], "state": aid["state"]})
		if aid_score > best_score:
			best = {"type": "aid", "party": aid["party"], "state": aid["state"]}
			best_score = aid_score

	if CardManager.can_censure(bot) and _censure_worth_it(bot):
		# Geçeceği hesaplanan gensoru: hükümet düşer, yeni kurma turu başlar.
		# Blokta gensoru planın son adımı: çok daha değerli.
		var censure_score := 7.0 if bloc_active() else 4.0
		if censure_score - GameRules.CENSURE_FUNDS_COST * funds_value > best_score:
			best = {"type": "censure"}
			_bloc_forming = bloc_active()
			best_score = censure_score - GameRules.CENSURE_FUNDS_COST * funds_value

	# ERKEN SEÇİM: kamuoyu bot lehineyse ve hükümette değilse sandığı ister.
	if CardManager.can_early_election(bot) and not CardManager.is_government_party(bot):
		var support := CardManager.national_of(bot)
		var early_score := 1.0 + support * 0.8 - GameRules.EARLY_ELECTION_FUNDS_COST * funds_value + _jitter(bot)
		if support > EARLY_ELECTION_SUPPORT:
			candidates.append({"type": "early_election"})
			if early_score > best_score:
				best = {"type": "early_election"}
				best_score = early_score

	var tier := miting_tier(bot)
	if CardManager.can_miting(bot, "", -1.0, tier):
		var miting := _eval_miting(bot)
		var miting_noise := _jitter(bot)
		var tier_cost := CardManager.miting_tier_cost(tier)
		var tier_mult := CardManager.miting_tier_mult(tier)
		if not miting.is_empty():
			var action := {"type": "miting", "province": miting["province"], "focus": miting["focus"], "tier": tier, "smear": -1}
			candidates.append(action)
			var score := float(miting["score"]) * tier_mult - tier_cost * funds_value + miting_noise
			if score > best_score:
				best = action
				best_score = score

	return best

## GRUP TOPLANTISI: geçici bonus seçime kaç tur kaldığına göre değerlidir
## (seçim bu tur sonundaysa +10, bir tur sonraysa +3...). Grup, ülkede en
## kalabalık olan ve bot için en çok uyum getiren gruptur; kriz grubu ek puan.
## Dönüş: {"group", "score"} (boş: toplantı hiç değmez).
## 0.0.228: toplantı KALICI seçmen kazandırır: bot çekirdek grubuyla toplanır
## (zıt gruba asla), kriz grubu ek puan.
static func choose_speech(bot: int) -> Dictionary:
	var crisis := CardManager.crisis_group()
	var core: Array = PartyManager.data_of(CardManager.party_of(bot)).get("core", [])
	var best := {}
	for group in VoterGroups.GROUP_IDS:
		var score := 0.4
		if core.has(group):
			score = 1.2
		elif core.has(VoterGroups.opposite(group)):
			score = -1.0
		if group == crisis:
			score += CRISIS_MEETING_BONUS
		# Eşitlikte botlar hep aynı grubu seçmesin.
		score += float((absi(bot) + CardManager.round_number + group.length()) % 7) * 0.005
		score += _jitter(bot, 0.2)  # zayıf bot bazen yanlış grupla toplanır
		if best.is_empty() or score > float(best["score"]):
			best = {"group": group, "score": score}
	return best

## Seçim desteğini en çok artıracak yasa: gündemdeki iki grup için, geçme
## ihtimaliyle beklenen grup kazancının ülke geneli uyuma etkisi + krize yanıt +
## kabul edilirse puan tablosu.
const CRISIS_LAW_BONUS := 0.6
const CRISIS_VOTE_BONUS := 0.3

static func _law_changes(law_type: String, gain: float) -> Array:
	var law := CardPresets.law_data(law_type)
	if law.is_empty():
		return []
	var backlash := float(VoterGroups.data(String(law["group"])).get("law_backlash", 0.4))
	return [{"group": law["group"], "amount": gain}, {"group": law["opposite"], "amount": -gain * backlash}]

static func _best_law(bot: int) -> Dictionary:
	var in_parliament := not CardManager.last_seats.is_empty()
	var best := {}
	# 0.0.182: her grup için yasa sunulabilir; gündemdeki grup daha güçlü.
	for group in VoterGroups.GROUP_IDS:
		var law_type := CardPresets.law_type(String(group))
		var pass_chance := _law_pass_chance(bot, law_type) if in_parliament else 0.0
		var expected_gain := pass_chance * PublicOpinion.LAW_GROUP_GAIN_PASSED \
			+ (1.0 - pass_chance) * PublicOpinion.LAW_GROUP_GAIN_REJECTED
		if CardManager.crisis_group() == group:
			expected_gain *= PublicOpinion.AGENDA_LAW_MULT
		var value := _appeal_gain(bot, _law_changes(law_type, expected_gain)) * APPEAL_TO_POINTS * PERMANENT_GAIN_VALUE
		if CardManager.crisis_group() == group:
			value += CRISIS_LAW_BONUS
		# Kabul edilen yasa puan tablosuna ciddi puan yazar.
		value += pass_chance * CardManager.law_pass_score(CardManager.is_government_party(bot)) * 0.12
		var score := LAW_BASE_SCORE + value * 3.0 - _repeat_penalty(bot, law_type)
		if best.is_empty() or score > float(best["score"]):
			best = {"law": law_type, "score": score}
	return best

## VERGİ SEZGİLERİ (oyuncuyla aynı kurallar ve aynı görünür bilgi: hazine,
## vergi kademesi, seçim takvimi). Az ve anlaşılır kural:
##   - Seçime TAX_CUT_LEAD turdan az kaldıysa vergi yüksek kalmaz (indirimin
##     etkisi yavaş gelir: erken indirmek gerekir); hazine bolsa düşüğe iner.
##   - Seçim uzaksa ve hazine yatırıma yetmiyorsa vergi artırılır (para biriktir).
##   - Hazine çok dolduysa yüksek vergi normale iner; düşük vergi hazineyi
##     eritiyorsa normale döner.
const TAX_CUT_LEAD := 2
const TAX_LAW_SCORE := 2.2
const TAX_LOW_TREASURY := 2.0   # × yatırım bedeli
const TAX_RICH_TREASURY := 6.0
const TAX_CUT_TREASURY := 3.0

## Bu turun sonunda seçim varsa 0; seçim yoksa 99.
static func _rounds_to_election() -> int:
	if CardManager.early_election_pending:
		return 0
	var next := GameRules.next_election_round(CardManager.round_number)
	return 99 if next == -1 else next - CardManager.round_number

static func _desired_tax() -> int:
	var current := CardManager.tax_level()
	var treasury := CardManager.state_treasury()
	var cost := Economy.INVEST_COST
	if _rounds_to_election() <= TAX_CUT_LEAD:
		if current == Economy.TAX_HIGH:
			return Economy.TAX_NORMAL
		if current == Economy.TAX_NORMAL and treasury >= cost * TAX_CUT_TREASURY and _rounds_to_election() >= 1:
			return Economy.TAX_LOW
		return current
	if treasury < cost * TAX_LOW_TREASURY:
		return mini(Economy.TAX_HIGH, current + 1)
	if current == Economy.TAX_HIGH and treasury > cost * TAX_RICH_TREASURY:
		return Economy.TAX_NORMAL
	if current == Economy.TAX_LOW and treasury < cost * TAX_CUT_TREASURY:
		return Economy.TAX_NORMAL
	return current

## Başbakanın partisi bot ise vergi kademesini sezgiye göre değiştirmeyi önerir.
static func _best_tax_law(bot: int) -> Dictionary:
	if CardManager.party_of(bot) != GovernmentManager.main_gov_peer_id or not CardManager.can_propose_tax_law(bot):
		return {}
	var level := _desired_tax()
	if level == CardManager.tax_level():
		return {}
	var law_type := CardPresets.tax_law_type(level)
	if _law_pass_chance(bot, law_type) < 0.5:
		return {}
	return {"law": law_type, "score": TAX_LAW_SCORE}

## Vergi yasasına oy: hükümet (genelde) destekler; ortak seçime yakın vergi
## artırımına destek vermez (sonucunu o da taşır). Muhalefet artırıma HAYIR,
## seçime yakın indirime HAYIR (iktidara kazanç bırakmaz), yoksa çekimser.
static func _tax_law_vote(voter: int, law_type: String, proposer: int, gov_ids: Array) -> int:
	var raising := CardPresets.tax_law_level(law_type) > CardManager.tax_level()
	var soon := _rounds_to_election() <= TAX_CUT_LEAD
	if gov_ids.has(voter):
		if raising and soon and voter != proposer:
			return GovernmentManager.VOTE_ABSTAIN
		return GovernmentManager.VOTE_YES if gov_ids.has(proposer) else GovernmentManager.VOTE_NO
	if raising:
		return GovernmentManager.VOTE_NO
	return GovernmentManager.VOTE_NO if _rounds_to_election() <= TAX_CUT_LEAD + 1 else GovernmentManager.VOTE_ABSTAIN

## Botun son sunduğu yasalar: aynı yasayı (ve karşıt grubun yasasını) üst üste sunmasın.
static var _recent_laws: Dictionary = {}
const RECENT_LAW_MEMORY := 4

static func note_law(bot: int, law_type: String) -> void:
	var recent: Array = _recent_laws.get(bot, [])
	recent.append(law_type)
	while recent.size() > RECENT_LAW_MEMORY:
		recent.pop_front()
	_recent_laws[bot] = recent

static func _repeat_penalty(bot: int, law_type: String) -> float:
	var law := CardPresets.law_data(law_type)
	var penalty := 0.0
	for previous in _recent_laws.get(bot, []):
		if previous == law_type:
			penalty += 0.9
		elif not law.is_empty() and CardPresets.law_data(previous).get("group", "") == law["opposite"]:
			penalty += 0.35  # aynı çiftte bir o yana bir bu yana yasa tutarsız görünür
	return penalty

## Kaba geçme ihtimali: diğer partilerin oyu, aynı oy kuralıyla tahmin edilir.
static func _law_pass_chance(bot: int, law_type: String) -> float:
	var gov_ids := GovernmentManager.government_party_ids()
	var yes := GovernmentManager.seats_of(bot)
	var no := 0
	for peer_id in GovernmentManager.voter_ids():
		if peer_id == bot:
			continue
		match _best_law_vote(peer_id, law_type, bot, gov_ids):
			GovernmentManager.VOTE_YES:
				yes += GovernmentManager.seats_of(peer_id)
			GovernmentManager.VOTE_NO:
				no += GovernmentManager.seats_of(peer_id)
	return 0.85 if yes > no else 0.15

## Bir partinin bir yasaya EVET/HAYIR demesinin grup uyumuna etkisi (ulusal
## puan cinsinden) + krize yanıt + iktidarın muhalefet yasasına EVET bedeli.
static func _law_vote_value(voter: int, law_type: String, choice: int, proposer: int, gov_ids: Array) -> float:
	var law := CardPresets.law_data(law_type)
	if law.is_empty() or choice == GovernmentManager.VOTE_ABSTAIN:
		return 0.0
	var group := String(law["group"])
	var opposite := String(law["opposite"])
	var backlash := float(VoterGroups.data(group).get("law_backlash", 0.4))
	var changes: Array = []
	if choice == GovernmentManager.VOTE_YES:
		changes = [{"group": group, "amount": PublicOpinion.LAW_VOTE_YES_GAIN},
			{"group": opposite, "amount": -PublicOpinion.LAW_VOTE_YES_GAIN * backlash}]
	else:
		changes = [{"group": opposite, "amount": PublicOpinion.LAW_VOTE_NO_GAIN},
			{"group": group, "amount": -PublicOpinion.LAW_VOTE_NO_GAIN * backlash}]
	var value := _appeal_gain(voter, changes) * APPEAL_TO_POINTS * PERMANENT_GAIN_VALUE
	if choice == GovernmentManager.VOTE_YES:
		if gov_ids.has(voter) and not gov_ids.has(proposer):
			value += PublicOpinion.LAW_GOV_YES_ON_OPPOSITION
		if CardManager.crisis_group() == group:
			value += CRISIS_VOTE_BONUS
	return value

static func _best_law_vote(voter: int, law_type: String, proposer: int, gov_ids: Array) -> int:
	if CardPresets.is_tax_law(law_type):
		return _tax_law_vote(voter, law_type, proposer, gov_ids)
	var best := GovernmentManager.VOTE_ABSTAIN
	var best_value := 0.0
	for choice in [GovernmentManager.VOTE_YES, GovernmentManager.VOTE_NO]:
		var value := _law_vote_value(voter, law_type, choice, proposer, gov_ids)
		if value > best_value + 0.01:
			best_value = value
			best = choice
	# İktidar muhalefetin yasasını genelde reddeder: yasa geçerse getiren daha çok kazanır.
	if gov_ids.has(voter) and not gov_ids.has(proposer) and best == GovernmentManager.VOTE_ABSTAIN:
		best = GovernmentManager.VOTE_NO
	return best

## Vekili çok, seçmen profili partiye uyumlu ve henüz teşkilatı zayıf il.
static func _best_organization(bot: int) -> Dictionary:
	var seats := _seats()
	var best := {}
	for province_id in seats.keys():
		if not CardManager.can_build_organization(bot, province_id):
			continue
		var level := CardManager.organization_level(province_id, bot)
		# 2 para: kalıcı ama pahalı — büyük illerde bile yasa/kartla yarışacak kadar.
		var closeness := PublicOpinion.appeal_closeness(CardManager.appeal_of(province_id, bot))
		# Kalıcı oy bonusu (seviye farkı) + bilgi: 1. seviye kaba, 2. seviye isabetli anket.
		var gain := PublicOpinion.org_activity(level + 1) - PublicOpinion.org_activity(level)
		var value := float(seats[province_id]) * (0.5 + closeness) / 30.0 * gain / 1.2 * 0.8
		if level == 0:
			value += 0.25 + float(seats[province_id]) / 40.0
		var score := 1.0 + value * (1.3 if _election_soon() else 1.0) + _jitter(bot, 0.5)
		if best.is_empty() or score > float(best["score"]):
			best = {"province": province_id, "score": score}
	return best

# --- Sıra: hangi kart? ---------------------------------------------------------

## Dönüş: {"index", "peer", "province", "score"} ya da boş sözlük (= oynama).
static func choose_play(bot: int) -> Dictionary:
	var hand: Array = CardManager.inventories.get(bot, [])
	var best := {}
	var best_score := PASS_THRESHOLD
	if hand.size() >= CardManager.MAX_HAND_SIZE:
		best_score = -INF  # el dolu: en iyisini oyna, desteyi tıkama
	for i in hand.size():
		var option := _evaluate(bot, String(hand[i]))
		if option.is_empty():
			continue
		option["score"] = float(option["score"]) + _jitter(bot, 0.6)
		if float(option["score"]) > best_score:
			best_score = float(option["score"])
			best = option
			best["index"] = i
	return best

static func _evaluate(bot: int, card_type: String) -> Dictionary:
	match card_type:
		CardPresets.POPULISM_CARD_TYPE:
			# Seçime az kala ya da hiç popülizm yokken değerli.
			if CardManager.populism_rounds_left(bot) > 0:
				return {}
			return {"score": 2.2 if _election_soon() else 1.4, "peer": -1, "province": ""}
		CardPresets.FUNDS_BONUS_CARD_TYPE, CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE:
			# Kasası azken, yapacak başka şey yokken kullanılır.
			return {"score": 0.9 if CardManager.funds_of(bot) < GameRules.MITING_FUNDS_COST else 0.3, "peer": -1, "province": ""}
		CardPresets.CARD_THEFT_CARD_TYPE:
			return _eval_card_theft(bot)
		CardPresets.PROPAGANDA_CARD_TYPE:
			return _eval_propaganda(bot)
	if CardPresets.needs_target(card_type):
		return _eval_steal(bot, card_type)
	if card_type == CardPresets.REPUTATION_CARD_TYPE:
		return _eval_reputation(bot)
	if card_type == CardPresets.REBELLION_CARD_TYPE:
		return _eval_rebellion(bot)
	return {}

## Kaset: en büyük rakibin (blok varsa insan hükümetinin) ulusal desteğini vurur.
static func _eval_reputation(bot: int) -> Dictionary:
	var target := _attack_target(bot)
	if target == -1:
		return {}
	var score := 1.9 + PublicOpinion.REPUTATION_NATIONAL_DAMAGE / 4.0
	if bloc_active() and bloc_members().has(bot) and target == GovernmentManager.main_gov_peer_id:
		score += BLOC_STEAL_BONUS * 0.6
	return {"score": score, "peer": target, "province": ""}

static func hand_size(peer_id: int) -> int:
	return (CardManager.inventories.get(peer_id, []) as Array).size()

## Kart çalma: eli en dolu rakip (eli boşsa kart boşa gider).
static func _eval_card_theft(bot: int) -> Dictionary:
	if hand_size(bot) >= CardManager.MAX_HAND_SIZE:
		return {}
	var target := -1
	for peer_id in CardManager.turn_order:
		if is_ally(bot, int(peer_id)) or hand_size(peer_id) == 0:
			continue
		if target == -1 or hand_size(peer_id) > hand_size(target):
			target = peer_id
	if target == -1:
		return {}
	return {"score": 1.0 + float(hand_size(target)) * 0.12, "peer": target, "province": ""}

## İç karışıklık: büyük bir rakibin desteğini düşürür ve partisini sarsar.
static func _eval_rebellion(bot: int) -> Dictionary:
	var target := _attack_target(bot)
	if target == -1 or not CardManager.has_seats(target):
		return {}
	var score := 1.2 + float(GovernmentManager.seats_of(target)) / float(maxi(1, GovernmentManager.total_seats())) * 3.0
	if CardManager.is_government_party(target) and not CardManager.is_government_party(bot):
		score += 0.5  # hükümetin yasasını zora sokar
	return {"score": score, "peer": target, "province": ""}

## Saldırı kartlarının hedefi: blok varsa hükümetin ana partisi, yoksa
## kendisi dışındaki en çok vekilli parti.
static func _attack_target(bot: int) -> int:
	if bloc_active() and bloc_members().has(bot):
		return GovernmentManager.main_gov_peer_id
	var target := -1
	for peer_id in CardManager.party_ids():
		if is_ally(bot, int(peer_id)):
			continue
		if target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target):
			target = peer_id
	return target

## MİTİNG YERİ (0.0.228): bot KALE kurar. İlin değeri vekil sayısıyla değil,
## partinin çekirdek gruplarının o ildeki YOĞUNLUĞUYLA ölçülür (büyük şehir
## kendiliğinden kazanmaz): çekirdek grup payı + diğer grupların küçük katkısı −
## çekirdeğin zıt gruplarının payı (zıt grupta seviye kaybı). Teşkilatı ya da
## memleketi olan il, kaleyi büyütmek için daha değerli; partinin ilde zaten
## çok seçmeni varsa getiri azalır. Vekil sayısı çok hafif (0,15 kuvvet) girer;
## uyum, en uygun ile oranla 4. kuvvetten girer: ideolojisinin yoğun olduğu
## iller açıkça öne çıkar.
static func _eval_miting(bot: int) -> Dictionary:
	var best_province := ""
	var best_focus: Array = []
	var best_value := -INF
	var core: Array = PartyManager.data_of(CardManager.party_of(bot)).get("core", [])
	var home := PoliticianPresets.hometown_of(bot)
	var best_fit := 0.0001
	for province_id in _seats().keys():
		best_fit = maxf(best_fit, _ideology_fit(bot, String(province_id), core))
	for province_id in _seats().keys():
		var org_level := CardManager.organization_level(String(province_id), bot)
		# 0.0.269: miting için teşkilat şart (bağımsız hariç).
		if org_level <= 0 and not PartyManager.is_independent(CardManager.party_of(bot)):
			continue
		var org_mult := PublicOpinion.miting_org_mult(org_level)
		var risk := CardManager.miting_risk(bot, province_id)
		var seats := float(CardManager.province_seat_count(province_id))
		var fit := _ideology_fit(bot, String(province_id), core)
		var held := _province_hold(bot, String(province_id))
		var stronghold := 1.0 + 0.35 * float(org_level) + (0.4 if String(province_id) == home else 0.0)
		var value := pow(fit / best_fit, 4.0) * org_mult * stronghold * pow(maxf(1.0, seats), 0.15) / (1.0 + held * 4.0) * 0.6 \
			+ risk * PublicOpinion.PROVOCATION_NATIONAL
		value *= 1.0 - risk
		value += _jitter(bot, 0.05)  # zayıf bot yanlış ilde miting yapar
		if value > best_value:
			best_value = value
			best_province = province_id
			best_focus = _miting_focus(bot, province_id, org_level)
	if best_province == "":
		return {}
	var score := best_value * 1.4 * (1.4 if _election_soon() else 1.0)
	return {"score": score, "peer": -1, "province": best_province, "focus": best_focus}

## İlin partinin ideolojisine uygunluğu (0..1 civarı): çekirdek grupların ildeki
## payı, diğerlerinin dörtte biri, çekirdeğin zıtları eksi yarısı.
static func _ideology_fit(bot: int, province_id: String, core: Array) -> float:
	var profile := CardManager.province_profile(province_id)
	var electorate := 0.0
	var counts := {}
	for group in VoterGroups.GROUP_IDS:
		var n := VoterGroups.group_count(profile, group)
		counts[group] = n
		electorate += n
	if electorate <= 0.0:
		return 0.0
	var fit := 0.0
	for group in VoterGroups.GROUP_IDS:
		var share := float(counts[group]) / electorate
		if core.has(group):
			fit += share
		elif core.has(VoterGroups.opposite(group)):
			fit -= share * 0.5
		else:
			fit += share * 0.25
	return maxf(0.05, fit)

## Partinin ildeki bağlı seçmen oranı (0..1).
static func _province_hold(bot: int, province_id: String) -> float:
	var state := CardManager.vb_province_state(province_id)
	var attached: Dictionary = state.get("attached", {})
	var total := float(state.get("undecided", 0.0))
	for pid in attached:
		total += float(attached[pid])
	return float(attached.get(CardManager.party_of(bot), 0.0)) / total if total > 0.0 else 0.0

## Botun mitingte odaklanacağı gruplar: ildeki teşkilat seviyesi kadar, ülke
## geneli uyumuna en çok katkı yapan gruplar (tek tek denenir).
static func _miting_focus(bot: int, province_id: String, slots: int) -> Array:
	if slots <= 0:
		return []
	# 0.0.228: önce çekirdek gruplar (ildeki seçmen sayısıyla), sonra diğerleri;
	# çekirdeğin zıt grubu hiç seçilmez.
	var core: Array = PartyManager.data_of(CardManager.party_of(bot)).get("core", [])
	var profile := CardManager.province_profile(province_id)
	var ranked: Array = []
	for group in VoterGroups.GROUP_IDS:
		if core.has(VoterGroups.opposite(group)):
			continue
		var value := VoterGroups.group_count(profile, group) * (3.0 if core.has(group) else 1.0)
		ranked.append({"group": String(group), "value": value})
	ranked.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
	var focus: Array = []
	for item in ranked:
		if focus.size() >= slots:
			break
		focus.append(String(item["group"]))
	return focus

## Yatırım: yerel memnuniyet. Büyük, partiye uyumlu ve aktivitesi henüz
## tavana dayanmamış il (azalan getiri: il puanı LIMIT'te durur).
## HAZİNE: seçim uzaksa bir yatırımlık yedek bırakır (hepsini harcamaz);
## yatırımın kalan dilimleri seçimden sonraya kalacaksa değeri düşer.
static func _eval_investment(bot: int) -> Dictionary:
	# Yatırım tamamen hazine kotasından (can_invest kotayı denetler).
	if not CardManager.is_government_party(bot) or not CardManager.can_invest(bot):
		return {}
	var left := _rounds_to_election()
	var reserve := Economy.INVEST_COST if left > TAX_CUT_LEAD else 0.0
	if CardManager.state_treasury() - Economy.INVEST_COST < reserve:
		return {}
	var timing := Economy.INVEST_IMMEDIATE + (1.0 - Economy.INVEST_IMMEDIATE) \
		* minf(float(left), float(Economy.INVEST_DELAY_ROUNDS)) / float(Economy.INVEST_DELAY_ROUNDS)
	var best_province := ""
	var best_value := -INF
	for province_id in _seats().keys():
		# 0.0.269: yatırım yalnız teşkilatlı ilde.
		if CardManager.organization_level(String(province_id), bot) <= 0:
			continue
		var room := clampf((PublicOpinion.INVEST_LIMIT - CardManager.local_of(province_id, bot)) / PublicOpinion.INVEST_LOCAL, 0.0, 1.0)
		var value := float(CardManager.province_seat_count(province_id)) \
			* (0.5 + PublicOpinion.appeal_closeness(CardManager.appeal_of(province_id, bot))) * room
		if value > best_value:
			best_value = value
			best_province = province_id
	if best_province == "":
		return {}
	# İl başkanlığı ve mitingle aynı ölçek (vekil/30).
	return {"score": (0.8 + best_value / 30.0 * 1.2 * (1.3 if _election_soon() else 1.0)) * timing, "peer": -1, "province": best_province}

## AFET YARDIMI: partisi bu afete henüz yardım etmediyse kasasının ~%40'ı,
## hükümetteyse kotasının yarısı (en çok 60 milyon ¤) devletten. Değer:
## miting ölçeğinde (vekil/30), afet yardımı güçlü olduğu için ×1,6.
static func eval_aid(bot: int) -> Dictionary:
	if not CardManager.can_aid(bot) or CardManager.disaster_aid_of(bot) > 0.0:
		return {}
	var lim := CardManager.aid_limits(bot)
	var party_m := Disaster.snap_amount(minf(float(lim["party_max"]), CardManager.funds_of(bot) * 0.4))
	var state_m := Disaster.snap_amount(minf(float(lim["state_max"]), minf(60.0, CardManager.state_quota(bot) * 0.5)))
	if party_m + state_m < Disaster.AID_MIN:
		party_m = Disaster.AID_MIN if float(lim["party_max"]) >= Disaster.AID_MIN else party_m
	if not CardManager.can_aid(bot, party_m, state_m):
		return {}
	var provinces: Array = CardManager.active_disaster().get("provinces", [])
	var gain := Disaster.local_gain(0.0, party_m + state_m, provinces.size())
	var value := 0.0
	for province_id in provinces:
		var seats := float(CardManager.province_seat_count(String(province_id)))
		var closeness := PublicOpinion.appeal_closeness(CardManager.appeal_of(String(province_id), bot))
		value += minf(gain, PublicOpinion.LIMIT - CardManager.local_of(String(province_id), bot)) / PublicOpinion.MITING_LOCAL * seats / 30.0 * (0.5 + closeness)
	value += Disaster.national_gain(0.0, party_m + state_m) * 0.5
	return {"score": value * 1.4 * 1.6 * (1.4 if _election_soon() else 1.0), "party": party_m, "state": state_m}

## İktidardaysa en büyük muhalefetten, muhalefetteyse hükümetten çal.
static func _eval_steal(bot: int, card_type: String) -> Dictionary:
	if bloc_active() and bloc_members().has(bot):
		var bloc := _eval_bloc_steal(bot, card_type)
		if not bloc.is_empty():
			return bloc
	var in_gov := CardManager.is_government_party(bot)
	var target := -1
	for peer_id in CardManager.party_ids():
		if not CardManager.is_valid_steal_target(bot, peer_id) or is_ally(bot, int(peer_id)):
			continue
		if GovernmentManager.has_government() and CardManager.is_government_party(peer_id) == in_gov:
			continue
		if target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target):
			target = peer_id
	if target == -1:
		for peer_id in CardManager.party_ids():
			if CardManager.is_valid_steal_target(bot, peer_id) and not is_ally(bot, int(peer_id)) \
					and (target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target)):
				target = peer_id
	if target == -1:
		return {}
	var r: Dictionary = CardManager.steal_range(bot, target, card_type)
	# Vekil sayısı bir sonraki seçime de momentum olarak yansır.
	var score := 1.8 + (float(r["min"]) + float(r["max"])) / 7.0
	# Muhalefetten hükümeti azınlığa düşürebilecek hamle çok değerli (gensoru yolu).
	if not in_gov and GovernmentManager.has_majority() and CardManager.is_government_party(target):
		var after: float = GovernmentManager.government_seats() - (float(r["min"]) + float(r["max"])) / 2.0
		if after * 2.0 <= GovernmentManager.total_seats():
			score += 3.0
	return {"score": score, "peer": target, "province": ""}

## Blok üyesi: hedef hükümetin ana partisi (insan). Bloğun lideri birinci
## partiyi geçebiliyorsa ya da hükümet azınlığa düşüyorsa hamle çok değerli.
static func _eval_bloc_steal(bot: int, card_type: String) -> Dictionary:
	var target := GovernmentManager.main_gov_peer_id
	if not CardManager.is_valid_steal_target(bot, target):
		return {}
	var r: Dictionary = CardManager.steal_range(bot, target, card_type)
	var avg: float = (float(r["min"]) + float(r["max"])) / 2.0
	var score := 1.8 + avg / 3.5 + BLOC_STEAL_BONUS
	var leader := bloc_leader()
	var leader_seats := float(GovernmentManager.seats_of(leader)) + (avg if leader == bot else 0.0)
	if leader_seats > float(GovernmentManager.seats_of(target)) - avg:
		score += BLOC_OVERTAKE_BONUS  # blok lideri birinci parti olur
	if GovernmentManager.has_majority() and (GovernmentManager.government_seats() - avg) * 2.0 <= GovernmentManager.total_seats():
		score += BLOC_OVERTAKE_BONUS  # hükümet çoğunluğu kaybeder
	return {"score": score, "peer": target, "province": ""}

## Gensoru ancak geçeceği hesaplanıyorsa ve hükümet yeni kurulmamışsa verilir;
## aynı tur içinde ikinci gensoru yok (her tur meclisi kilitlemesin).
static func _censure_worth_it(bot: int) -> bool:
	if CardManager.round_number - GovernmentManager.formed_round < 2:
		return false
	if GovernmentManager.censure_round == CardManager.round_number:
		return false
	var yes := GovernmentManager.seats_of(bot)
	var no := 0
	var main_gov := GovernmentManager.main_gov_peer_id
	for peer_id in GovernmentManager.voter_ids():
		if peer_id == bot:
			continue
		if CardManager.is_government_party(peer_id):
			no += GovernmentManager.seats_of(peer_id)
		elif bloc_active() and MultiplayerManager.is_bot(peer_id):
			yes += GovernmentManager.seats_of(peer_id)  # blok üyesi: kesin evet
		elif not MultiplayerManager.is_bot(peer_id):
			continue  # insanın oyu bilinmez: hesaba katılmaz
		elif _distance(peer_id, main_gov) < 2.0:
			continue  # çekimser
		else:
			yes += GovernmentManager.seats_of(peer_id)
	return yes > no

# --- Oylama --------------------------------------------------------------------

static func choose_vote(bot: int) -> int:
	# Kardeş parti ya da partideki ortak: teklifini destekler (gensoru hariç
	# kendi hükümetine karşıysa ayrıca bakılır).
	var proposer := GovernmentManager.proposal_peer_id
	if proposer != -1 and is_ally(bot, proposer) and GovernmentManager.proposal_kind != GovernmentManager.KIND_CENSURE:
		return GovernmentManager.VOTE_YES
	match GovernmentManager.proposal_kind:
		GovernmentManager.KIND_GOVERNMENT:
			if bot == GovernmentManager.proposal_peer_id:
				return GovernmentManager.VOTE_YES
			if GovernmentManager.proposal_partner_ids().has(bot):
				return _coalition_offer_vote(bot)
			if _bloc_solidarity() and MultiplayerManager.is_bot(GovernmentManager.proposal_peer_id):
				return GovernmentManager.VOTE_YES  # blok, kendi botunun hükümetini destekler
			return _government_confidence_vote(bot)
		GovernmentManager.KIND_CENSURE:
			if bot == GovernmentManager.proposal_peer_id:
				return GovernmentManager.VOTE_YES
			if CardManager.is_government_party(bot):
				return GovernmentManager.VOTE_NO
			if bloc_active():
				_bloc_forming = true
				return GovernmentManager.VOTE_YES
			return _censure_vote(bot)
		GovernmentManager.KIND_LAW:
			if bot == GovernmentManager.proposal_peer_id:
				return GovernmentManager.VOTE_YES
			return _best_law_vote(bot, GovernmentManager.proposal_law, GovernmentManager.proposal_peer_id,
				GovernmentManager.proposal_gov_ids)
		GovernmentManager.KIND_EARLY:
			if bot == GovernmentManager.proposal_peer_id:
				return GovernmentManager.VOTE_YES
			return _early_election_vote(bot)
		GovernmentManager.KIND_CONSTITUTION:
			if bot == GovernmentManager.proposal_peer_id:
				return GovernmentManager.VOTE_YES
			return _constitution_vote(bot)
	return GovernmentManager.VOTE_ABSTAIN

## ANAYASA TEKLİFİ: bot kendi çıkarına bir paket arar.
##   - Barajda zorlanıyorsa (oyu baraja yakın ya da altında) barajı düşürmek;
##     barajla zor durumdaki BAŞKA partileri de yanına alabilir.
##   - DÜŞMANCA BARAJ: barajı aşmakta zorlanan (ya da zorlanmaya başlayan)
##     bir rakip varsa, kendisi rahatça üstünde kalacaksa barajı o rakibin
##     hemen üstüne çıkarmak (rakibi meclisten atmak, vekillerini paylaşmak).
##   - KAZANAN HEPSİNİ ALIR: bot çok ilde birinciyse ve bu sayım ona vekil
##     kazandıracaksa (az ilde birinci rakipler ezilir).
##   - Hare: küçük parti (%20 altı) daha orantılı sayım ister.
## Teklif ancak meclisin 2/3'ünün EVET demesi bekleniyorsa yapılır;
## insanların oyu bilinmez, sayılmaz.
const CONSTITUTION_EVERY_ROUNDS := 4
static var _constitution_rounds: Dictionary = {}

static func _best_constitution(bot: int) -> Dictionary:
	if not CardManager.can_propose_constitution(bot):
		return {}
	if CardManager.round_number - int(_constitution_rounds.get(bot, -99)) < CONSTITUTION_EVERY_ROUNDS:
		return {}
	var threshold := MultiplayerManager.election_threshold
	var share := float(CardManager.last_vote_shares.get(bot, 0.0))
	var candidates: Array = []
	# 1) Barajda zorlanan bot: barajı oyunun belirgin altına indir.
	if threshold > 0.0 and share < threshold + 2.0:
		candidates.append({"threshold": MultiplayerManager.snap_threshold(maxf(0.0, share - 2.0)), "urgency": 2.5})
	# 2) Barajda zorlanan başkaları da varsa (ortak çıkar) aynı paket değerlidir.
	var struggling := 0
	for peer_id in CardManager.turn_order:
		var other := float(CardManager.last_vote_shares.get(peer_id, 0.0))
		if peer_id != bot and threshold > 0.0 and other < threshold + 2.0:
			struggling += 1
	# 3) DÜŞMANCA BARAJ: barajda zorlanan rakibi dışarıda bırak (kendisi güvendeyse).
	var victim := -1
	var victim_share := 0.0
	for peer_id in CardManager.turn_order:
		var other := float(CardManager.last_vote_shares.get(peer_id, 0.0))
		# Zorlanan: baraja 2 puan yakın ya da zaten çok küçük (%4 altı).
		if peer_id == bot or other <= 0.0 or other >= maxf(threshold + 2.0, 4.0) or other + 0.5 > MultiplayerManager.THRESHOLD_MAX:
			continue
		if share < other + 0.5 + 3.0:
			continue  # yeni baraj kendini de tehlikeye atar
		if victim == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(victim):
			victim = peer_id
			victim_share = other
	if victim != -1:
		var new_threshold := MultiplayerManager.snap_threshold(victim_share + 0.5)
		if new_threshold > threshold:
			candidates.append({"threshold": new_threshold, "urgency": 1.3
				+ float(GovernmentManager.seats_of(victim)) / _total_seats() * 4.0})
	# 4) Sayım yöntemi: kazanan hepsini alır vekil kazandırıyorsa; küçük parti Hare.
	var wta_gain := wta_seat_gain(bot)
	if MultiplayerManager.seat_method != ElectionModel.METHOD_WTA and wta_gain >= 10:
		candidates.append({"threshold": threshold, "urgency": 0.8 + minf(2.0, float(wta_gain) / 40.0),
			"seat_method": ElectionModel.METHOD_WTA})
	elif share < 20.0 and MultiplayerManager.seat_method != ElectionModel.METHOD_HARE:
		candidates.append({"threshold": threshold, "urgency": 0.8, "seat_method": ElectionModel.METHOD_HARE})
	var best := {}
	for option in candidates:
		var payload := {"threshold": float(option["threshold"]), "interval": MultiplayerManager.election_interval,
			"seat_method": String(option.get("seat_method", MultiplayerManager.seat_method))}
		if is_equal_approx(float(payload["threshold"]), threshold) and payload["seat_method"] == MultiplayerManager.seat_method:
			continue
		# Destekçileri say: teklif sahibi EVET, diğer botlar kendi çıkarına göre.
		var yes := GovernmentManager.seats_of(bot)
		for peer_id in GovernmentManager.voter_ids():
			if peer_id != bot and MultiplayerManager.is_bot(peer_id) \
					and _constitution_vote(peer_id, payload) == GovernmentManager.VOTE_YES:
				yes += GovernmentManager.seats_of(peer_id)
		if yes < GovernmentManager.constitution_threshold_seats():
			continue  # 2/3 yoksa teklif boşa gider
		var score := 1.6 + float(option["urgency"]) + float(struggling) * 0.2
		if best.is_empty() or score > float(best["score"]):
			best = {"payload": payload, "score": score}
	return best

## "Kazanan hepsini alır" olsaydı son seçimin il sonuçlarıyla bu parti kaç
## il vekili KAZANIR (+) ya da KAYBEDERDİ (−): birinci olduğu illerin bütün
## vekilleri eksi şu anki il vekilleri. Az ilde birinci
## partiler bu sayımda ezilir.
static func wta_seat_gain(peer_id: int) -> int:
	var now := 0
	var wta := 0
	for province_id in CardManager.last_province_results.keys():
		var entry: Dictionary = CardManager.last_province_results[province_id]
		var first := -1
		var best := -1.0
		var seats := 0
		for id in entry.keys():
			seats += int(entry[id].get("seats", 0))
			if float(entry[id].get("percent", 0.0)) > best:
				best = float(entry[id].get("percent", 0.0))
				first = int(id)
		now += int(entry.get(peer_id, {}).get("seats", 0))
		if first == peer_id:
			wta += seats
	return wta - now

static func note_constitution(bot: int) -> void:
	_constitution_rounds[bot] = CardManager.round_number

## ANAYASA DEĞİŞİKLİĞİ: küçük parti barajın DÜŞMESİNİ ister, büyük parti
## yükselmesini. Seçim aralığının uzaması iktidardakinin işine gelir.
static func _constitution_vote(bot: int, payload: Dictionary = {}) -> int:
	if payload.is_empty():
		payload = GovernmentManager.proposal_assignments
	var new_threshold := float(payload.get("threshold", MultiplayerManager.election_threshold))
	var new_interval := float(payload.get("interval", MultiplayerManager.election_interval))
	var score := 0.0
	# Oy oranı barajın altına yakınsa baraj düşmesi hayat kurtarır.
	var share := float(CardManager.last_vote_shares.get(bot, 0.0))
	var threshold_delta := new_threshold - MultiplayerManager.election_threshold
	if threshold_delta > 0.0 and share < new_threshold + 2.0:
		score -= 3.0   # yeni baraj beni meclisten atabilir
	elif share < MultiplayerManager.election_threshold + 5.0:
		score -= threshold_delta   # baraj düşerse iyi
	else:
		score += threshold_delta * 0.5   # güvendeki parti: baraj yükselsin, rakip elensin
	# SAYIM: en büyük parti "kazanan hepsini alır"ı sever, küçük partiler Hare'yi.
	var new_method := String(payload.get("seat_method", MultiplayerManager.seat_method))
	if new_method != MultiplayerManager.seat_method:
		if new_method == ElectionModel.METHOD_WTA or MultiplayerManager.seat_method == ElectionModel.METHOD_WTA:
			# Kazanan hepsini alır: kendi il birinciliklerine göre kazanır mı kaybeder mi?
			var gain := float(wta_seat_gain(bot)) * (1.0 if new_method == ElectionModel.METHOD_WTA else -1.0)
			score += clampf(gain / 15.0, -3.0, 3.0)
		elif share < 20.0:
			var method_rank := {"hare": 0.0, "dhondt": 1.0}
			score -= (float(method_rank.get(new_method, 1.0)) - float(method_rank.get(MultiplayerManager.seat_method, 1.0))) * 1.2
	var interval_delta := new_interval - MultiplayerManager.election_interval
	score += interval_delta * (1.0 if CardManager.is_government_party(bot) else -1.0)
	if score > 0.4:
		return GovernmentManager.VOTE_YES
	if score < -0.4:
		return GovernmentManager.VOTE_NO
	return GovernmentManager.VOTE_ABSTAIN

## ERKEN SEÇİM ÖNERGESİ: iktidardaki bot sandığa gitmek istemez; muhalefetteki
## bot ancak kamuoyu kendisine yarıyorsa evet der (yoksa meclisini kaybeder).
static func _early_election_vote(bot: int) -> int:
	if CardManager.is_government_party(bot):
		return GovernmentManager.VOTE_NO
	var support := CardManager.national_of(bot)
	if support > EARLY_ELECTION_SUPPORT:
		return GovernmentManager.VOTE_YES
	if support < -EARLY_ELECTION_SUPPORT:
		return GovernmentManager.VOTE_NO
	return GovernmentManager.VOTE_ABSTAIN

## ORTAK OLARAK ÇAĞRILAN BOT (koalisyon görüşmesi): teklif edilen makamların
## puanı, koalisyondaki sandalye payına göre hakkının altındaysa reddeder.
## İki partilik bir koalisyonda tek bakanlık (1 puan) hiçbir zaman yetmez.
static func _coalition_offer_vote(bot: int) -> int:
	if is_ally(bot, GovernmentManager.proposal_peer_id):
		return GovernmentManager.VOTE_YES  # kardeş partinin hükümetine katılır
	var offered := 0
	var gov_seats := float(GovernmentManager.seats_of(GovernmentManager.proposal_peer_id))
	for post in GovernmentManager.proposal_assignments.keys():
		if int(GovernmentManager.proposal_assignments[post]) == bot:
			offered += GovernmentPresets.post_points(String(post))
	for peer_id in GovernmentManager.proposal_partner_ids():
		gov_seats += float(GovernmentManager.seats_of(peer_id))
	var total_points := 0
	for post in GovernmentPresets.POSTS:
		total_points += int(post["points"])
	var share: float = float(GovernmentManager.seats_of(bot)) / maxf(1.0, gov_seats)
	# Hakkının en az COALITION_FAIR_SHARE'i teklif edilmeli; küçük ortak bile
	# sembolik bir bakanlıkla yetinmez (en az COALITION_MIN_POINTS puan).
	var required: float = maxf(float(COALITION_MIN_POINTS), float(total_points) * share * COALITION_FAIR_SHARE)
	# Eski ittifak ortağının hükümetine daha az makamla da girer.
	if CardManager.were_allies(bot, GovernmentManager.proposal_peer_id) or CardManager.are_allies(bot, GovernmentManager.proposal_peer_id):
		required = maxf(float(COALITION_MIN_POINTS), required * 0.75)
	if float(offered) + 0.01 < required:
		return GovernmentManager.VOTE_NO
	return GovernmentManager.VOTE_YES

## HÜKÜMETE ALINMAYAN BOT (meclis oylaması): azınlık hükümetine kolay geçit
## vermez — seçmen grupları çok yakın değilse reddeder. Çoğunluğu olan
## hükümeti ise durduramayacağı için grup yakınlığına göre oylar.
static func _government_confidence_vote(bot: int) -> int:
	var pm := int(GovernmentManager.proposal_assignments.get(GovernmentPresets.POST_PM, GovernmentManager.proposal_peer_id))
	var d := _friend_distance(bot, pm)
	var gov_seats := GovernmentManager.seats_of(GovernmentManager.proposal_peer_id)
	for peer_id in GovernmentManager.proposal_partner_ids():
		gov_seats += GovernmentManager.seats_of(peer_id)
	var minority: bool = gov_seats * 2 <= GovernmentManager.total_seats()
	if minority:
		# Dışarıda bırakıldı ve hükümetin çoğunluğu yok: güvenoyu bedava değil.
		if d < MINORITY_TRUST_DISTANCE:
			return GovernmentManager.VOTE_YES
		if d < MINORITY_TRUST_DISTANCE * 2.0:
			return GovernmentManager.VOTE_ABSTAIN
		return GovernmentManager.VOTE_NO
	if d < 2.5:
		return GovernmentManager.VOTE_YES
	if d < 4.0:
		return GovernmentManager.VOTE_ABSTAIN
	return GovernmentManager.VOTE_NO

## Muhalefetteki botun gensoru oyu. Hükümetin düşmesi ona yeni bir hükümet
## şansı verir: kendisi ya da kendisine hükümetten DAHA YAKIN olan gensoru
## sahibi hükümet kurabilir. Bu yüzden varsayılan EVET'tir; sadece hükümet
## seçmen grupları açısından çok yakınken ve gensoruyu veren belirgin biçimde uzakken
## çekimser kalır.
static func _censure_vote(bot: int) -> int:
	var gov := GovernmentManager.main_gov_peer_id
	if gov == -1:
		return GovernmentManager.VOTE_YES
	var d_gov := _distance(bot, gov)
	var d_prop := _distance(bot, GovernmentManager.proposal_peer_id)
	# Muhalefetin en büyük partisiyse hükümet kurma sırası ona gelebilir.
	var biggest_in_opposition := true
	for peer_id in GovernmentManager.voter_ids():
		if peer_id == bot or CardManager.is_government_party(peer_id):
			continue
		if GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(bot):
			biggest_in_opposition = false
	if biggest_in_opposition and d_gov >= 1.0:
		return GovernmentManager.VOTE_YES
	if d_prop <= d_gov:
		return GovernmentManager.VOTE_YES  # gensoruyu veren, hükümetten daha yakın
	if d_gov < CENSURE_LOYALTY_DISTANCE:
		return GovernmentManager.VOTE_ABSTAIN  # hükümet çok yakın: düşürmeye ortak olmaz
	return GovernmentManager.VOTE_YES

# --- Hükümet kurma -------------------------------------------------------------

## Seçmen grupları en yakın partilerle salt çoğunluğa ulaşana kadar koalisyon;
## bakanlıklar sandalyeyle orantılı. Reddedilince sonraki teklifte aday sırası
## kaydırılır (aynı teklifi tekrar tekrar sunmasın).
static func build_government(bot: int) -> Dictionary:
	var total := GovernmentManager.total_seats()
	# Ortak adayları PARTİLER (bağımsızlar hükümete giremez), kardeş parti önce.
	var candidates: Array = []
	for pid in GovernmentManager.seated_party_ids():
		if int(pid) != CardManager.party_of(bot) and not PartyManager.is_independent(int(pid)):
			candidates.append(int(pid))
	var bloc := _bloc_solidarity()
	candidates.sort_custom(func(a, b):
		if is_ally(bot, a) != is_ally(bot, b):
			return is_ally(bot, a)
		# Blok dayanışmasında önce diğer botlar ortak seçilir.
		if bloc and MultiplayerManager.is_bot(a) != MultiplayerManager.is_bot(b):
			return MultiplayerManager.is_bot(a)
		return _friend_distance(bot, a) < _friend_distance(bot, b))
	var shift := GovernmentManager.attempts_used % maxi(1, candidates.size())
	candidates = candidates.slice(shift) + candidates.slice(0, shift)
	# Döndürme blok dayanışmasını bozmasın: blok varken botlar yine önde kalır
	# (yoksa teklif hakkı el değiştirdikçe insan oyuncu koalisyona sızabiliyordu).
	if bloc:
		var bots: Array = []
		var others: Array = []
		for peer_id in candidates:
			if MultiplayerManager.is_bot(peer_id):
				bots.append(peer_id)
			else:
				others.append(peer_id)
		candidates = bots + others

	var partners: Array = []
	var seats := GovernmentManager.seats_of(bot)
	for peer_id in candidates:
		if seats * 2 > total:
			break
		partners.append(peer_id)
		seats += GovernmentManager.seats_of(peer_id)

	# MAKAMLAR ORTAKLARIN KABUL KURALINA GÖRE dağıtılır (bkz. _coalition_offer_vote):
	# her ortak koalisyondaki sandalye payının COALITION_FAIR_SHARE'i kadar (ve en
	# az COALITION_MIN_POINTS) makam puanı ister. Başbakanlık kurana kalır; diğer
	# makamlar büyükten küçüğe, açığı en büyük ortağa verilir, artanı kurana.
	var assignments := {}
	for post in GovernmentPresets.POSTS:
		assignments[post["id"]] = bot
	if partners.is_empty():
		return assignments
	var total_points := 0
	for post in GovernmentPresets.POSTS:
		total_points += int(post["points"])
	var required := {}
	var given := {}
	for peer_id in partners:
		var share := float(GovernmentManager.seats_of(peer_id)) / maxf(1.0, float(seats))
		required[peer_id] = maxf(float(COALITION_MIN_POINTS), float(total_points) * share * COALITION_FAIR_SHARE)
		given[peer_id] = 0
	var posts: Array = []
	for post in GovernmentPresets.POSTS:
		if post["id"] != GovernmentPresets.POST_PM:
			posts.append(post)
	posts.sort_custom(func(a, b): return int(a["points"]) > int(b["points"]))
	for post in posts:
		var pick := -1
		var deficit := 0.01
		for peer_id in partners:
			var missing: float = float(required[peer_id]) - float(given[peer_id])
			if missing > deficit:
				deficit = missing
				pick = peer_id
		if pick == -1:
			break  # herkes hakkını aldı: kalan makamlar kurana
		assignments[post["id"]] = pick
		given[pick] = int(given[pick]) + int(post["points"])
	return assignments
