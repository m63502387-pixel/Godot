extends CanvasLayer
# Весь интерфейс строится кодом: джойстик, кнопки, полоски, рюкзак, телефон, экран конца.

signal look(rel: Vector2)
signal action
signal ignite
signal bag_toggled
signal sprint_toggled(on: bool)
signal slot_tapped(id: String)
signal phone_done
signal restart
signal sens_changed(v: float)
signal sound_changed(on: bool)
signal vibro_changed(on: bool)
signal menu_requested

const SLOT_COUNT := 8
const SENS_VALUES := [0.0030, 0.0045, 0.0065, 0.0090]
const SENS_NAMES := ["Низкая", "Средняя", "Высокая", "Очень высокая"]

var move_vec := Vector2.ZERO
var sprint_on := false
var bag_open := false
var phone_visible := false
var end_visible := false
var pause_open := false
var sens_idx := 1
var sound_on := true
var vibro_on := true

var root: Control
var touches := {}
var stick_origin := Vector2.ZERO
var toast_t := 0.0
var _wf := 1.0
var _sf := 1.0

var warm_bg: ColorRect
var warm_fill: ColorRect
var warm_lbl: Label
var stam_bg: ColorRect
var stam_fill: ColorRect
var obj_lbl: Label
var clock_lbl: Label
var arrow: Polygon2D
var dist_lbl: Label
var cross: ColorRect
var prompt_lbl: Label
var toast_lbl: Label
var btn_action: Panel
var btn_fire: Panel
var btn_run: Panel
var btn_bag: Panel
var stick_base: Panel
var stick_knob: Panel
var frost: ColorRect
var frost_mat: ShaderMaterial
var phone_panel: Panel
var phone_from: Label
var phone_msg: Label
var phone_btn: Panel
var bag_panel: Panel
var bag_title: Label
var slots: Array = []
var slot_ids: Array = []
var end_panel: Control
var end_title: Label
var end_sub: Label
var end_btn: Panel
var fade_rect: ColorRect
var btn_pause: Panel
var hint_lbl: Label
var pause_panel: Panel
var pause_btns: Array = []


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


# ---------- построение ----------

