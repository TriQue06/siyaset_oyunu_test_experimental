extends SceneTree
## ARAYÜZ TARAYICI: oyunu gerçek pencerede, gerçek fare olaylarıyla baştan sona
## oynar. Her ekranda görünen düğmelere tıklar, kaydırılabilir alanları kaydırır,
## her adımda ekran görüntüsü alır. Bir düğmenin üstünü başka öğe kapatıyorsa
## (tıklanamıyorsa) ya da ekran dışına taşıyorsa ÖRTÜLÜ / TAŞMA diye yazar.
##   godot --path . --resolution 1280x720 --script res://tools/ui_crawl.gd
## Ortam: CRAWL_DIR (görüntü klasörü), CRAWL_STAGE (lobby|setup|game|all).
## DİKKAT: kullanıcının profil/ayar/kayıt dosyalarına dokunabilir; çalıştırmadan
## önce user:// yedeklenmeli.

var out_dir := ""
var shot_no := 0
var notes: Array = []
var _pointer := Vector2.ZERO

func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame

func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func note(kind: String, text: String) -> void:
	var line := "[%s] %s" % [kind, text]
	notes.append(line)
	print(line)

func shot(name: String) -> void:
	shot_no += 1
	var safe := name.to_lower().replace(" ", "_").replace("/", "_").replace("\n", "_").replace(":", "")
	safe = safe.substr(0, 40)
	var path := "%s/%03d_%s.png" % [out_dir, shot_no, safe]
	root.get_texture().get_image().save_png(path)
	print("SHOT %s" % path.get_file())

static func label_of(c: Control) -> String:
	var t := ""
	if c is Button:
		t = (c as Button).text
	if t == "" and c.tooltip_text != "":
		t = c.tooltip_text
	if t == "":
		for child in c.get_children():
			if child is Label:
				t = (child as Label).text
				break
	if t == "":
		t = String(c.name)
	return t.replace("\n", " ").strip_edges()

func screen_pos(c: Control) -> Vector2:
	var r := c.get_global_rect()
	return c.get_global_transform_with_canvas() * (c.get_local_mouse_position() * 0.0 + r.size * 0.5)

func _visible_on_screen(c: Control) -> bool:
	if not c.is_visible_in_tree():
		return false
	var vp := root.get_visible_rect()
	var p := c.get_global_transform_with_canvas() * (c.size * 0.5)
	return vp.has_point(p)

## Görünür, etkin, ekranda olan düğmeler (ağaç sırasıyla).
func buttons(scope: Node) -> Array:
	var found: Array = []
	_collect(scope, found)
	return found

