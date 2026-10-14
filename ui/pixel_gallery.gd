class_name PixelGallery
extends Control
## Galeria de teste da arte em pixel (Opções > Galeria de pixel art).
## Roda em escala INTEIRA de pixels (tela base 960x540): cada pixel da arte vira
## um bloco exato de pixels da tela, sem borrar. Ao sair, volta o layout normal.

signal back_requested

const NAIPES := ["ouros", "copas", "espadas", "paus"]
const FX := ["corte", "impacto", "fogo", "cura", "veneno", "escudo", "gelo", "morte"]
const GOLD := Color("#ffd27a")
const ALVOS := [["Lich", "lich", true, 2, 4], ["Mercador-Rei", "mercador_rei", true, 2, 5], ["7 de Copas", "copas_7", false, 1, 3]]

var body: Control
var card: PixelCard
var card_holder: Control
var zoom := 2
var alvo := 0


func _ready() -> void:
	var w := get_tree().root
	w.content_scale_size = Vector2i(960, 540)
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#14161b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	v.add_child(bar)
	var title := Label.new()
	title.text = "  GALERIA PIXEL ART (teste)"
	title.add_theme_color_override("font_color", GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	for spec in [["Cartas base", _show_base], ["Especiais", _show_specials], ["Efeitos", _show_fx], ["Voltar", go_back]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(110, 34)
		b.pressed.connect(spec[1])
		bar.add_child(b)
	body = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_show_specials.call_deferred()


func _exit_tree() -> void:
	var w := get_tree().root
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	UiProfile.apply_layout(get_tree())


## Botão "voltar" do Android.
func go_back() -> void:
	back_requested.emit()


func _clear() -> void:
	for c in body.get_children():
		c.queue_free()
	card = null


## Maior zoom inteiro que cabe (altura útil / altura da carta).
func _fit_zoom(cols: int) -> int:
	var s := body.size
	return clampi(mini(int((s.x - 20) / (cols * 170.0)), int((s.y - 30) / 192.0)), 1, 3)


# ---------------------------------------------------------------- cartas base

func _show_base() -> void:
	_clear()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.custom_minimum_size.x = body.size.x - 20
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	scroll.add_child(flow)
	var keys := []
	for n in NAIPES:
		for val in range(2, 15):
			keys.append("%s_%d" % [n, val])
	for n in NAIPES:
		keys.append("instantanea_" + n)
	keys.append("verso")
	for k in keys:
		var tr := TextureRect.new()
		tr.texture = load(PixelSheet.RAIZ + "cartas/" + k + ".png")
		tr.mouse_filter = Control.MOUSE_FILTER_PASS
		flow.add_child(tr)


# ---------------------------------------------------------------- especiais

func _show_specials() -> void:
	_clear()
	zoom = _fit_zoom(2)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	body.add_child(row)
	for spec in [["Lich (A de Paus)", "lich", 2, 4], ["Mercador-Rei (K de Ouros)", "mercador_rei", 2, 5]]:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		col.add_child(_holder(spec[1], true, spec[2], spec[3]))


## Carta dentro de um Control simples (containers zeram a escala dos filhos).
func _holder(key: String, special: bool, a: int, h: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = PixelCard.SIZE * zoom
	var c := PixelCard.new().setup(key, special)
	c.set_stats(a, h)
	c.scale = Vector2(zoom, zoom)
	holder.add_child(c)
	card = c
	card_holder = holder
	return holder


# ---------------------------------------------------------------- efeitos sobre uma carta

func _show_fx() -> void:
	_clear()
	zoom = _fit_zoom(2)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 20)
	body.add_child(row)
	var pad := Control.new()
	pad.custom_minimum_size.x = 12
	row.add_child(pad)
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(left)
	var a: Array = ALVOS[alvo]
	left.add_child(_holder(a[1], a[2], a[3], a[4]))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	var pick := HBoxContainer.new()
	right.add_child(pick)
	for i in ALVOS.size():
		var b := Button.new()
		b.text = ALVOS[i][0]
		b.toggle_mode = true
		b.button_pressed = i == alvo
		b.custom_minimum_size = Vector2(0, 34)
		b.pressed.connect(func():
			alvo = i
			_show_fx())
		pick.add_child(b)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	right.add_child(grid)
	for spec in [["Atacar (corte)", _act_attack], ["Bola de Fogo", _act_fire], ["Curar", _act_heal],
			["Envenenar", _act_poison], ["Armadura", _act_armor], ["Congelar", _act_freeze],
			["Destruir", _act_death], ["Restaurar", _show_fx]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(150, 38)
		b.pressed.connect(spec[1])
		grid.add_child(b)
	var l := Label.new()
	l.text = "Efeitos em laço"
	l.add_theme_color_override("font_color", GOLD)
	right.add_child(l)
	var loops := HFlowContainer.new()
	loops.add_theme_constant_override("h_separation", 8)
	right.add_child(loops)
	for n in FX:
		var cell := VBoxContainer.new()
		var anim := PixelAnim.new().setup(PixelSheet.load_sheet("fx/" + n), true)
		anim.play()
		cell.add_child(anim)
		var nl := Label.new()
		nl.text = n
		nl.add_theme_font_size_override("font_size", 11)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(nl)
		loops.add_child(cell)


## Toca um efeito por cima da carta (mesmo zoom); devolve a animação (sinal finished).
func _fx(name: String) -> PixelAnim:
	var anim := PixelAnim.new().setup(PixelSheet.load_sheet("fx/" + name), false)
	add_child(anim)
	anim.scale = Vector2(zoom, zoom)
	anim.position = (card.art_center_global() - anim.size * zoom / 2.0 - global_position).round()
	anim.finished.connect(anim.queue_free)
	anim.play()
	return anim


## Número subindo (dano em vermelho, cura em verde) com a fonte de dígitos.
func _float_number(text: String, color: Color) -> void:
	var digits := PixelSheet.load_sheet("ui/digitos")
	var n := Control.new()
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	n.draw.connect(func(): digits.draw_text(n, text, Vector2.ZERO, color))
	n.scale = Vector2(zoom * 2, zoom * 2)
	add_child(n)
	n.position = (card.art_center_global() - global_position).round()
	var tw := create_tween().set_parallel()
	tw.tween_property(n, "position:y", n.position.y - 50 * zoom, 0.8)
	tw.tween_property(n, "modulate:a", 0.0, 0.3).set_delay(0.5)
	tw.chain().tween_callback(n.queue_free)


func _damage(amount: int) -> void:
	var absorb := mini(card.arm, amount)
	card.set_stats(card.atk, maxi(0, card.hp - (amount - absorb)), card.arm - absorb)
	card.hp_color = Color("#ff8a8a")
	card.flash()
	card.shake(3)
	_float_number("-%d" % amount, Color("#ff5a4a"))


func _act_attack() -> void:
	if card == null:
		return
	var a := _fx("corte")
	await a.finished
	if card == null:
		return
	_fx("impacto")
	_damage(2)


func _act_fire() -> void:
	if card == null:
		return
	_fx("fogo")
	await get_tree().create_timer(0.25).timeout
	if card != null:
		_damage(3)


func _act_heal() -> void:
	if card == null:
		return
	_fx("cura")
	card.hp_color = Color("#a8ffa8")
	card.set_stats(card.atk, card.hp + 2, card.arm)
	_float_number("+2", Color("#7dff9a"))


func _act_poison() -> void:
	if card == null:
		return
	_fx("veneno")
	card.set_status("veneno", true)


func _act_armor() -> void:
	if card == null:
		return
	_fx("escudo")
	card.set_stats(card.atk, card.hp, card.arm + 3)


func _act_freeze() -> void:
	if card == null:
		return
	_fx("gelo")
	card.freeze(true)
	card.set_status("congelado", true)


func _act_death() -> void:
	if card == null:
		return
	_fx("morte")
	card.dissolve(0.9)
