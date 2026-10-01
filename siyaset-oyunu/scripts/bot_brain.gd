class_name BotBrain
extends RefCounted
## Botların KARARLARI (zamanlaması BotManager'da). Basit fayda puanı: her olası
## hamle oyunun kendi formülleriyle (seçim desteği, il gücü, miting riski,
## yasanın il etkileri...) kabaca puanlanır, en yükseği seçilir.
##
## BİLGİ KISITI: botlar da insanlar gibi illerin görüşünü BİLMEZ. Sadece
## teşkilat kurdukları illerde her eksenin hangi uçta ya da ortada olduğunu bilirler
## (bkz. _known_centers; gözcünün süresi bitse de görüş hatırlanır), bilmedikleri
## illeri nötr (0) sayarlar. Önce
## kimliklerini güçlendiren yasalar sunar, öğrendikçe yasalarını illere göre
## seçerler. Bu yüzden gözcü hamlesi botlar için de değerlidir. Miting riski
## ise insanlara da gösterilen bir ipucu olduğu için doğrudan kullanılır.
##
## HAMLE SINIRI YOK: BotManager, choose_action "pass" (turu bitir) diyene kadar
## hamle yaptırır. Her seçeneğin puanından mana bedeli × MANA_VALUE düşülür;
## böylece bot ucuz ama değersiz hamlelere manasını dağıtmaz, biriktirir.

## En iyi kartın puanı bunun altındaysa bot kart oynamaz (el doluysa oynar).
const PASS_THRESHOLD := 0.4
## Ana hamlelerin taban puanları.
const PASS_ACTION_SCORE := 0.7
## Bir mananın puan karşılığı (hamle puanından bedel × bu değer düşülür).
const MANA_VALUE := 0.3
## Gözcü bilgisinden tahmin edilen eksen değeri (uç biliniyor, büyüklük değil).
const LEANING_ESTIMATE := 2.0
## Yasanın taban puanı: yasa her tur meclisi durdurur, bot onu sadece gerçekten
## işe yarayacaksa sunsun (miting / il başkanlığı / kartlar öne geçebilsin).
const LAW_BASE_SCORE := 1.0
## Bot bir yasayı en fazla bu kadar turda bir sunar.
const LAW_EVERY_ROUNDS := 2
## Muhalefetteki bot, hükümete bu mesafeden yakınsa gensoruda çekimser kalır.
const CENSURE_LOYALTY_DISTANCE := 1.2
## Erken seçime EVET demek için gereken ulusal kamuoyu eşiği.
const EARLY_ELECTION_SUPPORT := 1.0
## Koalisyon ortağı, sandalye payına düşen makam puanının en az bu oranını ister.
const COALITION_FAIR_SHARE := 0.75
## Ortak olacak parti en az bu kadar makam puanı ister (1 bakanlık yetmez).
const COALITION_MIN_POINTS := 2
## Hükümete alınmayan bot, azınlık hükümetine ancak bu mesafeden yakınsa güvenoyu verir.
const MINORITY_TRUST_DISTANCE := 1.0

# --- BOT BLOĞU ------------------------------------------------------------------
## Hükümeti bir İNSAN partisi kurduysa muhalefetteki botlar birleşir:
##   1. Hepsi vekil çalma kartlarını hükümetin ana partisine yöneltir; bloğun
##      en büyük botunu birinci parti yapmak (hükümet kurma yetkisi sırası
##      sandalyeye göre) ve hükümeti azınlığa düşürmek ek puan kazandırır.
##   2. Gensoruyu blok olarak hesaplar ve oylar (ideolojik yakınlık fark etmez).
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
	for peer_id in GovernmentManager.voter_ids():
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

static func _ideology(peer_id: int) -> Dictionary:
	return PartyManager.parties.get(peer_id, {}).get("ideology", IdeologyAxes.default_values())

static func _seats() -> Dictionary:
	return CardManager._province_seat_counts

static func _total_seats() -> float:
	return float(maxi(1, CardManager.TOTAL_SEATS))

