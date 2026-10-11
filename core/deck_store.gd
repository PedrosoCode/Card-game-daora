class_name DeckStore
extends RefCounted
## Baralhos montados pelo jogador. Ficam em user://decks.json e são registrados
## em CardDB.decks com id "user:<nome>", então Game.setup os usa como qualquer outro.
## Regras de montagem: pelo menos MIN_CARDS cartas e MIN_UNITS unidades. Nada
## mais é restrito (cópias da mesma carta, valores e naipes repetidos).

## Arquivo dos baralhos do jogador (os testes trocam para não mexer no real).
static var path := "user://decks.json"
const PREFIX := "user:"
const MIN_UNITS := 25
const MIN_CARDS := 52


static func load_user_decks() -> void:
	CardDB.load_db()
	for k in CardDB.decks.keys():
		if String(k).begins_with(PREFIX):
			CardDB.decks.erase(k)
	var data := _read()
	for deck_name in data["decks"]:
		var ids: Array = []
		for cid in data["decks"][deck_name]:
			if CardDB.cards.has(cid):
				ids.append(String(cid))
		CardDB.decks[PREFIX + String(deck_name)] = {"name": String(deck_name), "cards": ids, "user": true}


## Retorna "" se salvou, ou a mensagem de erro.
static func save_deck(deck_name: String, ids: Array) -> String:
	deck_name = deck_name.strip_edges()
	if deck_name == "":
		return "Dê um nome ao baralho."
	var err := validate(ids)
	if err != "":
		return err
	var data := _read()
	data["decks"][deck_name] = ids.duplicate()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Não foi possível gravar %s." % path
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	load_user_decks()
	return ""


static func delete_deck(deck_name: String) -> void:
	var data := _read()
	data["decks"].erase(deck_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	load_user_decks()


## "" se o baralho é válido; senão, o motivo.
static func validate(ids: Array) -> String:
	for cid in ids:
		if not CardDB.cards.has(cid) or CardDB.is_token(cid):
			return "Carta inválida no baralho: %s." % cid
	if ids.size() < MIN_CARDS:
		return "O baralho precisa de pelo menos %d cartas (tem %d)." % [MIN_CARDS, ids.size()]
	var units := count_units(ids)
	if units < MIN_UNITS:
		return "O baralho precisa de pelo menos %d unidades (tem %d)." % [MIN_UNITS, units]
	return ""


static func count_units(ids: Array) -> int:
	var n := 0
	for cid in ids:
		if CardDB.cards.has(cid) and String(CardDB.get_def(cid).get("kind", "unit")) == "unit":
			n += 1
	return n


static func is_user_deck(deck_id: String) -> bool:
	return deck_id.begins_with(PREFIX)


static func _read() -> Dictionary:
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("decks")) == TYPE_DICTIONARY:
			return data
	return {"decks": {}}
