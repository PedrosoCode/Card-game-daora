class_name PixelSheet
extends RefCounted
## Folha de quadros exportada pelo Aseprite (PNG + JSON "json-array"), gerada por
## tools/pixel_art/gerar.py: textura, regiões e durações dos quadros e fatias
## nomeadas (ícones, dígitos). Sem JSON, a textura inteira é um quadro só.

const RAIZ := "res://assets/pixel/"
static var _cache := {}

var texture: Texture2D
var regions: Array[Rect2] = []
var durations: Array[float] = []
var slices := {}   # nome -> Rect2


## path relativo a assets/pixel, sem extensão (ex.: "fx/fogo", "especiais/lich").
static func load_sheet(path: String) -> PixelSheet:
	if _cache.has(path):
		return _cache[path]
	var s := PixelSheet.new()
	s.texture = load(RAIZ + path + ".png")
	var f := FileAccess.open(RAIZ + path + ".json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			for fr: Dictionary in d.get("frames", []):
				var r: Dictionary = fr["frame"]
				s.regions.append(Rect2(r["x"], r["y"], r["w"], r["h"]))
				s.durations.append(float(fr.get("duration", 100)) / 1000.0)
			for sl: Dictionary in d.get("meta", {}).get("slices", []):
				var b: Dictionary = sl["keys"][0]["bounds"]
				s.slices[String(sl["name"])] = Rect2(b["x"], b["y"], b["w"], b["h"])
	if s.regions.is_empty() and s.texture != null:
		s.regions.append(Rect2(Vector2.ZERO, s.texture.get_size()))
		s.durations.append(0.1)
	_cache[path] = s
	return s


static func exists(path: String) -> bool:
	return ResourceLoader.exists(RAIZ + path + ".png")


func frame_size() -> Vector2:
	return regions[0].size


## Desenha um texto com as fatias (dígitos, + e -) centrado em `center`.
func draw_text(ci: CanvasItem, text: String, center: Vector2, color := Color.WHITE, gap := 2.0) -> void:
	var w := 0.0
	for ch in text:
		w += (slices[ch] as Rect2).size.x + gap
	w -= gap
	var x := roundf(center.x - w / 2.0)
	for ch in text:
		var r: Rect2 = slices[ch]
		ci.draw_texture_rect_region(texture, Rect2(Vector2(x, roundf(center.y - r.size.y / 2.0)), r.size), r, color)
		x += r.size.x + gap


func draw_slice(ci: CanvasItem, name: String, center: Vector2, color := Color.WHITE) -> void:
	var r: Rect2 = slices[name]
	ci.draw_texture_rect_region(texture, Rect2((center - r.size / 2.0).round(), r.size), r, color)