## Botun bildiği il görüşleri: province_id -> tahmini merkez. Gözcü gönderilmemiş
## iller boş sözlük (= nötr) döner.
static func _known_centers(bot: int) -> Dictionary:
	var result := {}
	for province_id in _seats().keys():
		if not CardManager.knows_leaning(bot, province_id):
			result[province_id] = {}
			continue
		var center := CardManager.province_center(province_id)
		var estimate := {}
		for axis in IdeologyAxes.AXES:
			# Teşkilat raporu gibi kaba: yarım adıma yuvarlanmış görüş.
			estimate[axis] = snappedf(float(center.get(axis, 0.0)), 0.5)
		result[province_id] = estimate
	return result

## İdeolojinin tüm ülkedeki (bilinen) seçmen desteği (milletvekili ağırlıklı).
## Görüşü bilinmeyen iller sayılmaz: onları nötr saymak her yasayı (nötrden
## uzaklaştırdığı için) zararlı gösterir, botlar hep aynı yedek yasaya düşerdi.
static func _electoral_strength(ideology: Dictionary, known: Dictionary) -> float:
	var seats := _seats()
	var weighted := 0.0
	for province_id in seats.keys():
		var center: Dictionary = known.get(province_id, {})
		if center.is_empty():
			continue
		weighted += ElectionModel.support(ideology, center) * float(seats[province_id])
	return weighted / _total_seats()

static func _election_soon() -> bool:
	var next := GameRules.next_election_round(CardManager.round_number)
	return next != -1 and next - CardManager.round_number <= 1

# --- Ana hamle ------------------------------------------------------------------

## Manası bol olan bot için mana ucuzdur (birikip boşa durmasın), azsa değerlidir.
static func _mana_value(bot: int) -> float:
	return MANA_VALUE * clampf(4.0 / maxf(1.0, float(CardManager.mana_of(bot))), 0.2, 1.5)

## Dönüş: {"type": "card"} | {"type": "law", "law"} | {"type": "organization",
## "province"} | {"type": "miting", "province"} | |
## {"type": "pass"}
static func choose_action(bot: int) -> Dictionary:
	# MECLİS KONUŞMASI zorunlu: her şeyden önce.
	if CardManager.needs_speech(bot):
		return choose_speech(bot)
	var known := _known_centers(bot)
	var best := {"type": "pass"}
	var best_score := PASS_ACTION_SCORE
	var mana_value := _mana_value(bot)

	var hand: Array = CardManager.inventories.get(bot, [])
	var play := choose_play(bot)
	if not play.is_empty():
		var card: String = hand[int(play["index"])]
		var card_score := float(play["score"]) - CardPresets.card_cost(card) * mana_value
		if card_score > best_score:
			best = {"type": "card"}
			best_score = card_score

	if CardManager.can_propose_law(bot):
		var law := _best_law(bot, known)
		# Yasa sıklığı sınırı (her gündem turunda herkes yasa sunup meclisi kilitlemesin).
		var rested: bool = CardManager.round_number - int(CardManager.law_rounds.get(bot, -99)) >= LAW_EVERY_ROUNDS
		if not rested:
			law = {}
		var law_cost: int = CardManager.law_mana_cost(bot, String(law.get("law", "")))
		if not law.is_empty() and CardManager.can_propose_law(bot, String(law["law"])) and float(law["score"]) - law_cost * mana_value > best_score:
			best = {"type": "law", "law": law["law"]}
			best_score = float(law["score"]) - law_cost * mana_value

	# Anayasa teklifi yasa hakkını kullanır; o yüzden yasayla yarışır.
	var constitution := _best_constitution(bot)
	if not constitution.is_empty() and float(constitution["score"]) > best_score:
		best = {"type": "constitution", "payload": constitution["payload"]}
		best_score = float(constitution["score"])

	var org := _best_organization(bot, known)
	if not org.is_empty() and float(org["score"]) - GameRules.ORG_MANA_COST * mana_value > best_score:
		best = {"type": "organization", "province": org["province"]}
		best_score = float(org["score"]) - GameRules.ORG_MANA_COST * mana_value

	if CardManager.can_invest(bot):
		var invest := _eval_investment(bot, known)
		if not invest.is_empty() and float(invest["score"]) - GameRules.INVEST_MANA_COST * mana_value > best_score:
			best = {"type": "invest", "province": invest["province"]}
			best_score = float(invest["score"]) - GameRules.INVEST_MANA_COST * mana_value

	if CardManager.can_censure(bot) and _censure_worth_it(bot):
		# Geçeceği hesaplanan gensoru: hükümet düşer, yeni kurma turu başlar.
		# Blokta gensoru planın son adımı: çok daha değerli.
		var censure_score := 7.0 if bloc_active() else 4.0
		if censure_score - GameRules.CENSURE_MANA_COST * mana_value > best_score:
			best = {"type": "censure"}
			_bloc_forming = bloc_active()
			best_score = censure_score - GameRules.CENSURE_MANA_COST * mana_value

	if CardManager.can_miting(bot):
		var miting := _eval_miting(bot, known)
		if not miting.is_empty() and float(miting["score"]) - GameRules.MITING_MANA_COST * mana_value > best_score:
			best = {"type": "miting", "province": miting["province"]}
			best_score = float(miting["score"]) - GameRules.MITING_MANA_COST * mana_value

	return best

