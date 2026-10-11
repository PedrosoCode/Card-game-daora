extends Control
## Tela de jogo. Monta a UI em código, traduz cliques em ações do Game
## e redesenha tudo a cada `changed`. Toda regra fica em core/.
##
## Animação: o Game emite `event` para cada coisa que acontece dentro de uma
## ação. Os eventos entram numa fila e são animados em ordem sobre o tabuleiro
## ANTIGO; só depois a tela é redesenhada com o estado final. Assim uma carta
## destruída continua visível até a animação mostrar quem a destruiu.

signal anim_finished
signal dialog_done
## Pedido para voltar ao menu inicial (tratado pela tela App).
signal menu_requested

const HELP_TEXT := """[b]Como jogar[/b]
Melhor de 3 rodadas, 2 vidas. Você começa com 17 cartas e compra 10 a cada nova rodada.
Por turno: [b]baixe 1 carta[/b] numa fileira, [b]use 1 instantânea[/b] (⚡: resolve na hora e vai para o cemitério) ou [b]descarte[/b] 1 (compra outra na hora). Unidades prontas podem atacar e usar efeitos ativos.

[b]Frente / Retaguarda[/b]: atacam e defendem. Não contam no poker.
[b]Cadeia de Comando[/b]: até 5 cartas que formam sua mão de poker. Não atacam. Ao entrar, ganham armadura = HP + 50%.
Só a [b]Frente[/b] ataca a Cadeia inimiga, e só com a Retaguarda inimiga vazia.

Quando os dois passam (ou ficam sem cartas), a melhor Cadeia vence a rodada.
Quem passa [b]continua exposto[/b]: o oponente ainda ataca e usa efeitos, mas gasta cartas para virar.

Passe o mouse numa carta para ver os detalhes. No [b]Registro[/b], clique no nome de uma carta para inspecioná-la e ver o histórico dela. Botão direito ou Esc cancela."""

const SPEEDS := [1.0, 2.0, 0.0]
const SPEED_NAMES := ["Animação 1x", "Animação 2x", "Sem animação"]
const TONE_COLORS := {
	"attack": Color("#ff5050"),
	"effect": Color("#ff8a3a"),
	"poison": Color("#7dff6a"),
	"bleed": Color("#ff3d7a"),
	"heal": Color("#7dffb0"),
	"armor": Color("#7ac8ff"),
	"value": Color("#ffd84a"),
	"atk": Color("#ff9a5a"),
	"control": Color("#c08aff"),
}
const GOLD := Color("#ffd27a")
const SORT_NAMES := ["Padrão (ordem das jogadas)", "Naipe", "Valor", "HP"]
const SUIT_ORDER := ["espadas", "copas", "ouros", "paus"]

var game: Game
var ai: AIPlayer
## Baralhos da partida (ids de CardDB.decks). A tela App define antes de abrir.
var deck_ids := ["padrao", "padrao"]
## true: a IA monta um baralho novo a cada partida (AIDeckBuilder).
var ai_auto := false
var ai_delay := 0.5
## Qual jogador do Game sou eu (fica embaixo na tela). Contra a IA é 0; no
## online, quem entra na sala é 1. As chaves de layout ("0_front"...) são o LADO
## da tela (0 = embaixo, 1 = em cima); _side() converte jogador -> lado.
var me := 0
## Modo online (lockstep pela "caixa de correio" do server/api.php). A App passa
## o cliente já ligado à sala; os dois aparelhos rodam a mesma partida.
var online: OnlineClient = null
var net_seq := 0            # última mensagem conhecida na sala (enviada ou recebida)
var net_logged := 0         # entradas do action_log já tratadas (enviadas ou vindas da rede)
var net_outbox: Array = []  # minhas jogadas ainda não confirmadas pelo servidor
var net_inbox: Array = []   # jogadas do oponente esperando para serem aplicadas
var net_failed := false
var net_opp_acted := false  # chegou jogada do oponente desde a última dica de "sua vez"
## Multiplicador de velocidade das animações. 0 desliga (o fim de rodada ainda abre o diálogo).
var anim_speed := 1.0
## 0 padrão, 1 naipe, 2 valor, 3 HP. Só muda a exibição (mão e tabuleiro).
var sort_mode := 0

# estado de interação
var mode := "idle"          # idle | place | target_play | target_effect | attack | activate
var selected: Card = null
var pending_row := ""
var valid: Array = []
var cast_confirm: Card = null   # instantânea sem alvo aguardando o 2º clique
var ai_busy := false

# estado de animação
var views := {}             # uid -> CardView na tela
var anim_queue: Array = []
var anim_busy := false
var anim_gen := 0           # muda a cada nova partida: coroutines antigas abortam
var pending_slots := {}     # "pid_row" -> cartas já animadas entrando na fileira
var anim_current := ""      # tipo do evento sendo animado (útil para testes)
var anim_parallel := 0      # animações rodando em paralelo (área, dano no impacto)
var closed := false         # a tela saiu de cena (ver shutdown)

# nós
var row_boxes := {}
var row_panels := {}
var row_labels := {}
var hand_box: HBoxContainer
var enemy_info: Label
var my_info: Label
var center_label: RichTextLabel
var turn_label: Label
var hint_label: Label
var detail: RichTextLabel
var log_box: RichTextLabel
var btn_attack: Button
var btn_active: Button
var btn_cancel: Button
var btn_end: Button
var btn_pass: Button
var btn_discard: Button
var btn_speed: Button
var btn_new: Button
var btn_resign: Button
var end_again: Button
var dialog: AcceptDialog
# janela de decisão (escolha no cemitério / troca de mão)
var decision_shade: ColorRect
var decision_panel: PanelContainer
var decision_title: Label
var decision_sub: Label
var decision_cards: HFlowContainer
var decision_buttons: HBoxContainer
var mulligan_new: Dictionary = {}   # uid -> true (cartas que entraram na troca de mão)
var mulligan_sel: Dictionary = {}   # uid -> true (marcadas para a próxima troca)
var mull_suit := 0                  # filtro: 0 todos, 1..4 naipes, 5 instantâneas
var mull_value := 0                 # filtro: 0 todos, senão valor = índice + 1 (2..14)
var inspect_mode := false           # toque/clique inspeciona em vez de marcar (telas de toque)
var decision_tools: HBoxContainer   # filtros e botões extras da janela de decisão
# janela de visualização (cemitérios, baralho) e de inspeção (clique no registro)
var viewer_shade: ColorRect
var viewer_panel: PanelContainer
var viewer_title: Label
var viewer_body: VBoxContainer
var btn_my_grave: Button
var btn_op_grave: Button
var btn_my_deck: Button
var log_lines: Array = []          # linhas do registro (BBCode), para o histórico de cada carta
var end_panel: PanelContainer
var end_title: Label
var end_body: Label
var cards_layer: Control    # clones e cartas em movimento (limpo a cada redesenho)
var fx_layer: Control       # textos, setas, projéteis e faixas (somem sozinhos)


func _ready() -> void:
	CardDB.load_db()
	_build_ui()
	_new_game()


# ================================================================ construção da UI

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#14161b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# ---- coluna do tabuleiro
	var board := VBoxContainer.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.add_theme_constant_override("separation", 3)
	root.add_child(board)

	enemy_info = _label(15)
	board.add_child(enemy_info)
	for r in ["command", "back", "front"]:
		board.add_child(_make_row(1, r))

	center_label = RichTextLabel.new()
	center_label.bbcode_enabled = true
	center_label.fit_content = true
	center_label.scroll_active = false
	center_label.custom_minimum_size = Vector2(0, 26)
	center_label.add_theme_font_size_override("normal_font_size", 16)
	center_label.add_theme_font_size_override("bold_font_size", 16)
	board.add_child(center_label)

	for r in ["front", "back", "command"]:
		board.add_child(_make_row(0, r))

	var hand_title := _label(13)
	hand_title.text = "Sua mão"
	hand_title.modulate = Color(1, 1, 1, 0.6)
	board.add_child(hand_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, CardView.SIZE.y + 14)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board.add_child(scroll)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 6)
	scroll.add_child(hand_box)
	# o leque depende da largura real, que só existe depois do layout
	scroll.resized.connect(_fit_hand)

	my_info = _label(15)
	board.add_child(my_info)

	# ---- painel lateral
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	side.add_theme_constant_override("separation", 6)
	root.add_child(side)

	var title := _label(22)
	title.text = "CADEIA DE COMANDO"
	title.add_theme_color_override("font_color", GOLD)
	side.add_child(title)

	turn_label = _label(16)
	side.add_child(turn_label)

	hint_label = _label(13)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_color", Color("#ffe08a"))
	hint_label.custom_minimum_size = Vector2(0, 40)
	side.add_child(hint_label)

	var row1 := HBoxContainer.new()
	side.add_child(row1)
	btn_end = _button("Encerrar turno", row1, _on_end_turn)
	btn_pass = _button("Passar a rodada", row1, _on_pass)

	var row2 := HBoxContainer.new()
	side.add_child(row2)
	btn_attack = _button("Atacar", row2, _on_attack_pressed)
	btn_active = _button("Usar efeito", row2, _on_active_pressed)
	btn_discard = _button("Descartar", row2, _on_discard_pressed)
	btn_cancel = _button("Cancelar", row2, _cancel)

	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.custom_minimum_size = Vector2(0, 230)
	detail.add_theme_font_size_override("normal_font_size", 14)
	detail.add_theme_font_size_override("bold_font_size", 16)
	var detail_panel := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color("#1d2129")
	dsb.set_corner_radius_all(6)
	dsb.set_content_margin_all(8)
	detail_panel.add_theme_stylebox_override("panel", dsb)
	detail_panel.add_child(detail)
	side.add_child(detail_panel)

	var view_row := HBoxContainer.new()
	side.add_child(view_row)
	btn_my_grave = _button("Meu cemitério", view_row, func(): _open_pile("Seu cemitério", game.players[me].graveyard, false))
	btn_op_grave = _button("Cemitério inimigo", view_row, func(): _open_pile("Cemitério do oponente", game.players[_opp()].graveyard, false))
	btn_my_deck = _button("Meu baralho", view_row, func(): _open_pile("Seu baralho (cartas ainda não compradas, em ordem de naipe e valor)", game.players[me].deck, true))

	var log_title := _label(13)
	log_title.text = "Registro (clique no nome de uma carta para inspecioná-la)"
	log_title.modulate = Color(1, 1, 1, 0.6)
	side.add_child(log_title)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	# nomes de cartas no registro são links [url=uid]: clicar abre a inspeção
	log_box.meta_clicked.connect(func(meta): _inspect_uid(int(str(meta))))
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.add_theme_font_size_override("bold_font_size", 13)
	side.add_child(log_box)

	var sort_row := HBoxContainer.new()
	side.add_child(sort_row)
	var sort_lbl := _label(14)
	sort_lbl.text = "Ordenar cartas:"
	sort_row.add_child(sort_lbl)
	var sort_opt := OptionButton.new()
	sort_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for nm in SORT_NAMES:
		sort_opt.add_item(nm)
	sort_opt.item_selected.connect(func(i: int):
		sort_mode = i
		_refresh())
	sort_row.add_child(sort_opt)

	var row3 := HBoxContainer.new()
	side.add_child(row3)
	btn_speed = _button(SPEED_NAMES[0], row3, _on_speed_pressed)
	btn_new = _button("Nova partida", row3, _new_game)
	btn_resign = _button("Desistir", row3, _on_resign)
	btn_resign.visible = false
	_button("Menu", row3, func(): menu_requested.emit())

	# camadas de animação por cima de tudo, sem bloquear cliques
	cards_layer = _layer()
	fx_layer = _layer()
	_build_end_panel()
	_build_decision()
	_build_viewer()

	dialog = AcceptDialog.new()
	dialog.title = "Fim da rodada"
	dialog.ok_button_text = "Continuar"
	dialog.confirmed.connect(_on_dialog_closed)
	dialog.canceled.connect(_on_dialog_closed)
	add_child(dialog)


