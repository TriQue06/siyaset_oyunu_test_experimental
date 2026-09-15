extends Node
## Autoload. Hükümet görevlerinin (koltukların) katalogu ve puan değerleri.
##
## Toplam 8 görev: 1 başbakanlık, 1 başbakan yardımcılığı, 6 bakanlık.
## Hükümetin BAŞI başbakanlıktır — birinci parti başbakanlığı ortağına
## verirse, ANA İKTİDAR PARTİSİ o ortak sayılır (bkz.
## GovernmentManager.main_gov_peer_id).

const POST_PM := "pm"
const POST_DEPUTY_PM := "deputy_pm"

const PM_POINTS := 3
const DEPUTY_PM_POINTS := 2
const MINISTRY_POINTS := 1

## Koalisyondan çekilen küçük ortağın puan cezası.
const WITHDRAW_SCORE_PENALTY := 3
## Ortağı çekildiği için TEK BAŞINA kalan ana iktidar partisi gensoruyla
## düşerse: çok daha büyük puan cezası.
const ABANDONED_FALL_PENALTY := 8
## Meclis oylamasında bir hükümet teklifine HAYIR diyen partinin puan kaybı
## (koalisyon ya da azınlık fark etmez — ülkeyi istikrarsızlaştırır).
const GOVERNMENT_NO_PENALTY := 1

## Sıra ÖNEMLİ: hükümet kurma ekranında bu sırayla listelenir.
const POSTS: Array[Dictionary] = [
	{"id": POST_PM, "title": "Başbakanlık", "points": PM_POINTS},
	{"id": POST_DEPUTY_PM, "title": "Başbakan Yardımcılığı", "points": DEPUTY_PM_POINTS},
	{"id": "ministry_interior", "title": "İçişleri Bakanlığı", "points": MINISTRY_POINTS},
	{"id": "ministry_foreign", "title": "Dışişleri Bakanlığı", "points": MINISTRY_POINTS},
	{"id": "ministry_finance", "title": "Maliye Bakanlığı", "points": MINISTRY_POINTS},
	{"id": "ministry_justice", "title": "Adalet Bakanlığı", "points": MINISTRY_POINTS},
	{"id": "ministry_education", "title": "Milli Eğitim Bakanlığı", "points": MINISTRY_POINTS},
	{"id": "ministry_health", "title": "Sağlık Bakanlığı", "points": MINISTRY_POINTS},
]

func post_ids() -> Array:
	var ids: Array = []
	for post in POSTS:
		ids.append(post["id"])
	return ids

func post_title(post_id: String) -> String:
	for post in POSTS:
		if post["id"] == post_id:
			return post["title"]
	return post_id

func post_points(post_id: String) -> int:
	for post in POSTS:
		if post["id"] == post_id:
			return int(post["points"])
	return 0

func is_valid_post(post_id: String) -> bool:
	for post in POSTS:
		if post["id"] == post_id:
			return true
	return false
