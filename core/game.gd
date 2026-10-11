class_name Game
extends RefCounted
## Motor de regras. Não conhece nenhum Node: a UI só chama as ações
## (play_card, attack, activate, end_turn, pass_round) e escuta os sinais.

signal changed
signal logged(text: String)
## Fato estruturado para a UI animar ({"type": ..., "uid", "card", "snap", ...}).
## Emitido na ordem exata em que as coisas acontecem dentro de uma ação.
signal event(ev: Dictionary)
signal round_finished(info: Dictionary)
signal match_finished(info: Dictionary)

const ROWS: Array[String] = ["front", "back", "command"]
const ROW_NAMES := {"front": "Frente de Batalha", "back": "Retaguarda", "command": "Cadeia de Comando"}
const ROW_SIZE := 5
const START_HAND := 17
const START_GEMS := 2
const DRAW_AFTER_ROUND := {1: 10, 2: 10}
## A Cadeia de Comando só pode ser atacada por unidades da Frente de Batalha,
## e só enquanto a Retaguarda inimiga estiver vazia (Alcance ignora).
const BACK_PROTECTS_COMMAND := true
## Se true, passar Sela a Cadeia (inimigos não miram mais nela). Desligado: quem
## passa continua exposto a ataques e efeitos, e o oponente precisa GASTAR cartas
## para virar a rodada (quebra a economia de recursos dele), em vez de um xeque-mate.
const PASS_SEALS_COMMAND := false
## Ao entrar na Cadeia de Comando, a carta ganha armadura = HP × este fator,
## arredondado para cima (1.5 = HP + 50%). Protege as cartas que formam a mão.
const COMMAND_ARMOR_MULT := 1.5
## Armadura é um segundo HP consumido primeiro, mas veneno e sangramento a ignoram.
## Os dois funcionam igual: N acúmulos = 1 de dano por turno durante N turnos.
const DOTS_PIERCE_ARMOR := true
## Troca de mão (início de cada rodada): até tantas trocas, uma carta por vez.
const MULLIGAN_MAX := 10
const SUITS: Array[String] = ["espadas", "copas", "ouros", "paus"]
const SUIT_NAMES := {"espadas": "Espadas", "copas": "Copas", "ouros": "Ouros", "paus": "Paus", "": "-"}
const SUIT_SYMBOLS := {"espadas": "♠", "copas": "♥", "ouros": "♦", "paus": "♣", "": ""}
const KEYWORD_NAMES := {"guardiao": "Guardião", "investida": "Investida", "alcance": "Alcance",
	"furtivo": "Furtividade", "furia": "Fúria", "roubo_vida": "Roubo de Vida"}
const KEYWORD_HELP := {
	"guardiao": "na Frente, obriga os ataques inimigos a mirarem um Guardião",
	"investida": "pode atacar no turno em que entra",
	"alcance": "ataca qualquer carta, ignorando Guardiões e a proteção da Cadeia",
	"furtivo": "não pode ser alvo de ataques até atacar (efeitos o alcançam)",
	"furia": "pode atacar duas vezes por turno",
	"roubo_vida": "ao causar dano atacando, cura essa mesma quantidade",
}
## Operações sem alvo de carta (agem sobre o jogador).
const PLAYER_OPS := ["draw", "recall", "revive", "exile_grave", "discard_enemy", "mill", "discard_own", "summon"]

var players: Array[PlayerState] = []
var current := 0
var round_num := 1
var turn_num := 0
var starter := 0
var round_starter := 0
var over := false
var winner := -1
var history: Array = []
var last_error := ""
var rng := RandomNumberGenerator.new()
var _next_uid := 1
var _depth := 0
## Decisão que um jogador precisa tomar antes de o jogo seguir. Enquanto existir,
## nenhuma outra ação é aceita (is_turn = false). Quem decide é a UI (jogador
## humano) ou o AIPlayer.step() (IA). Formatos:
##   {"kind": "choice", "pid", "prompt", "options": [...], "option_kind": "card"|"row"|"target",
##    "apply": Callable(opção), "preview": Card?, + continuação (block, index, chosen, ctx, finish)}
##   {"kind": "mulligan", "pids": [..], "budget": {pid: N}, "swapped": {pid: N}}
var pending: Dictionary = {}
var _suspending := false
## Toda carta criada nesta partida, por uid (a UI acha a carta clicada no registro).
var cards_by_uid: Dictionary = {}
## Toda ação aceita, em ordem: [{"pid", "act"}]. Com a mesma semente e os mesmos
## baralhos, repetir estas ações (apply_action) reproduz a partida exatamente.
## É o que o modo online troca pela rede.
var action_log: Array = []


# ---------------------------------------------------------------- setup

func setup(deck_p0: String = "padrao", deck_p1: String = "padrao", p1_is_ai: bool = true, seed_value: int = 0) -> void:
	CardDB.load_db()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	players.clear()
	var deck_ids := [deck_p0, deck_p1]
	for i in 2:
		var p := PlayerState.new()
		p.id = i
		p.name = "Você" if i == 0 else "Oponente"
		p.is_ai = i == 1 and p1_is_ai
		p.gems = START_GEMS
		for cid in CardDB.decks[deck_ids[i]]["cards"]:
			p.deck.append(_new_card(cid, i))
		_shuffle(p.deck)
		players.append(p)
	for p in players:
		draw(p, START_HAND, true)
	starter = rng.randi_range(0, 1)
	round_starter = starter
	current = starter
	# troca de mão também antes da 1ª rodada
	_open_mulligan()


func _new_card(cid: String, owner: int) -> Card:
	var c := Card.new(_next_uid, CardDB.get_def(cid), owner)
	_next_uid += 1
	cards_by_uid[c.uid] = c
	return c


## Nome da carta como link para o registro ("[url=uid]Nome[/url]").
func _cn(c: Card) -> String:
	return "[url=%d]%s[/url]" % [c.uid, c.name]


## Onde a carta está agora, em texto (para a janela de inspeção).
func locate(c: Card, viewer: int = 0) -> String:
	var p := players[c.owner]
	var who := "sua" if c.owner == viewer else "do oponente"
	if c.on_board():
		return "%s %s" % [ROW_NAMES[c.row], who]
	if p.hand.has(c):
		return "Mão " + who
	if p.graveyard.has(c):
		return "Cemitério " + ("seu" if c.owner == viewer else "do oponente")
	if p.deck.has(c):
		return "Baralho " + ("seu" if c.owner == viewer else "do oponente")
	return "Fora de jogo (exilada ou em uso)"


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func draw(p: PlayerState, n: int, silent: bool = false) -> void:
	var got := 0
	for i in n:
		if p.deck.is_empty():
			break
		p.hand.append(p.deck.pop_back())
		got += 1
	if not silent and got > 0:
		_log("%s compra %d carta(s)." % [p.name, got])
		_ev("draw", {"pid": p.id, "n": got})


# ---------------------------------------------------------------- consultas

