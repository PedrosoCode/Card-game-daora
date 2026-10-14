class_name UiProfile
## Perfil de tela e preferências de exibição.
##
## "Compacto" (celular ou tela baixa): a tela base é bem menor (COMPACT_BASE),
## então cada pixel virtual fica fisicamente maior, e as telas usam um layout
## próprio (cartas compactas, botões grandes, menu ☰).
## "Amplo" (desktop, tablet): a tela base de sempre, 1600×1000.
##
## A escolha automática usa o tamanho físico da tela em dp (a menor dimensão
## abaixo de COMPACT_BELOW_DP = celular). Dá para forçar em Opções no menu ou
## com o argumento de linha de comando layout=compact|wide (testes).

const WIDE_BASE := Vector2i(1600, 1000)
const COMPACT_BASE := Vector2i(720, 420)
const COMPACT_BELOW_DP := 600.0
const SETTINGS_PATH := "user://settings.cfg"
const LAYOUTS := ["auto", "compact", "wide"]
const LAYOUT_NAMES := ["Automático", "Celular", "Computador"]

static var compact := false
static var pixel := true          # visual das cartas em pixel art (Opções)
static var _done := false
static var _cfg: ConfigFile


## Chamado uma vez no início (App ou a partida rodando sozinha nos testes).
static func setup(tree: SceneTree) -> void:
	if _done:
		return
	_done = true
	apply_layout(tree)
	_apply_window_pref()


## Aplica o layout da preferência (Opções) ou do argumento layout=. A tela atual
## precisa ser refeita depois (o menu faz isso ao trocar nas Opções).
static func apply_layout(tree: SceneTree) -> void:
	var pref := layout_pref()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("layout="):
			pref = a.substr(7)
	compact = pref == "compact" or (pref == "auto" and auto_compact())
	pixel = bool(get_pref("pixel", true))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("pixel="):
			pixel = a.substr(6) != "0"
	tree.root.content_scale_size = COMPACT_BASE if compact else WIDE_BASE
	tree.root.theme = _touch_theme() if compact else null
	refresh_cards(tree)


## Pixels da tela por pixel virtual (stretch canvas_items + expand).
static func phys_scale(tree: SceneTree) -> float:
	var ws := Vector2(tree.root.size)
	var base := Vector2(tree.root.content_scale_size)
	if base.x <= 0.0 or base.y <= 0.0 or ws.x <= 0.0 or ws.y <= 0.0:
		return 1.0
	return minf(ws.x / base.x, ws.y / base.y) * tree.root.content_scale_factor


## Recalcula o tamanho das cartas (a escala da tela muda com a janela).
static func refresh_cards(tree: SceneTree) -> void:
	CardView.configure(compact, phys_scale(tree), pixel)


## Celular? Menor dimensão da tela, em dp, abaixo de COMPACT_BELOW_DP.
static func auto_compact() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var scr := DisplayServer.screen_get_size()
	if scr.x <= 0 or scr.y <= 0:
		return false
	return float(mini(scr.x, scr.y)) / dp_scale() < COMPACT_BELOW_DP


## Pixels físicos por dp: Android usa a densidade real; web e desktop usam a
## escala da tela (devicePixelRatio na web).
static func dp_scale() -> float:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	return maxf(1.0, DisplayServer.screen_get_scale())


## Tamanho de fonte: no compacto as fontes grandes encolhem (a tela base é menor),
## mas nada fica abaixo de 11.
static func fs(wide_size: int) -> int:
	if not compact:
		return wide_size
	if wide_size <= 13:
		return maxi(11, wide_size - 1)
	if wide_size <= 18:
		return wide_size - 2
	return int(round(wide_size * 0.72))


## Altura mínima de botão (alvo de toque).
static func button_h() -> float:
	return 36.0 if compact else 34.0


# ================================================================ preferências

static func _settings() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(SETTINGS_PATH)
	return _cfg


static func get_pref(key: String, default: Variant) -> Variant:
	return _settings().get_value("ui", key, default)


static func set_pref(key: String, value: Variant) -> void:
	_settings().set_value("ui", key, value)
	_settings().save(SETTINGS_PATH)


static func layout_pref() -> String:
	var p := String(get_pref("layout", "auto"))
	return p if LAYOUTS.has(p) else "auto"


# ================================================================ tela cheia

## Android já roda em tela cheia (modo imersivo): lá não há o que alternar.
static func can_toggle_fullscreen() -> bool:
	return not (OS.has_feature("android") or OS.has_feature("ios")) and DisplayServer.get_name() != "headless"


static func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func set_fullscreen(on: bool) -> void:
	if not can_toggle_fullscreen():
		return
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		if OS.has_feature("web"):
			# celular no navegador: tenta travar em paisagem (só funciona em tela cheia)
			JavaScriptBridge.eval("try{screen.orientation.lock('landscape').catch(function(){})}catch(e){}")
	else:
		# no desktop volta maximizada (a janela "cheia" que o sistema permite)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if OS.has_feature("web") else DisplayServer.WINDOW_MODE_MAXIMIZED)
	if not OS.has_feature("web"):
		set_pref("fullscreen", on)


static func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


## Desktop: abre em tela cheia (padrão nos builds exportados) ou como o jogador
## deixou da última vez. Web precisa de um clique (regra do navegador); testes
## (-s script) não mexem na janela.
static func _apply_window_pref() -> void:
	if not can_toggle_fullscreen() or OS.has_feature("web"):
		return
	var args := OS.get_cmdline_args()
	if args.has("-s") or args.has("--script"):
		return
	var saved: Variant = get_pref("fullscreen", null)
	var on: bool = (not OS.has_feature("editor")) if saved == null else bool(saved)
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## F11 ou Alt+Enter alternam a tela cheia (desktop e web).
static func handle_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var k := event as InputEventKey
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		toggle_fullscreen()
		return true
	return false


# ================================================================ tema de toque

## Itens de lista e menus suspensos mais altos (dedo), fonte base menor (a tela
## base do compacto é pequena, mas cada pixel é grande).
static func _touch_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_constant("v_separation", "PopupMenu", 18)
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_constant("v_separation", "ItemList", 10)
	t.set_font_size("font_size", "TabContainer", 13)
	t.set_font_size("font_size", "LineEdit", 15)
	# barras de rolagem mais grossas para o dedo
	for sb_name in ["HScrollBar", "VScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1, 1, 1, 0.06)
		track.set_corner_radius_all(4)
		track.set_content_margin_all(5)
		t.set_stylebox("scroll", sb_name, track)
		for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var g := StyleBoxFlat.new()
			g.bg_color = Color(1, 1, 1, 0.28 if st == "grabber" else 0.45)
			g.set_corner_radius_all(4)
			g.set_content_margin_all(5)
			t.set_stylebox(st, sb_name, g)
	return t
