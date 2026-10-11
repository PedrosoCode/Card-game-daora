class_name DeckBuilder
extends Control
## Montador de baralhos. Clique numa carta do acervo para adicionar uma cópia,
## botão direito nela (toque longo no celular) ou clique na linha da lista
## remove uma. Arrastar as cartas rola o acervo. Salva em
## user://decks.json via DeckStore. Regra: pelo menos DeckStore.MIN_UNITS unidades.

signal back_requested

const KIND_FILTERS := ["Todas as cartas", "Unidades", "Instantâneas"]
const SUIT_FILTERS := ["Todos os naipes", "♠ Espadas", "♥ Copas", "♦ Ouros", "♣ Paus"]
const SUIT_ORDER := ["espadas", "copas", "ouros", "paus"]
const GOLD := Color("#ffd27a")

## Contexto só para desenhar as cartas (nenhuma partida acontece aqui).
var display_game := Game.new()
var deck: Dictionary = {}           # id -> cópias
var pool: Array = []                # ids do acervo, na ordem do cards.json
var cards: Dictionary = {}          # id -> Card de exibição
var cells: Dictionary = {}          # id -> célula do acervo
var counts: Dictionary = {}         # id -> Label "no baralho: N"

var grid: GridContainer
var scroll: ScrollContainer
var kind_opt: OptionButton
var suit_opt: OptionButton
var search: LineEdit
var load_opt: OptionButton
var name_edit: LineEdit
var stats: RichTextLabel
var deck_list: ItemList
var detail: RichTextLabel
var status: Label
var cell_w := CardView.FULL_SIZE.x   # largura da carta no acervo (colunas da grade)


func _ready() -> void:
	CardDB.load_db()
	DeckStore.load_user_decks()
	pool = CardDB.pool_ids()
	var uid := 1
	for cid in pool:
		cards[cid] = Card.new(uid, CardDB.get_def(cid), 0)
		uid += 1
	_build()
	_fill_load_options()
	_load_deck("padrao")
	_apply_filters()


## Botão "voltar" (Android).
func go_back() -> void:
	back_requested.emit()