## MECLİS KONUŞMASI: 6 uçtan, bilinen illerde desteği en çok artıran; bot
## kendi tarafında ılımlı-belirgin (|1,5| civarı) bir çizgide durmayı sever ve
## taraf değiştirmekten kaçınır.
static func choose_speech(bot: int) -> Dictionary:
	var known := _known_centers(bot)
	var mine := _ideology(bot)
	var base := _electoral_strength(mine, known)
	var best := {}
	var best_score := -INF
	for axis in IdeologyAxes.AXES:
		for dir in [-1, 1]:
			var v := float(mine.get(axis, 0.0))
			var moved := mine.duplicate()
			moved[axis] = IdeologyAxes.clamp_value(v + IdeologyAxes.SPEECH_SHIFT * dir)
			var nv := float(moved[axis])
			var score := (_electoral_strength(moved, known) - base) * 20.0
			score -= absf(absf(nv) - 1.5) * 0.4
			if absf(v) > 0.25 and signf(nv) != signf(v):
				score -= 0.6
			# Eşitlikte botlar hep aynı konuşmayı yapmasın.
			score += float((absi(bot) + CardManager.round_number + axis.length() * (dir + 2)) % 7) * 0.01
			if score > best_score:
				best_score = score
				best = {"type": "speech", "axis": axis, "dir": dir}
	return best

## Seçim desteğini en çok artıracak yasa: bilinen illerdeki etkiler (geçme
## ihtimaliyle) + partinin görüş kaymasının seçmene yaklaştırması.
static func _best_law(bot: int, known: Dictionary) -> Dictionary:
	var seats := _seats()
	var in_parliament := not CardManager.last_seats.is_empty()
	var mine := _ideology(bot)
	var best := {}
	# Sadece gözcü gönderilmiş illerden çıkarım yapılır: ortalama etki × güven
	# (bilinen vekil oranı arttıkça bot yasaya daha çok güvenir).
	var known_seats := 0.0
	for province_id in seats.keys():
		if not (known.get(province_id, {}) as Dictionary).is_empty():
			known_seats += float(seats[province_id])
	if known_seats <= 0.0:
		return _exploration_law(bot, mine)
	var confidence := clampf(known_seats / 60.0, 0.3, 1.0)
	for axis in _law_axes():
		for dir in [-1, 1]:
			var law_type := CardPresets.law_type(axis, dir)
			var sum := 0.0
			for province_id in seats.keys():
				if (known.get(province_id, {}) as Dictionary).is_empty():
					continue
				var alignment := PublicOpinion.law_alignment(known[province_id], axis, dir)
				sum += float(seats[province_id]) * PublicOpinion.law_proposer_delta(alignment, false)
			var value := sum / known_seats * confidence * CardManager.agenda_law_mult(law_type)
			if in_parliament:
				var pass_chance := _law_pass_chance(bot, law_type, known)
				value *= 1.0 + pass_chance * (PublicOpinion.LAW_PASSED_MULT - 1.0)
				# Kabul edilen yasa puan tablosuna ciddi puan yazar.
				value += pass_chance * CardManager.law_pass_score(CardManager.is_government_party(bot)) * 0.12
			var moved := mine.duplicate()
			moved[axis] = IdeologyAxes.clamp_value(float(mine.get(axis, 0)) + IdeologyAxes.LAW_PROPOSE_SHIFT * dir)
			value += (_electoral_strength(moved, known) - _electoral_strength(mine, known)) * 20.0
			var score := LAW_BASE_SCORE + value * 5.0 - _repeat_penalty(bot, law_type)
			if best.is_empty() or score > float(best["score"]):
				best = {"law": law_type, "score": score}
	# Tahmin gürültülü ya da bütün yasalar zararlı görünüyorsa kimlik yasası
	# (partinin belirgin ekseni) yedek seçenektir: meclis oyunu durmasın.
	var exploration := _exploration_law(bot, mine)
	if known_seats >= 60.0:
		exploration["score"] = 0.8
	if float(exploration["score"]) > float(best["score"]):
		return exploration
	return best