static func value_label(v: int) -> String:
	match v:
		11: return "J"
		12: return "Q"
		13: return "K"
		14: return "A"
	return str(v)


## Ex.: "A♠", "10♥".
static func card_label(value: int, suit: String) -> String:
	return value_label(value) + String(SUIT_SYMBOLS.get(suit, ""))


func opponent(pid: int) -> PlayerState:
	return players[1 - pid]


func all_board() -> Array:
	var out := []
	for p in players:
		out.append_array(p.board_cards())
	return out


func is_turn(pid: int) -> bool:
	return not over and pending.is_empty() and current == pid and not players[pid].passed


## Jogador que precisa decidir algo agora (-1 = ninguém).
func waiting_for() -> int:
	if pending.is_empty():
		return -1
	if pending["kind"] == "choice":
		return int(pending["pid"])
	var pids: Array = pending["pids"]
	return int(pids.min())


## Quantas trocas ainda restam ao jogador na troca de mão pendente.
func mulligan_left(pid: int) -> int:
	if pending.get("kind", "") != "mulligan" or not (pending["pids"] as Array).has(pid):
		return 0
	return mini(int(pending["budget"][pid]), players[pid].deck.size())


func effective_value(c: Card) -> int:
	if not c.is_unit():
		return 0
	return clampi(c.base_value + c.value_mod + _aura_sum(c, "value"), 2, 14)


func effective_atk(c: Card) -> int:
	return maxi(0, c.atk + c.atk_mod + _aura_sum(c, "atk"))


func _aura_sum(c: Card, stat: String) -> int:
	if not c.on_board():
		return 0
	var total := 0
	for src: Card in all_board():
		if src.silenced:
			continue
		for pas: Dictionary in src.def.get("passives", []):
			if String(pas.get("aura", "")) != stat:
				continue
			if pas.has("rows") and not (pas["rows"] as Array).has(src.row):
				continue
			if _matches(c, pas.get("filter", {}), src.owner, src):
				total += int(pas.get("amount", 0))
	return total


func hand_entries(pid: int) -> Array:
	var out := []
	for c: Card in players[pid].rows["command"]:
		out.append({"value": effective_value(c), "suit": c.suit})
	return out


func hand_key(pid: int) -> Array:
	return HandEvaluator.evaluate(hand_entries(pid))


func hand_name(pid: int) -> String:
	return HandEvaluator.describe(hand_key(pid))


func playable_rows(card: Card) -> Array:
	var out := []
	if not card.is_unit():
		return out
	var p := players[card.owner]
	for r in ROWS:
		if p.rows[r].size() < ROW_SIZE:
			out.append(r)
	return out


func play_spec(card: Card) -> Dictionary:
	var block: Dictionary = card.def.get("on_play", {})
	return block.get("target", {})


func active_spec(card: Card) -> Dictionary:
	var block: Dictionary = card.def.get("active", {})
	return block.get("target", {})


func is_sealed(c: Card) -> bool:
	return PASS_SEALS_COMMAND and c.row == "command" and players[c.owner].passed


func valid_targets(spec: Dictionary, owner: int, source: Card) -> Array:
	var out := []
	if spec.is_empty():
		return out
	for c: Card in all_board():
		if c.owner != owner and is_sealed(c):
			continue
		if _matches(c, spec, owner, source):
			out.append(c)
	return out


func can_play(card: Card) -> bool:
	var p := players[card.owner]
	if not is_turn(card.owner) or p.played_card or not p.hand.has(card):
		return false
	if card.is_unit():
		return not playable_rows(card).is_empty()
	var spec := play_spec(card)
	return spec.is_empty() or not valid_targets(spec, card.owner, card).is_empty()


func can_attack(card: Card) -> bool:
	if not card.on_board() or not is_turn(card.owner):
		return false
	if card.row == "command" or card.attacked or card.stunned:
		return false
	if card.exhausted and not card.has_kw("investida"):
		return false
	if effective_atk(card) <= 0:
		return false
	return not attack_targets(card).is_empty()


func attack_targets(card: Card) -> Array:
	var opp := opponent(card.owner)
	var all_t: Array = opp.board_cards().filter(func(c: Card): return not is_sealed(c) and not c.has_kw("furtivo"))
	if card.has_kw("alcance"):
		return all_t
	# Regra-base: só a Frente de Batalha alcança a Cadeia de Comando, e só com a
	# Retaguarda inimiga vazia (efeitos alcançam sempre).
	if BACK_PROTECTS_COMMAND and not can_hit_command(card):
		all_t = all_t.filter(func(c: Card): return c.row != "command")
	var guards := []
	for c: Card in opponent(card.owner).rows["front"]:
		if c.has_kw("guardiao") and not c.has_kw("furtivo"):
			guards.append(c)
	return guards if not guards.is_empty() else all_t


## Armadura que a carta ganha ao entrar na Cadeia de Comando.
static func command_armor(card: Card) -> int:
	return ceili(card.hp * COMMAND_ARMOR_MULT)


func can_hit_command(card: Card) -> bool:
	return card.row == "front" and opponent(card.owner).rows["back"].is_empty()


func can_activate(card: Card) -> bool:
	if not card.def.has("active") or not card.on_board() or card.silenced:
		return false
	if not is_turn(card.owner) or card.exhausted or card.active_used or card.stunned:
		return false
	if int(card.timers.get("active", 0)) > 0:
		return false
	var a: Dictionary = card.def["active"]
	if a.has("rows") and not (a["rows"] as Array).has(card.row):
		return false
	var spec := active_spec(card)
	return spec.is_empty() or not valid_targets(spec, card.owner, card).is_empty()


func can_discard(card: Card) -> bool:
	var p := players[card.owner]
	return is_turn(card.owner) and not p.played_card and p.hand.has(card)


func max_attacks(card: Card) -> int:
	return 2 if card.has_kw("furia") else 1


## Sem cartas na mão não há o que jogar: o turno serve só para atacar e ativar.
func can_end_turn(pid: int) -> bool:
	return is_turn(pid) and (players[pid].played_card or players[pid].hand.is_empty())


## Um jogador terminou a rodada quando passou ou ficou sem cartas na mão.
## Sem cartas ele ainda recebe turnos (para atacar) enquanto o outro joga.
func is_done(pid: int) -> bool:
	var p := players[pid]
	return p.passed or p.hand.is_empty()


# ---------------------------------------------------------------- ações

