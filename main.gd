extends Node3D
# «Метель» — выживание от первого лица. Весь баланс — в константах ниже.

const PlayerScript = preload("res://player.gd")
const WorldScript = preload("res://world.gd")
const HudScript = preload("res://hud.gd")
const FireScript = preload("res://fire.gd")
const WindScript = preload("res://wind.gd")

# ---------- баланс ----------
const LIGHTER_CHARGES := 7       # зажигалка на 7 использований
const WOOD_FOR_FIRE := 3         # досок на новый костёр
const CLOCK_SPEED := 1.3         # игровых минут в секунду (с 18:30 до 06:00 ≈ 9 минут)
const START_CLOCK := 1110.0      # 18:30
const DAWN_CLOCK := 1800.0       # 06:00
const COLD_MAX := 2.6            # потеря тепла/сек в метель на открытом месте
const FIRE_HEAT := 3.8           # нагрев/сек у самого костра
const FIRE_RADIUS := 5.5
const DRESSED_BONUS := 0.3       # одежда снижает потерю тепла
const FIRE_LIFE := 70.0
const FIRE_WOOD_LIFE := 20.0     # +секунд от одной доски

enum Phase { FLAT, OUTSIDE, STORM, DAWN, WIN, DEAD }

var phase := Phase.FLAT
var player
var world
var hud
var env: Environment
var sun: DirectionalLight3D
var snow: GPUParticles3D
var snow_mat: ParticleProcessMaterial

var storm := 0.0
var storm_target := 0.0
var light_t := 0.0
var clock := START_CLOCK
var warmth := 100.0
var charges := LIGHTER_CHARGES
var wood := 0
var paper := 0
var choco := 0
var has_jacket := false
var has_hat := false
var has_boots := false
var has_package := false
var door_open := false
var busy := false
var phone_open := true
var warned50 := false
var warned25 := false
var announced_dressed := false
var wind_dir := Vector3(0.8, 0.0, 0.6).normalized()
var t := 0.0
var inv_t := 0.0
var wind
var fires_lit := 0
var heat_now := 0.0
var expo_now := 1.0
var vibro_on := true
var flat_door_open := false
var multi := false
var avatars := {}       # peer_id -> {node, tp, ty, fresh}
var net_t := 0.0


func _ready() -> void:
	randomize()
	_setup_environment()
	world = WorldScript.new()
	add_child(world)
	world.build()
	player = PlayerScript.new()
	add_child(player)
	var slot := 0
	if Net.mode != "single":
		var ids: Array = Net.names.keys()
		ids.sort()
		slot = maxi(0, ids.find(multiplayer.get_unique_id()))
	player.global_position = Vector3(301, 3.1, -0.9 + slot * 0.6)
	player.rotation.y = -PI / 2.0
	_setup_snow()
	hud = HudScript.new()
	add_child(hud)
	hud.look.connect(player.look)
	hud.action.connect(on_action)
	hud.ignite.connect(on_ignite)
	hud.sprint_toggled.connect(func(on: bool): player.sprint = on)
	hud.slot_tapped.connect(on_slot)
	hud.bag_toggled.connect(_refresh_inv)
	hud.phone_done.connect(_on_phone_done)
	hud.restart.connect(func(): get_tree().reload_current_scene())
	hud.sens_changed.connect(func(v: float): player.sens = v)
	hud.sound_changed.connect(func(on: bool): AudioServer.set_bus_mute(0, not on))
	hud.vibro_changed.connect(func(on: bool): vibro_on = on)
	wind = WindScript.new()
	add_child(wind)
	hud.menu_requested.connect(_go_menu)
	multi = Net.mode != "single"
	if multi:
		multiplayer.peer_disconnected.connect(_on_peer_left)
		Net.server_lost.connect(_on_server_lost)
		for id in multiplayer.get_peers():
			_add_avatar(id)
	if multi:
		hud.toast("Игроков в сети: %d. Огни и найденные доски видят все." % (multiplayer.get_peers().size() + 1), 4.0)
	hud.show_phone("Любимая", "Сходи забери мою посылку, пожалуйста. Она на почте, ждёт тебя.")