## Hiç il bilinmiyorken: parti kimliğini güçlendiren (en belirgin ekseninde)
## yasa; kimlik yoksa bota ve tura göre bir eksen. Çok iyi bir kart (ör. büyük
## ilde gözcü) varsa o önce gelir. Yasa partiyi kaydırdıkça kimlik oluşur.
static func _exploration_law(bot: int, mine: Dictionary) -> Dictionary:
	# En az kullandığı eksen; yön partinin o eksendeki eğilimi (yoksa bota göre).
	var best_law := ""
	var best_penalty := INF
	var offset := absi(bot) + CardManager.round_number
	var axes := _law_axes()
	for i in axes.size():
		var axis: String = axes[(i + offset) % axes.size()]
		var v := float(mine.get(axis, 0))
		var dir := 1 if v > 0 else (-1 if v < 0 else (1 if (absi(bot) / 7 + i) % 2 == 0 else -1))
		var law_type := CardPresets.law_type(axis, dir)
		var penalty := _repeat_penalty(bot, law_type)
		if penalty < best_penalty:
			best_penalty = penalty
			best_law = law_type
	return {"law": best_law, "score": 1.0}

## Yasa sunulabilecek eksenler: sadece gündemdeki eksen (gündem yoksa hepsi;
## zaten yasa sunulamaz).
static func _law_axes() -> Array:
	var current := CardManager.agenda_type()
	if current == "":
		return IdeologyAxes.AXES
	return [CardPresets.agenda_data(current)["axis"]]

## Botun son sunduğu yasalar: aynı yasayı (ve aynı ekseni) üst üste sunmasın.
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
		elif not law.is_empty() and CardPresets.law_data(previous).get("axis", "") == law["axis"]:
			penalty += 0.35
	return penalty

## Kaba geçme ihtimali: diğer partilerin oyu, botun kendi bilgisiyle tahmin edilir.
static func _law_pass_chance(bot: int, law_type: String, known: Dictionary) -> float:
	var gov_ids := GovernmentManager.government_party_ids()
	var yes := GovernmentManager.seats_of(bot)
	var no := 0
	for peer_id in GovernmentManager.voter_ids():
		if peer_id == bot:
			continue
		match _best_law_vote(peer_id, law_type, bot, gov_ids, known):
			GovernmentManager.VOTE_YES:
				yes += GovernmentManager.seats_of(peer_id)
			GovernmentManager.VOTE_NO:
				no += GovernmentManager.seats_of(peer_id)
	return 0.85 if yes > no else 0.15

## Bir partinin bir yasaya EVET/HAYIR demesinin (bilinen) il etkilerinin vekil
## ağırlıklı toplamı.
static func _law_vote_value(voter: int, law_type: String, choice: int, proposer: int, gov_ids: Array, known: Dictionary) -> float:
	var law := CardPresets.law_data(law_type)
	if law.is_empty() or choice == GovernmentManager.VOTE_ABSTAIN:
		return 0.0
	var seats := _seats()
	var sum := 0.0
	for province_id in seats.keys():
		var alignment := PublicOpinion.law_alignment(known.get(province_id, {}), law["axis"], int(law["dir"]))
		sum += float(seats[province_id]) * PublicOpinion.law_vote_delta(alignment, choice, gov_ids.has(voter), gov_ids.has(proposer))
	return sum / _total_seats()