func play_card(pid: int, card: Card, row: String = "", target: Card = null) -> bool:
	if card.owner != pid or not can_play(card):
		return _fail("Não é possível jogar esta carta agora.")
	var p := players[pid]
	var spec := play_spec(card)
	if card.is_unit():
		if not playable_rows(card).has(row):
			return _fail("Fileira inválida ou cheia.")
		var targets := valid_targets(spec, pid, card)
		if target != null and not targets.has(target):
			return _fail("Alvo inválido.")
		# efeito de entrada com alvo é obrigatório quando existe alvo possível
		if target == null and not spec.is_empty() and not targets.is_empty():
			return _fail("Escolha o alvo do efeito de entrada.")
		_record(pid, {"a": "play", "c": card.uid, "r": row, "t": _uid(target)})
		p.hand.erase(card)
		card.row = row
		card.exhausted = true
		p.rows[row].append(card)
		p.played_card = true
		_log("%s baixa [b]%s[/b] na %s." % [p.name, _cn(card), ROW_NAMES[row]])
		_ev("play", {"pid": pid, "row": row}, card)
		if row == "command":
			var bonus := command_armor(card)
			if bonus > 0:
				card.armor += bonus
				_log("  %s ganha %d de armadura ao entrar na Cadeia." % [_cn(card), bonus])
				_buff(card, null, "+%d ARM" % bonus, "armor")
		var finish_unit := func() -> void:
			for c: Card in p.board_cards():
				if c != card:
					_trigger(c, "on_ally_played", {"other": card})
		if card.def.has("on_play"):
			_resolve_block(card.def["on_play"], card, target, {})
		if _defer(finish_unit):
			return true
		finish_unit.call()
	else:
		if not spec.is_empty() and not valid_targets(spec, pid, card).has(target):
			return _fail("Escolha um alvo válido.")
		_record(pid, {"a": "play", "c": card.uid, "r": "", "t": _uid(target)})
		p.hand.erase(card)
		p.played_card = true
		_log("%s usa [b]%s[/b]." % [p.name, _cn(card)])
		_ev("cast", {"pid": pid}, card)
		var finish_cast := func() -> void:
			p.graveyard.append(card)
			_ev("cast_end", {"pid": pid}, card)
			for c: Card in p.board_cards():
				_trigger(c, "on_cast", {})
		_resolve_block(card.def.get("on_play", {}), card, target, {})
		if _defer(finish_cast):
			return true
		finish_cast.call()
	changed.emit()
	return true


## Se a resolução parou numa escolha, guarda o que falta fazer depois dela.
func _defer(finish: Callable) -> bool:
	if pending.get("kind", "") != "choice":
		return false
	pending["finish"] = finish
	changed.emit()
	return true


## Resolve a escolha pendente ("escolha 1 entre X cartas do cemitério") e
## continua os efeitos que vinham depois dela.
func resolve_choice(pid: int, card) -> bool:
	if pending.get("kind", "") != "choice" or int(pending["pid"]) != pid:
		return _fail("Não há escolha pendente para você.")
	if not (pending["options"] as Array).has(card):
		return _fail("Essa opção não está disponível.")
	_record(pid, {"a": "choice", "o": card.uid if card is Card else card})
	var pend := pending
	pending = {}
	_suspending = false
	if card is Card:
		_log("  %s escolhe [b]%s[/b]." % [players[pid].name, _cn(card)])
	else:
		_log("  %s escolhe a %s." % [players[pid].name, ROW_NAMES.get(card, str(card))])
	# a escolha aplicada pode pedir outra decisão (ex.: carta -> fileira -> alvo)
	_depth = 1
	(pend["apply"] as Callable).call(card)
	_depth = 0
	if not pending.is_empty():
		_suspending = false
		for k in ["block", "block_source", "index", "chosen", "ctx", "finish"]:
			if pend.has(k):
				pending[k] = pend[k]
		changed.emit()
		return true
	if pend.has("block"):
		_resolve_block(pend["block"], pend["block_source"], pend["chosen"], pend["ctx"], int(pend["index"]) + 1)
	if pending.get("kind", "") == "choice":
		# outra escolha logo em seguida: leva junto o que falta fazer no fim
		pending["finish"] = pend["finish"]
		changed.emit()
		return true
	var finish: Callable = pend.get("finish", Callable())
	if finish.is_valid():
		finish.call()
	changed.emit()
	return true


func _open_mulligan() -> void:
	var pids := []
	var budget := {}
	var swapped := {}
	for p in players:
		if not p.deck.is_empty() and not p.hand.is_empty():
			pids.append(p.id)
			budget[p.id] = MULLIGAN_MAX
			swapped[p.id] = 0
	if pids.is_empty():
		_begin_round()
		return
	pending = {"kind": "mulligan", "pids": pids, "budget": budget, "swapped": swapped}
	changed.emit()


## Troca UMA carta da mão: ela volta ao BARALHO (não ao cemitério), em posição
## aleatória fora do topo, e o jogador compra a de cima na hora. Pode trocar de
## novo (inclusive a nova) enquanto houver trocas. Retorna a carta nova.
func mulligan_swap(pid: int, card: Card) -> Card:
	if mulligan_left(pid) <= 0:
		_fail("Sem trocas restantes.")
		return null
	var p := players[pid]
	if not p.hand.has(card):
		_fail("Essa carta não está na sua mão.")
		return null
	_record(pid, {"a": "mswap", "c": card.uid})
	p.hand.erase(card)
	var fresh: Card = p.deck.pop_back()
	p.hand.append(fresh)
	if p.deck.is_empty():
		p.deck.append(card)
	else:
		p.deck.insert(rng.randi_range(0, p.deck.size() - 1), card)
	pending["budget"][pid] = int(pending["budget"][pid]) - 1
	pending["swapped"][pid] = int(pending["swapped"][pid]) + 1
	_ev("mulligan_swap", {"pid": pid, "old": card.uid}, fresh)
	changed.emit()
	return fresh


## Encerra a troca de mão do jogador. Quando todos encerram, a rodada começa.
func mulligan_done(pid: int) -> bool:
	if pending.get("kind", "") != "mulligan" or not (pending["pids"] as Array).has(pid):
		return _fail("Não há troca de mão pendente para você.")
	_record(pid, {"a": "mdone"})
	var n := int(pending["swapped"][pid])
	_log("%s %s." % [players[pid].name, "mantém a mão" if n == 0 else "troca %d carta(s) da mão" % n])
	_ev("mulligan", {"pid": pid, "n": n})
	(pending["pids"] as Array).erase(pid)
	if (pending["pids"] as Array).is_empty():
		pending = {}
		_begin_round()
	changed.emit()
	return true


## Atalho (IA e testes): troca estas cartas, uma por vez, e encerra.
func mulligan(pid: int, cards: Array) -> bool:
	for c in cards:
		if mulligan_swap(pid, c) == null:
			return false
	return mulligan_done(pid)


## do turno (não dá para baixar outra depois). Ataques e ativos seguem normais.
func discard(pid: int, card: Card) -> bool:
	if card.owner != pid or not can_discard(card):
		return _fail("Não é possível descartar agora.")
	_record(pid, {"a": "discard", "c": card.uid})
	var p := players[pid]
	p.hand.erase(card)
	p.graveyard.append(card)
	p.played_card = true
	_log("%s descarta [b]%s[/b]." % [p.name, _cn(card)])
	_ev("discard", {"pid": pid}, card)
	# o descarte troca a carta: compra uma na hora, mas o turno já não baixa mais nada
	draw(p, 1)
	changed.emit()
	return true


