class_name CardView
extends PanelContainer
## Desenho de uma carta. Só lê o estado; nunca altera o jogo.
## `apply_snapshot` permite mostrar um estado intermediário durante animações.
## Duas faces: a completa (FULL_SIZE: desktop e inspeção) e a compacta (celular:
## valor + nome numa linha, HP/ATQ e estados). Entrada pensada para toque:
## o clique vale ao SOLTAR, arrastar rola o ScrollContainer de cima e o toque
## longo equivale ao botão direito (inspecionar / remover).

signal clicked(view: CardView)
signal right_clicked(view: CardView)
signal hovered(view: CardView)

const FULL_SIZE := Vector2(92, 112)
const NAME_HEIGHT := 34.0   # 2 linhas do nome (fonte 12, espaçamento -3)
const DRAG_THRESHOLD := 10.0  # px virtuais: mais que isso é arrasto, não clique
const LONG_PRESS := 0.5       # s segurando = botão direito
const SUIT_COLORS := {
	"copas": Color("#7a2832"),
	"ouros": Color("#8a4a1c"),
	"espadas": Color("#2a3448"),
	"paus": Color("#24452f"),
	"": Color("#3b4250"),
}
const KW_SHORT := {"guardiao": "GUA", "investida": "INV", "alcance": "ALC",
	"furtivo": "FURT", "furia": "FÚRIA", "roubo_vida": "VAMP"}

## Tamanho da carta no tabuleiro e na mão no perfil atual (ver UiProfile).
## No compacto a largura do tabuleiro é recalculada pela tela (set_board_width).
static var SIZE := FULL_SIZE
static var HAND_SIZE := FULL_SIZE
static var compact := false

var card: Card
var game: Game
var face_size := FULL_SIZE
## Marcada pela animação de morte, para nenhuma outra animação a reexibir.
var dead := false
var last_snap: Dictionary = {}
var _sb: StyleBoxFlat
var _top: Label
var _suit: Label
var _hp: Label
var _status: Label
# toque: clique ao soltar, arrasto rola, toque longo = botão direito
var _pressing := false
var _dragged := false
var _long_done := false
var _press_pos := Vector2.ZERO
var _press_id := 0
var _scroll_acc := Vector2.ZERO


static func configure(is_compact: bool) -> void:
	compact = is_compact
	SIZE = Vector2(96, 50) if compact else FULL_SIZE
	HAND_SIZE = Vector2(76, 56) if compact else FULL_SIZE


## Compacto: a largura das cartas do tabuleiro acompanha a largura disponível.
static func set_board_width(w: float) -> void:
	if compact:
		SIZE.x = clampf(floorf(w), 70.0, 110.0)
		HAND_SIZE.x = clampf(floorf(w * 0.8), 64.0, 84.0)


## face: tamanho desta carta (padrão: SIZE). Com altura >= 90 usa a face completa.
func setup(c: Card, g: Game, face := Vector2.ZERO) -> void:
	card = c
	game = g
	face_size = face if face != Vector2.ZERO else SIZE
	custom_minimum_size = face_size
	# PASS: o que a carta não usa (roda do mouse) chega ao ScrollContainer de cima
	mouse_filter = Control.MOUSE_FILTER_PASS
	var full := face_size.y >= 90.0
	_sb = StyleBoxFlat.new()
	_sb.bg_color = SUIT_COLORS.get(c.suit, SUIT_COLORS[""])
	_sb.set_corner_radius_all(7 if full else 5)
	_sb.set_border_width_all(2)
	_sb.border_color = Color(0, 0, 0, 0.55)
	_sb.set_content_margin_all(4 if full else 3)
	add_theme_stylebox_override("panel", _sb)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0 if full else -3)
	add_child(v)
	if full:
		_build_full(v, c)
	else:
		_build_compact(v, c)
	if c.is_unit():
		apply_snapshot(g.snapshot(c))
	mouse_entered.connect(func(): hovered.emit(self))
	gui_input.connect(_on_input)


## Face compacta (celular): "K♥ Nome..." / "HP 8 ATQ 3" / estados.
func _build_compact(v: VBoxContainer, c: Card) -> void:
	var top_size := 15 if face_size.y >= 54.0 else 14
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	if c.is_unit():
		_top = _lbl("", top_size)
		row.add_child(_top)
	else:
		var tag := _lbl("⚡" + String(Game.SUIT_SYMBOLS.get(c.suit, "")), top_size)
		tag.add_theme_color_override("font_color", Color("#ffd27a"))
		row.add_child(tag)
	var nm := _lbl(c.name, 11)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	v.add_child(row)
	if c.is_unit():
		_hp = _lbl("", 11)
		_hp.clip_text = true
		v.add_child(_hp)
		_status = _lbl("", 10)
		_status.clip_text = true
		_status.add_theme_color_override("font_color", Color("#e8e0b0"))
		v.add_child(_status)
	else:
		var kind := _lbl("instantânea", 10)
		kind.add_theme_color_override("font_color", Color("#ffd27a"))
		v.add_child(kind)


