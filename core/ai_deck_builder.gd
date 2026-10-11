class_name AIDeckBuilder
extends RefCounted
## A IA monta o próprio baralho. Ela sorteia um naipe principal e um secundário:
## - todas as unidades do naipe principal (favorece Flush e valores repetidos);
## - parte das unidades do secundário;
## - instantâneas dos dois naipes.
## O resultado sempre respeita DeckStore.MIN_UNITS.

const SECOND_UNITS := 14
const INSTANTS := 12


static func build(rng: RandomNumberGenerator) -> Array:
	CardDB.load_db()
	var suits: Array = Game.SUITS.duplicate()
	_shuffle(suits, rng)
	var main_suit: String = suits[0]
	var second_suit: String = suits[1]
	var main_units := []
	var second_units := []
	var instants := []
	for cid in CardDB.pool_ids():
		var d: Dictionary = CardDB.get_def(cid)
		var suit: String = d.get("suit", "")
		if String(d.get("kind", "unit")) == "unit":
			if suit == main_suit:
				main_units.append(cid)
			elif suit == second_suit:
				second_units.append(cid)
		elif suit == main_suit or suit == second_suit:
			instants.append(cid)
	_shuffle(second_units, rng)
	_shuffle(instants, rng)
	var deck := main_units.duplicate()
	deck.append_array(second_units.slice(0, SECOND_UNITS))
	deck.append_array(instants.slice(0, INSTANTS))
	# completa até o mínimo de cartas com o que sobrou do naipe secundário
	var extra := second_units.slice(SECOND_UNITS) + instants.slice(INSTANTS)
	while deck.size() < DeckStore.MIN_CARDS and not extra.is_empty():
		deck.append(extra.pop_front())
	return deck


static func name_for(ids: Array) -> String:
	var counts := {}
	for cid in ids:
		var d: Dictionary = CardDB.get_def(cid)
		if String(d.get("kind", "unit")) == "unit":
			var s: String = d.get("suit", "")
			counts[s] = int(counts.get(s, 0)) + 1
	var best := ""
	for s in counts:
		if best == "" or counts[s] > counts[best]:
			best = s
	return "Baralho da IA (foco em %s)" % Game.SUIT_NAMES.get(best, "?")


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