func _physics_process(delta: float) -> void:
	if not multi:
		return
	net_t += delta
	if net_t >= 0.05:
		net_t = 0.0
		rpc("net_pos", player.global_position, player.rotation.y)


@rpc("any_peer", "unreliable_ordered")
func net_pos(p: Vector3, yaw: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not avatars.has(id):
		_add_avatar(id)
	var a: Dictionary = avatars[id]
	a["tp"] = p
	a["ty"] = yaw


@rpc("any_peer", "reliable")
func net_fire(pos: Vector3) -> void:
	_spawn_fire(pos, false)


@rpc("any_peer", "reliable")
func net_take(id: int) -> void:
	var n = world.items.get(id)
	if n != null and is_instance_valid(n):
		n.queue_free()


func _share_take(n: Node) -> void:
	if multi and n.has_meta("id"):
		rpc("net_take", int(n.get_meta("id")))


func _add_avatar(id: int) -> void:
	if avatars.has(id):
		return
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.7
	mi.mesh = cm
	mi.position.y = 0.85
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.from_hsv(fmod(float(id) * 0.137, 1.0), 0.55, 0.9)
	mi.material_override = m
	n.add_child(mi)
	var nose := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.12, 0.25)
	nose.mesh = bm
	nose.position = Vector3(0, 1.5, -0.3)
	nose.material_override = m
	n.add_child(nose)
	var lab := Label3D.new()
	lab.text = str(Net.names.get(id, "Игрок"))
	lab.font_size = 48
	lab.pixel_size = 0.006
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = Vector3(0, 2.1, 0)
	n.add_child(lab)
	add_child(n)
	avatars[id] = {"node": n, "tp": Vector3(301, 3.1, 0), "ty": 0.0, "fresh": true}


func _update_avatars(delta: float) -> void:
	for id in avatars:
		var a: Dictionary = avatars[id]
		var n: Node3D = a["node"]
		if a["fresh"]:
			n.position = a["tp"]
			a["fresh"] = false
		else:
			n.position = n.position.lerp(a["tp"], minf(1.0, 12.0 * delta))
		n.rotation.y = lerp_angle(n.rotation.y, a["ty"], minf(1.0, 12.0 * delta))


func _on_peer_left(id: int) -> void:
	if avatars.has(id):
		var a: Dictionary = avatars[id]
		(a["node"] as Node).queue_free()
		avatars.erase(id)
		hud.toast("Игрок вышел из игры.", 3.0)


func _on_server_lost() -> void:
	hud.toast("Хозяин отключился. Возвращаемся в меню…", 3.0)
	await get_tree().create_timer(2.0).timeout
	_go_menu()


func _go_menu() -> void:
	get_tree().paused = false
	Net.leave()
	get_tree().change_scene_to_file("res://menu.tscn")


func _buzz(ms: int) -> void:
	if vibro_on:
		Input.vibrate_handheld(ms)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				on_action()
			KEY_F:
				on_ignite()
			KEY_I, KEY_TAB:
				hud.toggle_bag()


# ---------- окружение и метель ----------

func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.19, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.19, 0.26)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.4
	sun.light_color = Color(0.7, 0.78, 1.0)
	add_child(sun)


func _setup_snow() -> void:
	snow = GPUParticles3D.new()
	snow.amount = 1400
	snow.lifetime = 3.0
	snow.top_level = true
	snow.visibility_aabb = AABB(Vector3(-30, -14, -30), Vector3(60, 28, 60))
	snow_mat = ParticleProcessMaterial.new()
	snow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	snow_mat.emission_box_extents = Vector3(14, 5, 14)
	snow_mat.gravity = Vector3(0, -1.5, 0)
	snow_mat.initial_velocity_min = 0.0
	snow_mat.initial_velocity_max = 0.5
	snow_mat.damping_min = 0.4
	snow_mat.damping_max = 0.4
	snow.process_material = snow_mat
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	snow.draw_pass_1 = q
	add_child(snow)


