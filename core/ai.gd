class_name AIPlayer
extends RefCounted
## IA heurística simples. Cada chamada a step() executa UMA ação, para a UI
## poder animar entre elas. Retorna false quando não é o turno dela.

## Operações que prejudicam o alvo (boas contra inimigos, ruins contra aliados).
const HARMFUL := ["damage", "poison", "bleed", "destroy", "freeze", "silence", "strip", "bounce"]
## Operações que ajudam o alvo.
const HELPFUL := ["heal", "max_hp", "armor", "shield", "cleanse", "ready", "grant_kw"]
## Máximo de unidades da mão consideradas no plano da Cadeia (12 -> ~1.6k combinações).
const PLAN_POOL := 12

var game: Game
var pid: int
var _tried := {}
var _tried_turn := -1


## Sorteio próprio da IA (variar escolhas). Ela NUNCA usa game.rng: o sorteio
## da partida tem que depender só das ações, senão o replay/online diverge.
var rng := RandomNumberGenerator.new()


func _init(g: Game, id: int) -> void:
	game = g
	pid = id
	rng.seed = g.rng.seed + 7919 * (id + 1)


func step() -> bool:
	# decisões pendentes (escolha no cemitério, troca de mão) vêm antes de tudo
	var w := game.waiting_for()
	if w == pid:
		return _resolve_pending()
	if w >= 0:
		return false
	if game.over or game.current != pid or game.players[pid].passed:
		return false
	if _tried_turn != game.turn_num:
		_tried.clear()
		_tried_turn = game.turn_num
	var me := game.players[pid]

	# 1) efeitos ativos
	for c: Card in me.board_cards():
		if game.can_activate(c) and not _tried.has(c.uid):
			_tried[c.uid] = true
			var spec := game.active_spec(c)
			var t: Card = null
			if not spec.is_empty():
				t = _pick_target(game.valid_targets(spec, pid, c), c.def["active"])
				if t == null:
					continue
			if game.activate(pid, c, t):
				return true

	# 2) ataques
	for c: Card in me.board_cards():
		var atk_key := "atk_%d_%d" % [c.uid, c.attacks_made]
		if game.can_attack(c) and not _tried.has(atk_key):
			_tried[atk_key] = true
			var at := _pick_attack(c)
			if at != null and game.attack(pid, c, at):
				return true

	# 3) jogar (ou descartar) uma carta, passar ou encerrar
	if not me.played_card and not me.hand.is_empty():
		if _should_pass():
			return game.pass_round(pid)
		var play := _choose_play()
		if not play.is_empty() and game.play_card(pid, play["card"], play["row"], play["target"]):
			return true
		if _should_cycle():
			return game.discard(pid, _pick_discard())
		return game.pass_round(pid)
	if game.opponent(pid).passed and _cmp() > 0:
		return game.pass_round(pid)
	return game.end_turn(pid)


func _resolve_pending() -> bool:
	var pend: Dictionary = game.pending
	if pend["kind"] == "mulligan":
		# troca uma carta por vez (reavaliando a mão nova); para quando não vale mais
		if game.mulligan_left(pid) > 0:
			var cand := _mulligan_pick(1)
			if not cand.is_empty():
				return game.mulligan_swap(pid, cand[0]) != null
		return game.mulligan_done(pid)
	var options: Array = pend["options"]
	match String(pend.get("option_kind", "card")):
		"row":
			return game.resolve_choice(pid, _pick_row(options, pend.get("preview")))
		"target":
			var src: Card = pend["preview"]
			return game.resolve_choice(pid, _best_target(options, src.def.get("on_play", {})))
	var best: Card = null
	var best_s := -INF
	for c: Card in options:
		var s := _card_worth(c)
		if s > best_s:
			best_s = s
			best = c
	return game.resolve_choice(pid, best)