## Painel fixo de fim de partida, por cima do tabuleiro (o tabuleiro final fica visível).
func _build_end_panel() -> void:
	end_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = GOLD
	sb.set_content_margin_all(24)
	end_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	end_panel.add_child(v)
	end_title = _label(44)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_title)
	end_body = _label(16)
	end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_body)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	v.add_child(btns)
	for spec in [["Jogar de novo", _new_game], ["Menu", func(): menu_requested.emit()]]:
		var btn := Button.new()
		btn.text = spec[0]
		btn.add_theme_font_size_override("font_size", 20)
		btn.custom_minimum_size = Vector2(200, 44)
		btn.pressed.connect(spec[1])
		btns.add_child(btn)
		if end_again == null:
			end_again = btn
	end_panel.visible = false
	add_child(end_panel)
	resized.connect(_place_end_panel)


## Janela modal para decisões do jogador. Mostrada por _sync_decision a partir
## do estado do Game (game.pending), então sobrevive a redesenhos.
func _build_decision() -> void:
	decision_shade = ColorRect.new()
	decision_shade.color = Color(0, 0, 0, 0.55)
	decision_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	decision_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	decision_shade.visible = false
	add_child(decision_shade)
	decision_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = Color("#9ad8ff")
	sb.set_content_margin_all(20)
	decision_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	decision_panel.add_child(v)
	decision_title = _label(28)
	decision_title.add_theme_color_override("font_color", Color("#9ad8ff"))
	decision_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(decision_title)
	decision_sub = _label(15)
	decision_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	decision_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	decision_sub.custom_minimum_size = Vector2(900, 0)
	v.add_child(decision_sub)
	decision_tools = HBoxContainer.new()
	decision_tools.alignment = BoxContainer.ALIGNMENT_CENTER
	decision_tools.add_theme_constant_override("separation", 10)
	v.add_child(decision_tools)
	decision_cards = HFlowContainer.new()
	decision_cards.alignment = FlowContainer.ALIGNMENT_CENTER
	decision_cards.add_theme_constant_override("h_separation", 8)
	decision_cards.add_theme_constant_override("v_separation", 8)
	decision_cards.custom_minimum_size = Vector2(1000, 0)
	v.add_child(decision_cards)
	decision_buttons = HBoxContainer.new()
	decision_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	decision_buttons.add_theme_constant_override("separation", 16)
	v.add_child(decision_buttons)
	decision_panel.visible = false
	add_child(decision_panel)
	resized.connect(_place_decision)


func _sync_decision() -> void:
	var w := -1 if game == null or game.over else game.waiting_for()
	if w != me:
		decision_shade.visible = false
		decision_panel.visible = false
		if w < 0:
			mulligan_new.clear()
			mulligan_sel.clear()
		if w == _opp():
			_hint("O oponente está decidindo...")
		return
	_clear(decision_cards)
	_clear(decision_buttons)
	_clear(decision_tools)
	var pend: Dictionary = game.pending
	if pend["kind"] == "choice":
		_sync_choice(pend)
	else:
		_sync_mulligan()
	decision_shade.visible = true
	decision_panel.visible = true
	await get_tree().process_frame
	_place_decision()


func _sync_choice(pend: Dictionary) -> void:
	decision_sub.text = String(pend["prompt"])
	var kind := String(pend.get("option_kind", "card"))
	if kind == "row":
		# escolha de fileira: mostra a carta que vai entrar e um botão por fileira
		decision_title.text = "Escolha a fileira"
		var preview: Card = pend.get("preview")
		if preview != null:
			var view := CardView.new()
			view.setup(preview, game)
			view.hovered.connect(func(vw: CardView): _show_detail(vw.card))
			decision_cards.add_child(view)
		for r: String in pend["options"]:
			var b := Button.new()
			b.text = Game.ROW_NAMES[r]
			b.custom_minimum_size = Vector2(220, 44)
			b.add_theme_font_size_override("font_size", 18)
			b.pressed.connect(func(): _on_choice_picked(r))
			decision_buttons.add_child(b)
		_hint("Escolha em qual fileira a carta entra.")
		return
	decision_title.text = "Escolha o alvo" if kind == "target" else "Escolha 1 carta"
	for c: Card in pend["options"]:
		var cell := VBoxContainer.new()
		var view := CardView.new()
		view.setup(c, game)
		view.clicked.connect(func(_v: CardView): _on_choice_picked(c))
		view.right_clicked.connect(func(_v: CardView): _inspect(c))
		view.hovered.connect(func(vw: CardView): _show_detail(vw.card))
		cell.add_child(view)
		var who := _label(11)
		if kind == "target":
			who.text = game.locate(c, me)
		else:
			who.text = "seu cemitério" if c.owner == me else "do oponente"
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.clip_text = true
		who.custom_minimum_size = Vector2(CardView.SIZE.x, 0)
		who.modulate = Color(1, 1, 1, 0.7)
		cell.add_child(who)
		decision_cards.add_child(cell)
	_hint("Escolha uma das cartas da janela (passe o mouse para ler).")


## Troca de mão: marque uma ou mais cartas e confirme. As trocadas voltam ao
## baralho e as novas entram marcadas como NOVA; dá para repetir (inclusive com
## as novas) até acabarem as trocas.
func _sync_mulligan() -> void:
	var left := game.mulligan_left(me)
	var first := game.round_num == 1 and game.turn_num == 0
	decision_title.text = ("Mão inicial" if first else "Rodada %d" % game.round_num) + ": troca de mão"
	decision_sub.text = "Marque as cartas que quer trocar e confirme: elas voltam para o baralho (não vão para o cemitério) e você compra o mesmo número na hora. Pode repetir, inclusive com as novas.  Trocas restantes: %d de %d.  Marcadas: %d." % [
		left, Game.MULLIGAN_MAX, mulligan_sel.size()]
	# filtros + ver baralho + modo inspecionar
	decision_tools.add_child(_tool_label("Naipe:"))
	var suit_opt := OptionButton.new()
	for it in ["Todos", "♠ Espadas", "♥ Copas", "♦ Ouros", "♣ Paus", "⚡ Instantâneas"]:
		suit_opt.add_item(it)
	suit_opt.select(mull_suit)
	suit_opt.item_selected.connect(func(i: int):
		mull_suit = i
		_sync_decision())
	decision_tools.add_child(suit_opt)
	decision_tools.add_child(_tool_label("Valor:"))
	var val_opt := OptionButton.new()
	val_opt.add_item("Todos")
	for v in range(2, 15):
		val_opt.add_item(Game.value_label(v))
	val_opt.select(mull_value)
	val_opt.item_selected.connect(func(i: int):
		mull_value = i
		_sync_decision())
	decision_tools.add_child(val_opt)
	var deck_btn := Button.new()
	deck_btn.text = "Ver baralho (%d)" % game.players[me].deck.size()
	deck_btn.pressed.connect(func(): _open_pile("Seu baralho (ordem de naipe e valor)", game.players[me].deck, true))
	decision_tools.add_child(deck_btn)
	var insp := CheckButton.new()
	insp.text = "Inspecionar ao clicar"
	insp.button_pressed = inspect_mode
	insp.toggled.connect(func(on: bool): inspect_mode = on)
	decision_tools.add_child(insp)

	var shown := 0
	for c: Card in _sorted(game.players[me].hand):
		if not _mull_passes(c):
			continue
		shown += 1
		var cell := VBoxContainer.new()
		var view := CardView.new()
		view.setup(c, game)
		if mulligan_sel.has(c.uid):
			view.set_state("target")
		elif mulligan_new.has(c.uid):
			view.set_state("selected")
		view.clicked.connect(func(_v: CardView): _mulligan_click(c))
		view.right_clicked.connect(func(_v: CardView): _inspect(c))
		view.hovered.connect(func(vw: CardView): _show_detail(vw.card))
		cell.add_child(view)
		var tag := _label(11)
		if mulligan_sel.has(c.uid):
			tag.text = "TROCAR"
			tag.add_theme_color_override("font_color", Color("#ff8a8a"))
		elif mulligan_new.has(c.uid):
			tag.text = "NOVA"
			tag.add_theme_color_override("font_color", GOLD)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(tag)
		decision_cards.add_child(cell)
	if shown == 0:
		var none := _label(15)
		none.text = "Nenhuma carta da mão passa nesse filtro."
		none.modulate = Color(1, 1, 1, 0.6)
		decision_cards.add_child(none)

	var n := mulligan_sel.size()
	var swap := Button.new()
	swap.text = "Trocar %d marcada(s)" % n if n > 0 else "Marque cartas para trocar"
	swap.disabled = n == 0 or left <= 0
	swap.custom_minimum_size = Vector2(260, 44)
	swap.add_theme_font_size_override("font_size", 18)
	swap.pressed.connect(_mulligan_confirm)
	decision_buttons.add_child(swap)
	if n > 0:
		var clear := Button.new()
		clear.text = "Desmarcar"
		clear.custom_minimum_size = Vector2(160, 44)
		clear.pressed.connect(func():
			mulligan_sel.clear()
			_sync_decision())
		decision_buttons.add_child(clear)
	var done := Button.new()
	done.text = "Concluir troca" if left > 0 else "Concluir (sem trocas restantes)"
	done.custom_minimum_size = Vector2(240, 44)
	done.add_theme_font_size_override("font_size", 18)
	done.pressed.connect(_mulligan_finish)
	decision_buttons.add_child(done)
	_hint("Troca de mão: marque cartas (restam %d trocas), confirme em Trocar e, no fim, em Concluir. Botão direito numa carta inspeciona." % left)


