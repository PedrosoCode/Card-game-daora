extends SceneTree
## Teste de fumaça da UI: joga uma partida inteira "clicando" pelo código,
## com as animações ligadas, e tira screenshots no meio delas.
## godot --path . --disable-vsync -s res://tests/ui_smoke.gd   (salva screenshots em user://; layout=compact força o celular)
## Argumentos opcionais depois de "--": speed=0 (sem animação), speed=3 (padrão),
## sort=0..3 (ordem de exibição: padrão, naipe, valor, HP), decks=legiao,conspiracao (padrão)

var m: Control
var shots := 0
var burst_done := false
var captured := {}          # tipo de animação -> screenshots já tiradas


func _initialize() -> void:
	m = load("res://ui/main.tscn").instantiate()
	m.ai_delay = 0.0
	m.anim_speed = 3.0
	# baralhos com instantâneas e as mecânicas novas
	m.deck_ids = ["legiao", "conspiracao"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("speed="):
			m.anim_speed = float(arg.get_slice("=", 1))
		if arg.begins_with("decks="):
			m.deck_ids = Array(arg.get_slice("=", 1).split(","))
		if arg.begins_with("sort="):
			m.sort_mode = int(arg.get_slice("=", 1))
	root.add_child(m)
	_run()


func _run() -> void:
	await process_frame
	var guard := 0
	var t0 := Time.get_ticks_msec()
	while not m.game.over and guard < 200000:
		guard += 1
		await process_frame
		if m.dialog.visible:
			if shots < 6:
				await _shot("rodada")
			m.dialog.hide()
			m._on_dialog_closed()
			continue
		# rajada de screenshots durante as animações, a partir do meio da rodada 1
		if not burst_done and m.anim_busy and m.anim_speed > 0.0 and m.game.turn_num >= 12:
			burst_done = true
			for i in 5:
				await create_timer(0.12).timeout
				await _shot("anim")
		# captura os momentos de combate (até 2 de cada tipo)
		if m.anim_busy and m.anim_speed > 0.0 and m.anim_current in ["attack", "destroy", "damage", "buff", "cast", "summon", "move", "bounce"]:
			var k: String = m.anim_current
			if int(captured.get(k, 0)) < 2:
				captured[k] = int(captured.get(k, 0)) + 1
				await create_timer(0.1 / m.anim_speed).timeout
				await _shot(k)
		if m.decision_panel.visible and not m.anim_busy:
			await _decide()
			continue
		if m.anim_busy or not m.game.is_turn(0):
			continue
		_human_turn()
	while m.anim_busy:
		await process_frame
	await _shot("fim")
	var ok: bool = m.game.over and m.end_panel.visible
	print("UI: partida terminou = ", m.game.over, " | painel de fim = ", m.end_panel.visible,
		" | tabuleiro final na mesa = ", not m.game.all_board().is_empty(),
		" | rodadas = ", m.game.history.size(), " | turnos = ", m.game.turn_num,
		" | %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0 if ok else 1)


## Faz no máximo UMA ação por chamada; o laço espera as animações entre elas.
func _human_turn() -> void:
	var g: Game = m.game
	var me := g.players[0]
	for c: Card in me.board_cards():
		if g.can_activate(c):
			m.selected = c
			m._on_active_pressed()
			if m.mode == "activate":
				m._execute_target(_pick(m.valid))
			return
		if g.can_attack(c):
			m.selected = c
			m._on_attack_pressed()
			m._execute_target(_pick(m.valid))
			return
	if not me.played_card and not me.hand.is_empty():
		if me.rows["command"].size() >= 5 and randf() < 0.3:
			m._on_pass()
			return
		for c: Card in me.hand:
			if not g.can_play(c):
				continue
			m._select_hand(c)
			if m.cast_confirm == c:
				# instantânea sem alvo: o 2º clique confirma
				m._select_hand(c)
			if m.mode == "place":
				var rows: Array = g.playable_rows(c)
				var r: String = "command" if rows.has("command") and randf() < 0.5 else rows[randi() % rows.size()]
				var click := InputEventMouseButton.new()
				click.pressed = true
				click.button_index = MOUSE_BUTTON_LEFT
				m._on_row_input(click, 0, r)
			if m.mode in ["target_play", "target_effect"]:
				m._execute_target(_pick(m.valid))
			if me.played_card:
				return
		m.selected = me.hand[0]
		m._on_discard_pressed()
		return
	if g.is_turn(0):
		m._on_end_turn()


## Janelas de decisão: captura a primeira de cada tipo e resolve.
func _decide() -> void:
	var g: Game = m.game
	var kind: String = g.pending.get("kind", "")
	if kind == "choice":
		if int(captured.get("janela_escolha", 0)) < 1:
			captured["janela_escolha"] = 1
			await _shot("janela_escolha")
		if int(captured.get("janela_" + String(g.pending.get("option_kind")), 0)) < 1:
			captured["janela_" + String(g.pending.get("option_kind"))] = 1
			await _shot("janela_" + String(g.pending.get("option_kind")))
		m._on_choice_picked(g.pending["options"][0])
	elif kind == "mulligan":
		# marca 2 cartas, confirma; depois marca 1 (pode ser nova) e confirma de novo
		var hand: Array = g.players[0].hand
		for i in mini(2, hand.size()):
			m._mulligan_click(hand[i])
		if int(captured.get("janela_troca", 0)) < 1:
			captured["janela_troca"] = 1
			await _shot("janela_troca")
		m._mulligan_confirm()
		while m.anim_busy:
			await process_frame
		if g.mulligan_left(0) > 0 and not g.players[0].hand.is_empty():
			m._mulligan_click(g.players[0].hand[-1])
			m._mulligan_confirm()
			while m.anim_busy:
				await process_frame
		m._mulligan_finish()


func _pick(arr: Array) -> Card:
	return arr[randi() % arr.size()] if not arr.is_empty() else null


func _shot(tag: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := "user://ui_%d_%s.png" % [shots, tag]
	img.save_png(path)
	print("screenshot: ", ProjectSettings.globalize_path(path))
	shots += 1
