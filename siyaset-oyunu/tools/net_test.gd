extends SceneTree
## İki süreçli GERÇEK ağ testi (ENet, localhost). RPC imzalarını, büyük seçim
## paketini, heartbeat ile kendini onarmayı ve ayrılan oyuncunun temizlenmesini
## doğrular. Röle yerine ENet kullanır — oyun katmanı aynıdır. (ENet, röleden
## farklı olarak client'a RASTGELE peer id verir; test gerçek id'leri kullanır.)
##   godot --headless --script res://tools/net_test.gd -- --role=host
##   godot --headless --script res://tools/net_test.gd -- --role=client

const PORT := 27915
const CODE := "NETTS"
const TIMEOUT_SEC := 50.0

var mm
var pm
var cm
var gm
var gp
var role := ""
var _elapsed := 0.0

func log_line(text: String) -> void:
	print("[%s %.1fs] %s" % [role.to_upper(), _elapsed, text])

func fail(text: String) -> void:
	log_line("FAIL: " + text)
	quit(1)

func wait_until(cond: Callable, label: String) -> bool:
	while true:
		if root.multiplayer.multiplayer_peer == null or root.multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
			fail("multiplayer peer kayboldu (bekleniyordu: %s)" % label)
			return false
		if cond.call():
			break
		await create_timer(0.05).timeout
		_elapsed += 0.05
		if _elapsed > TIMEOUT_SEC:
			fail("zaman aşımı: " + label)
			return false
	log_line("ok: " + label)
	return true

func all_posts_to(peer_id: int) -> Dictionary:
	var a := {}
	for post in gp.POSTS:
		a[post["id"]] = peer_id
	return a

var _proposed := false

## Hangi fazda olursak olalım üzerimize düşeni yapar (görev bizdeyse teklif,
## oylama açıksa EVET). Sonuç kesinleşince hükümet diğer tarafın fazları
## görmesine fırsat kalmadan kurulabildiği için adım adım beklemek yarışlıydı.
## Hükümet kurulduysa true döner.
func _drive_government(me: int) -> bool:
	if gm.phase == gm.Phase.FORMING and gm.mandate_peer_id() == me and not _proposed:
		_proposed = true
		gm.submit_government_proposal(all_posts_to(me))
	elif gm.phase == gm.Phase.VOTING and gm.voter_ids().has(me) and not gm.has_voted(me):
		gm.cast_vote(true)
	return gm.phase == gm.Phase.GOVERNING

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
	await process_frame
	mm = root.get_node("MultiplayerManager")
	pm = root.get_node("PartyManager")
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	gp = root.get_node("GovernmentPresets")
	if role == "host":
		await run_host()
	else:
		await run_client()

func run_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 4) != OK:
		fail("sunucu açılamadı")
		return
	root.multiplayer.multiplayer_peer = peer
	mm.is_host = true
	mm.room_code = CODE
	mm.owner_id = 1
	mm.players = {1: {"name": "Host"}}
	mm.stage = mm.Stage.LOBBY
	if not await wait_until(func(): return mm.players.size() == 2, "client odaya katıldı (_request_join)"):
		return
	var client_id := 0
	for peer_id in mm.players.keys():
		if peer_id != 1:
			client_id = peer_id
	mm.stage = mm.Stage.PARTY_SETUP
	pm.parties = {
		1: {"name": "HostP", "icon_index": 0, "icon_color": Color.WHITE, "bg_color": Color.RED,
			"ideology": {"economic": 1, "social": 1, "administrative": 2}, "ready": true},
		client_id: {"name": "ClientP", "icon_index": 1, "icon_color": Color.WHITE, "bg_color": Color.BLUE,
			"ideology": {"economic": -1, "social": -1, "administrative": 1}, "ready": true},
	}
	pm._broadcast_parties()
	mm.finish_party_setup()
	cm.turn_order = [client_id, 1]
	cm.current_turn_index = 0
	cm._push_state({"type": "full"}, true)
	log_line("oyun başladı, sıra client'ta (id %d)" % client_id)

	if not await wait_until(func(): return cm.current_turn_peer_id() == 1, "client kart çekip oynadı, sıra host'ta"):
		return
	cm.pass_turn()
	if not await wait_until(func(): return cm.last_election_round == 1, "tur bitti -> seçim yapıldı"):
		return
	if not await wait_until(func(): return _drive_government(1), "hükümet kuruldu"):
		return

	# Kayıp mesaj simülasyonu: durumu değiştirip YAYINLAMADAN sürümü artır.
	cm.round_number = 99
	cm.state_version += 1
	log_line("kayıp mesaj simüle edildi (round=99, yayın yok)")

	if not await wait_until(func(): return mm.players.size() == 1, "client ayrıldı"):
		return
	if not await wait_until(func(): return cm.game_finished, "ayrılan oyuncu temizlendi -> yeterli oyuncu yok -> oyun bitti"):
		return
	log_line("HOST PASS")
	quit(0)

func run_client() -> void:
	await create_timer(1.5).timeout
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", PORT) != OK:
		fail("client oluşturulamadı")
		return
	mm.is_host = false
	mm._pending_code = CODE
	mm.room_code = CODE
	root.multiplayer.multiplayer_peer = peer
	mm.room_closed.connect(func(r): log_line("room_closed: " + r))
	mm.join_failed.connect(func(r): log_line("join_failed: " + r))
	if not await wait_until(func(): return mm._has_synced_once, "odaya katılım onaylandı"):
		return
	var me: int = root.multiplayer.get_unique_id()
	if not await wait_until(func(): return cm.turn_order.size() == 2 and pm.parties.has(me) and cm.is_my_turn(),
			"tam durum + parti verisi alındı, sıra bende"):
		return
	cm.draw_card()
	if not await wait_until(func(): return cm.my_inventory().size() == 1, "kart çekme RPC'si"):
		return
	var card: String = cm.my_inventory()[0]
	var before: Dictionary = pm.parties[me]["ideology"].duplicate()
	# İlk seçimden önce deste sadece ideoloji ve miting kartı verir; miting il ister.
	var is_miting := card == "miting"
	cm.play_card(0, -1, "ankara" if is_miting else "")
	# Sadece elin boşalmasını bekle: host sırasını anında geçip turu (ve seçimi)
	# bitirebilir, o zaman sıra çoktan tekrar bize dönmüş olur.
	if not await wait_until(func(): return cm.my_inventory().is_empty(), "kart oynama RPC'si (%s)" % card):
		return
	if is_miting:
		if not await wait_until(func(): return cm.province_events.has("ankara"), "miting sonucu (il olayı) senkronlandı"):
			return
	elif not await wait_until(func(): return pm.parties[me]["ideology"] != before, "ideoloji değişimi senkronlandı"):
		return
	if not await wait_until(func(): return cm.last_election_round == 1 and cm.last_province_results.size() == 67,
			"seçim sonucu (67 il, büyük paket) alındı"):
		return
	if not await wait_until(func(): return _drive_government(me), "hükümet kuruldu (client)"):
		return
	if not await wait_until(func(): return cm.round_number == 99, "heartbeat sürüm farkını yakaladı -> tam senkron"):
		return
	log_line("CLIENT PASS")
	root.multiplayer.multiplayer_peer.close()
	await create_timer(0.5).timeout
	quit(0)