# ================================================================ construção

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#14161b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var c := UiProfile.compact
	var face := Vector2(100, 50) if c else CardView.FULL_SIZE
	cell_w = face.x
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6 if c else 10)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8 if c else 12)
	margin.add_child(root)

	# ---- acervo
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4 if c else 6)
	root.add_child(left)
	if not c:
		var title := _label("MONTAR BARALHO", 26)
		title.add_theme_color_override("font_color", GOLD)
		left.add_child(title)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6 if c else 8)
	left.add_child(filters)
	kind_opt = _option(KIND_FILTERS, filters)
	suit_opt = _option(SUIT_FILTERS, filters)
	search = LineEdit.new()
	search.placeholder_text = "Buscar..." if c else "Buscar por nome ou texto..."
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = UiProfile.button_h()
	search.text_changed.connect(func(_t: String): _apply_filters())
	filters.add_child(search)
	var help := _label("Toque: +1 cópia · toque longo ou toque na lista: −1 · arraste para rolar" if c
		else "Clique numa carta para adicionar 1 cópia. Botão direito remove 1. Passe o mouse para ler a carta.", 11 if c else 13)
	help.modulate = Color(1, 1, 1, 0.6)
	left.add_child(help)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# SHOW_NEVER (e não DISABLED): a largura da grade não pode empurrar o layout;
	# as colunas são calculadas a partir da largura disponível (_fit_columns)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	left.add_child(scroll)
	# a grade fica centralizada na largura disponível
	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 8)
	grid_center.add_child(grid)
	scroll.resized.connect(_fit_columns)
	for cid in pool:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var view := CardView.new()
		view.setup(cards[cid], display_game, face)
		view.clicked.connect(func(_v: CardView): _add(cid))
		view.right_clicked.connect(func(_v: CardView):
			_show(cid)
			_remove(cid))
		view.hovered.connect(func(_v: CardView): _show(cid))
		cell.add_child(view)
		var cnt := _label("", 10 if c else 12)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# o rótulo não pode alargar a célula além da carta (quebra as colunas)
		cnt.clip_text = true
		cnt.custom_minimum_size = Vector2(face.x, 0)
		cnt.add_theme_color_override("font_color", GOLD)
		cell.add_child(cnt)
		counts[cid] = cnt
		cells[cid] = cell
		grid.add_child(cell)

	# ---- baralho
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(290 if c else 400, 0)
	right.add_theme_constant_override("separation", 4 if c else 6)
	root.add_child(right)
	if not c:
		right.add_child(_label("Baralho", 22))
	var load_row := HBoxContainer.new()
	right.add_child(load_row)
	load_opt = OptionButton.new()
	load_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_opt.fit_to_longest_item = false
	load_opt.clip_text = true
	load_opt.custom_minimum_size.y = UiProfile.button_h()
	load_row.add_child(load_opt)
	_button("Abrir", load_row, func(): _load_deck(String(load_opt.get_selected_metadata())))
	_button("Novo" if c else "Novo vazio", load_row, _new_empty)
	var name_row := HBoxContainer.new()
	right.add_child(name_row)
	name_row.add_child(_label("Nome:", UiProfile.fs(15)))
	name_edit = LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size.y = UiProfile.button_h()
	name_edit.placeholder_text = "Nome do baralho"
	name_row.add_child(name_edit)
	stats = RichTextLabel.new()
	stats.bbcode_enabled = true
	stats.fit_content = true
	stats.scroll_active = false
	stats.add_theme_font_size_override("normal_font_size", 11 if c else 14)
	stats.add_theme_font_size_override("bold_font_size", 11 if c else 14)
	right.add_child(stats)
	if not c:
		var list_help := _label("Clique numa linha para remover 1 cópia.", 12)
		list_help.modulate = Color(1, 1, 1, 0.6)
		right.add_child(list_help)
	deck_list = ItemList.new()
	deck_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_list.add_theme_font_size_override("font_size", 12 if c else 14)
	deck_list.item_clicked.connect(_on_list_clicked)
	right.add_child(deck_list)
	var dpanel := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color("#1d2129")
	dsb.set_corner_radius_all(6)
	dsb.set_content_margin_all(8)
	dpanel.add_theme_stylebox_override("panel", dsb)
	right.add_child(dpanel)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.custom_minimum_size = Vector2(0, 56 if c else 170)
	detail.add_theme_font_size_override("normal_font_size", 11 if c else 13)
	detail.add_theme_font_size_override("bold_font_size", 12 if c else 15)
	dpanel.add_child(detail)
	status = _label("", 12 if c else 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(status)
	var actions := HBoxContainer.new()
	right.add_child(actions)
	_button("Salvar", actions, _save)
	_button("Excluir", actions, func():
		Modal.confirm(self, "Excluir o baralho \"%s\"?" % name_edit.text.strip_edges(), "Excluir", _delete))
	_button("Voltar" if c else "Voltar ao menu", actions, func(): back_requested.emit())


func _fit_columns() -> void:
	var w := scroll.size.x - 16.0
	grid.columns = maxi(1, int(w / (cell_w + 6)))


# ================================================================ filtros

func _apply_filters() -> void:
	var kind := kind_opt.selected
	var suit := suit_opt.selected
	var q := search.text.strip_edges().to_lower()
	for cid in pool:
		var d: Dictionary = CardDB.get_def(cid)
		var is_unit := String(d.get("kind", "unit")) == "unit"
		var ok := true
		if kind == 1 and not is_unit:
			ok = false
		if kind == 2 and is_unit:
			ok = false
		if suit > 0 and String(d.get("suit", "")) != SUIT_ORDER[suit - 1]:
			ok = false
		if q != "" and not (String(d.get("name", "")).to_lower().contains(q) or String(d.get("text", "")).to_lower().contains(q)):
			ok = false
		cells[cid].visible = ok


# ================================================================ baralho

func _add(cid: String) -> void:
	deck[cid] = int(deck.get(cid, 0)) + 1
	_show(cid)
	_refresh_deck()


func _remove(cid: String) -> void:
	if not deck.has(cid):
		return
	deck[cid] = int(deck[cid]) - 1
	if int(deck[cid]) <= 0:
		deck.erase(cid)
	_refresh_deck()


func _ids() -> Array:
	var out := []
	for cid in _sorted_ids():
		for i in int(deck[cid]):
			out.append(cid)
	return out


## Unidades por naipe e valor (maior primeiro), depois instantâneas por naipe.
func _sorted_ids() -> Array:
	var ids := deck.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var da: Dictionary = CardDB.get_def(a)
		var db: Dictionary = CardDB.get_def(b)
		var ua := String(da.get("kind", "unit")) == "unit"
		var ub := String(db.get("kind", "unit")) == "unit"
		if ua != ub:
			return ua
		var sa := SUIT_ORDER.find(String(da.get("suit", "")))
		var sb := SUIT_ORDER.find(String(db.get("suit", "")))
		if sa != sb:
			return sa < sb
		if int(da.get("value", 0)) != int(db.get("value", 0)):
			return int(da.get("value", 0)) > int(db.get("value", 0))
		return String(da.get("name", "")) < String(db.get("name", "")))
	return ids


func _refresh_deck() -> void:
	deck_list.clear()
	for cid in _sorted_ids():
		var d: Dictionary = CardDB.get_def(cid)
		var tag: String
		if String(d.get("kind", "unit")) == "unit":
			tag = Game.card_label(int(d["value"]), String(d["suit"]))
		else:
			tag = "⚡" + String(Game.SUIT_SYMBOLS.get(String(d.get("suit", "")), ""))
		deck_list.add_item("%d×   %s   %s" % [int(deck[cid]), tag, d["name"]])
		deck_list.set_item_metadata(deck_list.item_count - 1, cid)
	for cid in counts:
		var n := int(deck.get(cid, 0))
		counts[cid].text = "%d no baralho" % n if n > 0 else ""
	_refresh_stats()