func attack(pid: int, attacker: Card, target: Card) -> bool:
	if attacker.owner != pid or not can_attack(attacker):
		return _fail("Esta unidade não pode atacar agora.")
	if not attack_targets(attacker).has(target):
		return _fail("Alvo inválido (há um Guardião na linha de frente?).")
	_record(pid, {"a": "attack", "c": attacker.uid, "t": target.uid})
	attacker.attacks_made += 1
	attacker.attacked = attacker.attacks_made >= max_attacks(attacker)
	# atacar revela a unidade furtiva
	attacker.keywords.erase("furtivo")
	_log("[b]%s[/b] ataca [b]%s[/b]." % [_cn(attacker), _cn(target)])
	_ev("attack", {"src": attacker.uid, "dst": target.uid})
	var taken := damage(target, effective_atk(attacker), attacker, false, "attack")
	if taken > 0 and attacker.on_board() and attacker.has_kw("roubo_vida"):
		attacker.hp += taken
		attacker.max_hp = maxi(attacker.max_hp, attacker.hp)
		_log("  %s rouba %d de vida." % [_cn(attacker), taken])
		_buff(attacker, attacker, "+%d HP" % taken, "heal")
	_trigger(attacker, "on_attack", {"other": target, "damage_dealt": taken})
	# não existe revide automático: só cartas com a passiva on_attacked reagem
	if target.on_board() and attacker.on_board():
		_trigger(target, "on_attacked", {"other": attacker, "damage_taken": taken})
	changed.emit()
	return true


func activate(pid: int, card: Card, target: Card = null) -> bool:
	if card.owner != pid or not can_activate(card):
		return _fail("Efeito ativo indisponível.")
	var spec := active_spec(card)
	if not spec.is_empty() and not valid_targets(spec, pid, card).has(target):
		return _fail("Alvo inválido.")
	_record(pid, {"a": "activate", "c": card.uid, "t": _uid(target)})
	card.active_used = true
	if card.timers.has("active"):
		card.timers["active"] = int(card.def["active"]["cooldown"])
	_log("%s ativa [b]%s[/b]." % [players[pid].name, _cn(card)])
	_ev("activate", {}, card)
	_resolve_block(card.def["active"], card, target, {})
	if _defer(func() -> void: pass):
		return true
	changed.emit()
	return true


func end_turn(pid: int) -> bool:
	if not can_end_turn(pid):
		return _fail("Jogue ou descarte uma carta antes de encerrar o turno, ou passe.")
	_record(pid, {"a": "end"})
	_next_turn()
	return true


func pass_round(pid: int) -> bool:
	if not is_turn(pid):
		return _fail("Não é seu turno.")
	_record(pid, {"a": "pass"})
	players[pid].passed = true
	_log("%s [b]passa[/b] a rodada." % players[pid].name)
	_ev("pass", {"pid": pid})
	for c: Card in players[pid].board_cards():
		_trigger(c, "on_pass", {})
	_next_turn()
	return true


# ---------------------------------------------------------------- fluxo

func _next_turn() -> void:
	if is_done(0) and is_done(1):
		_end_round()
		return
	var other := 1 - current
	if not players[other].passed:
		current = other
	_start_turn()


func _start_turn() -> void:
	if over:
		return
	turn_num += 1
	var p := players[current]
	p.played_card = false
	_ev("turn", {"pid": current})
	for c: Card in p.board_cards():
		c.exhausted = false
		c.attacked = false
		c.attacks_made = 0
		c.active_used = false
		c.stunned = false
		if c.frozen > 0:
			# Congelada: perde este turno inteiro
			c.frozen -= 1
			c.stunned = true
			c.exhausted = true
		_tick_timers(c)
	_tick_dots(p)
	# quem passou não tem turnos, então os DoTs dele correm no turno do outro
	var o := opponent(current)
	if o.passed:
		_tick_dots(o)
	for c: Card in p.board_cards():
		if c.on_board():
			_trigger(c, "turn_start", {})
	changed.emit()


## Temporizadores descem 1 no início de cada turno do dono (ver Card.timers).
func _tick_timers(c: Card) -> void:
	for k in c.timers:
		if int(c.timers[k]) > 0:
			c.timers[k] = int(c.timers[k]) - 1


func _tick_dots(p: PlayerState) -> void:
	for c: Card in p.board_cards():
		if is_sealed(c):
			continue
		if c.on_board() and c.poison > 0:
			c.poison -= 1
			_log("Veneno corrói %s." % _cn(c))
			damage(c, 1, null, DOTS_PIERCE_ARMOR, "poison")
		if c.on_board() and c.bleed > 0:
			c.bleed -= 1
			_log("%s sangra." % _cn(c))
			damage(c, 1, null, DOTS_PIERCE_ARMOR, "bleed")


func _end_round() -> void:
	var k0 := hand_key(0)
	var k1 := hand_key(1)
	var cmp := HandEvaluator.compare(k0, k1)
	var info := {
		"round": round_num,
		"names": [HandEvaluator.describe(k0), HandEvaluator.describe(k1)],
		"cards": [_command_desc(0), _command_desc(1)],
		"winner": -1,
		"match_over": false,
	}
	if cmp > 0:
		info["winner"] = 0
		players[1].gems -= 1
	elif cmp < 0:
		info["winner"] = 1
		players[0].gems -= 1
	else:
		players[0].gems -= 1
		players[1].gems -= 1
	var w: int = info["winner"]
	if w >= 0:
		_log("[b]Fim da rodada %d:[/b] %s vence com %s." % [round_num, players[w].name, info["names"][w]])
	else:
		_log("[b]Fim da rodada %d:[/b] empate com %s." % [round_num, info["names"][0]])
	if players[0].gems <= 0 or players[1].gems <= 0:
		over = true
		if players[0].gems > players[1].gems:
			winner = 0
		elif players[1].gems > players[0].gems:
			winner = 1
		else:
			winner = -1
		info["match_over"] = true
		info["match_winner"] = winner
	info["gems"] = [players[0].gems, players[1].gems]
	history.append(info)
	# o evento sai antes de limpar o tabuleiro, para a UI mostrar as Cadeias
	_ev("round_end", {"info": info})

	if over:
		# fim de jogo: o tabuleiro final fica na mesa para a UI mostrar
		_log("[b]Fim de jogo![/b] " + ("Empate." if winner < 0 else "%s vence a partida." % players[winner].name))
		round_finished.emit(info)
		match_finished.emit(info)
		changed.emit()
		return

	# tudo que estava no tabuleiro vai para o cemitério
	for p in players:
		for r in ROWS:
			for c: Card in p.rows[r]:
				c.row = ""
				p.graveyard.append(c)
			p.rows[r].clear()
		p.passed = false
		p.played_card = false

	round_num += 1
	var n: int = DRAW_AFTER_ROUND.get(round_num - 1, 0)
	for p in players:
		draw(p, n)
	# quem perdeu a rodada começa a próxima; em empate, alterna
	round_starter = (1 - round_starter) if w < 0 else (1 - w)
	current = round_starter
	round_finished.emit(info)
	_open_mulligan()