static func _best_law_vote(voter: int, law_type: String, proposer: int, gov_ids: Array, known: Dictionary) -> int:
	var best := GovernmentManager.VOTE_ABSTAIN
	var best_value := 0.0
	for choice in [GovernmentManager.VOTE_YES, GovernmentManager.VOTE_NO]:
		var value := _law_vote_value(voter, law_type, choice, proposer, gov_ids, known)
		if value > best_value + 0.01:
			best_value = value
			best = choice
	# İktidar muhalefetin yasasını genelde reddeder: yasa geçerse getiren 2 kat güçlenir.
	if gov_ids.has(voter) and not gov_ids.has(proposer) and best == GovernmentManager.VOTE_ABSTAIN:
		best = GovernmentManager.VOTE_NO
	return best

## Vekili çok, partiye (bilindiği kadarıyla) yakın ve henüz teşkilatı zayıf il.
static func _best_organization(bot: int, known: Dictionary) -> Dictionary:
	var seats := _seats()
	var mine := _ideology(bot)
	var best := {}
	for province_id in seats.keys():
		if not CardManager.can_build_organization(bot, province_id):
			continue
		var level := CardManager.organization_level(province_id, bot)
		# 2 mana: kalıcı ama pahalı — büyük illerde bile yasa/kartla yarışacak kadar.
		var center: Dictionary = known.get(province_id, {})
		# Bilinmeyen il: yakınlık orta varsayılır (nötr merkez parti için aldatıcı derecede yakın görünürdü).
		var closeness := ElectionModel.support(mine, center) if not center.is_empty() else 0.5
		# Kalıcı oy bonusu (seviye farkı) + bilgi: 1. seviye ilin görüşünü, 2-3 anketi açar.
		var gain := PublicOpinion.org_activity(level + 1) - PublicOpinion.org_activity(level)
		var value := float(seats[province_id]) * (0.5 + closeness) / 30.0 * gain / 1.2 * 0.8
		if level == 0:
			value += 0.25 + float(seats[province_id]) / 40.0
		var score := 1.0 + value * (1.3 if _election_soon() else 1.0)
		if best.is_empty() or score > float(best["score"]):
			best = {"province": province_id, "score": score}
	return best

# --- Sıra: hangi kart? ---------------------------------------------------------

## Dönüş: {"index", "peer", "province", "score"} ya da boş sözlük (= oynama).
static func choose_play(bot: int) -> Dictionary:
	var known := _known_centers(bot)
	var hand: Array = CardManager.inventories.get(bot, [])
	var best := {}
	var best_score := PASS_THRESHOLD
	if hand.size() >= CardManager.MAX_HAND_SIZE:
		best_score = -INF  # el dolu: en iyisini oyna, desteyi tıkama
	for i in hand.size():
		var option := _evaluate(bot, String(hand[i]), known)
		if option.is_empty():
			continue
		if float(option["score"]) > best_score:
			best_score = float(option["score"])
			best = option
			best["index"] = i
	return best

static func _evaluate(bot: int, card_type: String, known: Dictionary) -> Dictionary:
	if CardManager.mana_of(bot) < CardPresets.card_cost(card_type):
		return {}
	match card_type:
		CardPresets.POPULISM_CARD_TYPE:
			# Seçime az kala ya da hiç popülizm yokken değerli.
			if CardManager.populism_rounds_left(bot) > 0:
				return {}
			return {"score": 2.2 if _election_soon() else 1.4, "peer": -1, "province": ""}
		CardPresets.MANA_BONUS_CARD_TYPE, CardPresets.MANA_BONUS_STRONG_CARD_TYPE:
			# Manası azken, yapacak başka şey yokken kullanılır.
			return {"score": 0.9 if CardManager.mana_of(bot) < GameRules.MITING_MANA_COST else 0.3, "peer": -1, "province": ""}
		CardPresets.BONUS_CARD_TYPE:
			var room := CardManager.MAX_HAND_SIZE - hand_size(bot) + 1
			return {} if room < 2 else {"score": 1.1, "peer": -1, "province": ""}
		CardPresets.CARD_THEFT_CARD_TYPE:
			return _eval_card_theft(bot)
		CardPresets.PROPAGANDA_CARD_TYPE:
			return _eval_propaganda(bot, known)
	if CardPresets.needs_target(card_type):
		return _eval_steal(bot, card_type)
	if card_type == CardPresets.REPUTATION_CARD_TYPE:
		return _eval_reputation(bot)
	if card_type == CardPresets.REBELLION_CARD_TYPE:
		return _eval_rebellion(bot)
	return {}

