extends SceneTree
## Teste de ablação: tira a habilidade de uma carta (mantendo valor, naipe,
## HP e ATQ) só no baralho do jogador 0 e mede a taxa de vitória dele.
## Quanto mais a taxa cai abaixo da base, mais a habilidade pesa.
## godot --headless --path . -s res://tests/ablation.gd
const N := 40


func _rate() -> float:
	var w := 0
	for i in N:
		var g := Game.new()
		g.setup("ablado", "padrao", true, 1000 + i)
		g.players[0].is_ai = true
		var ais := [AIPlayer.new(g, 0), AIPlayer.new(g, 1)]
		var k := 0
		while not g.over and k < 20000:
			var who := g.waiting_for()
			ais[who if who >= 0 else g.current].step(); k += 1
		if g.winner == 0: w += 1
	return 100.0 * w / N


func _init() -> void:
	CardDB.load_db()
	var orig: Array = CardDB.decks["padrao"]["cards"]
	CardDB.decks["ablado"] = {"name": "ablado", "cards": orig.duplicate()}
	print("base: %.0f%%" % _rate())
	for cid in orig:
		var d: Dictionary = CardDB.get_def(cid).duplicate(true)
		for key in ["on_play", "active", "passives", "keywords"]:
			d.erase(key)
		d["id"] = cid + "__vanilla"
		CardDB.cards[d["id"]] = d
		var deck := orig.duplicate()
		deck[deck.find(cid)] = d["id"]
		CardDB.decks["ablado"]["cards"] = deck
		print("%s (%s) -> %.0f%%" % [cid, Game.card_label(int(d["value"]), d["suit"]), _rate()])
	quit()