func _mull_passes(c: Card) -> bool:
	if mull_suit == 5 and c.is_unit():
		return false
	if mull_suit >= 1 and mull_suit <= 4 and (not c.is_unit() or c.suit != SUIT_ORDER[mull_suit - 1]):
		return false
	if mull_value > 0 and (not c.is_unit() or c.base_value != mull_value + 1):
		return false
	return true


func _tool_label(text: String) -> Label:
	var l := _label(14)
	l.text = text
	return l


func _place_decision() -> void:
	if decision_panel == null or not decision_panel.visible:
		return
	decision_panel.reset_size()
	var c := center_label.global_position + center_label.size * 0.5
	var pos := c - decision_panel.size * 0.5
	decision_panel.position = Vector2(maxf(8.0, pos.x), maxf(8.0, pos.y))


func _hide_decision() -> void:
	decision_shade.visible = false
	decision_panel.visible = false


## Opção escolhida numa janela de decisão (carta, fileira ou alvo).
func _on_choice_picked(option) -> void:
	if anim_busy or game.waiting_for() != me:
		return
	_hide_decision()
	if not game.resolve_choice(me, option):
		_hint(game.last_error)
	else:
		_turn_hint()


## Dica padrão do momento (depois de uma decisão).
func _turn_hint() -> void:
	if game.is_turn(me):
		_hint("Sua vez." if not game.players[me].played_card else "Você já jogou uma carta neste turno. Ataque, use efeitos ou encerre o turno.")
	elif not game.over:
		_hint("Turno do oponente.")


func _mulligan_click(c: Card) -> void:
	if anim_busy or game.waiting_for() != me:
		return
	if inspect_mode:
		_inspect(c)
		return
	if mulligan_sel.has(c.uid):
		mulligan_sel.erase(c.uid)
	elif mulligan_sel.size() < game.mulligan_left(me):
		mulligan_sel[c.uid] = true
	else:
		_hint("Você só tem %d troca(s) restante(s)." % game.mulligan_left(me))
	_sync_decision()


## Troca de uma vez todas as cartas marcadas.
func _mulligan_confirm() -> void:
	if anim_busy or game.waiting_for() != me or mulligan_sel.is_empty():
		return
	var picked := []
	for c: Card in game.players[me].hand:
		if mulligan_sel.has(c.uid):
			picked.append(c)
	mulligan_sel.clear()
	for c: Card in picked:
		mulligan_new.erase(c.uid)
		var fresh := game.mulligan_swap(me, c)
		if fresh == null:
			_hint(game.last_error)
			break
		mulligan_new[fresh.uid] = true


func _mulligan_finish() -> void:
	if anim_busy or game.waiting_for() != me:
		return
	mulligan_new.clear()
	mulligan_sel.clear()
	_hide_decision()
	if not game.mulligan_done(me):
		_hint(game.last_error)
	else:
		_turn_hint()


# ================================================================ visualizar / inspecionar

func _build_viewer() -> void:
	viewer_shade = ColorRect.new()
	viewer_shade.color = Color(0, 0, 0, 0.55)
	viewer_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewer_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	viewer_shade.visible = false
	viewer_shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_viewer())
	add_child(viewer_shade)
	viewer_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = GOLD
	sb.set_content_margin_all(18)
	viewer_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	viewer_panel.add_child(v)
	viewer_title = _label(24)
	viewer_title.add_theme_color_override("font_color", GOLD)
	viewer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(viewer_title)
	viewer_body = VBoxContainer.new()
	viewer_body.add_theme_constant_override("separation", 10)
	v.add_child(viewer_body)
	var close := Button.new()
	close.text = "Fechar"
	close.custom_minimum_size = Vector2(200, 40)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_viewer)
	v.add_child(close)
	viewer_panel.visible = false
	add_child(viewer_panel)


func _show_viewer(title: String) -> void:
	viewer_title.text = title
	viewer_shade.visible = true
	viewer_panel.visible = true
	await get_tree().process_frame
	viewer_panel.reset_size()
	var c := center_label.global_position + center_label.size * 0.5
	var pos := c - viewer_panel.size * 0.5
	viewer_panel.position = Vector2(maxf(8.0, pos.x), maxf(8.0, pos.y))


func _close_viewer() -> void:
	if viewer_panel == null:
		return
	viewer_shade.visible = false
	viewer_panel.visible = false
	_clear(viewer_body)


## Mostra uma pilha de cartas (cemitério, baralho). O baralho sai ordenado
## por naipe e valor para não revelar a ordem de compra.
func _open_pile(title: String, cards: Array, hide_order: bool) -> void:
	_clear(viewer_body)
	var list := cards.duplicate()
	if hide_order:
		var keep := sort_mode
		sort_mode = 1
		list = _sorted(list)
		sort_mode = keep
	if list.is_empty():
		var empty := _label(16)
		empty.text = "(nenhuma carta)"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		viewer_body.add_child(empty)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(1040, mini(3, ceili(list.size() / 10.0)) * (CardView.SIZE.y + 8) + 8)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var flow := HFlowContainer.new()
		flow.custom_minimum_size = Vector2(1020, 0)
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 8)
		scroll.add_child(flow)
		for c: Card in list:
			var view := CardView.new()
			view.setup(c, game)
			view.hovered.connect(func(vw: CardView): _show_detail(vw.card))
			view.clicked.connect(func(vw: CardView): _inspect(vw.card))
			flow.add_child(view)
		viewer_body.add_child(scroll)
	_show_viewer("%s  ·  %d carta(s)" % [title, list.size()])


func _inspect_uid(uid: int) -> void:
	var c = game.cards_by_uid.get(uid)
	if c != null:
		_inspect(c)


## Inspeção de uma carta: desenho ampliado, texto completo, onde está agora e o
## histórico dela no registro (quem a atingiu, como morreu...).
func _inspect(c: Card) -> void:
	_clear(viewer_body)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	viewer_body.add_child(top)
	# CardView ampliada dentro de um Control simples (containers zeram a escala)
	var holder := Control.new()
	holder.custom_minimum_size = CardView.SIZE * 2.0
	var view := CardView.new()
	view.setup(c, game)
	view.scale = Vector2(2, 2)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(view)
	top.add_child(holder)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.custom_minimum_size = Vector2(560, CardView.SIZE.y * 2.0)
	info.add_theme_font_size_override("normal_font_size", 15)
	info.add_theme_font_size_override("bold_font_size", 18)
	info.text = CardView.describe(c, game) + "\n\n[color=#9aa4b8]Onde está agora: %s[/color]" % game.locate(c, me)
	top.add_child(info)
	var hist_title := _label(16)
	hist_title.text = "Histórico desta carta no registro"
	hist_title.add_theme_color_override("font_color", GOLD)
	viewer_body.add_child(hist_title)
	var hist := RichTextLabel.new()
	hist.bbcode_enabled = true
	hist.custom_minimum_size = Vector2(800, 200)
	hist.scroll_following = true
	hist.add_theme_font_size_override("normal_font_size", 14)
	hist.add_theme_font_size_override("bold_font_size", 14)
	hist.meta_clicked.connect(func(meta): _inspect_uid(int(str(meta))))
	var tag := "[url=%d]" % c.uid
	var mine := []
	for i in log_lines.size():
		if String(log_lines[i]).contains(tag):
			# linha recuada é consequência: inclui a ação que a causou (ex.:
			# "Oponente usa ⚡ Bola de Fogo" antes de "X sofre 4 de dano")
			if String(log_lines[i]).begins_with("  "):
				var j := i - 1
				while j > 0 and String(log_lines[j]).begins_with("  "):
					j -= 1
				if j >= 0 and not mine.has(j):
					mine.append(j)
			if not mine.has(i):
				mine.append(i)
	if mine.is_empty():
		hist.text = "(nada registrado ainda)"
	else:
		for i in mine.slice(maxi(0, mine.size() - 30)):
			hist.append_text(String(log_lines[i]) + "\n")
	viewer_body.add_child(hist)
	_show_viewer(c.name)