## Kaset: en büyük rakibin (blok varsa insan hükümetinin) ulusal desteğini vurur.
static func _eval_reputation(bot: int) -> Dictionary:
	if CardManager.is_referendum_active():
		var rival := _referendum_opponent(bot)
		return {} if rival == -1 else {"score": 2.8, "peer": rival, "province": ""}
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
		if peer_id == bot or hand_size(peer_id) == 0:
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
	for peer_id in CardManager.turn_order:
		if peer_id == bot:
			continue
		if target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target):
			target = peer_id
	return target

## Beklenen il gücü kazancı × ilin vekil sayısı × partinin o ildeki (bilinen) şansı.
static func _eval_miting(bot: int, known: Dictionary) -> Dictionary:
	if CardManager.is_referendum_active():
		return _eval_referendum_miting(bot)
	var ideology := _ideology(bot)
	var best_province := ""
	var best_value := -INF
	for province_id in _seats().keys():
		# Miting teşkilat ister; örgütsüz iller elenir.
		var org_level := CardManager.organization_level(String(province_id), bot)
		if org_level < 1:
			continue
		var org_mult := PublicOpinion.org_action_mult(org_level)
		var risk := CardManager.miting_risk(bot, province_id)
		var seats := float(CardManager.province_seat_count(province_id))
		var closeness := ElectionModel.support(ideology, known.get(province_id, {}))
		var expected := (1.0 - risk) * PublicOpinion.MITING_LOCAL + risk * PublicOpinion.PROVOCATION_LOCAL
		# İl başkanlığıyla aynı ölçek (vekil/30). Zaten güçlü olduğu ilde getirisi azalır.
		var diminish := 1.0 / (1.0 + maxf(0.0, CardManager.activity_of(province_id, bot)) / 2.0)
		var value := (expected / PublicOpinion.MITING_LOCAL * seats / 30.0 * (0.5 + closeness) * diminish \
			+ (1.0 - risk) * PublicOpinion.MITING_NATIONAL + risk * PublicOpinion.PROVOCATION_NATIONAL) * org_mult
		if value > best_value:
			best_value = value
			best_province = province_id
	if best_province == "":
		return {}
	var score := best_value * 1.4 * (1.4 if _election_soon() else 1.0)
	return {"score": score, "peer": -1, "province": best_province}

# --- Referandum kampanyası -------------------------------------------------------------

## Referandumda kararını (EVET/HAYIR) savunan bot: kendi kampanyasının en zayıf
## olduğu büyük illerde miting yapar. Çekimser bot kampanyaya katılmaz.
static func _eval_referendum_miting(bot: int) -> Dictionary:
	if CardManager.referendum_side(bot) == GovernmentManager.VOTE_ABSTAIN:
		return {}
	var best := ""
	var best_value := -INF
	for province_id in _seats().keys():
		var seats := float(CardManager.province_seat_count(province_id))
		var risk := CardManager.miting_risk(bot, province_id)
		var value := seats * (1.0 - risk * 1.5) / (1.0 + maxf(0.0, CardManager.ref_local_of(province_id, bot)) / 3.0)
		if value > best_value:
			best_value = value
			best = province_id
	if best == "":
		return {}
	return {"score": 1.6 + best_value / 8.0, "peer": -1, "province": best}

