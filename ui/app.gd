extends Control
## Tela raiz: menu inicial, partida (ui/main.tscn) e montador de baralhos.

const GAME_SCENE := preload("res://ui/main.tscn")
const AUTO := "__auto__"
const GOLD := Color("#ffd27a")

var screen: Control
var my_deck: OptionButton
var ai_deck: OptionButton
var summary: Label
var error_label: Label
## lembra a escolha entre idas e vindas do menu
var last_my := "padrao"
var last_ai := AUTO
## Cliente do modo online: vive na App (sobrevive à troca de telas).
var client: OnlineClient
var online_wait_gen := 0      # muda ao sair da tela online (para a espera parar)
var url_edit: LineEdit
var code_edit: LineEdit
var online_status: Label
var online_code: Label


func _ready() -> void:
	CardDB.load_db()
	DeckStore.load_user_decks()
	var bg := ColorRect.new()
	bg.color = Color("#14161b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	client = OnlineClient.new()
	add_child(client)
	show_menu()


## Botão "voltar" do Android (e Esc no desktop não passa por aqui): a tela atual
## trata (fecha janela, volta ao menu); no menu, sai do jogo.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen != null and screen.has_method("go_back"):
			screen.go_back()
		else:
			get_tree().quit()


## Troca a tela atual. A partida que sai é desligada e liberada depois que as
## coroutines dela (animações, IA) tiverem acordado e parado.
func _swap(next: Control) -> void:
	if screen != null:
		var old := screen
		if old.has_method("shutdown"):
			old.shutdown()
			get_tree().create_timer(3.0).timeout.connect(old.queue_free)
		else:
			old.queue_free()
	screen = next
	next.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(next)


# ================================================================ menu

func show_menu() -> void:
	online_wait_gen += 1
	DeckStore.load_user_decks()
	var root := Control.new()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1d2129")
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color("#3a4150")
	sb.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(560, 0)
	panel.add_child(v)

	var title := _label("CADEIA DE COMANDO", 44)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("♠ ♥ ♦ ♣   Gwent + Magic + Poker   ♠ ♥ ♦ ♣", 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.7)
	v.add_child(sub)
	v.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	grid.add_child(_label("Seu baralho", 18))
	my_deck = OptionButton.new()
	my_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(my_deck)
	grid.add_child(_label("Oponente (IA)", 18))
	ai_deck = OptionButton.new()
	ai_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ai_deck)
	my_deck.item_selected.connect(func(_i: int): _update_summary())
	ai_deck.item_selected.connect(func(_i: int): _update_summary())

	summary = _label("", 14)
	summary.modulate = Color(1, 1, 1, 0.75)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(summary)
	error_label = _label("", 14)
	error_label.add_theme_color_override("font_color", Color("#ff8a8a"))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(error_label)

	v.add_child(_big_button("Iniciar partida", _on_start))
	v.add_child(_big_button("Jogar online", _on_online))
	v.add_child(_big_button("Montar baralhos", _on_builder))
	v.add_child(_big_button("Sair", func(): get_tree().quit()))

	_swap(root)
	_fill_decks()


func _fill_decks() -> void:
	my_deck.clear()
	ai_deck.clear()
	ai_deck.add_item("A IA monta o próprio baralho (novo a cada partida)")
	ai_deck.set_item_metadata(0, AUTO)
	for deck_id in _deck_ids():
		var d: Dictionary = CardDB.decks[deck_id]
		var label := "%s  ·  %d cartas" % [d["name"], (d["cards"] as Array).size()]
		if DeckStore.is_user_deck(deck_id):
			label = "★ " + label
		my_deck.add_item(label)
		my_deck.set_item_metadata(my_deck.item_count - 1, deck_id)
		ai_deck.add_item(label)
		ai_deck.set_item_metadata(ai_deck.item_count - 1, deck_id)
	_select(my_deck, last_my)
	_select(ai_deck, last_ai)
	_update_summary()


## Baralhos prontos primeiro, depois os do jogador (★).
func _deck_ids() -> Array:
	var builtin := []
	var user := []
	for k in CardDB.decks:
		if k == "ia_auto":
			continue
		(user if DeckStore.is_user_deck(k) else builtin).append(k)
	return builtin + user


func _select(opt: OptionButton, id: String) -> void:
	for i in opt.item_count:
		if opt.get_item_metadata(i) == id:
			opt.select(i)
			return


func _update_summary() -> void:
	error_label.text = ""
	var mine: String = my_deck.get_selected_metadata()
	var ids: Array = CardDB.decks[mine]["cards"]
	var units := DeckStore.count_units(ids)
	summary.text = "Seu baralho: %d cartas (%d unidades, %d instantâneas). Mínimo para jogar: %d cartas e %d unidades." % [
		ids.size(), units, ids.size() - units, DeckStore.MIN_CARDS, DeckStore.MIN_UNITS]


