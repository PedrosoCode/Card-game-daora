extends SceneTree
## Oponente automático do modo online, em processo separado (para testar a tela).
##   role=host codefile=<arquivo>  cria a sala e grava o código no arquivo
##   role=guest code=<código>      entra na sala
##   url=<api.php>  deck=<id>
const NetPlayer := preload("res://tests/net_player.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := {"role": "guest", "url": "http://127.0.0.1:8070/api.php", "deck": "conspiracao", "code": "", "codefile": ""}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	CardDB.load_db()
	var c := OnlineClient.new()
	c.persist = false
	c.url = args["url"]
	root.add_child(c)
	await process_frame
	var d: Dictionary = CardDB.decks[args["deck"]]
	var r: Dictionary
	if args["role"] == "host":
		r = await c.create(OnlineClient.make_meta(d["cards"], d["name"], true))
		if not r.has("error"):
			var f := FileAccess.open(args["codefile"], FileAccess.WRITE)
			f.store_string(c.code)
			f.close()
	else:
		r = await c.join(args["code"], OnlineClient.make_meta(d["cards"], d["name"], false))
	if r.has("error"):
		print("BOT: erro ", r["error"])
		quit(1)
		return
	var p = NetPlayer.new()
	p.client = c
	p.step_delay = 0.15
	root.add_child(p)
	p.play()
	while not p.done:
		await process_frame
	print("BOT (%s): %s | enviadas %d recebidas %d" % [args["role"], p.error if p.error != "" else "OK", p.sent, p.received])
	quit(0 if p.error == "" else 1)