func _update_env(delta: float) -> void:
	storm = move_toward(storm, storm_target, delta * 0.04)
	if phase == Phase.DAWN:
		light_t = move_toward(light_t, 1.0, delta * 0.03)
	var col := Color(0.16, 0.19, 0.26).lerp(Color(0.66, 0.70, 0.76), light_t)
	col = col.lerp(Color(0.34, 0.37, 0.43), storm * 0.55 * (1.0 - light_t))
	env.background_color = col
	env.fog_light_color = col
	env.fog_density = lerpf(0.006, 0.1, storm)
	env.ambient_light_energy = lerpf(0.6, 1.0, light_t) + storm * 0.15
	sun.light_energy = lerpf(0.4, 0.9, light_t)
	var outside: bool = player.global_position.x < 200.0
	snow.emitting = outside and (phase != Phase.FLAT)
	snow.amount_ratio = clampf(0.15 + 0.85 * storm, 0.05, 1.0)
	snow.global_position = player.global_position + Vector3(-wind_dir.x * 8.0 * storm, 5.0, -wind_dir.z * 8.0 * storm)
	snow_mat.gravity = Vector3(wind_dir.x * 5.0 * storm, -1.5 - 1.5 * storm, wind_dir.z * 5.0 * storm)
	var wl: float = 0.06 + storm * 0.2
	if outside:
		var ex: float = world.exposure(player.global_position)
		wl = (0.1 + storm * 0.9) * (0.35 + 0.65 * ex)
	wind.level = clampf(wl, 0.0, 1.0)
	for l in world.lamp_lights:
		(l as OmniLight3D).light_energy = 1.3 * (0.55 + 0.45 * (1.0 - storm)) + randf() * 0.1 * storm


# ---------- главный цикл ----------

func _process(delta: float) -> void:
	t += delta
	player.move_input = hud.move_vec
	if multi:
		_update_avatars(delta)
	if flat_door_open and player.global_position.x > 311.0:
		flat_door_open = false
		world.close_flat_door()
		hud.toast("Щёлк. Дверь захлопнулась за спиной.", 3.0)
	if phase == Phase.WIN or phase == Phase.DEAD:
		return
	_update_env(delta)
	if phase == Phase.STORM:
		clock = minf(clock + CLOCK_SPEED * delta, DAWN_CLOCK)
		if clock >= DAWN_CLOCK:
			_dawn()
	_update_survival(delta)
	_update_hud(delta)


func _update_survival(delta: float) -> void:
	var outside: bool = player.global_position.x < 200.0
	if not outside or phase == Phase.FLAT:
		player.wind_push = Vector3.ZERO
		player.shiver = 0.0
		heat_now = 0.0
		expo_now = 1.0
		return
	var expo: float = world.exposure(player.global_position)
	expo_now = expo
	player.wind_push = wind_dir * storm * expo * 2.0 * (0.7 + 0.3 * sin(t * 1.3))
	var cold := lerpf(0.1, COLD_MAX, storm) * expo
	if has_jacket and has_hat and has_boots:
		cold *= (1.0 - DRESSED_BONUS)
	var heat := 0.0
	for f in get_tree().get_nodes_in_group("fires"):
		var d: float = f.global_position.distance_to(player.global_position)
		heat += maxf(0.0, 1.0 - d / FIRE_RADIUS) * FIRE_HEAT
	heat_now = heat
	warmth = clampf(warmth + (heat - cold) * delta, 0.0, 100.0)
	player.shiver = clampf((55.0 - warmth) / 55.0, 0.0, 1.0)
	if warmth < 50.0 and not warned50:
		warned50 = true
		hud.toast("Пальцы немеют. Нужно к костру или в укрытие.", 3.5)
		_buzz(200)
	if warmth < 25.0 and not warned25:
		warned25 = true
		hud.toast("Ты замерзаешь! Скорее к огню!", 3.5)
		_buzz(400)
	if warmth > 60.0:
		warned50 = false
		warned25 = false
	if warmth <= 0.0:
		_die()