func _sb(c: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	return s


func _rect(parent: Node, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _lbl(parent: Node, text: String, fs: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _mk_panel(parent: Node, c: Color, r: int) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _sb(c, r))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _mk_btn(parent: Node, text: String, fs: int, c: Color, r := 18) -> Panel:
	var p := _mk_panel(parent, c, r)
	var l := _lbl(p, text, fs)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.set_meta("lbl", l)
	return p


func _build() -> void:
	# морозный экран
	frost = ColorRect.new()
	frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float cold = 0.0;
uniform float haze = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.3, 1.0)) * 1.5;
	float v = smoothstep(0.3, 1.1, d) * cold;
	vec3 c = mix(vec3(0.8, 0.9, 1.0), vec3(1.0), haze);
	float a = clamp(v * 0.9 + haze * 0.12, 0.0, 0.95);
	COLOR = vec4(c, a);
}
"""
	frost_mat = ShaderMaterial.new()
	frost_mat.shader = sh
	frost.material = frost_mat
	root.add_child(frost)

	warm_bg = _rect(root, Color(0, 0, 0, 0.5))
	warm_fill = _rect(root, Color(1.0, 0.55, 0.2))
	warm_lbl = _lbl(root, "Тепло", 16)
	stam_bg = _rect(root, Color(0, 0, 0, 0.4))
	stam_fill = _rect(root, Color(0.4, 0.8, 1.0))
	obj_lbl = _lbl(root, "", 20)
	obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clock_lbl = _lbl(root, "18:30", 28)
	arrow = Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, -18), Vector2(13, 14), Vector2(0, 7), Vector2(-13, 14)])
	arrow.color = Color(1.0, 0.85, 0.3)
	arrow.visible = false
	root.add_child(arrow)
	dist_lbl = _lbl(root, "", 18)
	dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross = _rect(root, Color(1, 1, 1, 0.6))
	prompt_lbl = _lbl(root, "", 26, Color(1.0, 0.95, 0.6))
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl = _lbl(root, "", 24)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_lbl.visible = false

	stick_base = _mk_panel(root, Color(1, 1, 1, 0.10), 90)
	stick_knob = _mk_panel(root, Color(1, 1, 1, 0.28), 40)
	stick_base.visible = false
	stick_knob.visible = false

	btn_action = _mk_btn(root, "ДЕЙСТВИЕ", 20, Color(0.2, 0.5, 0.9, 0.55), 65)
	btn_fire = _mk_btn(root, "ОГОНЬ", 20, Color(0.9, 0.4, 0.1, 0.55), 30)
	btn_run = _mk_btn(root, "БЕГ", 20, Color(0.3, 0.3, 0.3, 0.55), 30)
	btn_bag = _mk_btn(root, "РЮКЗАК", 18, Color(0.3, 0.3, 0.3, 0.55), 20)

	# телефон
	phone_panel = _mk_panel(root, Color(0.08, 0.09, 0.12, 0.96), 28)
	phone_panel.visible = false
	var pt := _lbl(phone_panel, "Сообщения", 20, Color(0.7, 0.8, 1.0))
	pt.position = Vector2(26, 14)
	phone_from = _lbl(phone_panel, "", 22, Color(1.0, 0.8, 0.9))
	phone_from.position = Vector2(26, 56)
	phone_msg = _lbl(phone_panel, "", 26)
	phone_msg.position = Vector2(26, 100)
	phone_msg.custom_minimum_size = Vector2(470, 0)
	phone_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phone_btn = _mk_btn(phone_panel, "Убрать телефон", 24, Color(0.2, 0.6, 0.35, 0.95), 18)

	# рюкзак
	bag_panel = _mk_panel(root, Color(0.06, 0.07, 0.10, 0.94), 24)
	bag_panel.visible = false
	bag_title = _lbl(bag_panel, "Рюкзак  (тап по шоколадке — съесть, тап вне окна — закрыть)", 18, Color(0.8, 0.9, 1.0))
	bag_title.position = Vector2(24, 14)
	for i in range(SLOT_COUNT):
		var sp := _mk_panel(bag_panel, Color(0.2, 0.22, 0.28, 0.95), 14)
		var l := _lbl(sp, "", 18)
		l.position = Vector2(8, 8)
		l.custom_minimum_size = Vector2(134, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sp.set_meta("lbl", l)
		slots.append(sp)
		slot_ids.append("")

	btn_pause = _mk_btn(root, "ПАУЗА", 18, Color(0.3, 0.3, 0.3, 0.55), 20)
	hint_lbl = _lbl(root, "", 20, Color(0.8, 0.92, 1.0))
	pause_panel = _mk_panel(root, Color(0.06, 0.07, 0.10, 0.95), 24)
	pause_panel.visible = false
	var ptl := _lbl(pause_panel, "Пауза", 30, Color(0.8, 0.9, 1.0))
	ptl.position = Vector2(40, 14)
	var pcols := [Color(0.2, 0.55, 0.3, 0.95), Color(0.25, 0.3, 0.45, 0.95), Color(0.25, 0.3, 0.45, 0.95), Color(0.25, 0.3, 0.45, 0.95), Color(0.6, 0.2, 0.2, 0.95), Color(0.3, 0.3, 0.38, 0.95)]
	var ptexts := ["Продолжить", "", "", "", "Начать заново", "В главное меню"]
	for i in range(6):
		pause_btns.append(_mk_btn(pause_panel, ptexts[i], 22, pcols[i], 16))
	_refresh_pause_texts()

	# конец игры
	end_panel = Control.new()
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.visible = false
	root.add_child(end_panel)
	var dark := _rect(end_panel, Color(0, 0, 0, 0.8))
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_title = _lbl(end_panel, "", 54)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_sub = _lbl(end_panel, "", 24)
	end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_btn = _mk_btn(end_panel, "Заново", 28, Color(0.2, 0.5, 0.9, 0.95), 20)

	fade_rect = _rect(root, Color(0, 0, 0, 0))


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var w := s.x
	var h := s.y
	frost.size = s
	fade_rect.size = s
	end_panel.size = s

	warm_bg.position = Vector2(20, 16)
	warm_bg.size = Vector2(290, 28)
	warm_fill.position = Vector2(23, 19)
	warm_fill.size = Vector2(284.0 * _wf, 22)
	warm_lbl.position = Vector2(30, 13)
	stam_bg.position = Vector2(20, 50)
	stam_bg.size = Vector2(290, 8)
	stam_fill.position = Vector2(21, 51)
	stam_fill.size = Vector2(288.0 * _sf, 6)
	obj_lbl.position = Vector2(20, 66)
	obj_lbl.custom_minimum_size = Vector2(minf(w * 0.42, 520.0), 0)
	clock_lbl.position = Vector2(w - 130, 12)
	btn_bag.position = Vector2(w - 150, 62)
	btn_bag.size = Vector2(130, 52)
	arrow.position = Vector2(w / 2.0, 46)
	dist_lbl.position = Vector2(w / 2.0 - 110, 68)
	dist_lbl.custom_minimum_size = Vector2(220, 0)
	cross.position = s / 2.0 - Vector2(3, 3)
	cross.size = Vector2(6, 6)
	prompt_lbl.position = Vector2(w / 2.0 - 300, h * 0.6)
	prompt_lbl.custom_minimum_size = Vector2(600, 0)
	toast_lbl.position = Vector2(w / 2.0 - 350, h * 0.17)
	toast_lbl.custom_minimum_size = Vector2(700, 0)

	btn_action.size = Vector2(130, 130)
	btn_action.position = Vector2(w - 170, h - 170)
	btn_fire.size = Vector2(130, 100)
	btn_fire.position = Vector2(w - 320, h - 135)
	btn_run.size = Vector2(110, 80)
	btn_run.position = Vector2(w - 160, h - 275)

	phone_panel.size = Vector2(520, 320)
	phone_panel.position = (s - phone_panel.size) / 2.0
	phone_btn.size = Vector2(300, 66)
	phone_btn.position = Vector2(110, 230)

	bag_panel.size = Vector2(700, 340)
	bag_panel.position = (s - bag_panel.size) / 2.0
	for i in range(SLOT_COUNT):
		var sp: Panel = slots[i]
		sp.size = Vector2(150, 120)
		sp.position = Vector2(24 + (i % 4) * 162, 60 + (i / 4) * 132)

	btn_pause.position = Vector2(w - 150, 122)
	btn_pause.size = Vector2(130, 52)
	hint_lbl.position = Vector2(20, h - 44)
	hint_lbl.custom_minimum_size = Vector2(560, 0)
	pause_panel.size = Vector2(440, 590)
	pause_panel.position = (s - pause_panel.size) / 2.0
	for i in range(pause_btns.size()):
		var pb: Panel = pause_btns[i]
		pb.size = Vector2(360, 66)
		pb.position = Vector2(40, 60 + i * 84)

	end_title.position = Vector2(w / 2.0 - 400, h * 0.25)
	end_title.custom_minimum_size = Vector2(800, 0)
	end_sub.position = Vector2(w / 2.0 - 400, h * 0.25 + 90)
	end_sub.custom_minimum_size = Vector2(800, 0)
	end_btn.size = Vector2(240, 80)
	end_btn.position = Vector2(w / 2.0 - 120, h * 0.7)


# ---------- публичные функции ----------

func set_status(wf: float, sf: float, clock_txt: String, obj: String, warm_val: float) -> void:
	_wf = clampf(wf, 0.0, 1.0)
	_sf = clampf(sf, 0.0, 1.0)
	warm_fill.size = Vector2(284.0 * _wf, 22)
	warm_fill.color = Color(0.4, 0.7, 1.0).lerp(Color(1.0, 0.55, 0.2), _wf)
	stam_fill.size = Vector2(288.0 * _sf, 6)
	var wt := "Тепло %d" % int(warm_val)
	if warm_lbl.text != wt:
		warm_lbl.text = wt
	if clock_lbl.text != clock_txt:
		clock_lbl.text = clock_txt
	if obj_lbl.text != obj:
		obj_lbl.text = obj


func set_compass(show: bool, ang: float, dist: float, nm: String) -> void:
	arrow.visible = show
	dist_lbl.visible = show
	if show:
		arrow.rotation = ang
		dist_lbl.text = "%s · %d м" % [nm, int(dist)]


func set_prompt(text: String) -> void:
	prompt_lbl.text = text
	prompt_lbl.visible = text != ""


func set_cold(c: float, haze: float) -> void:
	frost_mat.set_shader_parameter("cold", c)
	frost_mat.set_shader_parameter("haze", haze)


func set_fire_info(charges: int, max_charges: int, pct: int) -> void:
	var l: Label = btn_fire.get_meta("lbl")
	var t := "ОГОНЬ %d/%d\nшанс %d%%" % [charges, max_charges, pct]
	if l.text != t:
		l.text = t


func toast(text: String, dur := 3.5) -> void:
	toast_lbl.text = text
	toast_lbl.modulate.a = 1.0
	toast_lbl.visible = true
	toast_t = dur


func show_phone(sender: String, text: String) -> void:
	_reset_input()
	phone_from.text = sender
	phone_msg.text = text
	phone_panel.visible = true
	phone_visible = true


func set_hint(text: String) -> void:
	if hint_lbl.text != text:
		hint_lbl.text = text


func _set_btn_text(b: Panel, txt: String) -> void:
	var l: Label = b.get_meta("lbl")
	l.text = txt


func _refresh_pause_texts() -> void:
	_set_btn_text(pause_btns[1], "Обзор: %s" % SENS_NAMES[sens_idx])
	_set_btn_text(pause_btns[2], "Звук: %s" % ("вкл" if sound_on else "выкл"))
	_set_btn_text(pause_btns[3], "Вибрация: %s" % ("вкл" if vibro_on else "выкл"))


func toggle_pause() -> void:
	if end_visible or phone_visible or bag_open:
		return
	_reset_input()
	pause_open = not pause_open
	pause_panel.visible = pause_open
	if Net.mode == "single":
		get_tree().paused = pause_open


func _pause_button(i: int) -> void:
	match i:
		0:
			toggle_pause()
		1:
			sens_idx = (sens_idx + 1) % SENS_VALUES.size()
			sens_changed.emit(SENS_VALUES[sens_idx])
		2:
			sound_on = not sound_on
			sound_changed.emit(sound_on)
		3:
			vibro_on = not vibro_on
			vibro_changed.emit(vibro_on)
		4:
			get_tree().paused = false
			restart.emit()
		5:
			get_tree().paused = false
			menu_requested.emit()
	_refresh_pause_texts()


func toggle_bag() -> void:
	_reset_input()
	bag_open = not bag_open
	bag_panel.visible = bag_open
	bag_toggled.emit()


func set_inventory(items: Array) -> void:
	for i in range(SLOT_COUNT):
		var sp: Panel = slots[i]
		var l: Label = sp.get_meta("lbl")
		if i < items.size():
			var it: Dictionary = items[i]
			slot_ids[i] = it["id"]
			l.text = "%s\n%s" % [it["name"], it["info"]]
			sp.modulate = Color(1, 1, 1, 0.5 if it["dim"] else 1.0)
		else:
			slot_ids[i] = ""
			l.text = ""


func show_end(title: String, sub: String) -> void:
	_reset_input()
	bag_open = false
	bag_panel.visible = false
	end_title.text = title
	end_sub.text = sub
	end_panel.visible = true
	end_visible = true


func fade_to(a: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", a, dur)
	await tw.finished


# ---------- ввод ----------

func _reset_input() -> void:
	touches.clear()
	move_vec = Vector2.ZERO
	stick_base.visible = false
	stick_knob.visible = false


func _hit(c: Control, pos: Vector2) -> bool:
	return c.is_visible_in_tree() and Rect2(c.global_position, c.size).has_point(pos)


func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		toast_lbl.modulate.a = clampf(toast_t, 0.0, 1.0)
		if toast_t <= 0.0:
			toast_lbl.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			toggle_pause()


func _on_press(idx: int, pos: Vector2) -> void:
	var s := get_viewport().get_visible_rect().size
	if end_visible:
		if _hit(end_btn, pos):
			restart.emit()
		return
	if pause_open:
		for i in range(pause_btns.size()):
			if _hit(pause_btns[i], pos):
				_pause_button(i)
				return
		return
	if phone_visible:
		if _hit(phone_btn, pos):
			phone_visible = false
			phone_panel.visible = false
			phone_done.emit()
		return
	if bag_open:
		for i in range(SLOT_COUNT):
			if _hit(slots[i], pos) and slot_ids[i] != "":
				slot_tapped.emit(slot_ids[i])
				return
		toggle_bag()
		return
	if _hit(btn_action, pos):
		action.emit()
		return
	if _hit(btn_fire, pos):
		ignite.emit()
		return
	if _hit(btn_run, pos):
		sprint_on = not sprint_on
		btn_run.modulate = Color(1.0, 0.8, 0.3) if sprint_on else Color(1, 1, 1)
		sprint_toggled.emit(sprint_on)
		return
	if _hit(btn_bag, pos):
		toggle_bag()
		return
	if _hit(btn_pause, pos):
		toggle_pause()
		return
	if pos.x < s.x * 0.45 and not touches.values().has("move"):
		touches[idx] = "move"
		stick_origin = pos
		stick_base.size = Vector2(170, 170)
		stick_base.position = pos - stick_base.size / 2.0
		stick_knob.size = Vector2(76, 76)
		stick_knob.position = pos - stick_knob.size / 2.0
		stick_base.visible = true
		stick_knob.visible = true
	else:
		touches[idx] = "look"


func _on_release(idx: int) -> void:
	var role = touches.get(idx, "")
	touches.erase(idx)
	if role == "move":
		move_vec = Vector2.ZERO
		stick_base.visible = false
		stick_knob.visible = false


func _on_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var role = touches.get(idx, "")
	if role == "move":
		var maxr := 75.0
		var v := (pos - stick_origin).limit_length(maxr)
		stick_knob.position = stick_origin + v - stick_knob.size / 2.0
		var n := Vector2(v.x, -v.y) / maxr
		if n.length() < 0.12:
			n = Vector2.ZERO
		move_vec = n
	elif role == "look":
		look.emit(rel)