## Fileira para uma carta que entra por efeito (reviver, invocar).
func _pick_row(rows: Array, c: Card) -> String:
	if c != null:
		if c.has_kw("guardiao") and rows.has("front"):
			return "front"
		var act: Dictionary = c.def.get("active", {})
		if (act.get("rows", []) as Array).has("back") and rows.has("back"):
			return "back"
		if c.atk <= 0 and rows.has("back"):
			return "back"
	return "front" if rows.has("front") else String(rows[0])


## Quanto vale ter esta carta (para escolher no cemitério).
func _card_worth(c: Card) -> float:
	if not c.is_unit():
		return 4.0
	return c.base_value * 0.6 + c.atk * 1.2 + c.max_hp * 0.3 + (3.0 if c.def.has("active") or c.def.has("passives") else 0.0)


## Troca de mão: devolve unidades baixas, sem par na mão e fora do plano da Cadeia.
func _mulligan_pick(limit: int) -> Array:
	var me := game.players[pid]
	var plan_cards: Array = _plan_command()["cards"]
	var counts := {}
	for c: Card in me.hand:
		if c.is_unit():
			counts[c.base_value] = int(counts.get(c.base_value, 0)) + 1
	var out := []
	for c: Card in me.hand:
		if c.is_unit() and not plan_cards.has(c) and int(counts[c.base_value]) == 1 and c.base_value <= 8:
			out.append(c)
	out.sort_custom(func(a: Card, b: Card) -> bool: return a.base_value < b.base_value)
	return out.slice(0, limit)


func _cmp() -> int:
	return HandEvaluator.compare(game.hand_key(pid), game.hand_key(1 - pid))


func _should_pass() -> bool:
	var me := game.players[pid]
	var opp := game.opponent(pid)
	var cmp := _cmp()
	if opp.passed:
		return cmp > 0
	var my_cmd: int = me.rows["command"].size()
	var opp_cmd: int = opp.rows["command"].size()
	if my_cmd >= 5 and opp_cmd >= 4 and cmp > 0:
		return true
	# rodada 1 perdida: economiza cartas para as próximas
	if game.round_num == 1 and me.gems == Game.START_GEMS and me.hand.size() <= 9 and opp_cmd >= 4 and cmp < 0:
		return true
	return false


## Sem jogada possível (fileiras cheias): descartar compra outra carta, então
## repetir isso queimaria o baralho das próximas rodadas. Só troca cartas se
## estiver perdendo e se o baralho ainda guardar as compras das rodadas futuras.
func _should_cycle() -> bool:
	if _cmp() > 0:
		return false
	var reserve := 0
	for r in Game.DRAW_AFTER_ROUND:
		if int(r) >= game.round_num:
			reserve += int(Game.DRAW_AFTER_ROUND[r])
	return game.players[pid].deck.size() > reserve


## Descarta a carta de menor valor que não está no plano da Cadeia de Comando.
func _pick_discard() -> Card:
	var me := game.players[pid]
	var plan := _plan_command()
	var worst: Card = null
	for c: Card in me.hand:
		if (plan["cards"] as Array).has(c):
			continue
		if worst == null or c.base_value < worst.base_value:
			worst = c
	if worst == null:
		worst = me.hand[0]
	return worst


func _choose_play() -> Dictionary:
	var me := game.players[pid]
	var best := {}
	var best_score := -INF
	var base_key := game.hand_key(pid)
	for c: Card in me.hand:
		if not game.can_play(c):
			continue
		var spec := game.play_spec(c)
		var block: Dictionary = c.def.get("on_play", {})
		if c.is_unit():
			# alvo de entrada é obrigatório quando existe: escolhe o menos ruim
			var t: Card = null
			var t_score := 0.0
			if not spec.is_empty():
				var targets := game.valid_targets(spec, pid, c)
				if not targets.is_empty():
					t = _best_target(targets, block)
					t_score = _target_value(t, block)
					if t_score <= -50.0:
						continue
			var extra := t_score * 0.5 + _untargeted_value(block, c) * 0.5
			for r in game.playable_rows(c):
				var s := _score_unit(c, r, base_key) + extra + rng.randf() * 0.5
				if s > best_score:
					best_score = s
					best = {"card": c, "row": r, "target": t}
		else:
			var t2: Card = null
			var s2 := 1.0 + _untargeted_value(block, c)
			if not spec.is_empty():
				t2 = _best_target(game.valid_targets(spec, pid, c), block)
				if t2 == null:
					continue
				var tv := _target_value(t2, block)
				if tv <= -50.0:
					continue
				s2 += tv
			# instantânea gasta a carta do turno: só vale se fizer algo útil
			if s2 < 2.0:
				continue
			s2 += rng.randf() * 0.5
			if s2 > best_score:
				best_score = s2
				best = {"card": c, "row": "", "target": t2}
	return best