func _update_hud(delta: float) -> void:
	var hh := int(clock / 60.0) % 24
	var mm := int(clock) % 60
	hud.set_status(warmth / 100.0, player.stamina / 100.0, "%02d:%02d" % [hh, mm], _objective(), warmth)
	var tgt = player.get_target()
	hud.set_prompt("" if tgt == null else str(tgt.get_meta("label", "")))
	hud.set_hint(_hint())
	var outside: bool = player.global_position.x < 200.0
	hud.set_cold(clampf((55.0 - warmth) / 55.0, 0.0, 1.0), storm * 0.5 if outside else 0.0)
	hud.set_fire_info(charges, LIGHTER_CHARGES, int(_ignite_chance(player.global_position) * 100.0))
	_update_compass()
	if hud.bag_open:
		inv_t += delta
		if inv_t > 0.3:
			inv_t = 0.0
			_refresh_inv()


func _hint() -> String:
	if player.global_position.x > 200.0 or phase == Phase.FLAT:
		return ""
	if heat_now > 0.3:
		return "У костра: тепло прибавляется"
	if expo_now < 0.8:
		return "Укрытие: ветер слабее"
	if storm > 0.4:
		return "Открытое место: быстро теряешь тепло"
	return ""


func _objective() -> String:
	var x: float = player.global_position.x
	if x > 200.0:
		if phone_open:
			return "Прочитай сообщение"
		if x < 309.0:
			if not (has_jacket and has_hat and has_boots):
				var n := int(has_jacket) + int(has_hat) + int(has_boots)
				return "Оденься: куртка, шапка, ботинки (%d/3)" % n
			return "Открой дверь и выйди из квартиры"
		if x < 316.6:
			return "Спустись по лестнице"
		return "Выйди из подъезда"
	match phase:
		Phase.OUTSIDE:
			return "Дойди до почты и забери посылку"
		Phase.STORM:
			return "Дожить до рассвета (06:00). Доски, костры, укрытия."
		Phase.DAWN:
			return "Метель стихает! Вернись к подъезду — дверь открыта."
	return ""


func _update_compass() -> void:
	var show := false
	var target := Vector3.ZERO
	var nm := ""
	if player.global_position.x < 200.0:
		if phase == Phase.OUTSIDE:
			show = true
			target = world.post_pos
			nm = "Почта"
		elif phase == Phase.STORM or phase == Phase.DAWN:
			show = true
			target = world.door_pos
			nm = "Подъезд"
	if not show:
		hud.set_compass(false, 0.0, 0.0, "")
		return
	var to: Vector3 = target - player.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	var f2 := Vector2(fwd.x, fwd.z)
	var t2 := Vector2(to.x, to.z)
	hud.set_compass(true, f2.angle_to(t2), t2.length(), nm)


# ---------- действия ----------

func _teleport(pos: Vector3, yaw: float) -> void:
	busy = true
	player.locked = true
	await hud.fade_to(1.0, 0.25)
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	await hud.fade_to(0.0, 0.25)
	player.locked = false
	busy = false


func on_action() -> void:
	if busy or phase == Phase.WIN or phase == Phase.DEAD:
		return
	var tgt = player.get_target()
	if tgt == null:
		return
	_interact(tgt)


func _check_dressed() -> void:
	if has_jacket and has_hat and has_boots and not announced_dressed:
		announced_dressed = true
		hud.toast("Готов. Пора идти.", 2.5)


