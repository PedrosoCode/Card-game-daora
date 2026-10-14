class_name PixelAnim
extends TextureRect
## Toca uma PixelSheet quadro a quadro (durações do Aseprite), 1:1 em pixels.

signal finished

var sheet: PixelSheet
var loop := true
var playing := false
var _i := 0
var _t := 0.0
var _atlas := AtlasTexture.new()


func setup(s: PixelSheet, do_loop := true) -> PixelAnim:
	sheet = s
	loop = do_loop
	_atlas.atlas = s.texture
	texture = _atlas
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = s.frame_size()
	size = s.frame_size()
	_show(0)
	return self


func play() -> void:
	playing = true
	_i = 0
	_t = 0.0
	_show(0)


func _process(delta: float) -> void:
	if not playing or sheet == null:
		return
	_t += delta
	while _t >= sheet.durations[_i]:
		_t -= sheet.durations[_i]
		_i += 1
		if _i >= sheet.regions.size():
			if not loop:
				playing = false
				finished.emit()
				return
			_i = 0
		_show(_i)


func _show(i: int) -> void:
	_atlas.region = sheet.regions[i]