func _show_end_panel(info: Dictionary) -> void:
	var mw := int(info["match_winner"])
	end_title.text = "EMPATE" if mw < 0 else ("VITÓRIA!" if mw == me else "DERROTA")
	end_title.add_theme_color_override("font_color",
		GOLD if mw < 0 else (Color("#7dff9a") if mw == me else Color("#ff8a8a")))
	var lines := PackedStringArray()
	if info.has("resigned"):
		lines.append("Você desistiu." if int(info["resigned"]) == me else "O oponente desistiu.")
	lines.append("Vidas: você %d  x  %d oponente" % [int(info["gems"][me]), int(info["gems"][_opp()])])
	lines.append("")
	for h: Dictionary in game.history:
		var w := int(h["winner"])
		var who := "empate" if w < 0 else ("você venceu" if w == me else "oponente venceu")
		lines.append("Rodada %d (%s):  %s  x  %s" % [int(h["round"]), who, h["names"][me], h["names"][_opp()]])
	if info.has("resigned"):
		lines.append("Rodada %d interrompida pela desistência." % int(info["round"]))
	end_body.text = "\n".join(lines)
	end_panel.visible = true
	_hint("Partida encerrada. Clique em Jogar de novo (ou Nova partida) para recomeçar.")
	turn_label.text = "Fim de jogo - " + ("empate" if mw < 0 else ("você venceu" if mw == me else "você perdeu"))
	await get_tree().process_frame
	_place_end_panel()


func _place_end_panel() -> void:
	if end_panel == null or not end_panel.visible:
		return
	end_panel.reset_size()
	var c := center_label.global_position + center_label.size * 0.5
	end_panel.position = c - end_panel.size * 0.5


func _opp() -> int:
	return 1 - me


func _side(pid: int) -> int:
	return 0 if pid == me else 1