func _begin_round() -> void:
	_log("[b]Rodada %d[/b] - %s começa." % [round_num, players[current].name])
	_start_turn()


func _command_desc(pid: int) -> String:
	var parts := PackedStringArray()
	for c: Card in players[pid].rows["command"]:
		parts.append(card_label(effective_value(c), c.suit))
	return ", ".join(parts) if not parts.is_empty() else "(vazia)"


# ---------------------------------------------------------------- dano e morte

## kind: "attack" | "effect" | "poison" | "bleed" (só informa a UI).
## Retorna o dano sofrido (HP perdido + armadura consumida).
func damage(target: Card, amount: int, source: Card = null, pierce: bool = false, kind: String = "effect") -> int:
	if target == null or not target.on_board() or amount <= 0:
		return 0
	# Escudo anula a instância inteira de dano (veneno e sangramento passam)
	if target.shield > 0 and kind != "poison" and kind != "bleed":
		target.shield -= 1
		_log("  O escudo de %s bloqueia o dano." % _cn(target))
		_ev("damage", {"amount": 0, "absorbed": 0, "kind": kind, "blocked": true,
			"src": source.uid if source != null else -1}, target)
		return 0
	var dmg := amount
	var absorbed := 0
	if not pierce and target.armor > 0:
		absorbed = mini(target.armor, dmg)
		target.armor -= absorbed
		dmg -= absorbed
	target.hp -= dmg
	if absorbed > 0:
		_log("  %s sofre %d de dano (%d absorvido pela armadura)." % [_cn(target), dmg, absorbed])
	else:
		_log("  %s sofre %d de dano." % [_cn(target), dmg])
	_ev("damage", {"amount": dmg, "absorbed": absorbed, "kind": kind,
		"src": source.uid if source != null else -1}, target)
	if dmg > 0 and target.hp > 0:
		_trigger(target, "on_damaged", {"other": source, "damage_taken": dmg + absorbed})
	if target.hp <= 0:
		destroy(target, source)
	return dmg + absorbed


func destroy(card: Card, source: Card = null) -> void:
	if not card.on_board():
		return
	var p := players[card.owner]
	var old_row := card.row
	_ev("destroy", {"by": source.uid if source != null else -1, "row": old_row}, card)
	p.rows[old_row].erase(card)
	card.row = ""
	p.graveyard.append(card)
	_log("  [color=#ff8080]%s é destruída.[/color]" % _cn(card))
	_trigger(card, "on_death", {}, old_row)
	for c: Card in all_board():
		var trig := "on_ally_destroyed" if c.owner == card.owner else "on_enemy_destroyed"
		_trigger(c, trig, {"other": card})


# ---------------------------------------------------------------- efeitos

func _trigger(card: Card, trig: String, ctx: Dictionary, row_override: String = "") -> void:
	if card.silenced:
		return
	var passives: Array = card.def.get("passives", [])
	for i in passives.size():
		var pas: Dictionary = passives[i]
		if String(pas.get("trigger", "")) != trig:
			continue
		var r := row_override if row_override != "" else card.row
		if pas.has("rows") and not (pas["rows"] as Array).has(r):
			continue
		# passiva com temporizador: só dispara com ele zerado, e então recomeça
		var key := "p%d" % i
		if card.timers.has(key):
			if int(card.timers[key]) > 0:
				continue
			card.timers[key] = int(pas["cooldown"])
			_log("  ◷ %s: temporizador dispara." % _cn(card))
			_ev("timer", {}, card)
		_resolve_block(pas, card, null, ctx)


func _resolve_block(block: Dictionary, source: Card, chosen: Card, ctx: Dictionary, start: int = 0) -> void:
	if _depth > 12:
		return
	_depth += 1
	var effects: Array = block.get("effects", [])
	for i in range(start, effects.size()):
		_apply_effect(effects[i], source, chosen, ctx)
		if _suspending:
			# parou numa escolha do jogador: guarda onde continuar (resolve_choice)
			_suspending = false
			pending["block"] = block
			pending["block_source"] = source
			pending["index"] = i
			pending["chosen"] = chosen
			pending["ctx"] = ctx
			break
	_depth -= 1


func _apply_effect(eff: Dictionary, source: Card, chosen: Card, ctx: Dictionary) -> void:
	var op: String = eff.get("op", "")
	var amount := _amount(eff, source, ctx)
	if PLAYER_OPS.has(op):
		_apply_player_op(op, eff, source, amount, ctx)
		return
	# efeitos de valor zero (ex.: armadura por cemitério vazio) não fazem nada
	if amount <= 0 and op in ["damage", "heal", "max_hp", "armor", "poison", "bleed", "shield", "freeze"]:
		return
	for t: Card in _resolve_targets(eff, source, chosen, ctx):
		if t == null or not t.on_board():
			continue
		match op:
			"damage":
				damage(t, amount, source, bool(eff.get("pierce", false)))
			"heal", "max_hp":
				# HP não tem teto: curar acima do valor impresso fortalece a carta
				t.hp += amount
				t.max_hp = maxi(t.max_hp, t.hp)
				_log("  %s recupera %d HP." % [_cn(t), amount])
				_buff(t, source, "+%d HP" % amount, "heal")
			"armor":
				t.armor += amount
				_log("  %s ganha %d de armadura." % [_cn(t), amount])
				_buff(t, source, "+%d ARM" % amount, "armor")
			"poison":
				t.poison += amount
				_log("  %s é envenenada (%d)." % [_cn(t), t.poison])
				_buff(t, source, "Veneno %d" % t.poison, "poison")
			"bleed":
				t.bleed += amount
				_log("  %s sangra (%d)." % [_cn(t), t.bleed])
				_buff(t, source, "Sangra %d" % t.bleed, "bleed")
			"cleanse":
				var had := t.poison + t.bleed > 0
				t.poison = 0
				t.bleed = 0
				if had:
					_buff(t, source, "Purificada", "heal")
			"value":
				t.value_mod += amount
				_log("  %s agora vale %s." % [_cn(t), value_label(effective_value(t))])
				_buff(t, source, "%+d valor" % amount, "value")
			"atk":
				t.atk_mod += amount
				_buff(t, source, "%+d ATQ" % amount, "atk")
			"set_suit":
				var s := suit_for(eff, source.owner)
				if s != "":
					t.suit = s
					_log("  %s agora é do naipe %s." % [_cn(t), SUIT_NAMES[s]])
					_buff(t, source, "agora " + SUIT_SYMBOLS[s], "value")
			"copy_value":
				if source.on_board():
					source.base_value = clampi(t.base_value + t.value_mod, 2, 14)
					source.value_mod = 0
					_log("  %s copia o valor %s." % [_cn(source), value_label(source.base_value)])
					_buff(source, t, "= " + value_label(source.base_value), "value")
			"destroy":
				destroy(t, source)
			"shield":
				t.shield += amount
				_log("  %s ganha Escudo %d." % [_cn(t), t.shield])
				_buff(t, source, "+%d ESCUDO" % amount, "armor")
			"freeze":
				t.frozen = maxi(t.frozen, amount)
				_log("  %s é congelada (%d turno(s))." % [_cn(t), t.frozen])
				_buff(t, source, "Congelada", "control")
			"silence":
				t.silenced = true
				_log("  %s é silenciada." % _cn(t))
				_buff(t, source, "Silenciada", "control")
			"strip":
				if t.armor + t.shield > 0:
					t.armor = 0
					t.shield = 0
					_log("  %s perde toda a armadura e escudos." % _cn(t))
					_buff(t, source, "Sem armadura", "control")
			"ready":
				t.exhausted = false
				t.attacked = false
				t.attacks_made = 0
				_buff(t, source, "Pronta!", "atk")
			"grant_kw":
				var kw: String = eff.get("kw", "")
				if kw != "" and not t.keywords.has(kw):
					t.keywords.append(kw)
					_buff(t, source, String(KEYWORD_NAMES.get(kw, kw)), "atk")
			"set_value":
				t.base_value = _value_for(eff, source.owner, t)
				t.value_mod = 0
				_log("  %s agora vale %s." % [_cn(t), value_label(effective_value(t))])
				_buff(t, source, "= " + value_label(effective_value(t)), "value")
			"move":
				_move(t, String(eff.get("row", "front")), source)
			"bounce":
				_bounce(t, source)
			_:
				push_warning("Operação desconhecida: %s" % op)