func _build_full(v: VBoxContainer, c: Card) -> void:
	if c.is_unit():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top = _lbl("", 17)
		row.add_child(_top)
		_suit = _lbl("", 11)
		_suit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_suit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_suit.modulate = Color(1, 1, 1, 0.8)
		row.add_child(_suit)
		v.add_child(row)
	else:
		# instantânea: ⚡ + naipe do tema no topo (como as unidades); não tem valor nem HP
		var row2 := HBoxContainer.new()
		row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag := _lbl("⚡" + String(Game.SUIT_SYMBOLS.get(c.suit, "")), 17)
		tag.add_theme_color_override("font_color", Color("#ffd27a"))
		row2.add_child(tag)
		var sname := _lbl(String(Game.SUIT_NAMES.get(c.suit, "")), 11)
		sname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sname.clip_text = true
		sname.modulate = Color(1, 1, 1, 0.8)
		row2.add_child(sname)
		v.add_child(row2)

	var nm := _lbl(c.name, 12)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# no máximo 2 linhas: a carta não pode crescer além de SIZE (fileiras, leque, grade).
	# (reticências + quebra automática cortam já na 1ª linha no Godot 4.5; por isso
	# só limita as linhas, com altura explícita e o excesso recortado)
	nm.max_lines_visible = 2
	nm.clip_text = true
	nm.add_theme_constant_override("line_spacing", -3)
	nm.custom_minimum_size = Vector2(FULL_SIZE.x - 12, NAME_HEIGHT)
	v.add_child(nm)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)

	if not c.is_unit():
		var kind := _lbl("instantânea", 11)
		kind.add_theme_color_override("font_color", Color("#ffd27a"))
		v.add_child(kind)
	if c.is_unit():
		_hp = _lbl("", 11)
		_hp.clip_text = true
		v.add_child(_hp)
		_status = _lbl("", 10)
		# status longo (ex.: "ESC 1 VEN 2 INV FÚRIA") é cortado em vez de alargar a carta
		_status.clip_text = true
		_status.add_theme_color_override("font_color", Color("#e8e0b0"))
		v.add_child(_status)


## snap: o dicionário de `Game.snapshot` (hp, max_hp, armor, poison, bleed, value, suit, atk).
func apply_snapshot(snap: Dictionary) -> void:
	if not card.is_unit():
		return
	last_snap = snap
	var ev: int = snap["value"]
	var suit: String = snap["suit"]
	_top.text = Game.card_label(ev, suit)
	_top.remove_theme_color_override("font_color")
	if ev > card.base_value:
		_top.add_theme_color_override("font_color", Color("#a8ffa8"))
	elif ev < card.base_value:
		_top.add_theme_color_override("font_color", Color("#ffaaaa"))
	if _suit != null:
		_suit.text = Game.SUIT_NAMES[suit]
	_sb.bg_color = SUIT_COLORS.get(suit, SUIT_COLORS[""])

	var hp: int = snap["hp"]
	var base_hp := int(card.def.get("hp", 0))
	_hp.text = ("HP %d  ATQ %d" if _suit != null else "HP %d ATQ %d") % [hp, int(snap["atk"])]
	_hp.remove_theme_color_override("font_color")
	if hp < base_hp:
		_hp.add_theme_color_override("font_color", Color("#ffb0b0"))
	elif hp > base_hp:
		_hp.add_theme_color_override("font_color", Color("#a8ffa8"))

	var st := PackedStringArray()
	if int(snap["armor"]) > 0:
		st.append("ARM %d" % int(snap["armor"]))
	if int(snap.get("shield", 0)) > 0:
		st.append("ESC %d" % int(snap["shield"]))
	if int(snap.get("frozen", 0)) > 0:
		st.append("❄%d" % int(snap["frozen"]))
	if bool(snap.get("silenced", false)):
		st.append("MUDA")
	if int(snap["poison"]) > 0:
		st.append("VEN %d" % int(snap["poison"]))
	if int(snap["bleed"]) > 0:
		st.append("SNG %d" % int(snap["bleed"]))
	if not bool(snap.get("silenced", false)):
		for k in card.keywords:
			st.append(KW_SHORT.get(k, k))
	var timers: Dictionary = snap.get("timers", {})
	for k in timers:
		if int(timers[k]) > 0:
			st.append("◷%d" % int(timers[k]))
	if card.on_board() and card.exhausted:
		st.append("zZ")
	if game.is_sealed(card):
		st.append("SELADA")
	_status.text = " ".join(st)