func _layer() -> Control:
	var l := Control.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _make_row(pid: int, r: String) -> Control:
	var key := "%d_%s" % [pid, r]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, CardView.SIZE.y + 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1c2230") if pid == 0 else Color("#261c22")
	if r == "command":
		sb.bg_color = sb.bg_color.lightened(0.06)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color("#2b303a")
	sb.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.gui_input.connect(_on_row_input.bind(pid, r))

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 8)
	panel.add_child(h)
	var lbl := _label(13)
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_FILL
	h.add_child(lbl)
	var cards := HBoxContainer.new()
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards.add_theme_constant_override("separation", 6)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(cards)

	row_boxes[key] = cards
	row_panels[key] = panel
	row_labels[key] = lbl
	return panel


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _button(text: String, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ================================================================ partida

func _new_game() -> void:
	# aborta animações e a IA da partida anterior
	anim_gen += 1
	anim_queue.clear()
	anim_busy = false
	anim_parallel = 0
	anim_finished.emit()
	if dialog.visible:
		dialog.hide()
		dialog_done.emit()
	_clear(cards_layer)
	_clear(fx_layer)
	end_panel.visible = false
	_hide_decision()
	_close_viewer()
	mulligan_new.clear()

	game = Game.new()
	game.logged.connect(func(t: String):
		log_lines.append(t)
		log_box.append_text(t + "\n"))
	log_box.clear()
	log_lines.clear()
	mode = "idle"
	selected = null
	valid = []
	cast_confirm = null
	btn_new.visible = online == null
	btn_resign.visible = online != null
	end_again.visible = online == null
	if online != null:
		ai = null
		var g := game
		if not await _net_setup():
			return
		if g != game:
			return
	else:
		ai = AIPlayer.new(game, 1)
		if ai_auto:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var ids := AIDeckBuilder.build(rng)
			CardDB.decks["ia_auto"] = {"name": AIDeckBuilder.name_for(ids), "cards": ids}
			deck_ids[1] = "ia_auto"
		game.setup(deck_ids[0], deck_ids[1], true)
	game.changed.connect(_refresh)
	game.set_viewer(me)
	log_box.append_text("[color=#9aa4b8]Você: %s  x  Oponente: %s[/color]\n" % [
		CardDB.decks[deck_ids[0]]["name"], CardDB.decks[deck_ids[1]]["name"]])
	game.event.connect(_on_game_event)
	_hint("Sua vez: baixe uma carta numa fileira, ataque ou use efeitos." if game.current == me else "O oponente começa.")
	detail.text = HELP_TEXT
	_redraw()
	if online != null:
		game.changed.connect(func(): _net_collect.call_deferred())
		_net_loop()
		if game.turn_num > 0:
			return  # partida retomada: sem faixa de início
	_banner("Rodada 1 - " + ("você começa" if game.current == me else "o oponente começa"), GOLD, 1.0)


## Pedido de redesenho. Durante animações ele espera a fila terminar.
func _refresh() -> void:
	if game == null or anim_busy:
		return
	_redraw()


func _redraw() -> void:
	for key in row_boxes:
		_clear(row_boxes[key])
	_clear(hand_box)
	_clear(cards_layer)
	views.clear()
	pending_slots.clear()

	var place_rows := game.playable_rows(selected) if (mode == "place" and selected != null) else []
	for pid in 2:
		var p := game.players[pid]
		for r in Game.ROWS:
			var key := "%d_%s" % [_side(pid), r]
			for c: Card in _sorted(p.rows[r]):
				row_boxes[key].add_child(_make_card_view(c))
			var txt: String = Game.ROW_NAMES[r]
			if r == "command":
				txt += "\n[%s]" % game.hand_name(pid)
				if p.passed:
					txt += "\nSELADA" if Game.PASS_SEALS_COMMAND else "\nPASSOU"
			row_labels[key].text = txt
			var hot := pid == me and place_rows.has(r)
			_set_row_border(key, Color("#5cff8a") if hot else Color("#2b303a"))
	for c: Card in _sorted(game.players[me].hand):
		hand_box.add_child(_make_card_view(c))
	_fit_hand()

	var mp := game.players[me]
	var op := game.players[_opp()]
	enemy_info.text = "OPONENTE  |  Vidas %d/%d  |  Mão %d  |  Baralho %d  |  Cemitério %d%s" % [
		op.gems, Game.START_GEMS, op.hand.size(), op.deck.size(), op.graveyard.size(), "  |  PASSOU" if op.passed else ""]
	my_info.text = "VOCÊ  |  Vidas %d/%d  |  Mão %d  |  Baralho %d  |  Cemitério %d%s" % [
		mp.gems, Game.START_GEMS, mp.hand.size(), mp.deck.size(), mp.graveyard.size(), "  |  PASSOU" if mp.passed else ""]
	var cmp := HandEvaluator.compare(game.hand_key(me), game.hand_key(_opp()))
	var status := "[color=#7dff9a]você está na frente[/color]" if cmp > 0 else ("[color=#ff8a8a]você está atrás[/color]" if cmp < 0 else "empate")
	center_label.text = "[center][b]Sua mão:[/b] %s     [b]Oponente:[/b] %s     (%s)[/center]" % [game.hand_name(me), game.hand_name(_opp()), status]

	if game.over:
		var mw := game.winner
		turn_label.text = "Fim de jogo - " + ("empate" if mw < 0 else ("você venceu" if mw == me else "você perdeu"))
	else:
		var who := "Seu turno" if game.current == me else "Turno do oponente"
		if game.pending.get("kind", "") == "mulligan":
			who = "Troca de mão" if game.waiting_for() == me else "Troca de mão do oponente"
		turn_label.text = "Rodada %d  -  %s" % [game.round_num, who]

	var my_turn := game.is_turn(me)
	btn_end.disabled = not game.can_end_turn(me)
	btn_pass.disabled = not my_turn
	btn_attack.disabled = not (selected != null and game.can_attack(selected))
	btn_active.disabled = not (selected != null and game.can_activate(selected))
	btn_discard.disabled = not (selected != null and selected.owner == me and game.can_discard(selected))
	btn_cancel.disabled = mode == "idle" and selected == null
	btn_resign.disabled = online == null or net_failed or game.over or not _my_action_time()

	btn_my_grave.text = "Meu cemitério (%d)" % mp.graveyard.size()
	btn_op_grave.text = "Cemitério inimigo (%d)" % op.graveyard.size()
	btn_my_deck.text = "Meu baralho (%d)" % mp.deck.size()
	_sync_decision()
	if _ai_should_act():
		_run_ai.call_deferred()


## Cópia ordenada para exibição. Naipe: ♠ ♥ ♦ ♣ e, dentro do naipe, maior valor
## primeiro. Valor e HP: maior primeiro. Padrão: a ordem real (jogadas / compras).
func _sorted(cards: Array) -> Array:
	var out := cards.duplicate()
	match sort_mode:
		1:
			out.sort_custom(func(a: Card, b: Card) -> bool:
				var sa := _suit_rank(a)
				var sb := _suit_rank(b)
				return sa < sb or (sa == sb and game.effective_value(a) > game.effective_value(b)))
		2:
			out.sort_custom(func(a: Card, b: Card) -> bool:
				var va := game.effective_value(a)
				var vb := game.effective_value(b)
				return va > vb or (va == vb and _suit_rank(a) < _suit_rank(b)))
		3:
			out.sort_custom(func(a: Card, b: Card) -> bool:
				return a.hp > b.hp or (a.hp == b.hp and game.effective_value(a) > game.effective_value(b)))
	return out


func _suit_rank(c: Card) -> int:
	var i := SUIT_ORDER.find(c.suit)
	return i if i >= 0 else SUIT_ORDER.size()


## Com muitas cartas, a mão se sobrepõe (como um leque) para caber sem rolagem.
func _fit_hand() -> void:
	var n := hand_box.get_child_count()
	var width: float = hand_box.get_parent().size.x - 16.0
	var sep := 6
	if width > CardView.SIZE.x and n > 1 and n * (CardView.SIZE.x + 6) > width:
		sep = int(floor((width - CardView.SIZE.x) / (n - 1) - CardView.SIZE.x))
	hand_box.add_theme_constant_override("separation", sep)


func _make_card_view(c: Card) -> CardView:
	var v := CardView.new()
	v.setup(c, game)
	v.clicked.connect(_on_card_clicked)
	v.hovered.connect(func(view: CardView): _show_detail(view.card))
	if c == selected:
		v.set_state("selected")
	elif valid.has(c):
		v.set_state("target")
	elif mode == "idle" and c.owner == me and _is_actionable(c):
		v.set_state("ready")
	views[c.uid] = v
	return v


func _is_actionable(c: Card) -> bool:
	if game.players[me].hand.has(c):
		return game.can_play(c)
	return game.can_attack(c) or game.can_activate(c)


func _clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


func _set_row_border(key: String, color: Color) -> void:
	var sb: StyleBoxFlat = row_panels[key].get_theme_stylebox("panel")
	sb.border_color = color


# ================================================================ interação

func _on_card_clicked(view: CardView) -> void:
	var c := view.card
	_show_detail(c)
	if game.over or anim_busy:
		return
	if mode in ["target_play", "target_effect", "attack", "activate"] and valid.has(c):
		_execute_target(c)
		return
	if game.players[me].hand.has(c):
		_select_hand(c)
	else:
		mode = "idle"
		valid = []
		selected = c
		cast_confirm = null
		if c.owner == me and game.is_turn(me):
			if game.can_attack(c) or game.can_activate(c):
				_hint("Use os botões Atacar / Usar efeito.")
			else:
				_hint(_why_idle(c))
		_refresh()


func _select_hand(c: Card) -> void:
	var confirming := cast_confirm == c
	cast_confirm = null
	mode = "idle"
	valid = []
	selected = c
	if not game.is_turn(me):
		_hint("Aguarde o seu turno.")
	elif game.players[me].played_card:
		_hint("Você já jogou uma carta neste turno. Encerre o turno ou passe.")
	elif game.playable_rows(c).is_empty() and c.is_unit():
		_hint("Todas as suas fileiras estão cheias. Use Descartar para trocar a carta por outra do baralho.")
	elif c.is_unit():
		mode = "place"
		_hint("Clique em uma das suas fileiras (destacadas em verde) para baixar a carta, ou em Descartar para trocá-la por outra do baralho.")
	else:
		var spec := game.play_spec(c)
		if spec.is_empty():
			# instantânea sem alvo: pede um 2º clique para não gastar a carta sem querer
			if not confirming:
				cast_confirm = c
				_hint("⚡ %s: clique de novo na carta para usar (ou escolha outra)." % c.name)
			elif game.play_card(me, c):
				_hint("Você usou ⚡ %s." % c.name)
				_cancel()
				return
			else:
				_hint(game.last_error)
		else:
			valid = game.valid_targets(spec, me, c)
			if valid.is_empty():
				_hint("Nenhum alvo válido para esta carta.")
			else:
				mode = "target_effect"
				_hint("Escolha o alvo (borda vermelha).")
	_refresh()


func _on_row_input(event: InputEvent, pid: int, r: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if anim_busy or mode != "place" or pid != 0 or selected == null:
		return
	if not game.playable_rows(selected).has(r):
		_hint("Essa fileira está cheia.")
		return
	var spec := game.play_spec(selected)
	var targets := game.valid_targets(spec, me, selected)
	if not spec.is_empty() and not targets.is_empty():
		mode = "target_play"
		pending_row = r
		valid = targets
		_hint("Escolha o alvo do efeito de entrada.")
		_refresh()
		return
	if not game.play_card(me, selected, r):
		_hint(game.last_error)
	_cancel()


## Explica por que uma unidade sua não pode atacar nem usar efeito agora.
func _why_idle(c: Card) -> String:
	if c.row == "command":
		return "Cartas na Cadeia de Comando não atacam: elas formam sua mão de poker."
	if c.stunned:
		return "Esta unidade está congelada e perde este turno."
	if c.exhausted:
		return "Esta carta acabou de entrar e só age no seu próximo turno."
	if c.attacked:
		return "Esta unidade já atacou neste turno."
	if game.effective_atk(c) <= 0:
		return "Esta unidade tem ATQ 0 e não ataca."
	var opp := game.players[_opp()]
	if game.attack_targets(c).is_empty():
		if Game.PASS_SEALS_COMMAND and opp.passed and not opp.rows["command"].is_empty():
			return "Sem alvos: o oponente passou, então a Cadeia de Comando dele está SELADA (não pode ser atacada nem receber efeitos), e não há outras cartas dele na mesa."
		return "Sem alvos: o oponente não tem cartas que esta unidade alcance."
	return "Esta carta não tem ação disponível agora."


func _execute_target(t: Card) -> void:
	var ok := false
	match mode:
		"target_play":
			ok = game.play_card(me, selected, pending_row, t)
		"target_effect":
			ok = game.play_card(me, selected, "", t)
		"attack":
			ok = game.attack(me, selected, t)
		"activate":
			ok = game.activate(me, selected, t)
	if not ok:
		_hint(game.last_error)
	_cancel()


func _on_attack_pressed() -> void:
	if anim_busy or selected == null or not game.can_attack(selected):
		return
	valid = game.attack_targets(selected)
	mode = "attack"
	if selected.row == "back":
		_hint("Escolha o alvo do ataque. Da Retaguarda não dá para atacar a Cadeia de Comando.")
	elif not game.can_hit_command(selected):
		_hint("Escolha o alvo do ataque. A Retaguarda inimiga protege a Cadeia de Comando.")
	else:
		_hint("Escolha o alvo do ataque.")
	_refresh()


func _on_active_pressed() -> void:
	if anim_busy or selected == null or not game.can_activate(selected):
		return
	var spec := game.active_spec(selected)
	if spec.is_empty():
		if not game.activate(me, selected):
			_hint(game.last_error)
		_cancel()
		return
	valid = game.valid_targets(spec, me, selected)
	mode = "activate"
	_hint("Escolha o alvo do efeito.")
	_refresh()


func _on_discard_pressed() -> void:
	if anim_busy or selected == null or not game.can_discard(selected):
		return
	if not game.discard(me, selected):
		_hint(game.last_error)
	else:
		_hint("Carta trocada. Neste turno você não baixa mais cartas, mas ainda pode atacar e usar efeitos.")
	_cancel()


func _on_end_turn() -> void:
	if anim_busy:
		return
	_cancel()
	if not game.end_turn(me):
		_hint(game.last_error)


func _on_pass() -> void:
	if anim_busy:
		return
	_cancel()
	game.pass_round(me)


func _on_speed_pressed() -> void:
	var i := (SPEEDS.find(anim_speed) + 1) % SPEEDS.size()
	anim_speed = SPEEDS[i]
	btn_speed.text = SPEED_NAMES[i]


func _cancel() -> void:
	mode = "idle"
	selected = null
	cast_confirm = null
	pending_row = ""
	valid = []
	if anim_busy:
		# a tela só é redesenhada no fim da animação: apaga já os destaques de seleção
		for v in views.values():
			if is_instance_valid(v):
				v.set_state("")
		for key in row_panels:
			_set_row_border(key, Color("#2b303a"))
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if viewer_panel.visible:
			_close_viewer()
			return
		_cancel()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if decision_panel.visible or viewer_panel.visible:
			return
		_cancel()


func _hint(t: String) -> void:
	hint_label.text = t


func _show_detail(c: Card) -> void:
	detail.text = CardView.describe(c, game)


# ================================================================ IA

# ================================================================ modo online

## Monta a partida da sala: semente e baralhos dos dois e, numa retomada, refaz
## (sem animação) todas as jogadas já feitas.
func _net_setup() -> bool:
	me = online.seat
	net_seq = 0
	net_outbox.clear()
	net_inbox.clear()
	net_failed = false
	net_opp_acted = false
	_hint("Carregando a sala %s..." % online.code)
	var r := await online.poll(0)
	if r.has("error"):
		_net_fail("Não foi possível carregar a sala: " + String(r["error"]))
		return false
	var host = JSON.parse_string(String(r["host_meta"]))
	var guest = JSON.parse_string(String(r["guest_meta"])) if r.get("guest_meta") != null else null
	if typeof(host) != TYPE_DICTIONARY or typeof(guest) != TYPE_DICTIONARY:
		_net_fail("A sala ainda não tem os dois jogadores.")
		return false
	CardDB.decks["net_0"] = {"name": String(host.get("name", "Baralho")), "cards": host["deck"]}
	CardDB.decks["net_1"] = {"name": String(guest.get("name", "Baralho")), "cards": guest["deck"]}
	deck_ids = ["net_0", "net_1"]
	game.setup("net_0", "net_1", false, int(host["seed"]))
	for m: Dictionary in r["messages"]:
		var d = JSON.parse_string(String(m["data"]))
		if typeof(d) != TYPE_DICTIONARY or not game.apply_action(int(m["seat"]), d["act"]):
			_net_fail("Não foi possível refazer a jogada %d da sala." % int(m["seq"]))
			return false
		net_seq = int(m["seq"])
	net_logged = game.action_log.size()
	return true


## Pega no action_log as jogadas MINHAS ainda não enviadas e põe na fila de envio.
## O hash vai na última de cada lote (estado logo depois dela).
func _net_collect() -> void:
	if online == null or game == null or net_failed:
		return
	var batch := []
	while net_logged < game.action_log.size():
		var e: Dictionary = game.action_log[net_logged]
		net_logged += 1
		if int(e["pid"]) == me:
			batch.append(e["act"])
	for i in batch.size():
		net_seq += 1
		var data := {"act": batch[i]}
		if i == batch.size() - 1:
			data["h"] = game.state_hash()
		net_outbox.append({"seq": net_seq, "data": data})


func _net_apply_next() -> void:
	var m: Dictionary = net_inbox.pop_front()
	var d = JSON.parse_string(String(m["data"]))
	if typeof(d) != TYPE_DICTIONARY or not game.apply_action(_opp(), d["act"]):
		_net_fail("Recebi uma jogada que não vale neste estado da partida (dessincronia).")
		return
	net_logged = game.action_log.size()
	net_opp_acted = true
	if d.get("h") != null and int(d["h"]) != game.state_hash():
		_net_fail("Os dois aparelhos ficaram com partidas diferentes (dessincronia).")


## Laço da rede: envia as minhas jogadas, busca as do oponente quando é a vez
## dele e as aplica uma a uma, esperando as animações.
func _net_loop() -> void:
	var g := game
	while online != null and g == game and not closed and not net_failed:
		if not net_outbox.is_empty():
			var m: Dictionary = net_outbox[0]
			var r := await online.send(int(m["seq"]), m["data"])
			if g != game or closed:
				return
			if r.has("error"):
				if int(r["status"]) >= 400 and int(r["status"]) < 500:
					_net_fail("O servidor recusou a jogada: " + String(r["error"]))
					return
				_hint("Sem conexão com o servidor. Tentando de novo...")
				await get_tree().create_timer(2.0).timeout
				continue
			net_outbox.pop_front()
			continue
		if not net_inbox.is_empty():
			if anim_busy:
				await anim_finished
				continue
			_net_apply_next()
			continue
		if game.over:
			OnlineClient.clear_session()
			return
		if net_opp_acted and not _ai_turn_pending():
			if anim_busy:
				await anim_finished
				continue
			net_opp_acted = false
			_opp_turn_done()
		if _ai_turn_pending():
			var p := await online.poll(net_seq)
			if g != game or closed:
				return
			if p.has("error"):
				_hint("Sem conexão com o servidor. Tentando de novo...")
				await get_tree().create_timer(2.0).timeout
				continue
			for m: Dictionary in p["messages"]:
				if int(m["seq"]) > net_seq:
					net_seq = int(m["seq"])
					if int(m["seat"]) != me:
						net_inbox.append(m)
			if net_inbox.is_empty():
				if not anim_busy:
					_hint("Aguardando a jogada do oponente... (sala %s)" % online.code)
				await get_tree().create_timer(1.2).timeout
			continue
		await get_tree().create_timer(0.25).timeout


func _net_fail(msg: String) -> void:
	net_failed = true
	_hint(msg)
	dialog.title = "Modo online"
	dialog.dialog_text = msg + "\n\nVolte ao menu. Se foi falta de conexão, dá para retomar a partida em Jogar online."
	dialog.popup_centered(Vector2i(460, 0))


## Minha vez de agir (turno ou decisão minha): só aí dá para desistir, para que
## os dois aparelhos nunca mandem jogadas ao mesmo tempo.
func _my_action_time() -> bool:
	var w := game.waiting_for()
	if w >= 0:
		return w == me
	return game.current == me and not game.players[me].passed


func _on_resign() -> void:
	if online == null or anim_busy or not _my_action_time():
		return
	game.resign(me)


## Botão "voltar" (Android): fecha a janela aberta, cancela a seleção ou volta ao menu.
func go_back() -> void:
	if viewer_panel.visible:
		_close_viewer()
	elif selected != null or mode != "idle":
		_cancel()
	elif not decision_panel.visible:
		menu_requested.emit()


## Chamado pela App antes de trocar de tela: interrompe animações e a IA.
## (Coroutines pendentes acordam, veem a geração nova e param.)
func shutdown() -> void:
	closed = true
	anim_gen += 1
	anim_queue.clear()
	anim_parallel = 0
	if dialog.visible:
		dialog.hide()
	dialog_done.emit()
	anim_finished.emit()
	hide()


## A IA tem algo a fazer: uma decisão pendente dela, ou o turno dela (sem
## decisão pendente de ninguém).
func _ai_turn_pending() -> bool:
	if closed or game.over:
		return false
	var w := game.waiting_for()
	if w >= 0:
		return w == _opp()
	return game.current == _opp() and not game.players[_opp()].passed


func _ai_should_act() -> bool:
	return game != null and ai != null and _ai_turn_pending() \
		and not ai_busy and not anim_busy and not dialog.visible


func _run_ai() -> void:
	if not _ai_should_act():
		return
	ai_busy = true
	var g := game
	while g == game and _ai_turn_pending():
		if anim_busy:
			await anim_finished
			continue
		if dialog.visible:
			break
		var delay := ai_delay / maxf(anim_speed, 1.0) if anim_speed > 0.0 else 0.0
		await get_tree().create_timer(delay).timeout
		if g != game or anim_busy or dialog.visible or not _ai_turn_pending():
			continue
		if not ai.step():
			break
	ai_busy = false
	if g == game:
		_opp_turn_done()


## Fim da vez do oponente (IA ou rede): devolve a dica para o jogador.
func _opp_turn_done() -> void:
	if game.is_turn(me):
		_hint("Sua vez." if not game.players[me].hand.is_empty() else "Sem cartas na mão: ataque, use efeitos e encerre o turno.")
	_refresh()


# ================================================================ fila de animação

func _on_game_event(ev: Dictionary) -> void:
	anim_queue.append(ev)
	if not anim_busy:
		anim_busy = true
		# adiado: junta todos os eventos da ação antes de começar
		_play_queue.call_deferred(anim_gen)


func _play_queue(gen: int) -> void:
	while not anim_queue.is_empty():
		if gen != anim_gen:
			return
		var ev: Dictionary = anim_queue.pop_front()
		await _animate(ev)
	# não redesenha (o que libera as cartas antigas) com animação paralela ainda rodando
	while anim_parallel > 0 and gen == anim_gen:
		await get_tree().process_frame
	if gen != anim_gen:
		return
	anim_busy = false
	_redraw()
	anim_finished.emit()


func _animate(ev: Dictionary) -> void:
	var t: String = ev["type"]
	anim_current = t
	if anim_speed <= 0.0:
		if t == "resign":
			_show_end_panel(ev["info"])
		if t == "round_end":
			if ev["info"].get("match_over", false):
				_show_end_panel(ev["info"])
			else:
				await _show_round_dialog(ev["info"])
		return
	match t:
		"turn":
			await _anim_turn(ev)
		"play":
			await _anim_play(ev)
		"revive":
			await _anim_revive(ev)
		"attack":
			await _anim_attack(ev)
		"activate":
			await _anim_activate(ev)
		"timer":
			await _anim_timer(ev)
		"damage", "buff":
			await _anim_group(ev)
		"destroy":
			await _anim_destroy(ev)
		"discard":
			await _anim_discard(ev)
		"draw", "recall", "exile", "mill", "mulligan":
			await _anim_toast(ev)
		"choice":
			pass  # a janela de escolha aparece no redesenho (_sync_decision)
		"pass":
			await _anim_pass(ev)
		"resign":
			_show_end_panel(ev["info"])
		"cast":
			await _anim_cast(ev)
		"cast_end":
			await _anim_cast_end(ev)
		"summon":
			await _anim_revive(ev)
		"move":
			await _anim_move(ev)
		"bounce":
			await _anim_bounce(ev)
		"round_end":
			await _anim_round_end(ev)


## Efeitos em área (ex.: dano em todos os inimigos, cura em todos os aliados,
## veneno no início do turno) chegam como vários eventos seguidos da mesma
## fonte. Eles são animados juntos em vez de um por um.
func _anim_group(ev: Dictionary) -> void:
	var group := [ev]
	while not anim_queue.is_empty() and _same_group(ev, anim_queue[0]):
		group.append(anim_queue.pop_front())
	for i in group.size() - 1:
		_anim_parallel(group[i])
	await _anim_one(group[-1])


func _same_group(a: Dictionary, b: Dictionary) -> bool:
	if a["type"] != b["type"] or int(a.get("src", -1)) != int(b.get("src", -1)):
		return false
	if a["type"] == "damage":
		return a.get("kind") == b.get("kind") and a.get("kind") != "attack"
	return a.get("label") == b.get("label")


## Roda uma animação sem esperar por ela, mas contando, para a fila não
## redesenhar a tela enquanto ela ainda mexe nas cartas.
func _anim_parallel(ev: Dictionary) -> void:
	var gen := anim_gen
	anim_parallel += 1
	await _anim_one(ev)
	if gen == anim_gen:
		anim_parallel -= 1


func _anim_one(ev: Dictionary) -> void:
	if ev["type"] == "damage":
		await _anim_damage(ev)
	else:
		await _anim_buff(ev)


func _anim_turn(ev: Dictionary) -> void:
	var mine := int(ev["pid"]) == me
	_banner("Seu turno" if mine else "Turno do oponente", Color("#7dff9a") if mine else Color("#ff9a9a"), 0.35)
	await _wait(0.2)


func _anim_play(ev: Dictionary) -> void:
	var c: Card = ev["card"]
	var pid := int(ev["pid"])
	var dest := _slot_pos("%d_%s" % [pid, ev["row"]])
	var nv := _spawn_view(c, ev["snap"])
	var old := _view(c.uid)
	var start: Vector2
	if old != null:
		start = old.global_position
		old.modulate.a = 0.0
	else:
		start = _hand_pos(pid) - CardView.SIZE * 0.5
		nv.scale = Vector2(0.6, 0.6)
	views[c.uid] = nv
	nv.position = _to_layer(start, cards_layer)
	var tw := create_tween().set_parallel()
	tw.tween_property(nv, "position", _to_layer(dest, cards_layer), _dur(0.4)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(nv, "scale", Vector2.ONE, _dur(0.4))
	await tw.finished
	if is_instance_valid(nv):
		_flash(nv, Color(1, 1, 0.55))
	await _wait(0.12)


func _anim_revive(ev: Dictionary) -> void:
	var c: Card = ev["card"]
	var dest := _slot_pos("%d_%s" % [_side(int(ev["pid"])), ev["row"]])
	var nv := _spawn_view(c, ev["snap"])
	views[c.uid] = nv
	nv.position = _to_layer(dest, cards_layer)
	nv.scale = Vector2(0.2, 0.2)
	nv.modulate = Color(0.5, 1, 0.6, 0)
	var tw := create_tween().set_parallel()
	tw.tween_property(nv, "scale", Vector2.ONE, _dur(0.4)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(nv, "modulate", Color.WHITE, _dur(0.5))
	_float_text(dest + CardView.SIZE * 0.5, "REVIVE" if ev["type"] == "revive" else "INVOCADA", TONE_COLORS["heal"], 20)
	await tw.finished


## Instantânea: a carta vai ao centro da mesa; os efeitos saem dela (projéteis).
func _anim_cast(ev: Dictionary) -> void:
	var c: Card = ev["card"]
	var pid := int(ev["pid"])
	var old := _view(c.uid)
	var nv := _spawn_view(c, ev["snap"])
	nv.z_index = 20
	var start: Vector2
	if old != null:
		start = old.global_position
		old.modulate.a = 0.0
	else:
		start = _hand_pos(pid) - CardView.SIZE * 0.5
	nv.position = _to_layer(start, cards_layer)
	views[c.uid] = nv
	var dest := center_label.global_position + center_label.size * 0.5 - CardView.SIZE * 0.5
	var tw := create_tween().set_parallel()
	tw.tween_property(nv, "position", _to_layer(dest, cards_layer), _dur(0.35)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(nv, "scale", Vector2(1.35, 1.35), _dur(0.35))
	await tw.finished
	if not is_instance_valid(nv):
		return
	_flash(nv, Color(1, 0.9, 0.5))
	var who := "Você usa" if pid == me else "O oponente usa"
	_float_text(nv.center() - Vector2(0, 90), "%s ⚡ %s" % [who, c.name], GOLD, 22)
	# a do oponente fica mais tempo à vista para dar tempo de ler
	await _wait(0.35 if pid == me else 1.1)


func _anim_cast_end(ev: Dictionary) -> void:
	var v := _view(int(ev["uid"]))
	views.erase(int(ev["uid"]))
	if v == null:
		return
	await _wait(0.15)
	if is_instance_valid(v):
		_fly_to_grave(v, int(ev["pid"]))
	await _wait(0.25)


func _anim_move(ev: Dictionary) -> void:
	var v := _view(int(ev["uid"]))
	if v == null:
		return
	var dest := _slot_pos("%d_%s" % [_side(int(ev["pid"])), ev["row"]])
	var cl := _clone(v)
	v.modulate.a = 0.0
	views[int(ev["uid"])] = cl
	_float_text(v.center(), "Movida para a %s" % Game.ROW_NAMES[ev["row"]], TONE_COLORS["control"], 18)
	var tw := create_tween()
	tw.tween_property(cl, "position", _to_layer(dest, cards_layer), _dur(0.4)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _anim_bounce(ev: Dictionary) -> void:
	var v := _view(int(ev["uid"]))
	views.erase(int(ev["uid"]))
	if v == null:
		return
	var cl := _clone(v)
	v.modulate.a = 0.0
	_float_text(v.center(), "Volta para a mão", TONE_COLORS["control"], 18)
	var dest := _to_layer(_hand_pos(int(ev["pid"])) - cl.size * 0.5, cards_layer)
	var tw := create_tween().set_parallel()
	tw.tween_property(cl, "position", dest, _dur(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(cl, "scale", Vector2(0.6, 0.6), _dur(0.45))
	tw.tween_property(cl, "modulate:a", 0.0, _dur(0.3)).set_delay(_dur(0.15))
	tw.chain().tween_callback(cl.queue_free)
	await _wait(0.4)


func _anim_attack(ev: Dictionary) -> void:
	var a := _view(int(ev["src"]))
	var d := _view(int(ev["dst"]))
	if a == null or d == null:
		return
	var from := a.center()
	var to := d.center()
	_arrow(from, to, TONE_COLORS["attack"])
	var cl := _clone(a)
	cl.z_index = 10
	a.modulate.a = 0.0
	var start := cl.position
	var tw := create_tween()
	tw.tween_property(cl, "position", start + (to - from) * 0.7, _dur(0.22)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tw.finished
	if not is_instance_valid(cl):
		return
	# impacto: o dano deste ataque aparece no instante do golpe
	if not anim_queue.is_empty():
		var nxt: Dictionary = anim_queue[0]
		if nxt["type"] == "damage" and nxt.get("kind") == "attack" and int(nxt["uid"]) == int(ev["dst"]):
			anim_queue.pop_front()
			_anim_parallel(nxt)
	var back := create_tween()
	back.tween_property(cl, "position", start, _dur(0.22)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await back.finished
	if is_instance_valid(cl):
		cl.queue_free()
	if is_instance_valid(a) and not a.dead:
		a.modulate.a = 1.0
	await _wait(0.1)


func _anim_activate(ev: Dictionary) -> void:
	var v := _view(int(ev["uid"]))
	if v == null:
		return
	_flash(v, Color(1, 0.85, 0.3))
	_float_text(v.center() - Vector2(0, 30), "ATIVA", GOLD, 16)
	await _wait(0.25)


func _anim_timer(ev: Dictionary) -> void:
	var v := _view(int(ev["uid"]))
	if v == null:
		return
	v.apply_snapshot(ev["snap"])
	_flash(v, Color(0.55, 0.85, 1))
	_float_text(v.center() - Vector2(0, 30), "◷ Temporizador!", Color("#9ad8ff"), 16)
	await _wait(0.3)


func _anim_damage(ev: Dictionary) -> void:
	var v := _view(int(ev["uid"]))
	if v == null:
		return
	var kind: String = ev.get("kind", "effect")
	var src := _view(int(ev.get("src", -1)))
	if kind == "effect" and src != null and src != v:
		await _projectile(src.center(), v.center(), TONE_COLORS["effect"])
		if not is_instance_valid(v):
			return
	v.apply_snapshot(ev["snap"])
	if bool(ev.get("blocked", false)):
		_float_text(v.center(), "BLOQUEADO", TONE_COLORS["armor"], 24)
		_flash(v, Color(0.6, 0.85, 1))
		await _wait(0.3)
		return
	var amt := int(ev["amount"])
	var absorbed := int(ev["absorbed"])
	# a cor diz o tipo (vermelho ataque, laranja efeito, verde veneno, rosa sangramento)
	if amt > 0:
		_float_text(v.center(), "-%d" % amt, TONE_COLORS.get(kind, TONE_COLORS["attack"]), 30)
	if absorbed > 0:
		_float_text(v.center() + Vector2(0, 26), "-%d ARM" % absorbed, TONE_COLORS["armor"], 20)
	_flash(v, Color(1, 0.35, 0.35))
	_shake(v)
	await _wait(0.3)


func _anim_buff(ev: Dictionary) -> void:
	var v := _view(int(ev["uid"]))
	if v == null:
		return
	var col: Color = TONE_COLORS.get(String(ev["tone"]), Color.WHITE)
	var src := _view(int(ev.get("src", -1)))
	if src != null and src != v:
		await _projectile(src.center(), v.center(), col)
		if not is_instance_valid(v):
			return
	v.apply_snapshot(ev["snap"])
	_float_text(v.center(), String(ev["label"]), col, 20)
	_flash(v, col.lerp(Color.WHITE, 0.3))
	await _wait(0.25)


func _anim_destroy(ev: Dictionary) -> void:
	var v := _view(int(ev["uid"]))
	if v == null:
		return
	v.dead = true
	v.apply_snapshot(ev["snap"])
	_float_text(v.center() - Vector2(0, 30), "DESTRUÍDA", Color("#ff6060"), 22)
	v.modulate = Color(1, 0.25, 0.25)
	_shake(v)
	await _wait(0.3)
	if not is_instance_valid(v):
		return
	# a carta voa para o cemitério do dono
	var cl := _clone(v)
	cl.modulate = Color(1, 0.3, 0.3)
	v.modulate.a = 0.0
	_fly_to_grave(cl, v.card.owner)
	await _wait(0.25)


func _anim_discard(ev: Dictionary) -> void:
	var c: Card = ev["card"]
	var pid := int(ev["pid"])
	var v := _view(c.uid)
	var cl: CardView
	if v != null:
		cl = _clone(v)
		v.modulate.a = 0.0
	else:
		cl = _spawn_view(c, ev["snap"])
		cl.position = _to_layer(_hand_pos(pid) - CardView.SIZE * 0.5, cards_layer)
	_float_text(cl.global_position + CardView.SIZE * 0.5, "Descarte", Color("#c0c0c0"), 18)
	cl.modulate = Color(0.7, 0.7, 0.7)
	await _wait(0.2)
	if not is_instance_valid(cl):
		return
	_fly_to_grave(cl, pid)
	await _wait(0.3)


func _anim_toast(ev: Dictionary) -> void:
	var pid := int(ev["pid"])
	var pos := _info_pos(pid)
	match String(ev["type"]):
		"draw":
			_float_text(pos, "+%d carta(s)" % int(ev["n"]), Color.WHITE, 20)
		"recall":
			_float_text(pos, "%s volta para a mão" % ev["card"].name, TONE_COLORS["heal"], 18)
		"exile":
			_float_text(pos, "%d exilada(s) do cemitério" % int(ev["n"]), Color("#c08aff"), 18)
		"mill":
			_float_text(pos, "-%d do baralho (direto ao cemitério)" % int(ev["n"]), Color("#c08aff"), 18)
		"mulligan":
			var n := int(ev["n"])
			_float_text(pos, ("Troca %d carta(s) da mão" % n) if n > 0 else "Mantém a mão", Color("#9ad8ff"), 18)
	await _wait(0.35)


func _anim_pass(ev: Dictionary) -> void:
	var pid := int(ev["pid"])
	_set_row_border("%d_command" % _side(pid), GOLD)
	var tail := " - Cadeia selada" if Game.PASS_SEALS_COMMAND else " - a Cadeia continua exposta"
	_banner(("Você passou" if pid == me else "O oponente passou") + tail, GOLD, 0.8)
	await _wait(0.6)


func _anim_round_end(ev: Dictionary) -> void:
	var info: Dictionary = ev["info"]
	var w := int(info["winner"])
	for pid in 2:
		var col := GOLD
		if w >= 0:
			col = Color("#5cff8a") if pid == w else Color("#ff5a5a")
		_set_row_border("%d_command" % _side(pid), col)
	_banner("Showdown:  %s  x  %s" % [info["names"][me], info["names"][_opp()]], GOLD, 1.4)
	await _wait(1.6)
	if info.get("match_over", false):
		# fim de jogo: painel fixo; o tabuleiro final continua na mesa
		_show_end_panel(info)
		return
	await _show_round_dialog(info)
	# o tabuleiro vai para o cemitério
	for key in row_boxes:
		for ch in row_boxes[key].get_children():
			create_tween().tween_property(ch, "modulate:a", 0.0, _dur(0.3))
	await _wait(0.35)


func _show_round_dialog(info: Dictionary) -> void:
	var w: int = info["winner"]
	var head := "Empate! As duas vidas caem." if w < 0 else ("Você venceu a rodada!" if w == me else "O oponente venceu a rodada.")
	var txt := "Rodada %d - %s\n\nSua mão: %s\n%s\n\nOponente: %s\n%s" % [
		info["round"], head, info["names"][me], info["cards"][me], info["names"][_opp()], info["cards"][_opp()]]
	dialog.title = "Fim da rodada"
	txt += "\n\nVidas: você %d, oponente %d.\nO tabuleiro vai para o cemitério. Cada um compra %d carta(s)." % [
		int(info["gems"][me]), int(info["gems"][_opp()]), int(Game.DRAW_AFTER_ROUND.get(info["round"], 0))]
	dialog.dialog_text = txt
	dialog.popup_centered(Vector2i(460, 0))
	await dialog_done


func _on_dialog_closed() -> void:
	dialog_done.emit()
	_refresh()


# ================================================================ peças de animação

func _dur(sec: float) -> float:
	return sec / maxf(anim_speed, 0.01)


func _wait(sec: float) -> void:
	if anim_speed > 0.0:
		await get_tree().create_timer(_dur(sec)).timeout


func _view(uid: int) -> CardView:
	var v = views.get(uid)
	return v if is_instance_valid(v) else null


func _to_layer(global_pos: Vector2, layer: Control) -> Vector2:
	return global_pos - layer.global_position


## Posição (global) da próxima vaga numa fileira: logo depois da última carta
## (as fileiras são centralizadas; o redesenho final recentraliza tudo).
func _slot_pos(key: String) -> Vector2:
	var box: Control = row_boxes[key]
	var step := CardView.SIZE.x + 6
	var pending := int(pending_slots.get(key, 0))
	pending_slots[key] = pending + 1
	var n := box.get_child_count()
	if n == 0:
		return box.global_position + Vector2((box.size.x - CardView.SIZE.x) * 0.5 + pending * step, 0)
	var last: Control = box.get_child(n - 1)
	return last.global_position + Vector2((pending + 1) * step, 0)


## De onde saem as cartas da mão (a do oponente fica escondida no topo).
func _hand_pos(pid: int) -> Vector2:
	if pid == me:
		return hand_box.get_parent().global_position + Vector2(200, CardView.SIZE.y * 0.5)
	return enemy_info.global_position + Vector2(300, enemy_info.size.y * 0.5)


func _info_pos(pid: int) -> Vector2:
	var l := my_info if pid == me else enemy_info
	return l.global_position + Vector2(260, l.size.y * 0.5)


func _spawn_view(c: Card, snap: Dictionary) -> CardView:
	var nv := CardView.new()
	nv.setup(c, game)
	nv.apply_snapshot(snap)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_layer.add_child(nv)
	nv.size = CardView.SIZE
	nv.pivot_offset = CardView.SIZE * 0.5
	return nv


## Cópia solta de uma carta do tabuleiro, para mover sem brigar com os containers.
func _clone(v: CardView) -> CardView:
	var cl := _spawn_view(v.card, v.last_snap if not v.last_snap.is_empty() else game.snapshot(v.card))
	cl.size = v.size
	cl.pivot_offset = v.size * 0.5
	cl.position = _to_layer(v.global_position, cards_layer)
	return cl


func _fly_to_grave(cl: CardView, pid: int) -> void:
	var dest := _to_layer(_info_pos(pid) - cl.size * 0.5, cards_layer)
	var tw := create_tween().set_parallel()
	tw.tween_property(cl, "position", dest, _dur(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(cl, "scale", Vector2(0.35, 0.35), _dur(0.45))
	tw.tween_property(cl, "rotation", randf_range(-0.6, 0.6), _dur(0.45))
	tw.tween_property(cl, "modulate:a", 0.0, _dur(0.3)).set_delay(_dur(0.15))
	tw.chain().tween_callback(cl.queue_free)


func _flash(v: CardView, color: Color, dur: float = 0.4) -> void:
	if not is_instance_valid(v) or v.dead:
		return
	var a := v.modulate.a
	v.modulate = Color(color.r, color.g, color.b, a)
	create_tween().tween_property(v, "modulate", Color(1, 1, 1, a), _dur(dur))


func _shake(v: Control) -> void:
	if not is_instance_valid(v):
		return
	var o := v.position
	var tw := create_tween()
	for i in 4:
		tw.tween_property(v, "position", o + Vector2(randf_range(-6, 6), randf_range(-3, 3)), _dur(0.04))
	tw.tween_property(v, "position", o, _dur(0.04))


func _float_text(pos: Vector2, text: String, color: Color, font_size: int = 24) -> void:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 7)
	fx_layer.add_child(l)
	l.reset_size()
	l.position = _to_layer(pos - l.size * 0.5, fx_layer)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 46, _dur(1.0)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, _dur(0.45)).set_delay(_dur(0.55))
	tw.chain().tween_callback(l.queue_free)


func _projectile(from: Vector2, to: Vector2, color: Color) -> void:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(9)
	sb.shadow_color = Color(color.r, color.g, color.b, 0.6)
	sb.shadow_size = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = Vector2(18, 18)
	fx_layer.add_child(p)
	var half := p.size * 0.5
	p.position = _to_layer(from - half, fx_layer)
	var tw := create_tween()
	tw.tween_property(p, "position", _to_layer(to - half, fx_layer), _dur(0.28)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	if is_instance_valid(p):
		p.queue_free()


## Seta do atacante até o alvo, que some sozinha.
func _arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var dir := (to - from).normalized()
	var n := Vector2(-dir.y, dir.x)
	var a := _to_layer(from, fx_layer)
	var b := _to_layer(to - dir * 24.0, fx_layer)
	var line := Line2D.new()
	line.width = 5
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.points = PackedVector2Array([a, b])
	var head := Polygon2D.new()
	head.color = color
	head.polygon = PackedVector2Array([b + dir * 14.0, b - dir * 8.0 + n * 11.0, b - dir * 8.0 - n * 11.0])
	line.add_child(head)
	fx_layer.add_child(line)
	var tw := create_tween()
	tw.tween_interval(_dur(0.5))
	tw.tween_property(line, "modulate:a", 0.0, _dur(0.35))
	tw.tween_callback(line.queue_free)


## Faixa no centro do tabuleiro (turno, passe, showdown).
func _banner(text: String, color: Color, hold: float) -> void:
	if anim_speed <= 0.0:
		return
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = color
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", color)
	p.add_child(l)
	p.modulate.a = 0.0
	fx_layer.add_child(p)
	# espera um quadro: no início da partida o layout ainda não tem tamanho
	await get_tree().process_frame
	if not is_instance_valid(p):
		return
	p.reset_size()
	var c := center_label.global_position + center_label.size * 0.5
	p.position = _to_layer(c - p.size * 0.5, fx_layer)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, _dur(0.12))
	tw.tween_interval(_dur(hold))
	tw.tween_property(p, "modulate:a", 0.0, _dur(0.25))
	tw.tween_callback(p.queue_free)