## Move uma unidade entre as fileiras do próprio dono ("front", "back",
## "command" ou "other_line" = troca Frente <-> Retaguarda). Sem vaga, nada.
func _move(t: Card, row: String, source: Card) -> void:
	var dest := row
	if row == "other_line":
		if t.row == "command":
			return
		dest = "back" if t.row == "front" else "front"
	var owner_p := players[t.owner]
	if dest == t.row or owner_p.rows[dest].size() >= ROW_SIZE:
		return
	var from := t.row
	owner_p.rows[from].erase(t)
	t.row = dest
	owner_p.rows[dest].append(t)
	_log("  %s é movida para a %s." % [_cn(t), ROW_NAMES[dest]])
	_ev("move", {"pid": t.owner, "from": from, "row": dest,
		"src": source.uid if source != null else -1}, t)


## Devolve a unidade para a mão do dono, zerada (não conta como destruída).
func _bounce(t: Card, source: Card) -> void:
	var owner_p := players[t.owner]
	_ev("bounce", {"pid": t.owner, "src": source.uid if source != null else -1}, t)
	owner_p.rows[t.row].erase(t)
	t.reset()
	owner_p.hand.append(t)
	_log("  %s volta para a mão de %s." % [_cn(t), owner_p.name])


func _value_for(eff: Dictionary, owner: int, t: Card) -> int:
	var v = eff.get("value", 2)
	if typeof(v) == TYPE_STRING and String(v) == "max_own_command":
		var best := 2
		for c: Card in players[owner].rows["command"]:
			if c != t:
				best = maxi(best, effective_value(c))
		return best
	return clampi(int(v), 2, 14)


func _apply_player_op(op: String, eff: Dictionary, source: Card, amount: int, ctx: Dictionary) -> void:
	var p := players[source.owner]
	var o := opponent(source.owner)
	match op:
		"draw":
			draw(p, amount)
		"recall", "revive":
			if op == "revive" and _entry_rows(eff, p).is_empty():
				return
			var cands := _grave_candidates(eff, p)
			if cands.is_empty():
				return
			var pick := String(eff.get("pick", "random" if op == "recall" else "highest"))
			if pick == "choose":
				# "escolha 1 entre X": sorteia X opções; com 1 opção não há o que escolher
				_shuffle(cands)
				var opts := cands.slice(0, maxi(1, int(eff.get("choices", 3))))
				if opts.size() == 1:
					_grave_take(op, eff, source, opts[0])
				elif _can_ask():
					_ask(source.owner, _choice_prompt(op, eff, source), opts, "card",
						func(picked: Card) -> void: _grave_take(op, eff, source, picked), source)
				else:
					# escolha dentro de um gatilho em cadeia: pega a de maior valor
					_grave_take(op, eff, source, _highest(opts))
			elif pick == "highest":
				_grave_take(op, eff, source, _highest(cands))
			else:
				_grave_take(op, eff, source, cands[rng.randi_range(0, cands.size() - 1)])
		"mill":
			var n := mini(amount, o.deck.size())
			for i in n:
				o.graveyard.append(o.deck.pop_back())
			_log("  %s perde %d carta(s) do topo do baralho." % [o.name, n])
			if n > 0:
				_ev("mill", {"pid": o.id, "n": n, "src": source.uid})
		"discard_own":
			for i in amount:
				if p.hand.is_empty():
					break
				var oc: Card = p.hand[rng.randi_range(0, p.hand.size() - 1)]
				p.hand.erase(oc)
				p.graveyard.append(oc)
				_log("  %s descarta [b]%s[/b]." % [p.name, _cn(oc)])
				_ev("discard", {"pid": p.id, "src": source.uid}, oc)
		"summon":
			var sp := p if String(eff.get("side", "ally")) == "ally" else o
			var rows := _entry_rows(eff, sp)
			if rows.is_empty():
				return
			var n := amount
			if rows.size() > 1 and _can_ask() and sp.id == source.owner:
				var preview := Card.new(-1, CardDB.get_def(String(eff["card"])), sp.id)
				_ask(sp.id, "%s: em qual fileira entram %d %s?" % [source.name, n, preview.name], rows, "row",
					func(r: String) -> void: _summon_tokens(eff, source, sp, r, n), preview)
			else:
				_summon_tokens(eff, source, sp, String(eff.get("row", rows[0])), n)
		"exile_grave":
			var n := mini(amount, o.graveyard.size())
			for i in n:
				o.graveyard.remove_at(rng.randi_range(0, o.graveyard.size() - 1))
			ctx["last_count"] = n
			_log("  %d carta(s) do cemitério de %s são exiladas." % [n, o.name])
			if n > 0:
				_ev("exile", {"pid": o.id, "n": n, "src": source.uid})
		"discard_enemy":
			for i in amount:
				if o.hand.is_empty():
					break
				var dc: Card = o.hand[rng.randi_range(0, o.hand.size() - 1)]
				o.hand.erase(dc)
				o.graveyard.append(dc)
				_log("  %s descarta [b]%s[/b]." % [o.name, _cn(dc)])
				_ev("discard", {"pid": o.id, "src": source.uid}, dc)


## Cartas que um efeito de cemitério pode pegar. "from": own | enemy | both;
## "kind": unit (padrão) | effect | any. revive só aceita unidades.
func _grave_candidates(eff: Dictionary, p: PlayerState) -> Array:
	var from := String(eff.get("from", "own"))
	var kind := String(eff.get("kind", "unit"))
	if String(eff.get("op", "")) == "revive":
		kind = "unit"
	var graves := []
	if from == "own" or from == "both":
		graves.append(p)
	if from == "enemy" or from == "both":
		graves.append(opponent(p.id))
	var out := []
	for gp: PlayerState in graves:
		for c: Card in gp.graveyard:
			if kind == "any" or (kind == "unit") == c.is_unit():
				out.append(c)
	return out