func _interact(n: Node) -> void:
	var kind: String = str(n.get_meta("kind", ""))
	match kind:
		"jacket":
			has_jacket = true
			n.queue_free()
			hud.toast("Надел куртку.", 2.0)
			_check_dressed()
		"hat":
			has_hat = true
			n.queue_free()
			hud.toast("Надел шапку.", 2.0)
			_check_dressed()
		"boots":
			has_boots = true
			n.queue_free()
			hud.toast("Обул ботинки.", 2.0)
			_check_dressed()
		"flat_door":
			if not (has_jacket and has_hat and has_boots):
				hud.toast("На улице холодно. Нужно одеться: куртка, шапка и ботинки.", 3.5)
			else:
				flat_door_open = true
				world.open_flat_door()
				hud.toast("Что-то я забыл... Ладно, я быстро.", 3.0)
		"flat_back":
			hud.toast("Дверь захлопнулась и заперта. Ключи остались внутри.", 3.0)
		"hall_door":
			busy = true
			world.open_hall_door()
			await get_tree().create_timer(0.6, false).timeout
			phase = Phase.OUTSIDE
			storm_target = 0.12
			await _teleport(Vector3(10, 0.1, -25.4), PI)
			world.close_hall_door()
			hud.toast("Дверь подъезда захлопнулась. Иди на почту — стрелка вверху покажет путь.", 5.0)
		"domofon":
			if not has_package:
				hud.toast("Домофон не работает: экран чёрный. Ключи... остались дома! Ладно, сначала посылка.", 5.0)
			else:
				hud.toast("Домофон мёртв. Придётся ждать, пока кто-нибудь откроет дверь. До рассвета...", 5.0)
		"door_locked":
			hud.toast("Эта дверь тоже заперта.", 2.5)
		"main_door":
			if door_open:
				_win()
			else:
				hud.toast("Дверь заперта. Без ключей и домофона — только ждать, пока кто-нибудь выйдет.", 4.0)
		"post":
			if has_package:
				hud.toast("Посылка уже у тебя.", 2.0)
			else:
				has_package = true
				phase = Phase.STORM
				storm_target = 1.0
				hud.toast("Внутри оказался брелок. Ветер крепчает...", 4.0)
				await get_tree().create_timer(4.5, false).timeout
				_buzz(120)
				hud.toast("Началась сильная метель! Телефон сел на морозе. До подъезда далеко, а домофон не работает...", 6.0)
		"wood":
			var amt := int(n.get_meta("amount", 1))
			wood += amt
			_share_take(n)
			n.queue_free()
			hud.toast("+%d досок (всего %d)" % [amt, wood], 2.0)
		"paper":
			paper += 1
			_share_take(n)
			n.queue_free()
			hud.toast("Газеты: помогут разжечь огонь (+30% к шансу).", 2.5)
		"choco":
			choco += 1
			_share_take(n)
			n.queue_free()
			hud.toast("Шоколадка! Съесть можно в рюкзаке.", 2.5)
		"fire":
			if wood > 0:
				wood -= 1
				n.get_parent().add_life(FIRE_WOOD_LIFE)
				hud.toast("Подбросил доску в костёр.", 2.0)
			else:
				hud.toast("Нечего подбросить. Собери доски.", 2.0)
		"ash":
			hud.toast("Костёр догорел. Остались остывшие угли.", 2.5)


func _ignite_chance(pos: Vector3) -> float:
	var expo: float = world.exposure(pos)
	var c := 0.95 - 0.8 * expo * storm
	if paper > 0:
		c += 0.3
	return clampf(c, 0.08, 0.97)


func on_ignite() -> void:
	if busy or phase == Phase.FLAT or phase == Phase.WIN or phase == Phase.DEAD:
		return
	if player.global_position.x > 200.0:
		return
	if charges <= 0:
		hud.toast("Зажигалка пуста. Остались только уже горящие костры.", 3.5)
		return
	if wood < WOOD_FOR_FIRE:
		hud.toast("Нужно досок: %d (у тебя %d). Ищи в переулках." % [WOOD_FOR_FIRE, wood], 3.5)
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	var pos: Vector3 = player.global_position + fwd.normalized() * 1.3
	pos.y = 0.0
	for f in get_tree().get_nodes_in_group("fires"):
		if f.global_position.distance_to(pos) < 2.5:
			hud.toast("Рядом уже горит костёр.", 2.0)
			return
	var chance := _ignite_chance(pos)
	if paper > 0:
		paper -= 1
	charges -= 1
	if randf() < chance:
		wood -= WOOD_FOR_FIRE
		_spawn_fire(pos)
		hud.toast("Костёр разгорается! Зарядов зажигалки: %d" % charges, 3.0)
		_buzz(70)
	else:
		hud.toast("Ветер задул пламя... Зарядов: %d. Прячься за стены и козырьки!" % charges, 3.5)
		_buzz(160)


