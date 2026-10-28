class_name PublicOpinion
extends RefCounted
## OY KURALLARI — saf fonksiyonlar ve sabitler, durum CardManager'da.
##
## TEK KURAL (0.0.284): OY = SEÇMEN. Her ilin her seçmen grubunda seçmenler
## ya bir partiye bağlıdır (1 zayıf, 2 orta, 3 sadık) ya kararsızdır. Sandıkta
## bağlı seçmen partisine oy verir, kararsızların sandığa gidenleri partilere
## eşit bölünür (bkz. ElectionModel). Ayrı bir ulusal destek ya da il puanı
## YOKTUR; bütün hamleler seçmen kazandırır ya da kaybettirir:
##   - MİTİNG  : ilin hedef gruplarından seçmen çeker (kararsızlardan, zayıf
##               bağlı rakiplerden), kendi seçmenini bir seviye yükseltir.
##   - YATIRIM : ildeki bütün gruplardan seçmen çeker (ideolojiye bakmaz).
##   - YASA    : grubun bütün illerinde seçmen; karşıt grupta küçük kayıp.
##   - KASET / KARALAMA: hedefin seçmeninin bir kısmı bir seviye düşer (1.
##               seviyedekiler kararsızlaşır); karalayan ilde kazanır.
##   - Diğer olaylar (iç karışıklık, gensoru, koalisyon, vergi, afet, onay):
##               PUAN olarak yazılır ve CardManager._shift_voters seçmene
##               çevirir: +1 puan = her gruptaki seçmenin VOTER_GAIN'i
##               kararsızlardan partiye; −1 puan = partinin her gruptaki
##               seçmeninin VOTER_LOSS'u kararsızlara (önce zayıf bağlılar).
## Etkiler KALICIDIR (kendiliğinden sönmez); seçmen yalnız rakiplerin
## hamleleriyle ya da olaylarla kaybedilir.
##
## Dengeyi değiştirmek için sadece bu dosyadaki sabitleri düzenlemek yeterli.

## Puanın seçmen karşılığı (bkz. CardManager._shift_voters).
const VOTER_GAIN := 0.005
const VOTER_LOSS := 0.02

# --- Miting -----------------------------------------------------------------
## TEŞKİLAT (0.0.213): miting teşkilat istemez ama teşkilatsız miting az getirir.
## Seviye 0 / 1 / 2 → etki 1x / 2x / 3x; seviye kadar grup ODAĞI seçilebilir.
const MITING_ORG_MULT := [1.0, 2.0, 3.5]  # 0.0.227: 2. seviye 3 -> 3,5
## ULUSAL HİTAP: miting ildeki HER grubun bir kısmını kazanır, il nüfusuyla
## orantılı: gruptaki kazanç (yüzde puan) = MITING_CONVERT × teşkilat çarpanı ×
## ildeki grup seçmeni / ülkedeki grup seçmeni × 100. Odak gruplarda
## MITING_FOCUS_MULT katı. Küçük bir ilde (3 vekil) %95 emekli olsa bile 2.
## seviye teşkilatla odaklı miting emeklilerde ancak ~%1-2 getirir.
const MITING_CONVERT := 0.12
const MITING_FOCUS_MULT := 2.5
## AZALAN GETİRİ: aynı gruba art arda miting yorgunluk biriktirir:
## kazanç × 1 / (1 + yorgunluk / FATIGUE_SCALE); yorgunluk her tur × DECAY.
## 0.0.217: çok kısık (miting art arda yapılabilmeli; sadece hafif dengeleme).
const MITING_FATIGUE_SCALE := 25.0
const MITING_FATIGUE_DECAY := 0.6

# --- Yatırım (sadece hükümet partileri) ---------------------------------------
## Yatırım partinin siyasi kimliğine (grup yakınlığına) dokunmaz; ildeki BÜTÜN
## gruplardan seçmen çeker, hemen (bkz. Economy.invest_scale: büyük yatırım
## orantıdan güçlü).
## YATIRIMIN SEÇMEN KARŞILIĞI (0.0.216): 100 milyonluk yatırım ildeki her
## grubun INVEST_CONVERT'ü kadarını getirene kazandırır (nüfusla orantılı,
## mitingdeki gibi: ildeki grup seçmeni / ülkedeki grup seçmeni × 100).
const INVEST_CONVERT := 0.3
## PAYLAŞIM (0.0.190): etkinin INVEST_OWN_SHARE'i getiren partiye; kalanı
## hükümet partilerine makam puanlarıyla doğru orantılı dağıtılır.
const INVEST_OWN_SHARE := 0.5