func _on_start() -> void:
	var mine: String = my_deck.get_selected_metadata()
	var theirs: String = ai_deck.get_selected_metadata()
	var err := DeckStore.validate(CardDB.decks[mine]["cards"])
	if err == "" and theirs != AUTO:
		err = DeckStore.validate(CardDB.decks[theirs]["cards"])
	if err != "":
		error_label.text = err
		return
	last_my = mine
	last_ai = theirs
	var g: Control = GAME_SCENE.instantiate()
	g.deck_ids = [mine, "padrao" if theirs == AUTO else theirs]
	g.ai_auto = theirs == AUTO
	g.menu_requested.connect(show_menu)
	_swap(g)


# ================================================================ online

func _on_online() -> void:
	last_my = my_deck.get_selected_metadata()
	last_ai = ai_deck.get_selected_metadata()
	show_online()


func show_online() -> void:
	online_wait_gen += 1
	var root := Control.new()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1d2129")
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color("#3a4150")
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(600, 0)
	panel.add_child(v)

	var title := _label("JOGAR ONLINE", 36)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var deck_name: String = CardDB.decks[last_my]["name"]
	var info := _label("Seu baralho: %s\nUm cria a sala e passa o código; o outro entra com ele." % deck_name, 15)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.modulate = Color(1, 1, 1, 0.8)
	v.add_child(info)

	var url_row := HBoxContainer.new()
	url_row.add_child(_label("Servidor:", 15))
	url_edit = LineEdit.new()
	url_edit.text = OnlineClient.default_url()
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_row.add_child(url_edit)
	v.add_child(url_row)

	v.add_child(_big_button("Criar sala", _online_create))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "Código da sala"
	code_edit.max_length = 5
	code_edit.custom_minimum_size = Vector2(200, 48)
	code_edit.add_theme_font_size_override("font_size", 22)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(code_edit)
	var join_btn := _big_button("Entrar", _online_join)
	join_btn.custom_minimum_size = Vector2(160, 48)
	join_row.add_child(join_btn)
	v.add_child(join_row)
	if OnlineClient.has_session():
		var c2 := OnlineClient.new()
		if c2.load_session():
			v.add_child(_big_button("Continuar partida (sala %s)" % c2.code, _online_resume))
		c2.free()

	online_code = _label("", 44)
	online_code.add_theme_color_override("font_color", GOLD)
	online_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(online_code)
	online_status = _label("", 15)
	online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(online_status)
	v.add_child(_big_button("Voltar", show_menu))
	_swap(root)


func _online_prepare() -> String:
	client.url = url_edit.text.strip_edges()
	if not client.url.begins_with("http"):
		return "Informe o endereço do servidor (http://.../api.php)."
	# o Android bloqueia HTTP sem TLS (targetSdk 35): só https funciona no APK
	if OS.get_name() == "Android" and not client.url.begins_with("https://"):
		return "No Android o servidor precisa ser https:// (ex.: https://seusite.com/api.php)."
	OnlineClient.remember_url(client.url)
	return DeckStore.validate(CardDB.decks[last_my]["cards"])


func _online_create() -> void:
	var err := _online_prepare()
	if err != "":
		online_status.text = err
		return
	online_status.text = "Criando sala..."
	var d: Dictionary = CardDB.decks[last_my]
	var r := await client.create(OnlineClient.make_meta(d["cards"], d["name"], true))
	if r.has("error"):
		online_status.text = String(r["error"])
		return
	online_code.text = client.code
	online_status.text = "Sala criada! Passe este código para o seu oponente.\nAguardando ele entrar..."
	var gen := online_wait_gen
	while gen == online_wait_gen:
		var p := await client.poll(0)
		if gen != online_wait_gen:
			return
		if not p.has("error") and p.get("guest_meta") != null:
			var bad := OnlineClient.check_meta(JSON.parse_string(String(p["guest_meta"])))
			if bad != "":
				online_status.text = bad
				OnlineClient.clear_session()
				return
			_start_online()
			return
		await get_tree().create_timer(1.5).timeout


func _online_join() -> void:
	var err := _online_prepare()
	if err != "":
		online_status.text = err
		return
	if code_edit.text.strip_edges().length() < 4:
		online_status.text = "Digite o código da sala."
		return
	online_status.text = "Entrando na sala..."
	var d: Dictionary = CardDB.decks[last_my]
	var r := await client.join(code_edit.text, OnlineClient.make_meta(d["cards"], d["name"], false))
	if r.has("error"):
		online_status.text = String(r["error"])
		return
	var bad := OnlineClient.check_meta(JSON.parse_string(String(r["host_meta"])))
	if bad != "":
		online_status.text = bad
		OnlineClient.clear_session()
		return
	_start_online()


func _online_resume() -> void:
	if client.load_session():
		_start_online()


func _start_online() -> void:
	online_wait_gen += 1
	var g: Control = GAME_SCENE.instantiate()
	g.online = client
	g.menu_requested.connect(show_menu)
	_swap(g)


func _on_builder() -> void:
	var b := DeckBuilder.new()
	b.back_requested.connect(show_menu)
	_swap(b)


# ================================================================ util

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b