## Melhor conjunto de cartas da mão para completar a Cadeia de Comando.
## Testa todas as combinações (12 cartas -> ~1.6k avaliações, barato).
func _plan_command() -> Dictionary:
	var me := game.players[pid]
	var fixed := game.hand_entries(pid)
	var free := Game.ROW_SIZE - fixed.size()
	var units: Array[Card] = []
	for c: Card in me.hand:
		if c.is_unit():
			units.append(c)
	# mãos enormes (30+ cartas) explodem a busca: fica com as 12 mais promissoras
	# (valores repetidos e naipes em comum valem mais para o poker)
	if units.size() > PLAN_POOL:
		var vcount := {}
		var scount := {}
		for c: Card in units:
			vcount[c.base_value] = int(vcount.get(c.base_value, 0)) + 1
			scount[c.suit] = int(scount.get(c.suit, 0)) + 1
		units.sort_custom(func(a: Card, b: Card) -> bool:
			return _plan_weight(a, vcount, scount) > _plan_weight(b, vcount, scount))
		units = units.slice(0, PLAN_POOL)
	var best := {"key": HandEvaluator.evaluate(fixed), "cards": []}
	if free <= 0:
		return best
	var combo: Array = []
	_search(units, 0, free, combo, fixed, best)
	return best


func _plan_weight(c: Card, vcount: Dictionary, scount: Dictionary) -> float:
	return int(vcount[c.base_value]) * 3.0 + int(scount[c.suit]) * 0.7 + c.base_value * 0.2


func _search(units: Array[Card], start: int, free: int, combo: Array, fixed: Array, best: Dictionary) -> void:
	if not combo.is_empty():
		var entries := fixed.duplicate()
		for c: Card in combo:
			entries.append({"value": c.base_value, "suit": c.suit})
		var k := HandEvaluator.evaluate(entries)
		if HandEvaluator.compare(k, best["key"]) > 0:
			best["key"] = k
			best["cards"] = combo.duplicate()
	if combo.size() >= free:
		return
	for i in range(start, units.size()):
		combo.append(units[i])
		_search(units, i + 1, free, combo, fixed, best)
		combo.pop_back()


var _plan: Dictionary = {}
var _plan_turn := -1


func _score_unit(c: Card, r: String, base_key: Array) -> float:
	if r == "command":
		if _plan_turn != game.turn_num:
			_plan = _plan_command()
			_plan_turn = game.turn_num
		var in_plan := (_plan.get("cards", []) as Array).has(c)
		var entries := game.hand_entries(pid)
		entries.append({"value": c.base_value, "suit": c.suit})
		var nk := HandEvaluator.evaluate(entries)
		var s := float(int(nk[0]) - int(base_key[0])) * 6.0
		if in_plan:
			s += 8.0 + float(int(_plan["key"][0])) * 2.0
		else:
			s -= 4.0
		return s + c.base_value * 0.2 + Game.command_armor(c) * 0.1
	var s2 := c.atk * 1.5 + c.max_hp * 0.4 - c.base_value * 0.35
	if c.def.has("active"):
		var ar: Array = (c.def["active"] as Dictionary).get("rows", [])
		s2 += 5.0 if (ar.is_empty() or ar.has(r)) else -4.0
	if c.has_kw("guardiao") and r == "front":
		s2 += 3.0
	return s2