## Decisões só podem ser pedidas no bloco de topo de uma ação (ou dentro de uma
## escolha sendo aplicada). Em gatilhos encadeados, o motor decide sozinho.
func _can_ask() -> bool:
	return _depth == 1


func _ask(pid: int, prompt: String, options: Array, option_kind: String, apply: Callable, preview: Card = null) -> void:
	pending = {"kind": "choice", "pid": pid, "prompt": prompt, "options": options,
		"option_kind": option_kind, "apply": apply, "preview": preview}
	_suspending = true
	_ev("choice", {"pid": pid})


## Fileiras onde um efeito pode pôr cartas: "rows" do efeito (padrão: Frente e
## Retaguarda; a Cadeia de Comando só se o efeito a listar), só as com vaga.
func _entry_rows(eff: Dictionary, p: PlayerState) -> Array:
	var rows: Array = eff.get("rows", ["front", "back"])
	return rows.filter(func(r: String) -> bool: return p.rows[r].size() < ROW_SIZE)


func _summon_tokens(eff: Dictionary, source: Card, sp: PlayerState, row: String, n: int) -> void:
	var order := [row]
	for r in _entry_rows(eff, sp):
		if r != row:
			order.append(r)
	for i in n:
		var dest := ""
		for r in order:
			if sp.rows[r].size() < ROW_SIZE:
				dest = r
				break
		if dest == "":
			return
		var tk := _new_card(String(eff["card"]), sp.id)
		_enter_board(tk, sp, dest, source, "summon")


## Põe no tabuleiro uma carta vinda de um efeito (reviver, invocar): entra
## exausta, ganha armadura de comando se for para a Cadeia, avisa as aliadas e,
## se pedido, reaplica o próprio efeito de entrada (que pode pedir um alvo).
func _enter_board(c: Card, p: PlayerState, row: String, source: Card, ev_type: String, replay: bool = false) -> void:
	c.row = row
	c.exhausted = true
	p.rows[row].append(c)
	if ev_type == "summon":
		_log("  %s invoca [b]%s[/b] na %s." % [p.name, _cn(c), ROW_NAMES[row]])
	_ev(ev_type, {"pid": p.id, "row": row, "src": source.uid}, c)
	if row == "command":
		var bonus := command_armor(c)
		c.armor += bonus
		_buff(c, null, "+%d ARM" % bonus, "armor")
	for a: Card in p.board_cards():
		if a != c:
			_trigger(a, "on_ally_played", {"other": c})
	if replay and c.def.has("on_play"):
		_replay_on_play(c)


## Carta revivida reaplica o efeito de entrada. Com alvo, o dono escolhe
## (quando dá para perguntar); senão, alvo aleatório.
func _replay_on_play(c: Card) -> void:
	var block: Dictionary = c.def["on_play"]
	var spec := play_spec(c)
	var targets := valid_targets(spec, c.owner, c)
	_log("  %s reaplica o efeito de entrada." % _cn(c))
	if spec.is_empty() or targets.is_empty():
		_resolve_block(block, c, null, {})
	elif targets.size() > 1 and _can_ask():
		_ask(c.owner, "%s reaplica o efeito de entrada: escolha o alvo." % c.name, targets, "target",
			func(t: Card) -> void: _resolve_block(block, c, t, {}), c)
	else:
		_resolve_block(block, c, targets[rng.randi_range(0, targets.size() - 1)], {})


func _highest(cards: Array) -> Card:
	var best: Card = cards[0]
	for c: Card in cards:
		if c.base_value > best.base_value:
			best = c
	return best


## Tira a carta do cemitério em que está e a entrega ao dono da fonte (pode
## ser carta do oponente: ela passa a ser sua). recall -> mão; revive -> fileira.
func _grave_take(op: String, eff: Dictionary, source: Card, c: Card) -> void:
	var p := players[source.owner]
	var orig := players[c.owner]
	orig.graveyard.erase(c)
	var stolen := c.owner != p.id
	c.reset()
	c.owner = p.id
	var from_txt := " do cemitério do oponente" if stolen else " do cemitério"
	if op == "recall":
		p.hand.append(c)
		_log("  %s recupera [b]%s[/b]%s." % [p.name, _cn(c), from_txt])
		_ev("recall", {"pid": p.id, "src": source.uid}, c)
		return
	if eff.has("hp"):
		c.hp = mini(c.max_hp, int(eff["hp"]))
	var rows := _entry_rows(eff, p)
	if rows.is_empty():
		c.owner = orig.id
		orig.graveyard.append(c)
		return
	var place := func(row: String) -> void:
		_log("  [b]%s[/b] volta%s para a %s." % [_cn(c), from_txt, ROW_NAMES[row]])
		_enter_board(c, p, row, source, "revive", true)
	if rows.size() > 1 and _can_ask():
		_ask(p.id, "%s: em qual fileira %s entra?" % [source.name, c.name], rows, "row", place, c)
	else:
		place.call(String(eff.get("row", rows[0])) if rows.has(eff.get("row", "")) else String(rows[0]))


func _choice_prompt(op: String, eff: Dictionary, source: Card) -> String:
	var from := String(eff.get("from", "own"))
	var where := "do seu cemitério"
	if from == "enemy":
		where = "do cemitério do oponente"
	elif from == "both":
		where = "dos dois cemitérios"
	var what := "pôr na sua mão"
	if op == "revive":
		what = "reviver no seu tabuleiro (depois você escolhe a fileira)"
	return "%s: escolha 1 carta %s para %s." % [source.name, where, what]


func _amount(eff: Dictionary, source: Card, ctx: Dictionary) -> int:
	var owner := source.owner
	var a := int(eff.get("amount", 1))
	match String(eff.get("per", "")):
		"self_atk":
			a *= effective_atk(source)
		"half_damage_taken":
			# Revide: metade do dano sofrido (armadura conta), mínimo 1
			a *= maxi(1, floori(int(ctx.get("damage_taken", 0)) / 2.0))
		"own_graveyard":
			a *= players[owner].graveyard.size()
		"allied_units":
			a *= players[owner].board_cards().size()
		"enemy_units":
			a *= players[1 - owner].board_cards().size()
		"own_command":
			a *= players[owner].rows["command"].size()
		"hand_size":
			a *= players[owner].hand.size()
		"damage_dealt":
			a *= int(ctx.get("damage_dealt", 0))
		"enemy_graveyard":
			a *= players[1 - owner].graveyard.size()
		"last_count":
			a *= int(ctx.get("last_count", 0))
	if eff.has("max"):
		a = mini(a, int(eff["max"]))
	return a


