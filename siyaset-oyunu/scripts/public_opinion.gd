class_name PublicOpinion
extends RefCounted
## GÜÇ kuralları — saf fonksiyonlar, durum CardManager'da.
##
## Bir partinin bir ildeki seçim desteği iki katmandan oluşur:
##   - GRUP UYUMU: partinin 8 seçmen grubundaki ULUSAL yakınlıkları ile ilin
##     seçmen profilinin (4 ikili dağılım) uyumu (bkz. VoterGroups.appeal,
##     ElectionModel.support). İl profilleri oyun boyunca DEĞİŞMEZ; değişen,
##     partilerin gruplardaki yakınlığıdır:
##       * YASA  : hedef grupta ulusal yakınlık (kalıcı), karşıt grupta daha
##                 küçük kayıp,
##       * MİTİNG: partinin hitabı ilin baskın gruplarına kayar: o gruplarda
##                 ulusal yakınlık (kalıcı, azalan getirili), karşıtlarda
##                 daha küçük kayıp,
##       * GRUP TOPLANTISI: seçilen grupta GEÇİCİ bonus (+10 / +3 / +1, sonra 0).
##   - AKTİVİTE (yerel memnuniyet): o ilde yapılanlar — miting, YATIRIM,
##     karalama (il puanı, tur sonunda söner) + teşkilat (seviye başına kalıcı
##     puan). Yatırım grup yakınlığına DOKUNMAZ; sadece burayı büyütür.
## Seçimde grup uyumunun ağırlığı şu çarpanla çarpılır:
##   1 + EFFECT_PER_POINT * (ulusal + aktivite)    (MIN_MULT..MAX_MULT arasında)
## Aynı etki iki kez yazılmaz: miting il aktivitesi + grup yakınlığı (iki ayrı
## katman) yazar, artık ayrıca ulusal puan yazmaz.
##
## Dengeyi değiştirmek için sadece bu dosyadaki sabitleri düzenlemek yeterli.

## Denge simülasyonuyla ayarlandı (tools/balance_sim.gd): güç puanları seçimi
## şanstan daha çok belirlesin, son turların hamleleri ağır bassın.
const EFFECT_PER_POINT := 0.10
const MIN_MULT := 0.3
const MAX_MULT := 2.0
## Bir puanın mutlak değer olarak ulaşabileceği en yüksek seviye.
const LIMIT := 10.0
## Tur sonu sönme katsayıları (düşük = eski hamleler çabuk unutulur).
const NATIONAL_DECAY := 0.75
const LOCAL_DECAY := 0.72

# --- Miting -----------------------------------------------------------------
## Yerel etki: ildeki aktivite (söner).
const MITING_LOCAL := 5.0
## ULUSAL YANSIMA (siyasi hitap): ilde çiftin baskın tarafı s payındaysa
## eğilim t = (s − 0,5) × 2; baskın gruba MITING_GROUP_GAIN × t ulusal
## yakınlık, karşıt gruba bunun grubun miting_backlash oranı kadar kayıp.
## t, MITING_MIN_LEAN'den küçükse (dengeli çift) o çiftte etki yok.
const MITING_GROUP_GAIN := 5.0
const MITING_MIN_LEAN := 0.1
## AZALAN GETİRİ: aynı gruba art arda miting yorgunluk biriktirir:
## kazanç × 1 / (1 + yorgunluk / FATIGUE_SCALE); yorgunluk her tur × DECAY.
const MITING_FATIGUE_SCALE := 6.0
const MITING_FATIGUE_DECAY := 0.6
const PROVOCATION_LOCAL := -2.5
const PROVOCATION_NATIONAL := -1.0
## Provokasyon riski: partinin ildeki GRUP UYUMU (0..100) SAFE_APPEAL ve
## üstündeyse risk yok; FULL_APPEAL'e indikçe MAX_RISK'e çıkar (il seçmeni
## partinin hitap ettiği gruplara uzak). İl başkanlığı riski seviye başına azaltır.
const PROVOCATION_MAX_RISK := 0.5
const PROVOCATION_SAFE_APPEAL := 50.0
const PROVOCATION_FULL_APPEAL := 40.0