# --- Popülizm bonusu -----------------------------------------------------------
## Popülizm süren partinin KENDİ hamlelerinin (miting, yatırım, yasa, oy,
## karalama kazancı, gensoru) iyi sonuçları bu çarpanla büyür, kötü sonuçları
## küçülür. Ayrıca karalamanın hasarı ve teşkilatın oy bonusu da bu çarpanla
## büyür, vekil çalma POPULISM_STEAL_MULT kat vekil getirir. Başkalarının ona
## yaptığı karalama etkilenmez.
const POPULISM_GOOD_MULT := 2.0
const POPULISM_BAD_MULT := 0.25
const POPULISM_STEAL_MULT := 1.5

# --- Gensoru ------------------------------------------------------------------
## Reddedilen gensoruyu getiren parti bu kadar ulusal destek kaybeder.
const CENSURE_REJECTED_NATIONAL := -0.25
## GÜNDEME YANIT: gündemdeki gruba yasa sunan ya da o yasaya EVET diyen
## parti bu kadar ulusal puan kazanır (eski kriz 0,4).
const CRISIS_RESPONSE_NATIONAL := 0.6
## HÜKÜMET ONAYI (0.0.282): kurulan hükümetin %0..%100 onayı. Başlangıç:
## ortakların oy oranı × bakanlık payı toplamı. Yalnız TUR SONUNDA güncellenir
## (tur içindeki olaylar bekleyen değişim olarak birikir). %50 nötr; her tur
## sonunda üstü hükümet ortaklarına ülke geneli seçmen kazandırır, altı
## kaybettirir (puan, bakanlık payına göre bölünür).
const APPROVAL_NEUTRAL := 50.0
## Onay %100 (ya da %0) iken tek başına iktidara her tur sonunda yazılan puan (±).
const APPROVAL_NATIONAL_MAX := 1.5
## Afet bitti: hükümet ortaklarının yardımı muhalefetinkinden fazlaysa / değilse.
const APPROVAL_DISASTER_MORE := 4.0
const APPROVAL_DISASTER_LESS := -3.0
## Krizli (gündemdeki) grubun yasası: geçerse artı; hükümet partisi HAYIR
## derse ağır eksi (× o partinin bakanlık payı); hükümet HAYIR'ıyla düşerse ek eksi.
const APPROVAL_CRISIS_LAW_PASSED := 4.0
const APPROVAL_CRISIS_LAW_NO := -22.0
const APPROVAL_CRISIS_LAW_FAILED := -5.0
## Göstergede tutulan tur sayısı.
const APPROVAL_HISTORY := 8
## YATIRIM İSTEKLERİ (0.0.283): hükümet varken her tur birkaç il bir tutar
## ister; istek bir tam tur sürer. Karşılanırsa onay artar; karşılanmazsa
## onay düşer ve hükümet ortakları o ilde il puanı kaybeder (bakanlık payıyla).
const REQUEST_PROVINCES_PER := 12
const REQUEST_MIN := 2
const APPROVAL_REQUEST_DONE := 2.0
const APPROVAL_REQUEST_MISSED := -1.5
const REQUEST_MISSED_LOCAL := -4.0
## Gündemdeki gruba sunulan yasanın grup etkisi (sunana) bu kadar büyür.
const AGENDA_LAW_MULT := 1.3

# --- Teşkilat ------------------------------------------------------------------
## Seviyeye göre toplam seçmen kazancı (puan): teşkilat kurulunca ya da
## geliştirilince seviye farkı kadarı o ilde seçmen olarak yazılır (0.0.284).
const ORG_ACTIVITY_BY_LEVEL := [0.0, 2.5, 8.0]  # 0.0.227: 2. seviye 6 -> 8
## MİTİNG ve KARALAMA artık teşkilat ister; izin kontrolü CardManager'da
## (can_miting / can_play_card) yapılır. Buradaki çarpan sadece ETKİ içindir:
## 2. seviye teşkilatın olduğu ilde miting ve karalama biraz daha vurur.
## (Seviye 0 zaten hamle yapamaz; çarpanı 1.0 bırakıyoruz ki kural tek yerde
## dursun ve yanlışlıkla "etkisiz miting" oluşmasın.)
const ORG_ACTION_MULT := [1.0, 1.0, 1.5]  # 0.0.227: 2. seviye 1,3 -> 1,5