func suit_for(eff: Dictionary, owner: int) -> String:
	var s: String = eff.get("suit", "")
	if s != "majority_own_command":
		return s
	var counts := {}
	for c: Card in players[owner].rows["command"]:
		if c.suit != "":
			counts[c.suit] = int(counts.get(c.suit, 0)) + 1
	var best := ""
	var best_n := 0
	for k in counts:
		if counts[k] > best_n:
			best_n = counts[k]
			best = k
	return best


func _resolve_targets(eff: Dictionary, source: Card, chosen: Card, ctx: Dictionary) -> Array:
	var mode: String = eff.get("target", "chosen")
	match mode:
		"chosen":
			return [chosen] if chosen != null else []
		"self":
			return [source]
		"context":
			var other = ctx.get("other")
			return [other] if other != null else []
		"all":
			return _filter_board(eff.get("filter", {}), source)
		"random":
			var l := _filter_board(eff.get("filter", {}), source)
			if l.is_empty():
				return []
			return [l[rng.randi_range(0, l.size() - 1)]]
	return []


func _filter_board(f: Dictionary, source: Card) -> Array:
	var out := []
	for c: Card in all_board():
		if c.owner != source.owner and is_sealed(c):
			continue
		if _matches(c, f, source.owner, source):
			out.append(c)
	return out


func _matches(c: Card, f: Dictionary, owner: int, source: Card) -> bool:
	if not c.on_board():
		return false
	var side: String = f.get("side", "any")
	if side == "enemy" and c.owner == owner:
		return false
	if side == "ally" and c.owner != owner:
		return false
	if f.has("rows") and not (f["rows"] as Array).has(c.row):
		return false
	if f.has("suit") and c.suit != String(f["suit"]):
		return false
	if bool(f.get("exclude_self", false)) and c == source:
		return false
	if f.has("hp_le") and c.hp > int(f["hp_le"]):
		return false
	if f.has("value_le") and effective_value(c) > int(f["value_le"]):
		return false
	if f.has("value_ge") and effective_value(c) < int(f["value_ge"]):
		return false
	if f.has("kw") and not c.has_kw(String(f["kw"])):
		return false
	match String(f.get("status", "")):
		"poison":
			if c.poison <= 0:
				return false
		"bleed":
			if c.bleed <= 0:
				return false
		"dot":
			if c.poison + c.bleed <= 0:
				return false
	return true


# ---------------------------------------------------------------- rede (modo online)

## Quem está deste lado da tela: o registro chama esse jogador de "Você".
func set_viewer(me: int) -> void:
	players[me].name = "Você"
	players[1 - me].name = "Oponente"


## Desistência: o outro jogador vence na hora.
func resign(pid: int) -> bool:
	if over:
		return _fail("A partida já acabou.")
	_record(pid, {"a": "resign"})
	over = true
	pending = {}
	winner = 1 - pid
	var info := {"round": round_num, "names": [hand_name(0), hand_name(1)], "cards": [_command_desc(0), _command_desc(1)],
		"winner": winner, "match_over": true, "match_winner": winner, "resigned": pid,
		"gems": [players[0].gems, players[1].gems]}
	# não entra em history: a rodada não terminou
	_log("[b]%s desiste.[/b] %s vence a partida." % [players[pid].name, players[winner].name])
	_ev("resign", {"pid": pid, "info": info})
	match_finished.emit(info)
	changed.emit()
	return true


## Aplica uma ação no formato do action_log (vinda da rede ou de um replay).
## Retorna false se a ação for inválida neste estado (sinal de dessincronia).
func apply_action(pid: int, act: Dictionary) -> bool:
	var c: Card = _card_of(act.get("c", -1))
	var t: Card = _card_of(act.get("t", -1))
	match String(act.get("a", "")):
		"play":
			return c != null and play_card(pid, c, String(act.get("r", "")), t)
		"discard":
			return c != null and discard(pid, c)
		"attack":
			return c != null and t != null and attack(pid, c, t)
		"activate":
			return c != null and activate(pid, c, t)
		"end":
			return end_turn(pid)
		"pass":
			return pass_round(pid)
		"choice":
			var o = act.get("o")
			if typeof(o) == TYPE_STRING:
				return resolve_choice(pid, String(o))
			var oc := _card_of(o)
			return oc != null and resolve_choice(pid, oc)
		"mswap":
			return c != null and mulligan_swap(pid, c) != null
		"mdone":
			return mulligan_done(pid)
		"resign":
			return resign(pid)
	return _fail("Ação desconhecida: %s" % act)


## Resumo do estado inteiro (inclui o estado do sorteio). Dois aparelhos com
## o mesmo hash depois da mesma ação estão na mesma partida.
func state_hash() -> int:
	var parts := PackedStringArray()
	parts.append("%d|%d|%d|%d|%s|%s" % [current, round_num, turn_num, winner, over, rng.state])
	parts.append(str(pending.get("kind", "")) + str(waiting_for()))
	for p in players:
		parts.append("P%d:%d:%s:%s" % [p.id, p.gems, p.passed, p.played_card])
		for zone in [p.hand, p.deck, p.graveyard]:
			var ids := PackedStringArray()
			for c: Card in zone:
				ids.append(str(c.uid))
			parts.append(",".join(ids))
		for c: Card in p.board_cards():
			parts.append("%d@%s:%d/%d/%d/%d/%d/%d/%d/%s/%d/%s/%d/%d/%s/%s" % [c.uid, c.row, c.hp, c.armor, c.shield,
				c.poison, c.bleed, c.value_mod, c.atk_mod, c.suit, c.base_value, c.exhausted, c.attacks_made,
				c.frozen, c.silenced, c.timers])
	return "\n".join(parts).hash()


func _record(pid: int, act: Dictionary) -> void:
	action_log.append({"pid": pid, "act": act})


func _uid(c: Card) -> int:
	return c.uid if c != null else -1


func _card_of(uid) -> Card:
	if uid == null:
		return null
	return cards_by_uid.get(int(uid))


# ---------------------------------------------------------------- util

func _log(text: String) -> void:
	logged.emit(text)


## Estado visível de uma carta neste instante (a UI usa para mostrar
## valores intermediários enquanto anima).
func snapshot(c: Card) -> Dictionary:
	return {"hp": c.hp, "max_hp": c.max_hp, "armor": c.armor, "poison": c.poison, "bleed": c.bleed,
		"value": effective_value(c), "suit": c.suit, "atk": effective_atk(c), "timers": c.timers.duplicate(),
		"shield": c.shield, "frozen": c.frozen + (1 if c.stunned else 0), "silenced": c.silenced}


func _ev(type: String, data: Dictionary = {}, card: Card = null) -> void:
	data["type"] = type
	if card != null:
		data["uid"] = card.uid
		data["card"] = card
		data["snap"] = snapshot(card)
	event.emit(data)


func _buff(t: Card, source: Card, label: String, tone: String) -> void:
	_ev("buff", {"label": label, "tone": tone, "src": source.uid if source != null else -1}, t)


func _fail(msg: String) -> bool:
	last_error = msg
	return false