func _pick_target(cands: Array, block: Dictionary) -> Card:
	var t := _best_target(cands, block)
	return t if t != null and _target_value(t, block) > -50.0 else null


func _best_target(cands: Array, block: Dictionary) -> Card:
	var best: Card = null
	var best_s := -INF
	for t: Card in cands:
		var s := _target_value(t, block)
		if s > best_s:
			best_s = s
			best = t
	return best


## Quanto vale aplicar os efeitos de alvo escolhido (target "chosen") em t.
## Muito negativo (<= -50) = não faça.
func _target_value(t: Card, block: Dictionary) -> float:
	var s := 0.0
	var enemy := t.owner != pid
	var in_cmd := t.row == "command"
	for e: Dictionary in block.get("effects", []):
		if String(e.get("target", "chosen")) != "chosen":
			continue
		var op: String = e.get("op", "")
		var amt := int(e.get("amount", 1))
		# custo pago de propósito (ex.: sacrificar uma aliada para comprar cartas)
		if bool(e.get("cost", false)) and not enemy:
			s -= 2.0 + t.base_value * 0.2 + (8.0 if in_cmd else 0.0)
			continue
		match op:
			"damage", "poison", "bleed", "destroy":
				if not enemy:
					return -100.0
				s += 2.0 + game.effective_atk(t)
				if in_cmd:
					s += 6.0 + game.effective_value(t) * 0.3
				var reach := 999 if op == "destroy" else amt
				var ehp := t.hp + (0 if op in ["poison", "bleed"] or bool(e.get("pierce", false)) else t.armor)
				if reach >= ehp and t.shield == 0:
					s += 8.0
				if t.shield > 0 and op == "damage":
					s -= 4.0
			"freeze":
				if not enemy:
					return -100.0
				s += 1.0 + game.effective_atk(t) * 1.5
			"silence":
				if not enemy:
					return -100.0
				var has_ability := t.def.has("passives") or t.def.has("active") or not t.keywords.is_empty()
				s += 6.0 if has_ability else -60.0
			"strip":
				if not enemy:
					return -100.0
				s += t.armor + t.shield * 3.0 - 1.0 + (3.0 if in_cmd else 0.0)
			"bounce":
				if not enemy:
					return -100.0
				s += 3.0 + game.effective_atk(t) + t.armor * 0.5
			"move":
				# puxar uma unidade da Retaguarda inimiga abre caminho para a Cadeia
				if not enemy:
					return -100.0
				var opp := game.players[t.owner]
				s += 6.0 if opp.rows["back"].size() == 1 else 2.0
			"value":
				if (amt > 0) == enemy:
					return -100.0
				s += 9.0 if in_cmd else -5.0
			"set_value":
				if enemy or not in_cmd:
					return -100.0
				var before := game.hand_key(pid)
				var old_base := t.base_value
				var old_mod := t.value_mod
				t.base_value = game._value_for(e, pid, t)
				t.value_mod = 0
				var after := game.hand_key(pid)
				t.base_value = old_base
				t.value_mod = old_mod
				s += float(HandEvaluator.compare(after, before)) * 6.0 + float(int(after[0]) - int(before[0])) * 4.0 - 1.0
			"heal":
				if enemy:
					return -100.0
				s += amt * 0.5 + maxi(0, int(t.def.get("hp", 0)) - t.hp) * 1.5 + (2.0 if in_cmd else 0.0)
			"armor", "max_hp", "shield":
				if enemy:
					return -100.0
				s += 2.0 + (4.0 if in_cmd else 0.0) + t.atk * 0.5 + (3.0 if op == "shield" else 0.0)
			"cleanse":
				if enemy:
					return -100.0
				s += (t.poison + t.bleed) * 3.0
			"ready":
				if enemy or not t.attacked:
					return -100.0
				s += 2.0 + game.effective_atk(t)
			"grant_kw", "atk":
				if (op == "atk" and amt < 0) == (not enemy):
					return -100.0
				s += 2.0 + (0.0 if in_cmd else game.effective_atk(t) * 0.5)
			"set_suit":
				s += _suit_change_value(t, e)
			"copy_value":
				if enemy:
					return -100.0
				s += t.base_value * 0.5 + (5.0 if in_cmd else 0.0)
	return s