# --- Yatırım (sadece hükümet partileri) ---------------------------------------
## YEREL MEMNUNİYET: yatırım partinin siyasi kimliğine (grup yakınlığına)
## dokunmaz; ildeki herkesin partiye yaklaşmasını sağlar (il aktivitesi).
## INVEST_NATIONAL mevcut ekonomik yansımadır (genel ulusal puan, grup değil).
## Azalan getiri: il puanı LIMIT ile sınırlı; aynı ile art arda yatırım tavana
## dayanınca daha az getirir.
const INVEST_LOCAL := 10.0
const INVEST_NATIONAL := 2.0
const INVEST_PARTNER_LOCAL := 4.0

# --- Popülizm bonusu -----------------------------------------------------------
## Popülizm süren partinin KENDİ hamlelerinin (miting, yatırım, yasa, oy,
## karalama kazancı, gensoru) iyi sonuçları bu çarpanla büyür, kötü sonuçları
## küçülür. Ayrıca karalamanın hasarı ve teşkilatın oy bonusu da bu çarpanla
## büyür, vekil çalma POPULISM_STEAL_MULT kat vekil getirir. Başkalarının ona
## yaptığı karalama etkilenmez.
const POPULISM_GOOD_MULT := 2.0
const POPULISM_BAD_MULT := 0.25
## Popülizm sürerken seçim yapılırsa partinin ulusal puanına eklenir.
const POPULISM_ELECTION_NATIONAL := 1.5
const POPULISM_STEAL_MULT := 1.5

# --- İktidar dengesi ----------------------------------------------------------
## Seçim anında hükümette olan her partiye eklenen ulusal puan. İktidar zaten
## yapısal olarak kaybeder (en büyük parti olmak, saldırıların hedefi olmak):
## bu değer yokken iktidar bir sonraki seçimde ortalama 44 vekil, eski −1.6 ile
## 67 vekil kaybediyordu. +1.1 bu dezavantajı yarıya indirir (bot simülasyonu,
## 40 oyun: iktidar −32, muhalefet +25). İktidar yine dezavantajlıdır.
const GOVERNMENT_FATIGUE := 1.1

# --- Gensoru ------------------------------------------------------------------
## Reddedilen gensoruyu getiren parti bu kadar ulusal destek kaybeder.
const CENSURE_REJECTED_NATIONAL := -0.25
## KRİZE YANIT: krizin istediği gruba yasa sunan, o yasaya EVET diyen ya da o
## grupla toplantı yapan parti bu kadar ulusal puan kazanır. Kısmi: oyunu tek
## başına çevirmez.
const CRISIS_RESPONSE_NATIONAL := 0.4

# --- Teşkilat ------------------------------------------------------------------
## Seviyeye göre KALICI aktivite (sönmez): 1 az, 2 orta, 3 yüksek oy bonusu.
## Seviye 0, 1, 2 (2 = tavan; eski 3. seviyenin bonusu buraya taşındı).
const ORG_ACTIVITY_BY_LEVEL := [0.0, 2.5, 6.0]
## MİTİNG ve KARALAMA artık teşkilat ister; izin kontrolü CardManager'da
## (can_miting / can_play_card) yapılır. Buradaki çarpan sadece ETKİ içindir:
## 2. seviye teşkilatın olduğu ilde miting ve karalama biraz daha vurur.
## (Seviye 0 zaten hamle yapamaz; çarpanı 1.0 bırakıyoruz ki kural tek yerde
## dursun ve yanlışlıkla "etkisiz miting" oluşmasın.)
const ORG_ACTION_MULT := [1.0, 1.0, 1.3]
## Seviye başına miting provokasyon riskinin azalma oranı.
const ORG_RISK_REDUCTION_PER_LEVEL := 0.35