func _refresh_stats() -> void:
	var ids := _ids()
	var units := DeckStore.count_units(ids)
	var per_suit := {}
	var per_value := {}
	for cid in ids:
		var d: Dictionary = CardDB.get_def(cid)
		if String(d.get("kind", "unit")) != "unit":
			continue
		per_suit[d["suit"]] = int(per_suit.get(d["suit"], 0)) + 1
		var v := int(d["value"])
		per_value[v] = int(per_value.get(v, 0)) + 1
	var ok_units := units >= DeckStore.MIN_UNITS
	var ok_size := ids.size() >= DeckStore.MIN_CARDS
	var ok := ok_units and ok_size
	var c := UiProfile.compact
	var t := ("[b][color=%s]%d cartas[/color][/b] (mín. %d) · [color=%s]%d[/color] unid. (mín. %d) · %d inst.\n" if c
		else "[b][color=%s]%d cartas[/color][/b] (mín. %d)   ·   unidades: [color=%s]%d[/color] (mín. %d)   ·   instantâneas: %d\n") % [
		"#7dff9a" if ok_size else "#ff8a8a", ids.size(), DeckStore.MIN_CARDS,
		"#7dff9a" if ok_units else "#ff8a8a", units, DeckStore.MIN_UNITS, ids.size() - units]
	var suits := PackedStringArray()
	for s in SUIT_ORDER:
		suits.append("%s %d" % [Game.SUIT_SYMBOLS[s], int(per_suit.get(s, 0))])
	t += ("Naipes:  " if c else "Naipes das unidades:  ") + "   ".join(suits)
	if not c:
		t += "\n"
	var vals := PackedStringArray()
	for v in range(2, 15):
		if per_value.has(v):
			vals.append("%s×%d" % [Game.value_label(v), int(per_value[v])])
	if not c:
		t += "Valores:  " + ("  ".join(vals) if not vals.is_empty() else "-")
	if not ok_size:
		t += "\n[color=#ff8a8a]Faltam %d cartas para o baralho ser válido.[/color]" % (DeckStore.MIN_CARDS - ids.size())
	if not ok_units:
		t += "\n[color=#ff8a8a]Faltam %d unidades para o baralho ser válido.[/color]" % (DeckStore.MIN_UNITS - units)
	stats.text = t


func _on_list_clicked(index: int, _pos: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var cid: String = deck_list.get_item_metadata(index)
	_show(cid)
	_remove(cid)


func _show(cid: String) -> void:
	detail.text = CardView.describe(cards[cid], display_game)


# ================================================================ salvar / abrir

func _fill_load_options() -> void:
	load_opt.clear()
	for deck_id in CardDB.decks:
		if deck_id == "ia_auto":
			continue
		var d: Dictionary = CardDB.decks[deck_id]
		load_opt.add_item(("★ " if DeckStore.is_user_deck(deck_id) else "") + String(d["name"]))
		load_opt.set_item_metadata(load_opt.item_count - 1, deck_id)


func _load_deck(deck_id: String) -> void:
	if not CardDB.decks.has(deck_id):
		return
	deck.clear()
	for cid in CardDB.decks[deck_id]["cards"]:
		deck[cid] = int(deck.get(cid, 0)) + 1
	var nm: String = CardDB.decks[deck_id]["name"]
	# baralhos prontos não são editados: vira uma cópia sua
	name_edit.text = nm if DeckStore.is_user_deck(deck_id) else "Cópia de " + nm
	status.text = ""
	_refresh_deck()


func _new_empty() -> void:
	deck.clear()
	name_edit.text = "Meu baralho"
	status.text = ""
	_refresh_deck()


func _save() -> void:
	var err := DeckStore.save_deck(name_edit.text, _ids())
	if err != "":
		_status(err, false)
		return
	_status("Baralho \"%s\" salvo. Ele aparece no menu com ★." % name_edit.text.strip_edges(), true)
	_fill_load_options()


func _delete() -> void:
	var nm := name_edit.text.strip_edges()
	if not CardDB.decks.has(DeckStore.PREFIX + nm):
		_status("Não há baralho salvo com o nome \"%s\" (os baralhos prontos não podem ser excluídos)." % nm, false)
		return
	DeckStore.delete_deck(nm)
	_status("Baralho \"%s\" excluído." % nm, true)
	_fill_load_options()


func _status(text: String, ok: bool) -> void:
	status.text = text
	status.add_theme_color_override("font_color", Color("#7dff9a") if ok else Color("#ff8a8a"))


# ================================================================ util

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _button(text: String, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = UiProfile.button_h()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _option(items: Array, parent: Control) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size.y = UiProfile.button_h()
	for it in items:
		o.add_item(it)
	o.item_selected.connect(func(_i: int): _apply_filters())
	parent.add_child(o)
	return o