func _suit_change_value(t: Card, e: Dictionary) -> float:
	var new_suit := game.suit_for(e, pid)
	if new_suit == "" or new_suit == t.suit:
		return -100.0
	var before := game.hand_key(t.owner)
	var old_suit := t.suit
	t.suit = new_suit
	var after := game.hand_key(t.owner)
	t.suit = old_suit
	var delta := float(int(after[0]) - int(before[0])) * 10.0
	return delta if t.owner == pid else -delta + 1.0


## Valor dos efeitos que não usam o alvo escolhido (área, aleatório, jogador).
func _untargeted_value(block: Dictionary, c: Card) -> float:
	var s := 0.0
	var me := game.players[pid]
	var opp := game.opponent(pid)
	for e: Dictionary in block.get("effects", []):
		var op: String = e.get("op", "")
		var tmode: String = e.get("target", "chosen")
		var amt := int(e.get("amount", 1))
		match op:
			"recall", "revive":
				var cands := game._grave_candidates(e, me)
				s += 5.0 + (2.0 if String(e.get("from", "own")) != "own" else 0.0) if not cands.is_empty() else -20.0
			"exile_grave":
				s += mini(amt, opp.graveyard.size()) * 1.0 - 1.0
			"draw":
				s += 2.5 * amt
			"discard_own":
				s -= 2.0 * amt
			"discard_enemy":
				s += 4.0 * amt if not opp.hand.is_empty() else -20.0
			"mill":
				s += 0.8 * mini(amt, opp.deck.size())
			"summon":
				var row: String = e.get("row", "front")
				s += 2.0 * mini(amt, Game.ROW_SIZE - me.rows[row].size())
			_:
				if tmode != "all" and tmode != "random":
					continue
				# efeito de área: conta inimigos e aliados atingidos
				var good := 0
				var bad := 0
				for t: Card in game._filter_board(e.get("filter", {}), c):
					var harmful: bool = op in HARMFUL or (op in ["value", "atk"] and amt < 0)
					if (t.owner != pid) == harmful:
						good += 2 if t.row == "command" else 1
					else:
						bad += 2 if t.row == "command" else 1
				if tmode == "random":
					s += 2.0 if good > 0 and bad == 0 else -1.0
				else:
					s += 2.0 * good - 2.5 * bad - 1.0
	return s


func _pick_attack(c: Card) -> Card:
	var best: Card = null
	var best_s := -3.0
	var dmg := game.effective_atk(c)
	for t: Card in game.attack_targets(c):
		var s := 0.0
		if t.row == "command":
			s += 6.0 + game.effective_value(t) * 0.3
		if dmg >= t.hp + t.armor:
			s += 8.0
		var counter := _retaliation(t, dmg)
		if counter >= c.hp + c.armor:
			s -= 6.0
		s -= counter * 0.5
		if t.shield > 0:
			# o golpe só tira o escudo
			s -= 3.0
		if s > best_s:
			best_s = s
			best = t
	return best


## Dano que o alvo devolve ao ser atacado (só cartas com a passiva on_attacked).
func _retaliation(t: Card, incoming: int) -> int:
	var total := 0
	for pas: Dictionary in t.def.get("passives", []):
		if String(pas.get("trigger", "")) != "on_attacked":
			continue
		for e: Dictionary in pas.get("effects", []):
			if String(e.get("op", "")) != "damage":
				continue
			var a := int(e.get("amount", 1))
			match String(e.get("per", "")):
				"self_atk":
					a *= game.effective_atk(t)
				"half_damage_taken":
					a *= maxi(1, floori(incoming / 2.0))
			total += a
	return total
