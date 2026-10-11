class_name Modal
extends Control
## Confirmação simples fora da partida (sombra + painel no centro, botões
## grandes): "Voltar" à esquerda, a ação à direita. Tocar fora cancela.


static func confirm(parent: Control, question: String, ok_text: String, action: Callable) -> Modal:
	var m := Modal.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(m)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			m.queue_free())
	m.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.97)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = Color("#ffd27a")
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var l := Label.new()
	l.text = question
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(minf(440.0, parent.get_viewport_rect().size.x - 80.0), 0)
	l.add_theme_font_size_override("font_size", UiProfile.fs(17))
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	for spec in [["Voltar", func(): m.queue_free()], [ok_text, func():
			m.queue_free()
			action.call()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(150, 44)
		b.add_theme_font_size_override("font_size", UiProfile.fs(18))
		b.pressed.connect(spec[1])
		row.add_child(b)
	return m
