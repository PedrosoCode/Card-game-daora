class_name OnlineClient
extends Node
## Cliente da "caixa de correio" (server/api.php). Só transporta texto: quem
## entende o conteúdo das mensagens é o jogo. Precisa estar na árvore (usa
## HTTPRequest). Funciona no desktop, no Android e na web (fetch).

const SESSION_PATH := "user://online_session.json"
const CONFIG_PATH := "user://online.cfg"
## Sobe quando o formato das mensagens mudar (aparelhos diferentes não se misturam).
const NET_VERSION := 1
## Endereço do api.php publicado (ex.: "https://seusite.com/cadeia/api.php").
## Preenchido, vira o servidor padrão no desktop e no Android. Na web o padrão
## é sempre o api.php ao lado do index.html.
const PUBLIC_URL := ""

var url := ""
var code := ""
var token := ""
var seat := -1
## false: não grava a sessão em disco (processos de teste que dividem o user://).
var persist := true


## Faz uma chamada ao api.php. Sempre devolve um Dictionary; em caso de erro,
## ele tem "error" (texto) e "status" (0 = sem conexão).
func call_api(body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var err := http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"error": "Não foi possível enviar o pedido (%d)." % err, "status": 0}
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Sem conexão com o servidor.", "status": 0}
	var status := int(res[1])
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "Resposta inválida do servidor (HTTP %d)." % status, "status": status}
	data["status"] = status
	if status >= 400 and not data.has("error"):
		data["error"] = "Erro HTTP %d." % status
	return data


func create(meta: Dictionary) -> Dictionary:
	var r := await call_api({"action": "create", "meta": JSON.stringify(meta)})
	if not r.has("error"):
		code = String(r["code"])
		token = String(r["token"])
		seat = 0
		save_session()
	return r


func join(room_code: String, meta: Dictionary) -> Dictionary:
	var r := await call_api({"action": "join", "code": room_code.strip_edges().to_upper(), "meta": JSON.stringify(meta)})
	if not r.has("error"):
		code = room_code.strip_edges().to_upper()
		token = String(r["token"])
		seat = 1
		save_session()
	return r


func send(seq: int, data: Dictionary) -> Dictionary:
	return await call_api({"action": "send", "code": code, "token": token, "seq": seq, "data": JSON.stringify(data)})


func poll(since: int) -> Dictionary:
	return await call_api({"action": "poll", "code": code, "token": token, "since": since})


# ---------------------------------------------------------------- sessão e configuração

func save_session() -> void:
	if not persist:
		return
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"url": url, "code": code, "token": token, "seat": seat}))


## Carrega a sessão salva (partida em andamento). Retorna false se não houver.
func load_session() -> bool:
	if not FileAccess.file_exists(SESSION_PATH):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if typeof(d) != TYPE_DICTIONARY or not d.has("code"):
		return false
	url = String(d["url"])
	code = String(d["code"])
	token = String(d["token"])
	seat = int(d["seat"])
	return true


static func has_session() -> bool:
	return FileAccess.file_exists(SESSION_PATH)


static func clear_session() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))


## Endereço padrão do servidor: na web, o api.php ao lado do index.html (mesma
## hospedagem); fora dela, o último usado (ou o servidor local de testes).
static func default_url() -> String:
	if OS.has_feature("web"):
		var href = JavaScriptBridge.eval("window.location.href.split('?')[0].split('#')[0]")
		if typeof(href) == TYPE_STRING and String(href).begins_with("http"):
			return String(href).substr(0, String(href).rfind("/") + 1) + "api.php"
	var fallback := PUBLIC_URL if PUBLIC_URL != "" else "http://127.0.0.1:8070/api.php"
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		return String(cfg.get_value("online", "url", fallback))
	return fallback


static func remember_url(u: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("online", "url", u)
	cfg.save(CONFIG_PATH)


## Identifica a versão das cartas: os dois aparelhos precisam ter o mesmo cards.json.
static func cards_hash() -> int:
	return FileAccess.get_file_as_string("res://data/cards.json").hash()


## Dados do jogador enviados ao criar/entrar na sala.
static func make_meta(deck_ids: Array, deck_name: String, with_seed: bool) -> Dictionary:
	var m := {"v": NET_VERSION, "cards": cards_hash(), "deck": deck_ids, "name": deck_name}
	if with_seed:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		m["seed"] = rng.randi_range(1, 2000000000)
	return m


## "" se os dados do outro jogador são compatíveis; senão, o motivo.
static func check_meta(m) -> String:
	if typeof(m) != TYPE_DICTIONARY:
		return "Dados do oponente inválidos."
	if int(m.get("v", -1)) != NET_VERSION:
		return "O oponente usa outra versão do modo online."
	if int(m.get("cards", 0)) != cards_hash():
		return "O oponente tem outra versão das cartas. Os dois precisam estar com o jogo atualizado."
	var err := DeckStore.validate(m.get("deck", []))
	if err != "":
		return "Baralho do oponente inválido: " + err
	return ""
