extends SceneTree
## Galeria de pixel art: abre pelas Opções, passa pelas abas, dispara os efeitos
## sobre a carta e tira screenshots (user://pixel_<n>_<tag>.png).
##   godot --path . --disable-vsync --resolution 1920x1080 -s res://tests/pixel_gallery_smoke.gd

var app: Control
var shots := 0
var ok := true


func _initialize() -> void:
	app = load("res://ui/app.tscn").instantiate()
	root.add_child(app)
	_run()


func _run() -> void:
	await _frames(5)
	app.show_options()
	await _frames(3)
	app.show_pixel_gallery()
	await _frames(8)
	var g = app.screen
	_check(g is PixelGallery, "a galeria deveria abrir")
	_check(root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "a galeria usa escala inteira")
	await create_timer(0.3).timeout
	await _shot("especiais_a")
	await create_timer(0.45).timeout
	await _shot("especiais_b")
	g._show_base()
	await _frames(4)
	await _shot("base")
	for i in 3:
		g.alvo = i
		g._show_fx()
		await _frames(4)
		for act in ["_act_attack", "_act_fire", "_act_heal", "_act_poison", "_act_armor", "_act_freeze", "_act_death"]:
			g.call(act)
			await create_timer(0.22).timeout
			if i == 0 or act in ["_act_attack", "_act_death"]:
				await _shot("fx_%d_%s" % [i, act.substr(5)])
			await create_timer(0.9).timeout
		await _shot("fx_%d_fim" % i)
	g.go_back()
	await _frames(6)
	_check(root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "ao sair volta a escala normal")
	print("GALERIA: ", "OK" if ok else "FALHOU")
	quit(0 if ok else 1)


func _check(cond: bool, what: String) -> void:
	if not cond:
		push_error("Falhou: " + what)
		ok = false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(tag: String) -> void:
	await _frames(1)
	var img := root.get_texture().get_image()
	if img == null:
		return
	img.save_png("user://pixel_%02d_%s.png" % [shots, tag])
	shots += 1