## Referandumda karşı taraftaki en büyük parti (karalama/kaset hedefi).
static func _referendum_opponent(bot: int) -> int:
	var side := CardManager.referendum_side(bot)
	if side == GovernmentManager.VOTE_ABSTAIN:
		return -1
	var target := -1
	for peer_id in CardManager.turn_order:
		if peer_id == bot or CardManager.referendum_side(peer_id) != -side:
			continue
		if target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target):
			target = peer_id
	return target

static func _eval_investment(bot: int, known: Dictionary) -> Dictionary:
	if not CardManager.is_government_party(bot):
		return {}
	var ideology := _ideology(bot)
	var best_province := ""
	var best_value := -INF
	for province_id in _seats().keys():
		var value := float(CardManager.province_seat_count(province_id)) \
			* (0.5 + ElectionModel.support(ideology, known.get(province_id, {})))
		if value > best_value:
			best_value = value
			best_province = province_id
	# İl başkanlığı ve mitingle aynı ölçek (vekil/30).
	return {"score": 0.8 + best_value / 30.0 * 1.2 * (1.3 if _election_soon() else 1.0), "peer": -1, "province": best_province}

## En büyük rakibi, en çok vekilli ve onun zayıf, botun güçlü olduğu ilde karala.
static func _eval_propaganda(bot: int, known: Dictionary) -> Dictionary:
	if CardManager.is_referendum_active():
		# Referandumda karşı kampanyayı en kalabalık ilde karala.
		var rival := _referendum_opponent(bot)
		if rival == -1:
			return {}
		var biggest := ""
		for province_id in _seats().keys():
			if biggest == "" or CardManager.province_seat_count(province_id) > CardManager.province_seat_count(biggest):
				biggest = province_id
		return {"score": 2.2, "peer": rival, "province": biggest}
	var best := {}
	var best_value := -INF
	for province_id in _seats().keys():
		# Karalama da teşkilat ister.
		var org_level := CardManager.organization_level(String(province_id), bot)
		if org_level < 1:
			continue
		var seats := float(CardManager.province_seat_count(province_id)) * PublicOpinion.org_action_mult(org_level)
		var center: Dictionary = known.get(province_id, {})
		var gain := PublicOpinion.propaganda_gain(PublicOpinion.party_strength(
			_ideology(bot), center, CardManager.activity_of(province_id, bot)))
		for target in CardManager.turn_order:
			if target == bot:
				continue
			var damage := PublicOpinion.propaganda_damage(PublicOpinion.party_strength(
				_ideology(target), center, CardManager.activity_of(province_id, target)))
			var rival := 1.0 + float(GovernmentManager.seats_of(target)) / _total_seats() * 2.0
			var value := (gain + damage * 0.6 * rival) * seats / 6.0
			if value > best_value:
				best_value = value
				best = {"peer": target, "province": province_id}
	if best.is_empty():
		return {}
	best["score"] = best_value * 0.45
	return best

## İktidardaysa en büyük muhalefetten, muhalefetteyse hükümetten çal.
static func _eval_steal(bot: int, card_type: String) -> Dictionary:
	if bloc_active() and bloc_members().has(bot):
		var bloc := _eval_bloc_steal(bot, card_type)
		if not bloc.is_empty():
			return bloc
	var in_gov := CardManager.is_government_party(bot)
	var target := -1
	for peer_id in CardManager.turn_order:
		if not CardManager.is_valid_steal_target(bot, peer_id):
			continue
		if GovernmentManager.has_government() and CardManager.is_government_party(peer_id) == in_gov:
			continue
		if target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target):
			target = peer_id
	if target == -1:
		for peer_id in CardManager.turn_order:
			if CardManager.is_valid_steal_target(bot, peer_id) \
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
		elif ElectionModel.distance(_ideology(peer_id), _ideology(main_gov)) < 2.0:
			continue  # çekimser
		else:
			yes += GovernmentManager.seats_of(peer_id)
	return yes > no

# --- Oylama --------------------------------------------------------------------

