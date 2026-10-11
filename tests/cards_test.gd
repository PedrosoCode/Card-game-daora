extends SceneTree
## Exercita TODAS as cartas: para cada uma, monta uma mesa com unidades dos dois
## lados, joga a carta (com alvo, se houver), ativa, ataca, passa e roda turnos.
## Qualquer "SCRIPT ERROR" na saída aponta a carta (o id é impresso antes).
## godot --headless --path . -s res://tests/cards_test.gd

const FILLER := ["cavaleiro", "carrasco", "bruxa", "lich", "ciborgue", "clerigo", "golem", "ia_central"]


func _init() -> void:
	CardDB.load_db()
	var tested := 0
	var played := 0
	var idle := PackedStringArray()
	for cid in CardDB.pool_ids():
		tested += 1
		if _exercise(cid):
			played += 1
		else:
			idle.append(cid)
	print("Cartas exercitadas: %d | jogadas com sucesso: %d" % [tested, played])
	if not idle.is_empty():
		print("Sem alvo válido nesta mesa de teste (esperado): ", ", ".join(idle))
	quit()


func _exercise(cid: String) -> bool:
	var g := Game.new()
	g.setup("padrao", "padrao", true, 11)
	_settle(g)  # troca de mão inicial
	g.current = 0
	for p in g.players:
		p.passed = false
		p.played_card = false
	# mesa: unidades nas três fileiras dos dois lados, já prontas
	var i := 0
	for pid in 2:
		for r in ["front", "back", "command"]:
			for k in 2:
				var c := Card.new(9000 + i, CardDB.get_def(FILLER[i % FILLER.size()]), pid)
				i += 1
				c.row = r
				c.exhausted = false
				c.poison = 1
				g.players[pid].rows[r].append(c)
	for pid in 2:
		for k in 4:
			g.players[pid].graveyard.append(Card.new(9500 + pid * 10 + k, CardDB.get_def(FILLER[k]), pid))
	var card := Card.new(8000, CardDB.get_def(cid), 0)
	g.players[0].hand.append(card)
	var ok := false
	if g.can_play(card):
		var spec := g.play_spec(card)
		var targets := g.valid_targets(spec, 0, card)
		var t: Card = targets[0] if not targets.is_empty() else null
		var row := "front" if card.is_unit() else ""
		ok = g.play_card(0, card, row, t)
		if not ok:
			push_error("[%s] não jogou: %s" % [cid, g.last_error])
		_settle(g)
	if card.on_board():
		card.exhausted = false
		if g.can_activate(card):
			var at := g.valid_targets(g.active_spec(card), 0, card)
			g.activate(0, card, at[0] if not at.is_empty() else null)
		if g.can_attack(card):
			var tg := g.attack_targets(card)
			g.attack(0, card, tg[0])
	# um aliado da mesa ataca (dispara on_attacked/on_damaged de quem estiver lá)
	for c: Card in g.players[0].rows["front"]:
		if g.can_attack(c):
			g.attack(0, c, g.attack_targets(c)[0])
			break
	# turnos e passe (on_pass, temporizadores, DoTs, on_death em cadeia)
	g.players[0].played_card = true
	g.end_turn(0)
	if not g.over and g.current == 1:
		g.players[1].played_card = true
		g.end_turn(1)
	if not g.over and g.is_turn(0):
		g.pass_round(0)
	_settle(g)
	return ok


## Resolve decisões pendentes (escolha no cemitério, troca de mão) pegando a 1ª opção.
func _settle(g: Game) -> void:
	var guard := 0
	while g.waiting_for() >= 0 and guard < 20:
		guard += 1
		var w := g.waiting_for()
		if g.pending["kind"] == "choice":
			g.resolve_choice(w, g.pending["options"][0])
		else:
			g.mulligan_done(w)
