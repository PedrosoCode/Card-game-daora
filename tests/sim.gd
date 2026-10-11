extends SceneTree
## Testes headless: avaliador de mãos + N partidas IA x IA.
## godot --headless --path . -s res://tests/sim.gd

func _init() -> void:
	var ok := _test_evaluator()
	ok = _test_deck() and ok
	ok = _test_timer() and ok
	ok = _test_decisions() and ok
	ok = _test_lockstep() and ok
	var n_games := 150
	var seat_wins := [0, 0]
	var draws := 0
	var starter_wins := 0
	var turns_total := 0
	var rounds_total := 0
	var steps_total := 0
	# lambdas capturam int por valor: contadores ficam num Dictionary
	var counts := {"events": 0, "discards": 0}
	var rank_count := {}
	for i in n_games:
		var g := Game.new()
		g.setup("padrao", "padrao", true, i + 1)
		var first := g.starter
		g.players[0].is_ai = true
		g.logged.connect(func(t: String):
			if t.contains(" descarta "):
				counts["discards"] += 1)
		g.event.connect(func(_ev: Dictionary): counts["events"] += 1)
		g.round_finished.connect(func(info: Dictionary):
			for nm in info["names"]:
				var k: String = String(nm).split(" (")[0]
				rank_count[k] = int(rank_count.get(k, 0)) + 1)
		var ais := [AIPlayer.new(g, 0), AIPlayer.new(g, 1)]
		var steps := 0
		while not g.over and steps < 20000:
			# quem age: quem tem decisão pendente (troca de mão, escolha) ou quem está no turno
			var who := g.waiting_for()
			var a: AIPlayer = ais[who if who >= 0 else g.current]
			if not a.step():
				push_error("IA travou (seed %d): %s" % [i + 1, g.last_error])
				ok = false
				break
			steps += 1
		steps_total += steps
		if not g.over:
			push_error("Partida não terminou (seed %d)" % (i + 1))
			ok = false
			continue
		turns_total += g.turn_num
		rounds_total += g.history.size()
		if g.winner < 0:
			draws += 1
		else:
			seat_wins[g.winner] += 1
			if g.winner == first:
				starter_wins += 1
	print("Partidas: %d | rodadas: %.2f | turnos: %.1f | ações: %.0f | eventos: %.0f | descartes: %.1f (médias por partida)" % [
		n_games, float(rounds_total) / n_games, float(turns_total) / n_games, float(steps_total) / n_games,
		float(counts["events"]) / n_games, float(counts["discards"]) / n_games])
	print("Vitórias: jogador 0 = %d, jogador 1 = %d, empates = %d" % [seat_wins[0], seat_wins[1], draws])
	print("Quem começa vence: %.1f%%" % (100.0 * starter_wins / n_games))
	print("Mãos no showdown: ", rank_count)
	ok = _random_decks(100) and ok
	print("RESULTADO: ", "OK" if ok else "FALHOU")
	quit(0 if ok else 1)


## Partidas com baralhos montados pela IA (AIDeckBuilder): exercita todas as cartas do acervo
## em jogo de verdade e mede quais naipes principais vencem mais.
func _random_decks(n_games: int) -> bool:
	var ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var seen := {}
	var suit_wins := {}
	var suit_games := {}
	var turns_total := 0
	for i in n_games:
		var decks := []
		for pid in 2:
			var ids := AIDeckBuilder.build(rng)
			if DeckStore.validate(ids) != "":
				push_error("AIDeckBuilder montou baralho inválido: " + DeckStore.validate(ids))
				ok = false
			CardDB.decks["sim_%d" % pid] = {"name": "sim", "cards": ids}
			decks.append(AIDeckBuilder.name_for(ids))
			for cid in ids:
				seen[cid] = true
		var g := Game.new()
		g.setup("sim_0", "sim_1", true, 5000 + i)
		g.players[0].is_ai = true
		var ais := [AIPlayer.new(g, 0), AIPlayer.new(g, 1)]
		var steps := 0
		while not g.over and steps < 20000:
			var who := g.waiting_for()
			if not ais[who if who >= 0 else g.current].step():
				push_error("IA travou com baralhos aleatórios (seed %d): %s" % [5000 + i, g.last_error])
				ok = false
				break
			steps += 1
		if not g.over:
			push_error("Partida com baralhos aleatórios não terminou (seed %d)" % (5000 + i))
			ok = false
			continue
		turns_total += g.turn_num
		for pid in 2:
			suit_games[decks[pid]] = int(suit_games.get(decks[pid], 0)) + 1
		if g.winner >= 0:
			suit_wins[decks[g.winner]] = int(suit_wins.get(decks[g.winner], 0)) + 1
	print("Baralhos da IA: %d partidas | turnos: %.1f | cartas diferentes usadas: %d de %d" % [
		n_games, float(turns_total) / n_games, seen.size(), CardDB.pool_ids().size()])
	var rates := PackedStringArray()
	for k in suit_games:
		rates.append("%s: %.0f%%" % [String(k).replace("Baralho da IA (foco em ", "").replace(")", ""),
			100.0 * int(suit_wins.get(k, 0)) / int(suit_games[k])])
	print("Vitórias por naipe principal: ", ", ".join(rates))
	return ok