# --- Yasalar ------------------------------------------------------------------
## Yasa bir SEÇMEN GRUBUNU hedefler (gündemdeki çiftten). Etki ULUSALDIR ve
## grup yakınlığına yazılır (il il aktiviteye değil: aynı etki iki kez sayılmaz).
## Sunan parti: hedef grupta +GAIN (kabul edilirse PASSED, edilmezse/meclis
## yokken vaat olarak REJECTED); karşıt grupta GAIN × grubun law_backlash'ı kadar kayıp.
const LAW_GROUP_GAIN_PASSED := 7.0
const LAW_GROUP_GAIN_REJECTED := 2.5
## Oy veren parti (genel başkanın oyu): EVET → hedef grupta +YES, karşıtta
## YES × backlash kayıp; HAYIR → karşıt grupta +NO, hedefte NO × backlash
## kayıp; çekimser etkisiz.
const LAW_VOTE_YES_GAIN := 1.5
const LAW_VOTE_NO_GAIN := 1.0
## İktidar partisi muhalefetin yasasına EVET: gündemi kaptırdı (ulusal puan).
const LAW_GOV_YES_ON_OPPOSITION := -1.0
## KOALİSYON UYUMU (ulusal puan, kısmi): başbakanın partisinin yasasına ortak
## EVET derse uyumlu görünür ve kazanır; HAYIR derse kendisi küçük, başbakanın
## partisi (ortağına yasa geçirtemedi) biraz daha fazla kaybeder.
const LAW_PARTNER_YES_NATIONAL := 0.5
const LAW_PARTNER_NO_NATIONAL := -0.4
const LAW_PM_PARTNER_NO_NATIONAL := -0.8

# --- Grup toplantısı ------------------------------------------------------------
## GEÇİCİ destek: toplantının yapıldığı tur, sonraki tur, ondan sonraki tur
## seçilen grupta bu kadar yakınlık bonusu (sonra 0). Bonus kalıcı yakınlığı
## DEĞİŞTİRMEZ, seçim hesabında üstüne eklenir; aynı gruba yeni toplantı
## bonusları TOPLAMAZ (en büyüğü geçerli). Toplantı yapmamanın cezası YOK.
const MEETING_BONUS := [10.0, 3.0, 1.0]

# --- Koalisyondan çekilme ---------------------------------------------------
## Çekilmek PUAN TABLOSUNA dokunmaz; sadece sonraki seçime yansıyan ulusal
## puanı düşürür. Etki kısmî: taban + bıraktığın bakanlık başına küçük bir ek
## (ne kadar çok görev aldıysan sözünden dönmen o kadar göze batar).
const WITHDRAW_NATIONAL_BASE := -0.5
const WITHDRAW_NATIONAL_PER_POST := -0.25
const WITHDRAW_NATIONAL_LIMIT := -2.0
## Hükümetin sandalyelerinin en az bu kadarını taşıyan ortak çekilirse koalisyon
## fiilen çöker: kalan ortaklar da dağınık görünür ve çekilenin cezasının bu
## oranı kadar (daha az) ulusal puan kaybeder.
const WITHDRAW_BIG_PARTNER_SEAT_SHARE := 0.4
const WITHDRAW_ALLY_SHARE := 0.4

## Koalisyondan çekilen ortağın ulusal puan kaybı (bıraktığı görev sayısına bağlı).
static func withdraw_national(posts: int) -> float:
	var posts_f := float(maxi(posts, 0))
	return maxf(WITHDRAW_NATIONAL_LIMIT, WITHDRAW_NATIONAL_BASE + WITHDRAW_NATIONAL_PER_POST * posts_f)

## Büyük ortak çekilince koalisyonda KALAN ortakların kaybı (daha küçük).
static func withdraw_ally_national(leaver_penalty: float) -> float:
	return leaver_penalty * WITHDRAW_ALLY_SHARE

# --- Kaset / itibar suikastı ------------------------------------------------------
## Hedefin ULUSAL desteğinden doğrudan düşer (il puanlarına dokunmaz).
const REPUTATION_NATIONAL_DAMAGE := 4.0
## İÇ KARIŞIKLIK: hedefin ulusal desteğini düşürür ve partide (gizli)
## karışıklık çıkarır (bkz. TURMOIL_REBELLION).
const REBELLION_NATIONAL_DAMAGE := 1.5
# --- Karalama -----------------------------------------------------------------
## Hedefin kaybı = DAMAGE / (1 + DEFENSE_FACTOR × hedefin il gücü)
## Karalayanın kazancı = GAIN × (1 + ATTACK_FACTOR × karalayanın il gücü)
const PROPAGANDA_DAMAGE := 5.0
## Karalama bir partinin il puanını bunun altına İTEMEZ: parti sarsılır ama o
## ilden silinmez, karşı kampanyayla toparlanabilir.
const PROPAGANDA_FLOOR := -3.0
const PROPAGANDA_GAIN := 1.5
const PROPAGANDA_DEFENSE_FACTOR := 0.2
const PROPAGANDA_ATTACK_FACTOR := 0.3
## Bir partinin bir ildeki GÜCÜ = APPEAL_WEIGHT × grup uyumu (0..1, bkz.
## appeal_closeness) + ACTIVITY_WEIGHT × pozitif aktivite.
const STRENGTH_APPEAL_WEIGHT := 3.0
const STRENGTH_ACTIVITY_WEIGHT := 0.4

