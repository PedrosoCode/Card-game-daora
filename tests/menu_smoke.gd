extends SceneTree
## Teste de fumaça do menu e do montador de baralhos (usa um arquivo de
## baralhos próprio, não mexe nos baralhos salvos do jogador).
## xvfb-run godot --path . -s res://tests/menu_smoke.gd   (screenshots em user://)

const TEST_PATH := "user://test_decks.json"
var app: Control
var shots := 0
var ok := true


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	DeckStore.path = TEST_PATH
	app = load("res://ui/app.tscn").instantiate()
	root.add_child(app)
	_run()


func _run() -> void:
	await _frames(5)
	await _shot("menu")

	# ---- montador
	app._on_builder()
	await _frames(5)
	var b: DeckBuilder = app.screen
	await _shot("deckbuilder")
	b._new_empty()
	var units := []
	var instants := []
	for cid in CardDB.pool_ids():
		if String(CardDB.get_def(cid).get("kind")) == "unit":
			units.append(cid)
		else:
			instants.append(cid)
	# inválido: 24 unidades (52 cartas)
	for i in 24:
		b._add(units[i])
	for i in 28:
		b._add(instants[i])
	b.name_edit.text = "Teste"
	b._save()
	_check(not CardDB.decks.has("user:Teste"), "baralho com 24 unidades não pode ser salvo")
	# inválido: 25 unidades mas só 51 cartas
	b._add(units[0])
	b._remove(instants[27])
	b._remove(instants[26])
	b._save()
	_check(not CardDB.decks.has("user:Teste"), "baralho com 51 cartas não pode ser salvo")
	# válido: 25 unidades (uma cópia repetida) + 27 instantâneas = 52
	b._add(instants[26])
	b._save()
	_check(CardDB.decks.has("user:Teste"), "baralho válido deveria ser salvo")
	_check((CardDB.decks.get("user:Teste", {"cards": []})["cards"] as Array).size() == 52, "baralho salvo com 52 cartas")
	b.kind_opt.select(2)
	b._apply_filters()
	await _frames(3)
	await _shot("deckbuilder_instantaneas")

	# ---- volta ao menu e joga com o baralho novo contra a IA automática
	b.back_requested.emit()
	await _frames(5)
	app._select(app.my_deck, "user:Teste")
	app._select(app.ai_deck, app.AUTO)
	app._on_start()
	await _frames(10)
	var g = app.screen
	_check(g.has_method("shutdown"), "a partida deveria abrir")
	var total: int = g.game.players[0].deck.size() + g.game.players[0].hand.size()
	_check(total == 52, "a partida deveria usar o baralho de 52 cartas (usou %d)" % total)
	_check(g.decision_panel.visible, "a troca de mão inicial deveria abrir")
	_check(String(CardDB.decks["ia_auto"]["name"]).begins_with("Baralho da IA"), "IA deveria montar o próprio baralho")
	await create_timer(1.5).timeout
	await _shot("partida")
	g.menu_requested.emit()
	await create_timer(3.5).timeout
	await _shot("menu_de_volta")
	_check(not is_instance_valid(g), "a partida anterior deveria ter sido liberada")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("MENU: ", "OK" if ok else "FALHOU")
	quit(0 if ok else 1)


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
	var p := "user://menu_%d_%s.png" % [shots, tag]
	img.save_png(p)
	print("screenshot: ", ProjectSettings.globalize_path(p))
	shots += 1