## "", "selected", "target", "ready"
func set_state(state: String) -> void:
	match state:
		"selected":
			_sb.border_color = Color("#ffd84a")
			_sb.set_border_width_all(4 if face_size.y >= 90.0 else 3)
		"target":
			_sb.border_color = Color("#ff5a5a")
			_sb.set_border_width_all(4 if face_size.y >= 90.0 else 3)
		"ready":
			_sb.border_color = Color("#6fd3ff")
			_sb.set_border_width_all(2)
		_:
			_sb.border_color = Color(0, 0, 0, 0.55)
			_sb.set_border_width_all(2)


## Texto completo da carta (BBCode) para o painel de detalhes.
static func describe(c: Card, game: Game) -> String:
	var t := "[b]%s[/b]\n" % c.name
	if c.is_unit():
		var ev := game.effective_value(c)
		t += "%s  (%s de %s)" % [Game.card_label(ev, c.suit), Game.value_label(ev), Game.SUIT_NAMES[c.suit]]
		if ev != c.base_value:
			t += "  (base %s)" % Game.value_label(c.base_value)
		t += "\nHP %d    ATQ %d    Armadura %d" % [c.hp, game.effective_atk(c), c.armor]
		if c.poison > 0:
			t += "\n[color=#8fe37a]Veneno %d[/color] (1 de dano por turno durante %d turnos, ignora armadura)" % [c.poison, c.poison]
		if c.bleed > 0:
			t += "\n[color=#ff7a7a]Sangramento %d[/color] (1 de dano por turno durante %d turnos, ignora armadura)" % [c.bleed, c.bleed]
		if c.shield > 0:
			t += "\n[color=#7ac8ff]Escudo %d[/color] (anula por completo a próxima instância de dano)" % c.shield
		if c.frozen > 0 or c.stunned:
			t += "\n[color=#c08aff]Congelada[/color] (não ataca nem ativa%s)" % (" neste turno" if c.stunned else " no próximo turno")
		if c.silenced:
			t += "\n[color=#c08aff]Silenciada[/color] (sem habilidades, auras e palavras-chave)"
		if not c.silenced:
			for k in c.keywords:
				t += "\n[i]%s[/i]: %s" % [Game.KEYWORD_NAMES.get(k, k), Game.KEYWORD_HELP.get(k, "")]
		for k in c.timers:
			var left := int(c.timers[k])
			t += "\n[color=#9ad8ff]◷ Temporizador: %s[/color]" % (
				"pronto" if left <= 0 else "dispara em %d turno(s) seu(s)" % left)
		if c.on_board():
			t += "\n[color=#9aa4b8]%s%s[/color]" % [Game.ROW_NAMES[c.row], " - exausta" if c.exhausted else ""]
		else:
			t += "\n[color=#7ac8ff]Na Cadeia de Comando entra com +%d de armadura.[/color]" % Game.command_armor(c)
	else:
		t += "[color=#ffd27a]⚡ Instantânea[/color] de %s %s\n[i]Resolve na hora e vai para o cemitério: não entra no tabuleiro nem conta no poker.[/i]" % [
			Game.SUIT_SYMBOLS.get(c.suit, ""), Game.SUIT_NAMES.get(c.suit, "")]
	t += "\n\n" + String(c.def.get("text", ""))
	return t


func center() -> Vector2:
	return global_position + size * 0.5


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_dragged = false
				_long_done = false
				_press_pos = mb.global_position
				_scroll_acc = Vector2.ZERO
				_press_id += 1
				if is_inside_tree():
					get_tree().create_timer(LONG_PRESS).timeout.connect(_on_long_press.bind(_press_id))
			elif _pressing:
				_pressing = false
				if not _dragged and not _long_done:
					clicked.emit(self)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			right_clicked.emit(self)
			accept_event()
	elif event is InputEventMouseMotion and _pressing:
		var mm := event as InputEventMouseMotion
		if not _dragged and mm.global_position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragged = true
		if _dragged:
			_drag_scroll(mm.relative)
		accept_event()


## Arrastar uma carta rola a lista/mão em que ela está (celular).
func _drag_scroll(rel: Vector2) -> void:
	var n := get_parent()
	while n != null and not n is ScrollContainer:
		n = n.get_parent()
	if n == null:
		return
	var sc := n as ScrollContainer
	_scroll_acc -= rel
	var step := Vector2i(int(_scroll_acc.x), int(_scroll_acc.y))
	_scroll_acc -= Vector2(step)
	sc.scroll_horizontal += step.x
	sc.scroll_vertical += step.y


func _on_long_press(id: int) -> void:
	if _pressing and id == _press_id and not _dragged:
		_long_done = true
		right_clicked.emit(self)


func _lbl(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