func _collect(node: Node, found: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is BaseButton:
		var b := node as BaseButton
		if not b.disabled and b.is_visible_in_tree() and b.size.x >= 4 and b.size.y >= 4 \
				and b.mouse_filter != Control.MOUSE_FILTER_IGNORE and _visible_on_screen(b):
			found.append(b)
	for child in node.get_children():
		_collect(child, found)

func find_button(scope: Node, text: String) -> BaseButton:
	for b in buttons(scope):
		if label_of(b).to_lower().contains(text.to_lower()):
			return b
	return null

## Düğmenin içindeki tüm etiket metinleriyle arar (kart biçimli düğmeler).
func find_button_deep(scope: Node, text: String) -> BaseButton:
	for b in buttons(scope):
		if _deep_text(b).to_lower().contains(text.to_lower()):
			return b
	return null

func _deep_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + " "
	elif n is Button:
		s += (n as Button).text + " "
	elif n is RichTextLabel:
		s += (n as RichTextLabel).get_parsed_text() + " "
	for c in n.get_children():
		s += _deep_text(c)
	return s

func move_to(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.relative = p - _pointer
	_pointer = p
	root.push_input(ev, true)
	await _frames(2)

func mouse_button(index: MouseButton, pressed: bool, factor := 1.0) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = _pointer
	ev.global_position = _pointer
	ev.button_index = index
	ev.pressed = pressed
	ev.factor = factor
	if pressed and index == MOUSE_BUTTON_LEFT:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev, true)
	await _frames(1)

func click_at(p: Vector2) -> void:
	await move_to(p)
	await mouse_button(MOUSE_BUTTON_LEFT, true)
	await mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(2)

func _fx_busy() -> bool:
	return _fx_node(root) != null

func _fx_node(n: Node) -> Node:
	if n.get_script() != null and (n.get_script() as Script).resource_path.ends_with("event_fx.gd") and bool(n.get("_active")):
		return n
	for c in n.get_children():
		var f := _fx_node(c)
		if f != null:
			return f
	return null

## Olay animasyonu (kart, afet, haber) bitene kadar bekler; uzarsa tıklayıp geçer.
func wait_fx(tag := "") -> void:
	var waited := 0.0
	while _fx_busy() and waited < 8.0:
		await _wait(0.4)
		waited += 0.4
		if int(waited * 10) % 20 == 0 and tag != "":
			shot("%s_fx" % tag)
	if _fx_busy():
		await click_at(Vector2(10, 10))
		await _wait(0.5)

## Gerçek tıklama: imleç öğenin ortasına gider; üstte başka öğe varsa ÖRTÜLÜ.
func click(c: Control, tag := "") -> bool:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		note("YOK", "tıklanacak öğe yok: %s" % tag)
		return false
	if _fx_busy():
		await wait_fx()
		if not is_instance_valid(c) or not c.is_visible_in_tree():
			return false
	var p := c.get_global_transform_with_canvas() * (c.size * 0.5)
	await move_to(p)
	var hovered := root.gui_get_hovered_control()
	# Sahne geçişi perdesi: bekleyip yeniden dene.
	for retry in 6:
		if hovered == null or not str(hovered.get_path()).contains("SceneTransition"):
			break
		await _wait(0.5)
		await move_to(p + Vector2(0.5, 0))
		hovered = root.gui_get_hovered_control()
	if hovered != c and not (hovered != null and c.is_ancestor_of(hovered)):
		# Yerleşim yeni değişmiş olabilir: bir kez bekleyip yeniden dene.
		await _wait(0.5)
		p = c.get_global_transform_with_canvas() * (c.size * 0.5)
		await move_to(p + Vector2(0.5, 0.5))
		hovered = root.gui_get_hovered_control()
	if hovered != c and not (hovered != null and c.is_ancestor_of(hovered)):
		note("ÖRTÜLÜ", "'%s' (%s) üstünde: %s" % [label_of(c), str(c.get_path()).get_file(),
			"yok" if hovered == null else "%s '%s'" % [str(hovered.get_path()).right(60), label_of(hovered)]])
		return false
	await mouse_button(MOUSE_BUTTON_LEFT, true)
	await mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	return true

func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	root.push_input(ev)
	await _frames(1)
	ev = ev.duplicate()
	ev.pressed = false
	root.push_input(ev)
	await _frames(2)

## Görünür kaydırma alanlarını tekerlekle sonuna kadar kaydırıp görüntü alır.
func scroll_all(scope: Node, tag: String) -> void:
	if fast:
		return
	var list: Array = []
	_collect_scrolls(scope, list)
	var i := 0
	for s in list:
		var sc := s as ScrollContainer
		var bar := sc.get_v_scroll_bar()
		if bar.max_value - bar.page <= 2.0:
			continue
		i += 1
		await move_to(sc.get_global_transform_with_canvas() * (sc.size * 0.5))
		var before := sc.scroll_vertical
		for k in 30:
			await mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
			await mouse_button(MOUSE_BUTTON_WHEEL_DOWN, false)
		await _wait(0.4)
		if sc.scroll_vertical == before:
			note("KAYMIYOR", "%s: %s kaydırılamadı (taşma %.0f)" % [tag, str(sc.get_path()).right(70), bar.max_value - bar.page])
		shot("%s_scroll%d" % [tag, i])
		for k in 30:
			await mouse_button(MOUSE_BUTTON_WHEEL_UP, true)
			await mouse_button(MOUSE_BUTTON_WHEEL_UP, false)
		await _wait(0.3)

func _collect_scrolls(node: Node, list: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is ScrollContainer and (node as Control).is_visible_in_tree() and _visible_on_screen(node):
		list.append(node)
	for child in node.get_children():
		_collect_scrolls(child, list)

## Ekran dışına taşan görünür öğeler (metinli kutular).
func overflow_check(scope: Node, tag: String) -> void:
	var vp := root.get_visible_rect()
	var seen := 0
	for c in _all_controls(scope):
		var ctl := c as Control
		if not (ctl is Label or ctl is BaseButton or ctl is PanelContainer):
			continue
		if ctl.size.x < 8 or ctl.size.y < 8:
			continue
		var xf := ctl.get_global_transform_with_canvas()
		var r := Rect2(xf * Vector2.ZERO, xf.basis_xform(ctl.size))
		if r.position.x < vp.position.x - 2 or r.end.x > vp.end.x + 2 or r.end.y > vp.end.y + 2 or r.position.y < -2:
			if _clipped_by_parent(ctl):
				continue
			seen += 1
			if seen <= 8:
				note("TAŞMA", "%s: %s '%s' %s" % [tag, ctl.get_class(), label_of(ctl).substr(0, 30), str(r)])

func _clipped_by_parent(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer or (p is Control and (p as Control).clip_contents):
			return true
		p = p.get_parent()
	return false

func _all_controls(node: Node, acc: Array = []) -> Array:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return acc
	if node is Control:
		acc.append(node)
	for child in node.get_children():
		_all_controls(child, acc)
	return acc

## Düğmeleri sırayla dener; her tıklamadan sonra görüntü, ardından geri alma.
## skip: bu metinleri içeren düğmeler atlanır.
var fast := false

func explore(scope: Node, tag: String, skip: Array, limit := 40) -> void:
	if fast:
		return
	var start := buttons(scope)
	var start_ids := {}
	for b in start:
		start_ids[b.get_instance_id()] = true
	var done := 0
	for b in start:
		if done >= limit:
			break
		if not is_instance_valid(b) or not (b as Control).is_visible_in_tree() or (b as BaseButton).disabled:
			continue
		var text := label_of(b)
		var bad := false
		for s in skip:
			if text.to_lower().contains(String(s).to_lower()):
				bad = true
		if bad:
			continue
		done += 1
		if not await click(b, text):
			continue
		await _wait(0.45)
		shot("%s_%s" % [tag, text])
		# Yeni bir pencere açıldıysa kapat (Esc, sonra kapat/vazgeç düğmeleri).
		var fresh := 0
		for nb in buttons(scope):
			if not start_ids.has(nb.get_instance_id()):
				fresh += 1
		if fresh > 0:
			for close_text in ["Tamam", "Kapat", "Vazgeç", "İptal", "×", "✕"]:
				var cb := find_button(scope, close_text)
				if cb != null and not start_ids.has(cb.get_instance_id()):
					await click(cb, close_text)
					await _wait(0.3)
					break

# --- AŞAMALAR -------------------------------------------------------------------

func scene_now() -> Node:
	return current_scene

func wait_scene(file_part: String, timeout := 20.0) -> bool:
	var t := 0.0
	while t < timeout:
		if current_scene != null and current_scene.scene_file_path.contains(file_part):
			await _wait(0.8)
			return true
		await _wait(0.2)
		t += 0.2
	note("SAHNE", "%s sahnesi gelmedi (şu an: %s)" % [file_part, "yok" if current_scene == null else current_scene.scene_file_path])
	return false

func stage_lobby() -> void:
	await wait_scene("Lobby.tscn")
	var s := scene_now()
	shot("lobby")
	overflow_check(root, "lobby")
	await click(find_button(s, "Çevrim İçi"), "online")
	await _wait(0.3)
	shot("lobby_online")
	await click(find_button(s, "Katıl"), "katil_bos")
	await _wait(0.3)
	shot("lobby_join_empty")
	await click(find_button(s, "Çevrim Dışı"), "offline")
	await _wait(0.3)
	shot("lobby_offline")
	print("DBG settings")
	await stage_settings("lobby")
	print("DBG explore")
	await explore(scene_now(), "lobby", ["Botlarla", "Oda Kur", "Katıl", "Çık", "Devam Et", "Çevrim", "Menü"])
	print("DBG click")
	await click(find_button(scene_now(), "Botlarla Oyna"), "botlarla")

## Ayarlar / oyun menüsü: her kategori, kaydırma, sonra DEVAM ET ile kapanış.
func stage_settings(tag: String) -> void:
	if fast:
		return
	var overlay: Node = root.get_node("SettingsOverlay")
	var menu := find_button(scene_now(), "Menü")
	if menu == null:
		menu = find_button(overlay, "Menü")
	await click(menu, "menü")
	await _wait(0.5)
	shot("%s_menu" % tag)
	for cat in ["Oyun menüsü", "Görüntü", "Ses", "Oynanış", "Dil"]:
		var b := find_button(overlay, cat)
		if b == null:
			note("YOK", "%s ayarlar kategorisi yok: %s" % [tag, cat])
			continue
		await click(b, cat)
		await _wait(0.4)
		shot("%s_menu_%s" % [tag, cat])
		overflow_check(overlay, "%s_menu_%s" % [tag, cat])
		await scroll_all(overlay, "%s_menu_%s" % [tag, cat])
	await key(KEY_ESCAPE)
	await _wait(0.4)
	if (overlay.get("panel") as Control).visible:
		note("ESC", "%s: Esc oyun menüsünü kapatmadı" % tag)
		await click(find_button(overlay, "DEVAM ET"), "devam")
		await _wait(0.4)
	if (overlay.get("panel") as Control).visible:
		note("KAPANMIYOR", "%s: oyun menüsü kapanmadı" % tag)

func stage_room() -> void:
	if not await wait_scene("RoomLobby.tscn"):
		return
	shot("room")
	overflow_check(root, "room")
	await scroll_all(scene_now(), "room")
	# Bot ekle: boş satırlardaki düğmeler.
	for i in 6:
		var add := find_button(scene_now(), "Bot ekle")
		if add == null:
			add = find_button(scene_now(), "Bot")
		if add == null:
			break
		await click(add, "bot ekle")
		await _wait(0.25)
	shot("room_bots")
	await explore(scene_now(), "room", ["Oyunu başlat", "Ayrıl", "Kopyala", "Çıkar", "Bot", "Menü"], 60)
	shot("room_after")
	await scroll_all(scene_now(), "room2")
	if OS.get_environment("CRAWL_SHORT") != "":
		# Kısa oyun (oyun sonuna ulaşmak için): en sık, en az seçim.
		root.get_node("MultiplayerManager").set_game_length(0.0, 1)
		await _wait(0.5)
		shot("room_short")
	await click(find_button(scene_now(), "Oyunu başlat"), "start")

func stage_setup() -> void:
	if not await wait_scene("PartySetup.tscn"):
		return
	var s := scene_now()
	shot("setup_1")
	overflow_check(root, "setup1")
	await explore(s, "setup1", ["İleri", "Geri", "Hazır", "Düzenle", "Ben", "İptal", "· ", "Menü"], 12)
	for step in 5:
		var nb := find_button(s, "İleri")
		if nb == null:
			break
		if step == 1:
			pass
		await click(nb, "ileri")
		await _wait(0.5)
		shot("setup_step%d" % (step + 2))
		overflow_check(root, "setup%d" % (step + 2))
		await scroll_all(s, "setup%d" % (step + 2))
		# Adıma özgü: meslek kartı, il, logo/renk, seçmen grupları.
		await explore(s, "setup%d" % (step + 2), ["İleri", "Geri", "Hazır", "Düzenle", "Ben", "İptal", "· ", "Profili", "Menü"], 10)
	shot("setup_last")
	# Eksikleri tamamla: memleket (haritadan il), parti adı; sonra Hazırım.
	await click(find_button(s, "3 · Memleket"), "memleket sekmesi")
	await _wait(0.5)
	var map: Node = s.get("_map")
	if map != null:
		var gm: Node = root.get_node("GameMap")
		var ids: Array = map.get_all_province_ids()
		var pid: String = ids[ids.size() / 2]
		await click_at((map as CanvasItem).get_global_transform_with_canvas() * gm.center_of(pid))
		await _wait(0.5)
		shot("setup_home_picked")
	else:
		note("YOK", "parti kurma haritası bulunamadı")
	await click(find_button(s, "4 · Parti"), "kimlik sekmesi")
	await _wait(0.4)
	var edit: LineEdit = s.get("_name_edit")
	await click(edit, "parti adı")
	for ch in "Deneme":
		var ev := InputEventKey.new()
		ev.unicode = ch.unicode_at(0)
		ev.keycode = OS.find_keycode_from_string(ch.to_upper())
		ev.pressed = true
		root.push_input(ev)
		await _frames(1)
	await _wait(0.3)
	shot("setup_name_typed")
	await click(find_button(s, "2 · Meslek"), "meslek sekmesi")
	await _wait(0.4)
	if s.get("_background_id") == "":
		await click(find_button_deep(s, "Gazeteci"), "gazeteci")
		await _wait(0.3)
	await click(find_button(s, "5 · Seçmen"), "seçmen sekmesi")
	await _wait(0.4)
	if (s.get("_core") as Array).size() < 2:
		for g in ["İşveren", "Milliyetçi"]:
			await click(find_button_deep(s, g), g)
			await _wait(0.3)
	shot("setup_ready_check")
	await click(find_button(s, "Hazırım"), "hazırım")
	await _wait(0.5)
	shot("setup_ready")

func _find_class(node: Node, script_class: String) -> Node:
	var sc: Script = node.get_script()
	if sc != null and sc.get_global_name() == script_class:
		return node
	for child in node.get_children():
		var f := _find_class(child, script_class)
		if f != null:
			return f
	return null

func dump_buttons(scope: Node, tag: String) -> void:
	print("--- DÜĞMELER %s ---" % tag)
	for b in buttons(scope):
		var p := (b as Control).get_global_transform_with_canvas() * Vector2.ZERO
		print("   '%s'  @%d,%d  %s" % [label_of(b), p.x, p.y, str(b.get_path()).right(50)])

# --- OYUN DÖNGÜSÜ ---------------------------------------------------------------

var cm: Node
var gm: Node
var my_turns := 0
var _last_turn_key := ""
var _votes_cast := 0
var _scene_shots := {}
var _formation_tried := {}
var _endgame_done := false

func me() -> int:
	return root.get_node("MultiplayerManager").owner_id

func gs() -> Node:
	if current_scene != null and current_scene.scene_file_path.contains("GameScreen"):
		return current_scene
	return null

func stage_game_loop() -> void:
	cm = root.get_node("CardManager")
	gm = root.get_node("GovernmentManager")
	if not await wait_scene("GameScreen.tscn", 40.0):
		return
	var started := Time.get_ticks_msec()
	var minutes := OS.get_environment("CRAWL_MINUTES")
	var max_ms := int(minutes if minutes != "" else "90") * 60000
	var last_periodic := 0
	while Time.get_ticks_msec() - started < max_ms:
		if _endgame_done:
			break
		var path: String = current_scene.scene_file_path if current_scene != null else ""
		var now := Time.get_ticks_msec()
		if path.contains("GameScreen"):
			if cm.game_finished:
				Engine.time_scale = 1.0
				await stage_endgame()
				continue
			var turn_key := "%d:%d" % [cm.round_number, cm.current_turn_index]
			if cm.is_my_turn() and turn_key != _last_turn_key and not cm.is_turn_blocked():
				_last_turn_key = turn_key
				Engine.time_scale = 1.0
				await _wait(1.2)
				await my_turn()
				continue
			if _need_my_vote():
				Engine.time_scale = 1.0
				await cast_vote()
				continue
			if _need_my_formation():
				Engine.time_scale = 1.0
				await do_formation()
				continue
			Engine.time_scale = float(OS.get_environment("CRAWL_SPEED")) if OS.get_environment("CRAWL_SPEED") != "" else 3.0
			if now - last_periodic > 6000:
				last_periodic = now
				shot("bot_r%d_t%d" % [cm.round_number, cm.current_turn_index])
		else:
			Engine.time_scale = 1.0
			var scene_name := path.get_file().get_basename()
			var n := int(_scene_shots.get(scene_name, 0))
			if now - last_periodic > 2500 and n < 80:
				last_periodic = now
				_scene_shots[scene_name] = n + 1
				shot("%s_r%d_%02d" % [scene_name, cm.round_number, n])
				if n == 3:
					overflow_check(root, scene_name)
					dump_buttons(current_scene, scene_name)
		await _wait(0.3)
	Engine.time_scale = 1.0
	print("oyun döngüsü bitti: tur=%d bitti=%s benim sıram=%d oy=%d" % [cm.round_number, str(cm.game_finished), my_turns, _votes_cast])

func _need_my_vote() -> bool:
	return gm.phase == gm.Phase.VOTING and gm.eligible_voter_ids().has(me()) and not gm.has_voted(me())

func _need_my_formation() -> bool:
	return gm.phase == gm.Phase.FORMING and gm.mandate_peer_id() == me() and not _formation_tried.has("%d:%d" % [cm.round_number, gm.attempts_used])

func cast_vote() -> void:
	var s := gs()
	await _wait(1.0)
	shot("vote_r%d_%s" % [cm.round_number, gm.proposal_kind])
	overflow_check(root, "vote")
	var choice: Control = s.get("vote_yes_button") if _votes_cast % 3 != 1 else s.get("vote_no_button")
	var abstain: Control = s.get("_abstain_button")
	if _votes_cast % 3 == 2 and abstain != null and abstain.is_visible_in_tree():
		choice = abstain
	_votes_cast += 1
	if not await click(choice, "oy"):
		note("OY", "oy düğmesine basılamadı (%s)" % gm.proposal_kind)
	await _wait(0.6)
	shot("vote_cast")
	if _need_my_vote():
		note("OY", "tıklandı ama oy kaydedilmedi (%s)" % gm.proposal_kind)
		gm._apply_vote(me(), gm.VOTE_YES)

func do_formation() -> void:
	_formation_tried["%d:%d" % [cm.round_number, gm.attempts_used]] = true
	await _wait(1.0)
	shot("formation_mine")
	dump_buttons(current_scene, "hükümet kurma")
	await explore(current_scene, "formation", ["Menü", "TURU BİTİR"], 12)
	shot("formation_after")

func stage_endgame() -> void:
	note("BİTİŞ", "oyun bitti; oyun sonu izleniyor")
	for i in 150:
		shot("end_%03d" % i)
		if i == 5:
			overflow_check(root, "end")
		await _wait(2.0)
		if current_scene == null or not current_scene.scene_file_path.contains("GameScreen"):
			break
	dump_buttons(root, "oyun sonu")
	_endgame_done = true

func hand_cards(s: Node) -> Array:
	var hc: Node = s.get("hand_container")
	var list: Array = []
	if hc != null:
		for c in hc.get_children():
			if c is Control and (c as Control).is_visible_in_tree():
				list.append(c)
	return list

func close_popups(s: Node) -> void:
	for close_text in ["Tamam", "Kapat", "Vazgeç", "İptal", "Haritaya dön"]:
		var cb := find_button(s, close_text)
		if cb != null:
			await click(cb, close_text)
			await _wait(0.3)

## Kendi sıram: her turda farklı bir bölümü didikler, sonra TURU BİTİR.
func my_turn() -> void:
	my_turns += 1
	var s := gs()
	cm._turn_time_left = 900.0
	var tag := "my%02d" % my_turns
	shot("%s_start" % tag)
	var draw := find_button_deep(s, "KART ÇEK")
	var skip := find_button(s, "ATLA")
	if my_turns % 5 == 4 and skip != null:
		await click(skip, "atla")
	elif draw != null:
		await click(draw, "kart çek")
	await _wait(1.0)
	await wait_fx(tag)
	shot("%s_drawn" % tag)
	await _dismiss_new(s, tag)
	if gs() == null:
		return
	if my_turns <= 2:
		dump_buttons(s, "sıra başı")
	overflow_check(root, tag)
	var phase := my_turns % 4
	if phase == 1:
		await tour_panels(s, tag)
	elif phase == 2:
		await tour_provinces(s, tag)
	elif phase == 3:
		await tour_hand_and_actions(s, tag)
	else:
		await tour_provinces(s, tag)
		await tour_hand_and_actions(s, tag)
	if gs() == null or not cm.is_my_turn():
		return
	shot("%s_end" % tag)
	var pass_b: Control = find_button_deep(s, "TURU BİTİR")
	if pass_b == null or not await click(pass_b, "turu bitir"):
		note("SIRA", "%s: TURU BİTİR tıklanamadı" % tag)
		cm.pass_turn()
	await _wait(1.0)

func _dismiss_new(s: Node, tag: String) -> void:
	for i in 3:
		var b := find_button(s, "Tamam")
		if b == null:
			b = find_button(s, "Devam")
		if b == null:
			# Afet yardımı sorusu: ilk kez yardım götür, sonra atla.
			b = find_button_deep(s, "YARDIM GÖTÜR") if my_turns % 2 == 0 else find_button_deep(s, "ŞİMDİLİK ATLA")
		if b == null:
			break
		shot("%s_popup%d" % [tag, i])
		await click(b, "popup")
		await _wait(0.6)

func tour_panels(s: Node, tag: String) -> void:
	for t in ["Vekil", "Teşkilat", "Güç", "Seçmen"]:
		var b := find_button(s, t)
		if b == null:
			continue
		await click(b, t)
		await _wait(0.8)
		shot("%s_layer_%s" % [tag, t])
	await click(find_button(s, "Vekil"), "vekil")
	for t in ["PUAN", "VEKİL"]:
		await click(find_button(s, t), t)
		await _wait(0.5)
		shot("%s_left_%s" % [tag, t])
		await scroll_all(s, "%s_left_%s" % [tag, t])
	for t in ["HÜKÜMET", "LOG", "SEÇİLİ"]:
		var b := find_button(s, t)
		if b == null:
			continue
		await click(b, t)
		await _wait(0.6)
		shot("%s_right_%s" % [tag, t])
		await scroll_all(s, "%s_right_%s" % [tag, t])
	var plates: Array = _party_plates(s)
	for i in plates.size():
		plates = _party_plates(s)
		if i >= plates.size():
			break
		await click(plates[i], "parti %d" % i)
		await _wait(0.6)
		shot("%s_party%d" % [tag, i])
		if i == 0:
			await scroll_all(s, "%s_party%d" % [tag, i])
	await close_popups(s)
	await click(find_button(s, "HÜKÜMET"), "hükümet")
	await _wait(0.4)
	for t in ["DÜŞÜK", "YÜKSEK", "NORMAL"]:
		var b := find_button(s, t)
		if b != null:
			await click(b, t)
			await _wait(0.5)
			shot("%s_tax_%s" % [tag, t])
	if my_turns == 1:
		await stage_settings("game")

func _party_plates(s: Node) -> Array:
	var box: Node = s.get("_board_scroll")
	var list: Array = []
	if box != null:
		_collect_plates(box, list)
	return list

func _collect_plates(node: Node, list: Array) -> void:
	for c in node.get_children():
		if c is PanelContainer and (c as Control).is_visible_in_tree() and (c as Control).size.y > 50 \
				and (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			list.append(c)
		else:
			_collect_plates(c, list)

func _province_screen_pos(s: Node, pid: String) -> Vector2:
	var map: CanvasItem = s.get("map_holder")
	return map.get_global_transform_with_canvas() * root.get_node("GameMap").center_of(pid)

func _my_org_province() -> String:
	for pid in cm._province_ids:
		if cm.organization_level(pid, me()) > 0:
			return pid
	return ""

func _open_province(s: Node, pid: String) -> Node:
	await click_at(_province_screen_pos(s, pid))
	await _wait(0.7)
	var pa: Node = s.get("_province_actions")
	if pa == null or not (pa as Control).is_visible_in_tree():
		return null
	return pa

func tour_provinces(s: Node, tag: String) -> void:
	var home := _my_org_province()
	var ids: Array = cm._province_ids
	var other: String = ids[(my_turns * 7) % ids.size()]
	for pid in [home, other]:
		if pid == "" or gs() == null:
			continue
		var pa := await _open_province(s, pid)
		shot("%s_prov_%s" % [tag, pid])
		if pa == null:
			note("İL", "%s: il menüsü açılmadı (%s)" % [tag, pid])
			continue
		if my_turns <= 2:
			dump_buttons(pa, "il menüsü")
		overflow_check(pa, "%s_ilmenu" % tag)
		var org := find_button_deep(pa, "KUR")
		if org == null:
			org = find_button_deep(pa, "GELİŞTİR")
		if org != null and pid != home:
			await click(org, "teşkilat")
			await _wait(0.8)
			shot("%s_org_%s" % [tag, pid])
			pa = await _open_province(s, pid)
		if pa != null:
			var mit := find_button_deep(pa, "MİTİNG")
			if mit != null:
				await click(mit, "miting")
				await _wait(0.6)
				shot("%s_miting_page" % tag)
				if my_turns <= 2:
					dump_buttons(pa, "miting sayfası")
				await explore(pa, "%s_mitbtn" % tag, ["GERİ", "İLERİ", "MİTİNG YAP", "İL BİLGİSİ", "YATIRIM", "X"], 8)
				var go := find_button_deep(pa, "MİTİNG YAP")
				if go != null:
					await click(go, "miting yap")
					await _wait(1.5)
					shot("%s_miting_done" % tag)
		pa = await _open_province(s, pid)
		if pa != null:
			var inv := find_button_deep(pa, "YATIRIM")
			if inv != null:
				await click(inv, "yatırım")
				await _wait(0.6)
				shot("%s_invest_page" % tag)
				await explore(pa, "%s_invbtn" % tag, ["GERİ", "İLERİ", "YATIRIM YAP", "İL BİLGİSİ", "MİTİNG", "X"], 6)
				var go2 := find_button_deep(pa, "YATIRIM YAP")
				if go2 != null:
					await click(go2, "yatırım yap")
					await _wait(1.5)
					shot("%s_invest_done" % tag)
		pa = await _open_province(s, pid)
		if pa != null:
			var info := find_button_deep(pa, "İL BİLGİSİ")
			if info != null:
				await click(info, "il bilgisi")
				await _wait(0.8)
				shot("%s_info_%s" % [tag, pid])
				await scroll_all(s, "%s_info" % tag)
		await click_at(Vector2(20, 1070) * root.get_visible_rect().size / Vector2(1920, 1080))
		await _wait(0.3)

func tour_hand_and_actions(s: Node, tag: String) -> void:
	var count := hand_cards(s).size()
	for i in count:
		var cards := hand_cards(s)
		if i >= cards.size():
			break
		await click(cards[i], "kart %d" % i)
		await _wait(0.7)
		shot("%s_card%d" % [tag, i])
		if i == 0 and my_turns <= 4:
			dump_buttons(s, "kart açık")
		await close_popups(s)
	var extra := find_button(s, "KART ÇEK ·")
	if extra != null:
		await click(extra, "ek kart")
		await _wait(2.0)
		shot("%s_extra_draw" % tag)
		await _dismiss_new(s, tag + "x")
	for t in ["MECLİS", "İTTİFAK", "YARDIM"]:
		var b := find_button_deep(s, t)
		if b == null:
			note("YOK", "%s: %s düğmesi yok/etkin değil" % [tag, t])
			continue
		await click(b, t)
		await _wait(1.0)
		shot("%s_%s" % [tag, t])
		overflow_check(root, "%s_%s" % [tag, t])
		if t == "MECLİS":
			if my_turns <= 4:
				dump_buttons(s, "meclis")
			await explore(s, "%s_meclis" % tag, ["Haritaya dön", "TURU BİTİR", "Menü", "MECLİS", "İTTİFAK", "YARDIM",
				"Vekil", "Teşkilat", "Güç", "Seçmen", "VEKİL", "PUAN", "LOG", "SEÇİLİ", "HÜKÜMET",
				"DÜŞÜK", "NORMAL", "YÜKSEK", "ONAYLA", "Onayla"], 14)
		else:
			await explore(s, "%s_%s" % [tag, t], ["TURU BİTİR", "Menü", "MECLİS", "İTTİFAK", "YARDIM",
				"Vekil", "Teşkilat", "Güç", "Seçmen", "VEKİL", "PUAN", "LOG", "SEÇİLİ", "HÜKÜMET",
				"DÜŞÜK", "NORMAL", "YÜKSEK"], 8)
		await close_popups(s)
		await _wait(0.4)

func _initialize() -> void:
	out_dir = OS.get_environment("CRAWL_DIR")
	if out_dir == "":
		out_dir = OS.get_user_data_dir() + "/crawl"
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(5)
	change_scene_to_file("res://scenes/Lobby.tscn")
	await _frames(5)
	fast = OS.get_environment("CRAWL_FAST") != ""
	await stage_lobby()
	await stage_room()
	await stage_setup()
	fast = false
	await stage_game_loop()
	print("--- NOTLAR (%d) ---" % notes.size())
	for n in notes:
		print(n)
	quit()
