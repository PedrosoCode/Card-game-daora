extends SceneTree
## Teste de ponta a ponta do modo online PELA TELA: a App joga contra um
## processo separado (tests/net_bot.gd) através do api.php local.
##   role=host  a tela cria a sala; o bot entra    (tela = jogador 0)
##   role=guest o bot cria a sala; a tela entra    (tela = jogador 1, testa me = 1)
## Precisa do servidor:  php -S 127.0.0.1:8070 -t server
## godot --path . -s res://tests/online_ui_smoke.gd -- role=guest

const URL := "http://127.0.0.1:8070/api.php"
var app: Control
var role := "host"
var bot_pid := -1
var shots := 0
var stale_hints := 0  # vezes em que a dica "Aguardando..." ficou presa na minha vez


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("role="):
			role = a.substr(5)
	OnlineClient.clear_session()
	app = load("res://ui/app.tscn").instantiate()
	root.add_child(app)
	_run()


func _bot(args: Array) -> void:
	var full := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/net_bot.gd", "--", "url=" + URL]
	full.append_array(args)
	bot_pid = OS.create_process(OS.get_executable_path(), full)


func _run() -> void:
	for i in 5:
		await process_frame
	app._on_online()
	await process_frame
	app.url_edit.text = URL
	if role == "host":
		app._online_create()
		while app.client.code == "":
			await process_frame
		_bot(["role=guest", "code=" + app.client.code, "deck=conspiracao"])
	else:
		var codefile := ProjectSettings.globalize_path("user://test_room_code.txt")
		DirAccess.remove_absolute(codefile)
		_bot(["role=host", "codefile=" + codefile, "deck=conspiracao"])
		var t := 0
		while not FileAccess.file_exists(codefile) and t < 600:
			t += 1
			await create_timer(0.1).timeout
		app.code_edit.text = FileAccess.get_file_as_string(codefile).strip_edges()
		app._online_join()
	# espera a partida abrir
	var guard := 0
	while not (app.screen.has_method("shutdown") and app.screen.game != null and app.screen.game.players.size() == 2) and guard < 600:
		guard += 1
		await create_timer(0.1).timeout
	var m = app.screen
	m.anim_speed = 3.0
	await create_timer(0.5).timeout
	await _shot("inicio")
	var t0 := Time.get_ticks_msec()
	guard = 0
	var last_dbg := 0
	while not m.game.over and not m.net_failed and guard < 200000:
		guard += 1
		await process_frame
		if Time.get_ticks_msec() - last_dbg > 3000:
			last_dbg = Time.get_ticks_msec()
			print("DBG turno=%d atual=%d espera=%d pend=%s seq=%d out=%d in=%d anim=%s dec=%s" % [m.game.turn_num, m.game.current,
				m.game.waiting_for(), m.game.pending.get("kind", "-"), m.net_seq, m.net_outbox.size(), m.net_inbox.size(),
				m.anim_busy, m.decision_panel.visible])
		if m.dialog.visible:
			m.dialog.hide()
			m._on_dialog_closed()
			continue
		if m.anim_busy:
			continue
		if m.decision_panel.visible:
			if int(shots) < 2:
				await _shot("decisao")
			_decide(m)
			continue
		if m.game.is_turn(m.me) and m.net_outbox.is_empty():
			# a dica tem que sair de "Aguardando a jogada do oponente" quando a vez volta
			var w := 0
			while m.hint_label.text.begins_with("Aguardando a jogada") and w < 60:
				w += 1
				await process_frame
			if m.hint_label.text.begins_with("Aguardando a jogada"):
				stale_hints += 1
			_turn(m)
	while m.anim_busy:
		await process_frame
	await create_timer(0.5).timeout
	await _shot("fim")
	var ok: bool = m.game.over and not m.net_failed and m.end_panel.visible and stale_hints == 0
	print("ONLINE UI (%s, tela = jogador %d): %s | turnos %d | net_failed=%s | dica presa %d | %.1fs" % [
		role, m.me, "OK" if ok else "FALHOU", m.game.turn_num, m.net_failed, stale_hints, (Time.get_ticks_msec() - t0) / 1000.0])
	await create_timer(3.0).timeout  # deixa o bot terminar
	if bot_pid > 0:
		OS.kill(bot_pid)
	OnlineClient.clear_session()
	quit(0 if ok else 1)


func _decide(m) -> void:
	var g: Game = m.game
	if g.pending.get("kind") == "mulligan":
		var hand: Array = g.players[m.me].hand
		if g.mulligan_left(m.me) > 0 and not hand.is_empty() and m.mulligan_new.is_empty():
			m._mulligan_click(hand[0])
			m._mulligan_confirm()
		else:
			m._mulligan_finish()
	elif g.pending.get("kind") == "choice":
		m._on_choice_picked(g.pending["options"][0])


func _turn(m) -> void:
	var g: Game = m.game
	var me: int = m.me
	var p := g.players[me]
	for c: Card in p.board_cards():
		if g.can_attack(c):
			m.selected = c
			m._on_attack_pressed()
			m._execute_target(m.valid[0])
			return
	if not p.played_card and not p.hand.is_empty():
		for c: Card in p.hand:
			if not g.can_play(c) or not c.is_unit():
				continue
			m._select_hand(c)
			if m.mode == "place":
				var rows: Array = g.playable_rows(c)
				var click := InputEventMouseButton.new()
				click.pressed = true
				click.button_index = MOUSE_BUTTON_LEFT
				m._on_row_input(click, 0, "command" if rows.has("command") and randf() < 0.5 else rows[0])
			if m.mode == "target_play":
				m._execute_target(m.valid[0])
			if p.played_card:
				return
		m._on_pass()
		return
	if g.is_turn(me):
		m._on_end_turn()


func _shot(tag: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("user://online_%s_%d_%s.png" % [role, shots, tag])
	shots += 1