# --- Anket --------------------------------------------------------------------
## Anket sonucundaki her oy payı en fazla bu oranda sapar (%80 doğruluk).
const POLL_ERROR := 0.2

# --- Vekil çalmanın bedeli -------------------------------------------------------
## Vekil transferi seçmene meşru görünmez: ÇALAN parti çalınan vekil başına
## küçük bir ulusal destek kaybeder, ÇALINAN parti "mağduriyet" olarak küçük bir
## destek kazanır. İkisi de kısmidir: hamleyi caydırmaz, bedava da bırakmaz.
## MECLİS DIŞI PARTİ (son seçimde baraj altı) vekil çalarken yarı verimlidir.
## Kartla meclise girse bile ceza sonraki seçime kadar sürer.
const STEAL_OUTSIDER_EFFICIENCY := 0.5

## Vekil çalmanın ulusal bedeli neredeyse simgesel: oyuncular çalmaktan
## caymasın, sadece "bedava değil" hissi kalsın.
const STEAL_THIEF_NATIONAL_PER_SEAT := -0.008
const STEAL_THIEF_NATIONAL_LIMIT := -0.25
const STEAL_VICTIM_NATIONAL_PER_SEAT := 0.012
const STEAL_VICTIM_NATIONAL_LIMIT := 0.35

## İl menüsünde "seçmen sana yakın/uzak": grup uyumu (0..100) bu aralıkta
## 0..1'e çevrilir (bkz. appeal_closeness); CLOSENESS_NEAR (uyum 50, nötr) üstü "yakın".
const APPEAL_LOW := 40.0
const APPEAL_HIGH := 60.0
const CLOSENESS_NEAR := 0.5

# --- Karışıklık ve bölünme ------------------------------------------------------
## GİZLİ KARIŞIKLIK: iç karışıklık kartı çok, kaset biraz yazar. Her tur
## TURMOIL_DECAY ile söner, olumlu hamleler (miting, teşkilat, yatırım, kabul
## edilen yasa, hükümete girmek) toparlar.
const TURMOIL_REBELLION := 3.5
const TURMOIL_REPUTATION := 1.5
const TURMOIL_DECAY := 0.85
const TURMOIL_EASE_MITING := 0.3
const TURMOIL_EASE_ORG := 0.2
const TURMOIL_EASE_INVEST := 0.5
const TURMOIL_EASE_LAW := 0.8
const TURMOIL_EASE_GOVERNMENT := 1.5
## Karışıklık bunu aşan (ve en az SPLIT_MIN_SEATS vekili olan) parti tur sonunda
## BÖLÜNÜR: vekillerinin SPLIT_SEAT_SHARE_MIN..MAX'ı aynı grup yakınlıklarıyla yeni partiye
## geçer, teşkilatlarının bir kısmı (SPLIT_ORG_CHANCE) onunla gider.
const SPLIT_TURMOIL := 7.0
const SPLIT_MIN_SEATS := 8
const SPLIT_SEAT_SHARE_MIN := 0.35
const SPLIT_SEAT_SHARE_MAX := 0.5
const SPLIT_ORG_CHANCE := 0.4
const SPLIT_NATIONAL_DAMAGE := -1.0
const SPLIT_AFTER_TURMOIL := 4.0
## Ayrılan parti en erken SPLIT_MIN, en geç SPLIT_MAX seçim atlattıktan sonra
## döner; erken dönüş için ana partinin karışıklığı REUNION_TURMOIL'e inmeli.
const SPLIT_MIN_ELECTIONS := 1
const SPLIT_MAX_ELECTIONS := 4
const REUNION_TURMOIL := 2.0

