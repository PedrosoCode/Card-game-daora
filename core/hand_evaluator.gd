class_name HandEvaluator
extends RefCounted
## Avalia a mão de poker formada pela Cadeia de Comando (0 a 5 cartas).
## Sequência e flush exigem 5 cartas. Cartas sem naipe nunca formam flush.

enum { HIGH_CARD, PAIR, TWO_PAIR, TRIPS, STRAIGHT, FLUSH, FULL_HOUSE, QUADS, STRAIGHT_FLUSH }
const NAMES := ["Carta Alta", "Par", "Dois Pares", "Trinca", "Sequência", "Flush",
	"Full House", "Quadra", "Straight Flush"]


## entries: Array de {"value": int, "suit": String}
## Retorna uma chave comparável: [rank, desempates...]. Mão vazia = [-1].
static func evaluate(entries: Array) -> Array:
	if entries.is_empty():
		return [-1]
	var counts := {}
	for e: Dictionary in entries:
		var v: int = e["value"]
		counts[v] = int(counts.get(v, 0)) + 1
	var groups: Array = counts.keys()
	groups.sort_custom(func(a, b):
		return counts[a] > counts[b] or (counts[a] == counts[b] and a > b))
	var shape: Array = []
	for g in groups:
		shape.append(counts[g])

	var flush := false
	var straight_high := 0
	if entries.size() == 5:
		flush = true
		var s0: String = entries[0]["suit"]
		for e: Dictionary in entries:
			if e["suit"] != s0 or s0 == "":
				flush = false
		if groups.size() == 5:
			if int(groups[0]) - int(groups[4]) == 4:
				straight_high = groups[0]
			elif groups == [14, 5, 4, 3, 2]:
				straight_high = 5

	var rank := HIGH_CARD
	if straight_high > 0 and flush:
		rank = STRAIGHT_FLUSH
	elif shape[0] == 4:
		rank = QUADS
	elif shape[0] == 3 and shape.size() > 1 and shape[1] == 2:
		rank = FULL_HOUSE
	elif flush:
		rank = FLUSH
	elif straight_high > 0:
		rank = STRAIGHT
	elif shape[0] == 3:
		rank = TRIPS
	elif shape[0] == 2 and shape.size() > 1 and shape[1] == 2:
		rank = TWO_PAIR
	elif shape[0] == 2:
		rank = PAIR

	var key: Array = [rank]
	if straight_high > 0:
		key.append(straight_high)
	else:
		key.append_array(groups)
	return key


## >0 se a vence b, <0 se b vence a, 0 empate. Mais cartas de desempate vence.
static func compare(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return signi(a.size() - b.size())


static func describe(key: Array) -> String:
	if key.is_empty() or int(key[0]) < 0:
		return "Nenhuma carta"
	var rank: int = key[0]
	var txt: String = NAMES[rank]
	if rank == TWO_PAIR:
		return "%s (%s e %s)" % [txt, Game.value_label(key[1]), Game.value_label(key[2])]
	return "%s (%s)" % [txt, Game.value_label(key[1])]
