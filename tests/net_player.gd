extends Node
## Jogador automático do modo online (IA), para testes. Usa o mesmo protocolo
## da tela: lockstep pela caixa de correio, hash conferido a cada jogada recebida.

var client: OnlineClient
var game: Game
var ai: AIPlayer
var me := -1
var net_seq := 0
var logged := 0
var error := ""
var done := false
var sent := 0
var received := 0
var step_delay := 0.0   # pausa entre ações (para o teste de tela acompanhar)


func play() -> void:
	var r: Dictionary
	while true:
		r = await client.poll(0)
		if r.has("error"):
			_finish("poll inicial: " + String(r["error"]))
			return
		if r.get("guest_meta") != null:
			break
		await get_tree().create_timer(0.5).timeout
	var host = JSON.parse_string(String(r["host_meta"]))
	var guest = JSON.parse_string(String(r["guest_meta"]))
	CardDB.decks["bot_net_0"] = {"name": String(host["name"]), "cards": host["deck"]}
	CardDB.decks["bot_net_1"] = {"name": String(guest["name"]), "cards": guest["deck"]}
	game = Game.new()
	game.setup("bot_net_0", "bot_net_1", false, int(host["seed"]))
	me = client.seat
	ai = AIPlayer.new(game, me)
	for m: Dictionary in r["messages"]:
		var d = JSON.parse_string(String(m["data"]))
		if not game.apply_action(int(m["seat"]), d["act"]):
			_finish("replay falhou na jogada %d" % int(m["seq"]))
			return
		net_seq = int(m["seq"])
	logged = game.action_log.size()
	var guard := 0
	while not game.over and guard < 20000:
		guard += 1
		var w := game.waiting_for()
		var actor := w if w >= 0 else game.current
		if actor == me:
			if step_delay > 0.0:
				await get_tree().create_timer(step_delay).timeout
			if not ai.step():
				_finish("IA travou: " + game.last_error)
				return
			var batch := []
			while logged < game.action_log.size():
				var e: Dictionary = game.action_log[logged]
				logged += 1
				if int(e["pid"]) == me:
					batch.append(e["act"])
			for i in batch.size():
				net_seq += 1
				var data := {"act": batch[i]}
				if i == batch.size() - 1:
					data["h"] = game.state_hash()
				var s := await client.send(net_seq, data)
				if s.has("error"):
					_finish("send %d: %s" % [net_seq, String(s["error"])])
					return
				sent += 1
		else:
			var p := await client.poll(net_seq)
			if p.has("error"):
				_finish("poll: " + String(p["error"]))
				return
			var got := false
			for m: Dictionary in p["messages"]:
				if int(m["seq"]) <= net_seq:
					continue
				net_seq = int(m["seq"])
				if int(m["seat"]) == me:
					continue
				var d = JSON.parse_string(String(m["data"]))
				if not game.apply_action(1 - me, d["act"]):
					_finish("jogada recebida inválida: %s (%s)" % [d["act"], game.last_error])
					return
				logged = game.action_log.size()
				received += 1
				got = true
				if d.get("h") != null and int(d["h"]) != game.state_hash():
					_finish("DESSINCRONIA na jogada %d: %s" % [net_seq, d["act"]])
					return
			if not got:
				await get_tree().create_timer(0.3).timeout
	_finish("" if game.over else "partida não terminou")


func _finish(err: String) -> void:
	error = err
	done = true