## Grup uyumunun (0..100) 0..1 karşılığı (il menüsü ve güç hesabı için).
static func appeal_closeness(appeal: float) -> float:
	return clampf((appeal - APPEAL_LOW) / (APPEAL_HIGH - APPEAL_LOW), 0.0, 1.0)

## Grup toplantısının toplantıdan `age` tur sonraki bonusu.
static func meeting_bonus(age: int) -> float:
	if age < 0 or age >= MEETING_BONUS.size():
		return 0.0
	return float(MEETING_BONUS[age])

## Miting yorgunluğunun kazanç çarpanı.
static func miting_fatigue_mult(fatigue: float) -> float:
	return 1.0 / (1.0 + maxf(0.0, fatigue) / MITING_FATIGUE_SCALE)

## Mitingin bir ildeki siyasi hitap etkisi (azalan getiri öncesi ham değerler):
## [{"group": baskın grup, "gain": kazanç, "loss_group": karşıt, "loss": kayıp}].
static func miting_positioning(profile: Dictionary, mult: float = 1.0) -> Array:
	var result: Array = []
	for pair in VoterGroups.PAIR_IDS:
		var groups: Array = VoterGroups.PAIRS[pair]
		var s := VoterGroups.share(profile, groups[0])
		var lead: String = groups[0] if s >= 0.5 else groups[1]
		var lean := absf(s - 0.5) * 2.0
		if lean < MITING_MIN_LEAN:
			continue
		var gain := MITING_GROUP_GAIN * lean * mult
		result.append({"group": lead, "gain": gain, "loss_group": VoterGroups.opposite(lead),
			"loss": gain * float(VoterGroups.data(lead).get("miting_backlash", 0.3))})
	return result

static func org_action_mult(level: int) -> float:
	return float(ORG_ACTION_MULT[clampi(level, 0, ORG_ACTION_MULT.size() - 1)])

static func org_activity(level: int) -> float:
	return float(ORG_ACTIVITY_BY_LEVEL[clampi(level, 0, ORG_ACTIVITY_BY_LEVEL.size() - 1)])

static func clamp_points(value: float) -> float:
	return clampf(value, -LIMIT, LIMIT)

static func multiplier(national: float, local: float) -> float:
	return clampf(1.0 + EFFECT_PER_POINT * (national + local), MIN_MULT, MAX_MULT)

## 0..PROVOCATION_MAX_RISK arası provokasyon olasılığı (appeal: ildeki grup uyumu).
static func provocation_risk(appeal: float, org_level: int = 0) -> float:
	var t: float = clampf((PROVOCATION_SAFE_APPEAL - appeal) / (PROVOCATION_SAFE_APPEAL - PROVOCATION_FULL_APPEAL), 0.0, 1.0)
	return PROVOCATION_MAX_RISK * t * maxf(0.0, 1.0 - ORG_RISK_REDUCTION_PER_LEVEL * org_level)

## Bir partinin bir ildeki gücü (karalamada saldırı/savunma).
static func party_strength(appeal: float, activity: float) -> float:
	return STRENGTH_APPEAL_WEIGHT * appeal_closeness(appeal) + STRENGTH_ACTIVITY_WEIGHT * maxf(0.0, activity)

static func propaganda_damage(defender_strength: float) -> float:
	return PROPAGANDA_DAMAGE / (1.0 + PROPAGANDA_DEFENSE_FACTOR * maxf(0.0, defender_strength))

static func propaganda_gain(attacker_strength: float) -> float:
	return PROPAGANDA_GAIN * (1.0 + PROPAGANDA_ATTACK_FACTOR * maxf(0.0, attacker_strength))

## Vekil payı değişimi (yüzde puan) -> ulusal puan.
## Çalınan vekil sayısına göre ulusal puan (çalan için eksi, çalınan için artı).
static func steal_thief_national(seats: int) -> float:
	return maxf(float(seats) * STEAL_THIEF_NATIONAL_PER_SEAT, STEAL_THIEF_NATIONAL_LIMIT)

static func steal_victim_national(seats: int) -> float:
	return minf(float(seats) * STEAL_VICTIM_NATIONAL_PER_SEAT, STEAL_VICTIM_NATIONAL_LIMIT)
