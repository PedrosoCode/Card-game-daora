class_name PixelCard
extends Control
## Carta em pixel art (160x192): arte exportada do Aseprite (estática ou animada)
## + números e ícones de estado desenhados pelo jogo na barra lateral.
## Efeitos visuais: clarão de dano, tremida, gelo e dissolver (shader).

const SIZE := Vector2(160, 192)
const BAR_X := 141.5            # centro da barra de stats
const Y_ATQ := 34.0
const Y_HP := 65.0
const Y_ARM_ICON := 84.0
const Y_ARM := 98.0
const Y_STATUS := 118.0
const ART_CENTER := Vector2(65.5, 96.5)
const DISSOLVER := preload("res://ui/pixel/dissolver.gdshader")

var atk := 0
var hp := 0
var arm := 0
var statuses: Array[String] = []
var hp_color := Color.WHITE
var show_stats := true          # instantâneas não têm ATQ/HP
var base: Control
var overlay: Control
var _digits: PixelSheet
var _icons: PixelSheet
var _mat: ShaderMaterial
var _tint := Color.WHITE


## key: nome da carta base (ex.: "copas_7") ou de uma especial animada ("lich").
func setup(key: String, special := false) -> PixelCard:
	custom_minimum_size = SIZE
	size = SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_digits = PixelSheet.load_sheet("ui/digitos")
	_icons = PixelSheet.load_sheet("ui/icones")
	if special:
		var a := PixelAnim.new().setup(PixelSheet.load_sheet("especiais/" + key))
		a.play()
		base = a
	else:
		var tr := TextureRect.new()
		tr.texture = load(PixelSheet.RAIZ + "cartas/" + key + ".png")
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		base = tr
	base.use_parent_material = true
	add_child(base)
	overlay = Control.new()
	overlay.size = SIZE
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.use_parent_material = true
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	_mat = ShaderMaterial.new()
	_mat.shader = DISSOLVER
	material = _mat
	return self


func set_stats(a: int, h: int, ar := 0) -> void:
	atk = a
	hp = h
	arm = ar
	overlay.queue_redraw()


func set_status(name: String, on: bool) -> void:
	if on and not statuses.has(name):
		statuses.append(name)
	elif not on:
		statuses.erase(name)
	overlay.queue_redraw()


func _draw_overlay() -> void:
	if not show_stats:
		return
	_digits.draw_text(overlay, str(atk), Vector2(BAR_X, Y_ATQ))
	_digits.draw_text(overlay, str(hp), Vector2(BAR_X, Y_HP), hp_color)
	if arm > 0:
		_icons.draw_slice(overlay, "arm", Vector2(BAR_X, Y_ARM_ICON))
		_digits.draw_text(overlay, str(arm), Vector2(BAR_X, Y_ARM))
	var y := Y_STATUS + 6.0
	for s in statuses:
		_icons.draw_slice(overlay, s, Vector2(BAR_X, y))
		y += 13.0


## Centro da arte em coordenadas globais (onde os efeitos aparecem).
func art_center_global() -> Vector2:
	return get_global_transform() * ART_CENTER


func flash() -> void:
	var tw := create_tween()
	modulate = Color(4, 4, 4)
	tw.tween_property(self, "modulate", _tint, 0.18)


func shake(px := 3) -> void:
	var p0 := position
	var tw := create_tween()
	for d in [Vector2(px, 0), Vector2(-px, 1), Vector2(px - 1, -1), Vector2(-1, 0), Vector2.ZERO]:
		tw.tween_property(self, "position", p0 + d * scale.x, 0.04)


func freeze(on: bool) -> void:
	_tint = Color(0.65, 0.85, 1.35) if on else Color.WHITE
	modulate = _tint


func dissolve(seconds := 0.8) -> void:
	_mat.set_shader_parameter("cell", get_viewport().get_final_transform().get_scale().x * get_global_transform().get_scale().x)
	var tw := create_tween()
	tw.tween_method(func(v: float): _mat.set_shader_parameter("progress", v), 0.0, 1.0, seconds)


func restore() -> void:
	_mat.set_shader_parameter("progress", 0.0)
	freeze(false)
