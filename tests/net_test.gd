extends SceneTree
## Teste do modo online SEM tela: dois jogadores automáticos (IA) no mesmo
## processo, conversando por HTTP de verdade com o api.php.
## Precisa do servidor:  php -S 127.0.0.1:8070 -t server
## godot --headless --path . -s res://tests/net_test.gd [-- url=http://127.0.0.1:8070/api.php]

const NetPlayer := preload("res://tests/net_player.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var url := "http://127.0.0.1:8070/api.php"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("url="):
			url = arg.substr(4)
	CardDB.load_db()
	var ok := true
	for pair in [["legiao", "conspiracao"], ["padrao", "legiao"]]:
		var t0 := Time.get_ticks_msec()
		var host_c := OnlineClient.new()
		var guest_c := OnlineClient.new()
		root.add_child(host_c)
		root.add_child(guest_c)
		await process_frame
		host_c.url = url
		guest_c.url = url
		var d0: Dictionary = CardDB.decks[pair[0]]
		var d1: Dictionary = CardDB.decks[pair[1]]
		var r := await host_c.create(OnlineClient.make_meta(d0["cards"], d0["name"], true))
		if r.has("error"):
			push_error("create: " + String(r["error"]))
			quit(1)
			return
		var j := await guest_c.join(host_c.code, OnlineClient.make_meta(d1["cards"], d1["name"], false))
		if j.has("error"):
			push_error("join: " + String(j["error"]))
			quit(1)
			return
		var a = NetPlayer.new()
		var b = NetPlayer.new()
		a.client = host_c
		b.client = guest_c
		root.add_child(a)
		root.add_child(b)
		a.play()
		b.play()
		while not (a.done and b.done):
			await process_frame
		var same: bool = a.error == "" and b.error == "" and a.game.state_hash() == b.game.state_hash() \
			and a.game.winner == b.game.winner
		if not same:
			push_error("Partida %s x %s: host='%s' convidado='%s'" % [pair[0], pair[1], a.error, b.error])
		ok = ok and same
		print("Online %s x %s (sala %s): %s | jogadas enviadas %d + %d | vencedor %d | %.1fs" % [
			pair[0], pair[1], host_c.code, "OK" if same else "FALHOU", a.sent, b.sent, a.game.winner,
			(Time.get_ticks_msec() - t0) / 1000.0])
	OnlineClient.clear_session()
	print("ONLINE: ", "OK" if ok else "FALHOU")
	quit(0 if ok else 1)