# --- Yasalar ------------------------------------------------------------------
## Yasa bir SEÇMEN GRUBUNU hedefler (gündemdeki çiftten). Etki ULUSALDIR ve
## grup yakınlığına yazılır (il il aktiviteye değil: aynı etki iki kez sayılmaz).
## Sunan parti: hedef grupta +GAIN (kabul edilirse PASSED, edilmezse/meclis
## yokken vaat olarak REJECTED); karşıt grupta GAIN × grubun law_backlash'ı kadar kayıp.
## (0.0.213: yüzde hitap ölçeğinde, mitinge oranla.)
const LAW_GROUP_GAIN_PASSED := 3.0
const LAW_GROUP_GAIN_REJECTED := 1.0
## Oy veren parti (genel başkanın oyu): EVET → hedef grupta +YES, karşıtta
## YES × backlash kayıp; HAYIR → karşıt grupta +NO, hedefte NO × backlash
## kayıp; çekimser etkisiz.
const LAW_VOTE_YES_GAIN := 0.5
const LAW_VOTE_NO_GAIN := 0.4
## İktidar partisi muhalefetin yasasına EVET: gündemi kaptırdı (ulusal puan).
const LAW_GOV_YES_ON_OPPOSITION := -1.0
## KOALİSYON UYUMU (ulusal puan, kısmi): başbakanın partisinin yasasına ortak
## EVET derse uyumlu görünür ve kazanır; HAYIR derse kendisi küçük, başbakanın
## partisi (ortağına yasa geçirtemedi) biraz daha fazla kaybeder.
const LAW_PARTNER_YES_NATIONAL := 0.5
const LAW_PARTNER_NO_NATIONAL := -0.4
const LAW_PM_PARTNER_NO_NATIONAL := -0.8

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
## KASET: bütün illerde hedefin seçmeninin KASET_DEMOTE'u bir seviye düşer (1.
## seviyedekiler kararsızlaşır) ve ülke genelinde puan kaybı.
const KASET_DEMOTE := 0.15
const REPUTATION_NATIONAL_DAMAGE := 1.5
## İÇ KARIŞIKLIK: bütün gruplardan seçmen kaybı (puan) ve partide (gizli)
## karışıklık (bkz. TURMOIL_REBELLION).
const REBELLION_NATIONAL_DAMAGE := 1.5
# --- Karalama -----------------------------------------------------------------
## Hedefin O İLDEKİ seçmeninin PROPAGANDA_DEMOTE'u bir seviye düşer;
## karalayan ilde PROPAGANDA_GAIN puan kazanır (ikisi de teşkilatla büyür).
const PROPAGANDA_DEMOTE := 0.3
const PROPAGANDA_GAIN := 2.5

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

## İl menüsünde "seçmen sana yakın/uzak": grup uyumu (ildeki seçmenin yüzde
## kaçına hitap ediyorsun) bu aralıkta 0..1'e çevrilir; CLOSENESS_NEAR üstü "yakın".
const APPEAL_LOW := 0.0
const APPEAL_HIGH := 20.0
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

## Miting yorgunluğunun kazanç çarpanı.
static func miting_fatigue_mult(fatigue: float) -> float:
	return 1.0 / (1.0 + maxf(0.0, fatigue) / MITING_FATIGUE_SCALE)

## Mitingin bir ildeki grup hitap kazançları (azalan getiri ve çekirdek
## çarpanı öncesi ham değerler): [{"group", "gain"}]. national: grup -> ülkedeki
## seçmen sayısı (VoterGroups.national_counts), focus: odak gruplar.
static func miting_gains(profile: Dictionary, national: Dictionary, mult: float = 1.0, focus: Array = []) -> Array:
	var result: Array = []
	for group in VoterGroups.GROUP_IDS:
		var here := VoterGroups.group_count(profile, group)
		var total := float(national.get(group, 0))
		if here <= 0.0 or total <= 0.0:
			continue
		var gain := MITING_CONVERT * mult * here / total * VoterGroups.AFFINITY_MAX
		if focus.has(group):
			gain *= MITING_FOCUS_MULT
		result.append({"group": group, "gain": gain})
	return result

static func miting_org_mult(level: int) -> float:
	return float(MITING_ORG_MULT[clampi(level, 0, MITING_ORG_MULT.size() - 1)])

static func org_action_mult(level: int) -> float:
	return float(ORG_ACTION_MULT[clampi(level, 0, ORG_ACTION_MULT.size() - 1)])

static func org_activity(level: int) -> float:
	return float(ORG_ACTIVITY_BY_LEVEL[clampi(level, 0, ORG_ACTIVITY_BY_LEVEL.size() - 1)])

## Vekil payı değişimi (yüzde puan) -> ulusal puan.
## Çalınan vekil sayısına göre ulusal puan (çalan için eksi, çalınan için artı).
static func steal_thief_national(seats: int) -> float:
	return maxf(float(seats) * STEAL_THIEF_NATIONAL_PER_SEAT, STEAL_THIEF_NATIONAL_LIMIT)

static func steal_victim_national(seats: int) -> float:
	return minf(float(seats) * STEAL_VICTIM_NATIONAL_PER_SEAT, STEAL_VICTIM_NATIONAL_LIMIT)