static func choose_vote(bot: int) -> int:
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
				GovernmentManager.proposal_gov_ids, _known_centers(bot))
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
##     kazandıracaksa (kalesi olmayan, az ilde birinci rakipler ezilir).
##   - Hare: küçük parti (%20 altı) daha orantılı sayım ister.
## Teklif ancak meclisin salt çoğunluğunun (referandum yolu) EVET demesi
## bekleniyorsa yapılır; insanların oyu bilinmez, sayılmaz.
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
		if yes < GovernmentManager.referendum_threshold_seats():
			continue
		var score := 1.6 + float(option["urgency"]) + float(struggling) * 0.2
		if yes >= GovernmentManager.constitution_threshold_seats():
			score += 0.5  # referandumsuz geçer
		if best.is_empty() or score > float(best["score"]):
			best = {"payload": payload, "score": score}
	return best

## "Kazanan hepsini alır" olsaydı son seçimin il sonuçlarıyla bu parti kaç
## il vekili KAZANIR (+) ya da KAYBEDERDİ (−): birinci olduğu illerin bütün
## vekilleri eksi şu anki il vekilleri. Kalesi olmayan, az ilde birinci
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
	var new_interval := int(payload.get("interval", MultiplayerManager.election_interval))
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
	var interval_delta := float(new_interval - MultiplayerManager.election_interval)
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
	if float(offered) + 0.01 < required:
		return GovernmentManager.VOTE_NO
	return GovernmentManager.VOTE_YES

## HÜKÜMETE ALINMAYAN BOT (meclis oylaması): azınlık hükümetine kolay geçit
## vermez — ideolojik olarak çok yakın değilse reddeder. Çoğunluğu olan
## hükümeti ise durduramayacağı için ideolojik yakınlığa göre oylar.
static func _government_confidence_vote(bot: int) -> int:
	var pm := int(GovernmentManager.proposal_assignments.get(GovernmentPresets.POST_PM, GovernmentManager.proposal_peer_id))
	var d := ElectionModel.distance(_ideology(bot), _ideology(pm))
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
## ideolojik olarak çok yakınken ve gensoruyu veren belirgin biçimde uzakken
## çekimser kalır.
static func _censure_vote(bot: int) -> int:
	var gov := GovernmentManager.main_gov_peer_id
	if gov == -1:
		return GovernmentManager.VOTE_YES
	var d_gov := ElectionModel.distance(_ideology(bot), _ideology(gov))
	var d_prop := ElectionModel.distance(_ideology(bot), _ideology(GovernmentManager.proposal_peer_id))
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

## İdeolojik olarak en yakın partilerle salt çoğunluğa ulaşana kadar koalisyon;
## bakanlıklar sandalyeyle orantılı. Reddedilince sonraki teklifte aday sırası
## kaydırılır (aynı teklifi tekrar tekrar sunmasın).
static func build_government(bot: int) -> Dictionary:
	var total := GovernmentManager.total_seats()
	var mine := _ideology(bot)
	var candidates: Array = GovernmentManager.voter_ids()
	candidates.erase(bot)
	var bloc := _bloc_solidarity()
	candidates.sort_custom(func(a, b):
		# Blok dayanışmasında önce diğer botlar ortak seçilir.
		if bloc and MultiplayerManager.is_bot(a) != MultiplayerManager.is_bot(b):
			return MultiplayerManager.is_bot(a)
		return ElectionModel.distance(mine, _ideology(a)) < ElectionModel.distance(mine, _ideology(b)))
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

	var assignments := {}
	var ministries: Array = []
	for post in GovernmentPresets.POSTS:
		assignments[post["id"]] = bot
		if post["id"] != GovernmentPresets.POST_PM and post["id"] != GovernmentPresets.POST_DEPUTY_PM:
			ministries.append(post["id"])
	if partners.is_empty():
		return assignments
	assignments[GovernmentPresets.POST_DEPUTY_PM] = partners[0]
	var slot := 0
	for peer_id in partners:
		var share := maxi(1, int(round(ministries.size() * float(GovernmentManager.seats_of(peer_id)) / float(seats))))
		for i in share:
			if slot >= ministries.size() - 1:  # görevli parti en az bir bakanlık tutsun
				break
			assignments[ministries[slot]] = peer_id
			slot += 1
	return assignments