## Decisões: troca de mão iterativa no início e a cadeia do Necromante
## (escolher carta -> escolher fileira -> a revivida pede o alvo da entrada).
func _test_decisions() -> bool:
	var ok := true
	var g := Game.new()
	g.setup("padrao", "padrao", true, 77)
	ok = _expect(g.waiting_for() == 0 and g.pending["kind"] == "mulligan", "troca de mão inicial pendente") and ok
	var p := g.players[0]
	var hand_before := p.hand.size()
	var deck_before := p.deck.size()
	var old: Card = p.hand[0]
	var fresh := g.mulligan_swap(0, old)
	ok = _expect(fresh != null and p.hand.has(fresh) and not p.hand.has(old) and p.deck.has(old), "troca 1 carta") and ok
	ok = _expect(p.hand.size() == hand_before and p.deck.size() == deck_before, "mão e baralho mantêm o tamanho") and ok
	ok = _expect(g.mulligan_left(0) == Game.MULLIGAN_MAX - 1, "orçamento de trocas desce") and ok
	g.mulligan_swap(0, fresh)  # pode trocar a nova de novo
	ok = _expect(g.mulligan_left(0) == Game.MULLIGAN_MAX - 2, "trocar a carta nova também conta") and ok
	g.mulligan_done(0)
	ok = _expect(g.waiting_for() == 1, "depois é a vez da IA trocar") and ok
	g.mulligan_done(1)
	ok = _expect(g.pending.is_empty() and g.turn_num == 1, "rodada começa depois das trocas") and ok

	# Necromante: cemitério só com Piromante e Arqueira; 2 inimigos na mesa
	g.current = 0
	p.played_card = false
	p.graveyard.clear()
	var piro := Card.new(9901, CardDB.get_def("piromante"), 0)
	p.graveyard.append(piro)
	p.graveyard.append(Card.new(9902, CardDB.get_def("arqueira_real"), 0))
	for k in 2:
		var e := Card.new(9910 + k, CardDB.get_def("golem"), 1)
		e.row = "front"
		g.players[1].rows["front"].append(e)
	var necro := Card.new(9900, CardDB.get_def("necromante"), 0)
	p.hand.append(necro)
	ok = _expect(g.play_card(0, necro, "front"), "Necromante entra") and ok
	ok = _expect(g.pending.get("option_kind") == "card" and (g.pending["options"] as Array).has(piro), "escolha de carta no cemitério") and ok
	g.resolve_choice(0, piro)
	ok = _expect(g.pending.get("option_kind") == "row" and g.pending["options"] == ["front", "back"], "escolha de fileira (Frente/Retaguarda)") and ok
	g.resolve_choice(0, "back")
	ok = _expect(piro.row == "back" and piro.hp == 2, "Piromante revivido na Retaguarda com 2 de HP") and ok
	ok = _expect(g.pending.get("option_kind") == "target", "revivida reaplica a entrada e pede o alvo") and ok
	var tgt: Card = g.pending["options"][0]
	var hp0 := tgt.hp + tgt.armor
	g.resolve_choice(0, tgt)
	ok = _expect(tgt.hp + tgt.armor == hp0 - 3, "efeito de entrada do Piromante (3 de dano) aplicado") and ok
	ok = _expect(g.pending.is_empty() and g.is_turn(0), "jogo segue depois das decisões") and ok
	print("Decisões (troca de mão, escolha, fileira, alvo): ", "OK" if ok else "FALHOU")
	return ok


## Base do modo online: a mesma semente + as mesmas ações (passando por JSON,
## como na rede) reproduzem a partida com o mesmo hash depois de CADA ação.
func _test_lockstep() -> bool:
	var ok := true
	for seed in [101, 202, 303]:
		var a := Game.new()
		a.setup("legiao", "conspiracao", true, seed)
		var ais := [AIPlayer.new(a, 0), AIPlayer.new(a, 1)]
		var hashes := []
		var guard := 0
		while not a.over and guard < 20000:
			guard += 1
			var who := a.waiting_for()
			if not ais[who if who >= 0 else a.current].step():
				break
			while hashes.size() < a.action_log.size():
				hashes.append(a.state_hash() if hashes.size() == a.action_log.size() - 1 else -1)
		var b := Game.new()
		b.setup("legiao", "conspiracao", true, seed)
		var bad := -1
		for i in a.action_log.size():
			var entry: Dictionary = a.action_log[i]
			var act: Dictionary = JSON.parse_string(JSON.stringify(entry["act"]))
			if not b.apply_action(int(entry["pid"]), act):
				bad = i
				push_error("Lockstep (semente %d): ação %d recusada: %s (%s)" % [seed, i, act, b.last_error])
				break
			if int(hashes[i]) != -1 and b.state_hash() != int(hashes[i]):
				bad = i
				push_error("Lockstep (semente %d): estado divergiu na ação %d: %s" % [seed, i, act])
				break
		var same: bool = bad < 0 and b.state_hash() == a.state_hash() and b.over == a.over and b.winner == a.winner
		if not same and bad < 0:
			push_error("Lockstep (semente %d): estado final diferente" % seed)
		ok = same and ok
	print("Lockstep (replay das ações por JSON, hash a cada passo): ", "OK" if ok else "FALHOU")
	return ok


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		push_error("Falhou: " + what)
	return cond