func _spawn_fire(pos: Vector3, share := true) -> void:
	var f = FireScript.new()
	if share:
		fires_lit += 1
		if multi:
			rpc("net_fire", pos)
	f.main = self
	f.life = FIRE_LIFE
	f.position = pos
	add_child(f)


# ---------- рюкзак ----------

func _refresh_inv() -> void:
	var dressed := has_jacket and has_hat and has_boots
	var items := [
		{"id": "lighter", "name": "Зажигалка", "info": "заряды: %d/%d" % [charges, LIGHTER_CHARGES], "dim": charges == 0},
		{"id": "wood", "name": "Доски", "info": "%d шт. (костёр = %d)" % [wood, WOOD_FOR_FIRE], "dim": wood == 0},
		{"id": "paper", "name": "Бумага", "info": "%d шт." % paper, "dim": paper == 0},
		{"id": "choco", "name": "Шоколадка", "info": "%d шт. (тап — съесть)" % choco, "dim": choco == 0},
		{"id": "package", "name": "Посылка", "info": "брелок" if has_package else "ещё не забрал", "dim": not has_package},
		{"id": "clothes", "name": "Одежда", "info": "куртка, шапка, ботинки" if dressed else "не одет", "dim": not dressed},
		{"id": "keys", "name": "Ключи", "info": "забыл дома", "dim": true},
		{"id": "phone", "name": "Телефон", "info": "разряжен" if has_package else "в кармане", "dim": has_package},
	]
	hud.set_inventory(items)


func on_slot(id: String) -> void:
	match id:
		"choco":
			if choco > 0:
				choco -= 1
				warmth = minf(100.0, warmth + 18.0)
				hud.toast("Сладкое согревает: +18 тепла.", 2.5)
			else:
				hud.toast("Шоколадок нет.", 2.0)
		"lighter":
			hud.toast("Каждая попытка разжечь костёр тратит заряд. Ветер мешает — прячься под козырьки и стены.", 5.0)
		"wood":
			hud.toast("Новый костёр = %d доски. Подкидывай доски в горящий костёр, чтобы он жил дольше." % WOOD_FOR_FIRE, 5.0)
		"paper":
			hud.toast("Бумага повышает шанс розжига на 30%.", 3.0)
		"keys":
			hud.toast("Остались на тумбочке. Классика.", 3.0)
		"phone":
			if has_package:
				hud.toast("Телефон сел на морозе.", 2.5)
			else:
				hud.toast("Телефон в кармане.", 2.0)
		_:
			pass
	_refresh_inv()


func _on_phone_done() -> void:
	phone_open = false
	hud.toast("Убрал телефон в карман. Теперь одеться: куртка, шапка, ботинки.", 4.0)


# ---------- рассвет, победа, смерть ----------

func _dawn() -> void:
	phase = Phase.DAWN
	storm_target = 0.0
	door_open = true
	world.open_main_door()
	hud.toast("Светает. Метель стихает — из подъезда вышел сосед, дверь осталась открытой!", 6.0)


func _win() -> void:
	phase = Phase.WIN
	player.locked = true
	_buzz(150)
	hud.show_end("Ты дома!", "Ты пережил метель и принёс брелок. Костров разведено: %d. В следующий раз бери ключи." % fires_lit)


func _die() -> void:
	phase = Phase.DEAD
	player.locked = true
	_buzz(600)
	var hh := int(clock / 60.0) % 24
	var mm := int(clock) % 60
	hud.show_end("Ты замёрз", "Метель не прощает ошибок. Дожил до %02d:%02d. Ключи так и остались на тумбочке." % [hh, mm])
