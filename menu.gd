extends Control
# Главное меню: одиночная игра, мультиплеер по LAN (создать / найти / по IP).

var box: VBoxContainer
var status: Label
var list_lbl: Label
var ip_edit: LineEdit
var name_edit: LineEdit
var found_box: VBoxContainer
var screen := "main"
var found_sig := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var snow := CPUParticles2D.new()
	snow.position = Vector2(640, -10)
	snow.amount = 140
	snow.lifetime = 7.0
	snow.preprocess = 7.0
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(700, 4)
	snow.direction = Vector2(0.4, 1.0)
	snow.spread = 12.0
	snow.gravity = Vector2(25, 45)
	snow.initial_velocity_min = 30.0
	snow.initial_velocity_max = 70.0
	snow.scale_amount_min = 2.0
	snow.scale_amount_max = 5.0
	snow.color = Color(1, 1, 1, 0.8)
	add_child(snow)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	Net.peers_changed.connect(_refresh_lobby)
	Net.joined_ok.connect(_show_wait)
	Net.join_failed.connect(_on_join_failed)
	Net.server_lost.connect(_on_server_lost)
	_show_main()


func _process(_delta: float) -> void:
	if screen == "join":
		var sig := ",".join(Net.found.keys())
		if sig != found_sig:
			found_sig = sig
			_fill_found()


# ---------- помощники ----------

func _clear() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	status = null
	list_lbl = null
	ip_edit = null
	found_box = null


func _label(text: String, size: int, col := Color(0.85, 0.92, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(560, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l


func _btn(text: String, cb: Callable, col := Color(0.2, 0.35, 0.55), parent: Node = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(560, 72)
	b.add_theme_font_size_override("font_size", 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(16)
	var sh: StyleBoxFlat = sb.duplicate()
	sh.bg_color = col.lightened(0.2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.add_theme_stylebox_override("focus", sb)
	b.pressed.connect(cb)
	if parent == null:
		box.add_child(b)
	else:
		parent.add_child(b)
	return b


func _apply_name() -> void:
	if name_edit != null and name_edit.text.strip_edges() != "":
		Net.player_name = name_edit.text.strip_edges().substr(0, 16)


# ---------- экраны ----------

func _show_main() -> void:
	screen = "main"
	_clear()
	_label("МЕТЕЛЬ", 72, Color(0.9, 0.96, 1.0))
	_label("Выживание в снежную ночь", 24, Color(0.6, 0.72, 0.85))
	var nm := LineEdit.new()
	nm.text = Net.player_name if Net.player_name != "Игрок" else "Игрок%d" % (randi() % 90 + 10)
	nm.placeholder_text = "Твоё имя"
	nm.custom_minimum_size = Vector2(560, 60)
	nm.add_theme_font_size_override("font_size", 26)
	nm.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.max_length = 16
	box.add_child(nm)
	name_edit = nm
	_btn("Одиночная игра", _on_single, Color(0.2, 0.5, 0.3))
	_btn("Мультиплеер по LAN", _show_lan)
	_btn("Выход", func(): get_tree().quit(), Color(0.45, 0.2, 0.2))


func _on_single() -> void:
	_apply_name()
	Net.leave()
	Net.start_game()


func _show_lan() -> void:
	_apply_name()
	screen = "lan"
	Net.leave()
	_clear()
	_label("Мультиплеер по LAN", 44)
	_label("Все устройства должны быть в одной Wi-Fi сети", 22, Color(0.6, 0.72, 0.85))
	_btn("Создать игру", _show_host, Color(0.2, 0.5, 0.3))
	_btn("Найти игру / подключиться", _show_join)
	_btn("Назад", _show_main, Color(0.3, 0.3, 0.35))


func _show_host() -> void:
	screen = "host"
	if not Net.host_game():
		_show_lan()
		status = _label("Не удалось создать сервер (порт занят?)", 22, Color(1, 0.6, 0.5))
		return
	_clear()
	_label("Ты хозяин игры", 44)
	var ips := Net.local_ips()
	var txt := "Адрес для подключения:\n" + ("\n".join(ips) if ips.size() > 0 else "не удалось определить, смотри в настройках Wi-Fi")
	_label(txt, 26, Color(1.0, 0.9, 0.6))
	_label("Друзья увидят игру сами (кнопка «Найти игру») или введут адрес вручную.", 20, Color(0.6, 0.72, 0.85))
	list_lbl = _label("", 26)
	_refresh_lobby()
	_btn("Начать игру", func(): Net.start_game(), Color(0.2, 0.5, 0.3))
	_btn("Отмена", _show_lan, Color(0.45, 0.2, 0.2))


func _show_join() -> void:
	screen = "join"
	Net.leave()
	Net.start_listen()
	found_sig = "?"
	_clear()
	_label("Поиск игр в сети", 44)
	found_box = VBoxContainer.new()
	found_box.add_theme_constant_override("separation", 10)
	box.add_child(found_box)
	_fill_found()
	_label("или введи адрес хоста вручную:", 22, Color(0.6, 0.72, 0.85))
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "например 192.168.0.5"
	ip_edit.custom_minimum_size = Vector2(560, 60)
	ip_edit.add_theme_font_size_override("font_size", 26)
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ip_edit)
	_btn("Подключиться по адресу", func(): _connect(ip_edit.text))
	status = _label("", 22, Color(1, 0.7, 0.5))
	_btn("Назад", _show_lan, Color(0.3, 0.3, 0.35))


func _fill_found() -> void:
	if found_box == null:
		return
	for c in found_box.get_children():
		found_box.remove_child(c)
		c.queue_free()
	if Net.found.is_empty():
		var l := Label.new()
		l.text = "Игр пока не видно… (если не находит — введи адрес)"
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(560, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		found_box.add_child(l)
		return
	for ip in Net.found.keys():
		var info: Dictionary = Net.found[ip]
		var addr: String = ip
		_btn("%s — игроков: %s (%s)" % [info["name"], info["n"], addr], func(): _connect(addr), Color(0.2, 0.5, 0.3), found_box)


func _connect(ip: String) -> void:
	if ip.strip_edges() == "":
		if status != null:
			status.text = "Введи адрес хоста"
		return
	_apply_name()
	Net.stop_listen()
	if not Net.join_game(ip):
		if status != null:
			status.text = "Не удалось начать подключение"
		return
	screen = "connecting"
	_clear()
	_label("Подключаюсь к %s…" % ip, 32)
	_btn("Отмена", _show_join, Color(0.45, 0.2, 0.2))


func _show_wait() -> void:
	screen = "wait"
	_clear()
	_label("Ты в лобби", 44)
	_label("Ждём, пока хозяин начнёт игру", 24, Color(1.0, 0.9, 0.6))
	list_lbl = _label("", 26)
	_refresh_lobby()
	_btn("Выйти", _show_lan, Color(0.45, 0.2, 0.2))


func _refresh_lobby() -> void:
	if list_lbl == null or not is_instance_valid(list_lbl):
		return
	var lines: Array = []
	for id in Net.names.keys():
		lines.append("• " + str(Net.names[id]) + ("  (хозяин)" if int(id) == 1 else ""))
	list_lbl.text = "Игроки:\n" + "\n".join(lines)


func _on_join_failed() -> void:
	_show_join()
	if status != null:
		status.text = "Не получилось подключиться. Проверь адрес и что хозяин создал игру."


func _on_server_lost() -> void:
	_show_lan()
	status = _label("Хозяин отключился", 22, Color(1, 0.6, 0.5))
