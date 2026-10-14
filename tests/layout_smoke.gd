extends SceneTree
## Layout das telas no modo celular e no modo computador: abre cada tela e
## janela, confere que nada sai da tela (sem cortes) e tira screenshots.
##   godot --path . --resolution 1200x540 -s res://tests/layout_smoke.gd -- layout=compact
##   godot --path . --resolution 1600x900 -s res://tests/layout_smoke.gd -- layout=wide
## Screenshots: user://layout_<modo>_<n>_<tela>.png

var app: Control
var ok := true
var shots := 0
var mode := ""


func _initialize() -> void:
	DeckStore.path = "user://test_decks.json"
	app = load("res://ui/app.tscn").instantiate()
	root.add_child(app)
	_run()


func _run() -> void:
	await _frames(5)
	mode = "celular" if UiProfile.compact else "computador"
	await _screen("menu")
	app.show_options()
	await _screen("opcoes")
	app.show_online()
	await _screen("online")
	app._on_builder()
	await _screen("montador")
	app.show_menu()
	await _frames(3)
	app._on_start()
	await _frames(10)
	var m = app.screen
	m.anim_speed = 0.0
	await _frames(3)
	_fits(m.decision_panel, "janela de troca de mão")
	await _shot("troca_de_mao")
	m._mulligan_finish()
	var guard := 0
	while (m.game.waiting_for() >= 0 or m.anim_busy or m.ai_busy) and guard < 600:
		guard += 1
		await _frames(1)
	await _frames(3)
	_fits(m.hand_scroll, "mão")
	_fits(m.board_col, "tabuleiro")
	_fits(m.menu_btn, "botão de menu")
	_fits(m.btn_end, "botão Encerrar turno")
	if UiProfile.compact:
		# no celular a mão é uma faixa própria embaixo das fileiras
		_check(m.hand_scroll.get_global_rect().position.y >= m.board_col.get_global_rect().end.y - 1, "a mão não pode cobrir o tabuleiro")
	await _shot("partida")

	m._open_game_menu()
	await _frames(3)
	_fits(m.viewer_panel, "menu da partida")
	await _shot("menu_da_partida")
	m._confirm("Começar uma nova partida?\nA partida atual será perdida.", "Nova partida", func(): pass)
	await _frames(3)
	_fits(m.viewer_panel, "confirmação")
	await _shot("confirmacao")
	m._close_viewer()
	m._open_pile("Seu baralho", m.game.players[m.me].deck, true)
	await _frames(3)
	_fits(m.viewer_panel, "pilha (baralho)")
	await _shot("pilha")
	m._close_viewer()
	m._inspect(m.game.players[m.me].hand[0])
	await _frames(3)
	_fits(m.viewer_panel, "inspeção")
	await _shot("inspecao")
	m._close_viewer()
	# carta especial animada (o Baralho Padrão tem o Lich)
	for c: Card in m.game.cards_by_uid.values():
		if c.id == "lich":
			m._inspect(c)
			await _frames(3)
			_fits(m.viewer_panel, "inspeção do Lich")
			await _shot("inspecao_lich")
			m._close_viewer()
			break
	m._show_end_panel({"match_winner": m.me, "gems": [2, 0], "round": 2})
	await _frames(3)
	_fits(m.end_panel, "painel de fim")
	await _shot("fim")
	m.menu_requested.emit()
	await create_timer(3.5).timeout

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_decks.json"))
	print("LAYOUT (%s, %dx%d virtual): %s" % [mode, int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y), "OK" if ok else "FALHOU"])
	quit(0 if ok else 1)


## Tela de menu: todos os painéis visíveis dentro da tela.
func _screen(tag: String) -> void:
	await _frames(4)
	for p in app.screen.find_children("*", "PanelContainer", true, false):
		if (p as Control).is_visible_in_tree() and not _in_scroll(p):
			_fits(p, tag)
	await _shot(tag)


## O que está dentro de uma área com rolagem pode ficar fora da tela (rola).
func _in_scroll(n: Node) -> bool:
	n = n.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


func _fits(c: Control, what: String) -> void:
	var vp := root.get_visible_rect().grow(1.0)
	var r := c.get_global_rect()
	_check(vp.encloses(r), "%s sai da tela: %s (tela %s)" % [what, r, root.get_visible_rect().size])


func _check(cond: bool, what: String) -> void:
	if not cond:
		push_error("Falhou: " + what)
		ok = false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(tag: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	if img == null:
		return
	var p := "user://layout_%s_%d_%s.png" % [mode, shots, tag]
	img.save_png(p)
	shots += 1
