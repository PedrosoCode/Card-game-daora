class_name CardDB
extends RefCounted
## Carrega as definições de cartas e baralhos de data/cards.json.

static var cards: Dictionary = {}
static var decks: Dictionary = {}


static func load_db(path: String = "res://data/cards.json") -> void:
	if not cards.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Não foi possível abrir %s" % path)
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("cards.json inválido")
		return
	for c in data["cards"]:
		cards[c["id"]] = c
	decks = data["decks"]
	for deck_id in decks:
		for cid in decks[deck_id]["cards"]:
			if not cards.has(cid):
				push_error("Baralho %s referencia carta inexistente: %s" % [deck_id, cid])


static func get_def(id: String) -> Dictionary:
	return cards[id]


## Fichas (tokens) só nascem por invocação; não entram em baralhos.
static func is_token(id: String) -> bool:
	return bool(cards.get(id, {}).get("token", false))


## Todas as cartas que podem entrar num baralho, na ordem do cards.json.
static func pool_ids() -> Array:
	var out := []
	for cid in cards:
		if not is_token(cid):
			out.append(cid)
	return out