## Temporizador genérico: o Paladino (cooldown 3) dispara no 3º, 6º e 9º turno do dono.
func _test_timer() -> bool:
	var g := Game.new()
	g.setup("padrao", "padrao", true, 7)
	var p := g.players[0]
	var pal: Card = null
	for c: Card in p.hand + p.deck:
		if c.id == "paladino":
			pal = c
	p.hand.erase(pal)
	p.deck.erase(pal)
	pal.row = "front"
	p.rows["front"].append(pal)
	# o lambda não pode capturar `g` (ciclo g -> sinal -> lambda -> g vaza memória)
	var fired := []
	var state := {"turn": 0}
	var uid := pal.uid
	var on_event := func(ev: Dictionary):
		if ev["type"] == "timer" and int(ev["uid"]) == uid:
			fired.append(state["turn"])
	g.event.connect(on_event)
	for i in 9:
		state["turn"] = i + 1
		g.current = 0
		g._start_turn()
	g.event.disconnect(on_event)
	var expected := [3, 6, 9]
	var ok: bool = fired == expected
	if not ok:
		push_error("Temporizador: disparou em %s, esperado %s" % [fired, expected])
	print("Temporizador (cooldown): ", "OK" if ok else "FALHOU")
	return ok


## O baralho padrão precisa ter as 52 combinações de valor e naipe, sem repetir.
func _test_deck() -> bool:
	CardDB.load_db()
	var seen := {}
	for cid in CardDB.decks["padrao"]["cards"]:
		var d: Dictionary = CardDB.get_def(cid)
		seen["%s_%d" % [d["suit"], int(d["value"])]] = true
	var ok: bool = CardDB.decks["padrao"]["cards"].size() == 52 and seen.size() == 52
	if not ok:
		push_error("Baralho padrão não tem 52 cartas únicas (%d combinações)" % seen.size())
	print("Baralho de 52 cartas: ", "OK" if ok else "FALHOU")
	return ok


func _h(arr: Array) -> Array:
	var out := []
	for x in arr:
		out.append({"value": x[0], "suit": x[1]})
	return HandEvaluator.evaluate(out)


func _test_evaluator() -> bool:
	var ok := true
	var cases := [
		[[[14, "copas"], [13, "copas"], [12, "copas"], [11, "copas"], [10, "copas"]], HandEvaluator.STRAIGHT_FLUSH],
		[[[5, "paus"], [4, "copas"], [3, "copas"], [2, "copas"], [14, "copas"]], HandEvaluator.STRAIGHT],
		[[[9, "paus"], [9, "copas"], [9, "ouros"], [4, "copas"], [4, "paus"]], HandEvaluator.FULL_HOUSE],
		[[[2, "paus"], [7, "paus"], [9, "paus"], [11, "paus"], [4, "paus"]], HandEvaluator.FLUSH],
		[[[8, "paus"], [8, "copas"]], HandEvaluator.PAIR],
		[[[8, "paus"], [8, "copas"], [3, "paus"], [3, "copas"]], HandEvaluator.TWO_PAIR],
		[[[8, "paus"], [8, "copas"], [8, "espadas"], [8, "ouros"]], HandEvaluator.QUADS],
		[[[2, "paus"], [3, "paus"], [4, "paus"], [5, "paus"]], HandEvaluator.HIGH_CARD],
	]
	for c in cases:
		var k := _h(c[0])
		if int(k[0]) != int(c[1]):
			push_error("Avaliador: esperado %d, obtido %s para %s" % [c[1], k, c[0]])
			ok = false
	# desempates
	var a := _h([[10, "paus"], [10, "copas"], [14, "paus"]])
	var b := _h([[10, "ouros"], [10, "espadas"], [13, "paus"]])
	if HandEvaluator.compare(a, b) <= 0:
		push_error("Desempate por kicker falhou"); ok = false
	var c1 := _h([[10, "paus"], [10, "copas"]])
	var c2 := _h([[10, "ouros"], [10, "espadas"], [2, "paus"]])
	if HandEvaluator.compare(c2, c1) <= 0:
		push_error("Kicker extra deveria vencer"); ok = false
	var wheel := _h([[5, "paus"], [4, "copas"], [3, "copas"], [2, "copas"], [14, "copas"]])
	var six := _h([[6, "paus"], [5, "copas"], [4, "copas"], [3, "copas"], [2, "copas"]])
	if HandEvaluator.compare(six, wheel) <= 0:
		push_error("Sequência até 6 deveria vencer A-5"); ok = false
	if HandEvaluator.compare(_h([]), _h([[2, "paus"]])) >= 0:
		push_error("Mão vazia deveria perder"); ok = false
	print("Avaliador de mãos: ", "OK" if ok else "FALHOU")
	return ok
