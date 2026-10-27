extends Node3D
# Мир строится кодом: кирпичные дома буквой П, двор с детской площадкой, улица, переулки с гаражами,
# почта, квартира + лестничная площадка + холл подъезда (далеко в стороне, x ~ 300).

var rng := RandomNumberGenerator.new()
var shelters: Array = []      # {aabb, f}: f — доля ветра (меньше = лучше укрытие)
var blocks: Array = []        # Rect2 в XZ — занятые места
var lamp_lights: Array = []
var post_pos := Vector3(-58.0, 0.0, 56.0)
var door_pos := Vector3(10.0, 0.0, -28.0)
var main_door: StaticBody3D
var items := {}               # id -> узел-предмет (для сетевой игры)
var item_seq := 0
var door_spots: Array = []    # места подъездов — тут не рисуем окна
var flat_pivot: Node3D
var flat_door: StaticBody3D
var hall_pivot: Node3D
var hall_door: StaticBody3D
var trng := RandomNumberGenerator.new()
var t_plaster: ImageTexture
var t_wood: ImageTexture
var t_slab: ImageTexture

var m_brick: StandardMaterial3D
var m_ground: StandardMaterial3D
var m_win: StandardMaterial3D
var m_grey: StandardMaterial3D
var m_dark: StandardMaterial3D
var m_wood: StandardMaterial3D
var m_road: StandardMaterial3D
var m_path: StandardMaterial3D
var m_metal: StandardMaterial3D
var m_spruce: StandardMaterial3D
var m_canopy: StandardMaterial3D
var m_lamp: StandardMaterial3D
var m_white: StandardMaterial3D
var m_snow: StandardMaterial3D
var m_step: StandardMaterial3D

const FY := 3.0   # высота пола квартиры (спускаемся по лестнице на 0)


func build() -> void:
	rng.seed = 20261025
	_make_materials()
	_build_ground()
	_build_buildings()
	_build_courtyard()
	_build_streets()
	_build_post_office()
	_build_garages_and_clutter()
	_build_interior()
	_scatter_pickups()
	_build_bounds()


# ---------- материалы и помощники ----------

func _mat(c: Color, rough := 0.9, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _tex_mat(tex: Texture2D, scale: float, rough := 0.95, tint := Color.WHITE) -> StandardMaterial3D:
	var m := _mat(tint, rough)
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


func _make_materials() -> void:
	trng.seed = 5
	var bt := _brick_tex()
	m_brick = _mat(Color.WHITE, 0.92)
	m_brick.albedo_texture = bt[0]
	m_brick.normal_enabled = true
	m_brick.normal_texture = bt[1]
	m_brick.normal_scale = 0.8
	m_brick.uv1_triplanar = true
	m_brick.uv1_world_triplanar = true
	m_brick.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m_ground = _tex_mat(_ground_tex(), 0.07, 1.0)
	m_win = StandardMaterial3D.new()
	m_win.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_win.vertex_color_use_as_albedo = true
	m_win.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_grey = _tex_mat(_noise_tex(3, 0.07, Color(0.5, 0.5, 0.48), Color(0.7, 0.7, 0.67), 0.06), 0.5, 0.95)
	m_dark = _mat(Color(0.1, 0.1, 0.11), 0.6)
	t_wood = _wood_tex()
	m_wood = _tex_mat(t_wood, 0.8, 0.9, Color(0.8, 0.6, 0.4))
	m_road = _tex_mat(_noise_tex(21, 0.09, Color(0.12, 0.12, 0.14), Color(0.2, 0.2, 0.22), 0.09), 0.35, 0.9)
	t_slab = _slab_tex()
	m_path = _tex_mat(t_slab, 0.4, 0.9, Color(0.75, 0.73, 0.72))
	m_metal = _mat(Color(0.5, 0.52, 0.55), 0.5)
	m_spruce = _mat(Color(0.07, 0.2, 0.12))
	m_canopy = _mat(Color(0.7, 0.35, 0.18))
	m_lamp = _mat(Color(1.0, 0.95, 0.8), 0.5, 2.0)
	m_white = _mat(Color(0.85, 0.87, 0.9))
	m_snow = _tex_mat(_noise_tex(9, 0.1, Color(0.8, 0.84, 0.92), Color(0.97, 0.98, 1.0), 0.04), 0.6, 0.8)
	m_step = _tex_mat(t_slab, 0.9, 0.9, Color(0.6, 0.6, 0.62))
	t_plaster = _noise_tex(4, 0.06, Color(0.9, 0.9, 0.9), Color(1.0, 1.0, 1.0), 0.05)


func _tile_noise(n: FastNoiseLite, x: int, y: int, w: int) -> float:
	var fx := float(x) / w
	var fy := float(y) / w
	var a := n.get_noise_2d(x, y)
	var b := n.get_noise_2d(x - w, y)
	var c := n.get_noise_2d(x, y - w)
	var d := n.get_noise_2d(x - w, y - w)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func _noise_tex(seed_: int, freq: float, c1: Color, c2: Color, grain: float) -> ImageTexture:
	var w := 128
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	for y in w:
		for x in w:
			var v: float = n.get_noise_2d(x, y) * 0.5 + 0.5
			var g: float = (trng.randf() - 0.5) * grain
			var c := c1.lerp(c2, clampf(v, 0.0, 1.0))
			img.set_pixel(x, y, Color(c.r + g, c.g + g, c.b + g))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _brick_tex() -> Array:
	var w := 256
	var n := FastNoiseLite.new()
	n.seed = 11
	n.frequency = 0.06
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	var hm := Image.create(w, w, false, Image.FORMAT_RGB8)
	for y in w:
		var row := y / 16
		var off := (row % 2) * 16
		for x in w:
			var xx := (x + off) % w
			var bx := xx / 32
			var tone := float((bx * 73 + row * 131) % 11) * 0.011
			var soot: float = n.get_noise_2d(x, y) * 0.05
			var g: float = (trng.randf() - 0.5) * 0.05
			var ey := y % 16
			var ex := xx % 32
			var c: Color
			var hgt: float
			if ey < 2 or ex < 2:
				c = Color(0.6 + soot, 0.56 + soot, 0.52 + soot)
				hgt = 0.15
			else:
				c = Color(0.72 + tone + soot + g, 0.29 + tone * 0.6 + soot * 0.6 + g, 0.17 + soot * 0.4 + g)
				hgt = 0.7 + tone + g * 0.5
				if ey == 2 or ex == 2:
					hgt = 0.55
			img.set_pixel(x, y, c)
			hm.set_pixel(x, y, Color(hgt, hgt, hgt))
	img.generate_mipmaps()
	hm.bump_map_to_normal_map(3.0)
	hm.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(hm)]


func _ground_tex() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.04
	var n2 := FastNoiseLite.new()
	n2.seed = 8
	n2.frequency = 0.25
	var w := 128
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	var dirt := Color(0.33, 0.29, 0.22)
	var grass := Color(0.34, 0.38, 0.24)
	var snow := Color(0.9, 0.92, 0.96)
	for y in w:
		for x in w:
			var v := _tile_noise(n, x, y, w)
			var f: float = n2.get_noise_2d(x, y) * 0.04
			var base := dirt.lerp(grass, smoothstep(-0.25, 0.0, v))
			var c := base.lerp(snow, smoothstep(-0.1, 0.12, v))
			var g: float = (trng.randf() - 0.5) * 0.04
			img.set_pixel(x, y, Color(c.r + f + g, c.g + f + g, c.b + f + g))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _wood_tex() -> ImageTexture:
	var w := 128
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	for y in w:
		for x in w:
			var plank := x / 32
			var tone := float((plank * 37) % 7) * 0.025
			var grain := sin(float(y) * 0.35 + float(plank) * 2.1) * 0.03 + sin(float(x) * 1.7) * 0.015
			var g: float = (trng.randf() - 0.5) * 0.03
			var c := Color(0.62 + tone + grain + g, 0.45 + tone + grain + g, 0.28 + tone * 0.6 + grain + g)
			if x % 32 < 2:
				c = Color(0.18, 0.12, 0.07)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _slab_tex() -> ImageTexture:
	var w := 128
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	for y in w:
		for x in w:
			var sx := x / 32
			var sy := y / 32
			var tone := float((sx * 5 + sy * 11) % 6) * 0.02
			var g: float = (trng.randf() - 0.5) * 0.06
			var v := 0.62 + tone + g
			if x % 32 < 2 or y % 32 < 2:
				v = 0.32
			img.set_pixel(x, y, Color(v, v, v * 1.02))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _vis(parent: Node, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _solid(parent: Node, pos: Vector3, size: Vector3, mat: Material, layer := 1) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	parent.add_child(sb)
	return sb


func _item(parent: Node, kind: String, label: String, pos: Vector3, size: Vector3, mat: Material, solid := false, extra := {}) -> StaticBody3D:
	var sb := _solid(parent, pos, size, mat, 3 if solid else 2)
	if not solid:
		var cs := sb.get_child(0) as CollisionShape3D
		(cs.shape as BoxShape3D).size = size.max(Vector3(0.7, 0.7, 0.7))
	sb.set_meta("kind", kind)
	sb.set_meta("label", label)
	item_seq += 1
	sb.set_meta("id", item_seq)
	items[item_seq] = sb
	for k in extra:
		sb.set_meta(k, extra[k])
	return sb


func exposure(p: Vector3) -> float:
	if p.x > 200.0:
		return 0.0
	var e := 1.0
	for s in shelters:
		if (s["aabb"] as AABB).has_point(p):
			e = minf(e, s["f"])
	return e


func open_main_door() -> void:
	if main_door == null:
		return
	var mi := main_door.get_child(1) as MeshInstance3D
	mi.material_override = _mat(Color(1.0, 0.85, 0.5), 0.6, 1.5)
	main_door.set_meta("label", "Войти в подъезд — дверь открыта")


# ---------- земля и дома ----------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(500, 1, 500)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	for ix in range(-4, 4):
		for iz in range(-4, 4):
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(30, 30)
			mi.mesh = pm
			mi.material_override = m_ground
			mi.position = Vector3(ix * 30 + 15, 0, iz * 30 + 15)
			add_child(mi)


func _building(cx: float, cz: float, sx: float, sz: float, h: float) -> void:
	_solid(self, Vector3(cx, h / 2.0, cz), Vector3(sx, h, sz), m_brick)
	blocks.append(Rect2(cx - sx / 2.0, cz - sz / 2.0, sx, sz))
	for f in range(1, int(h / 3.6) + 1):
		_vis(self, Vector3(cx, f * 3.6, cz), Vector3(sx + 0.12, 0.3, sz + 0.12), m_grey)
	_vis(self, Vector3(cx, h + 0.15, cz), Vector3(sx + 0.3, 0.3, sz + 0.3), m_canopy)
	_vis(self, Vector3(cx, h + 0.36, cz), Vector3(sx + 0.2, 0.14, sz + 0.2), m_snow)
	_windows(cx, cz, sx, sz, h)


func _quad(st: SurfaceTool, c: Vector3, u: Vector3, n: Vector3, size: Vector2, col: Color) -> void:
	var up := Vector3.UP
	var a := c - u * size.x / 2.0 - up * size.y / 2.0
	var b := c + u * size.x / 2.0 - up * size.y / 2.0
	var d := c + u * size.x / 2.0 + up * size.y / 2.0
	var e := c - u * size.x / 2.0 + up * size.y / 2.0
	for v in [a, b, d, a, d, e]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


func _near_door(p: Vector3) -> bool:
	for d in door_spots:
		var dd: Vector3 = d
		if absf(p.x - dd.x) < 2.9 and absf(p.z - dd.z) < 2.9:
			return true
	return false


func _windows(cx: float, cz: float, sx: float, sz: float, h: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var floors := int(h / 3.6)
	var faces := [
		[Vector3(cx, 0, cz + sz / 2.0), Vector3(1, 0, 0), Vector3(0, 0, 1), sx],
		[Vector3(cx, 0, cz - sz / 2.0), Vector3(-1, 0, 0), Vector3(0, 0, -1), sx],
		[Vector3(cx + sx / 2.0, 0, cz), Vector3(0, 0, -1), Vector3(1, 0, 0), sz],
		[Vector3(cx - sx / 2.0, 0, cz), Vector3(0, 0, 1), Vector3(-1, 0, 0), sz],
	]
	for f in faces:
		var c: Vector3 = f[0]
		var u: Vector3 = f[1]
		var n: Vector3 = f[2]
		var length: float = f[3]
		var cells := int(length / 3.0)
		for i in range(cells):
			var along := -length / 2.0 + (i + 0.5) * (length / cells)
			var loggia := rng.randf() < 0.3
			var wc: Vector3 = c + u * along
			for fl in range(floors):
				if fl == 0 and _near_door(wc):
					continue
				var wsize := Vector2(2.4, 2.4) if loggia else Vector2(1.2, 1.5)
				var y0 := fl * 3.6 + 1.0 + wsize.y / 2.0
				var lit := rng.randf() < 0.3
				var col := Color(0.14, 0.17, 0.22)
				if loggia:
					col = Color(0.95, 0.82, 0.5) if lit else Color(0.6, 0.72, 0.8)
				elif lit:
					col = Color(1.0, 0.82, 0.45)
				var center := c + u * along + Vector3(0, y0, 0)
				_quad(st, center + n * 0.04, u, n, wsize + Vector2(0.2, 0.2), Color(0.92, 0.93, 0.95))
				_quad(st, center + n * 0.06, u, n, wsize, col)
				if not loggia:
					_quad(st, center + n * 0.07, u, n, Vector2(0.07, wsize.y), Color(0.92, 0.93, 0.95))
					_quad(st, center + n * 0.07, u, n, Vector2(wsize.x, 0.07), Color(0.92, 0.93, 0.95))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m_win
	add_child(mi)


func _entrance(wall_pos: Vector3, normal: Vector3, is_main: bool) -> void:
	var e := Node3D.new()
	e.position = wall_pos
	e.rotation.y = atan2(normal.x, normal.z)
	add_child(e)
	var dm := _mat(Color(0.07, 0.07, 0.08), 0.5)
	var door := _item(e, "main_door" if is_main else "door_locked", "Дверь подъезда", Vector3(0, 1.15, 0.12), Vector3(1.5, 2.3, 0.2), dm, true)
	if is_main:
		main_door = door
	_vis(e, Vector3(0, 3.1, 1.4), Vector3(5.0, 0.25, 2.8), m_canopy)
	_item(e, "domofon", "Домофон", Vector3(1.2, 1.35, 0.1), Vector3(0.22, 0.32, 0.1), m_metal, false)
	_vis(e, Vector3(0, 2.6, 0.12), Vector3(0.3, 0.12, 0.12), m_lamp)
	var sz := Vector3(5.0, 3.5, 3.0)
	if absf(normal.x) > 0.5:
		sz = Vector3(3.0, 3.5, 5.0)
	var center := wall_pos + normal * 1.6 + Vector3(0, 1.75, 0)
	shelters.append({"aabb": AABB(center - sz / 2.0, sz), "f": 0.45})


func _build_buildings() -> void:
	door_spots = [Vector3(-24, 0, -28), Vector3(-8, 0, -28), Vector3(10, 0, -28), Vector3(26, 0, -28)]
	for z in [-17.5, -7.5, 2.5]:
		door_spots.append(Vector3(-32, 0, z))
		door_spots.append(Vector3(32, 0, z))
	_building(0, -34, 64, 12, 18)       # северный корпус
	_building(-38, -13, 12, 54, 18)     # западное крыло
	_building(38, -13, 12, 54, 18)      # восточное крыло
	_building(-85, -10, 14, 60, 16)
	_building(85, -10, 14, 60, 16)
	_building(-55, -70, 60, 12, 16)
	_building(55, -70, 60, 12, 16)
	_building(45, 60, 16, 12, 6)        # магазин
	# подъезды северного корпуса (главный — x=10)
	_entrance(Vector3(-24, 0, -28), Vector3(0, 0, 1), false)
	_entrance(Vector3(-8, 0, -28), Vector3(0, 0, 1), false)
	_entrance(Vector3(10, 0, -28), Vector3(0, 0, 1), true)
	_entrance(Vector3(26, 0, -28), Vector3(0, 0, 1), false)
	for z in [-17.5, -7.5, 2.5]:
		_entrance(Vector3(-32, 0, z), Vector3(1, 0, 0), false)
		_entrance(Vector3(32, 0, z), Vector3(-1, 0, 0), false)


# ---------- двор ----------

func _build_path() -> Array:
	var pts: Array = []
	for i in range(0, 21):
		var tt := i / 20.0
		pts.append(Vector3(lerpf(10.0, -4.0, tt) + 9.0 * sin(tt * TAU), 0.025, lerpf(-25.0, 14.0, tt)))
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := b - a
		var mi := _vis(self, (a + b) / 2.0, Vector3(3.2, 0.05, d.length() + 0.4), m_path)
		mi.rotation.y = atan2(d.x, d.z)
	_vis(self, Vector3(-4, 0.025, 22), Vector3(3.2, 0.05, 16), m_path)
	_vis(self, Vector3(0, 0.025, -24.5), Vector3(60, 0.05, 3), m_path)
	return pts


func _lamp(pos: Vector3, lit := true) -> void:
	_solid(self, pos + Vector3(0, 1.8, 0), Vector3(0.12, 3.6, 0.12), m_dark)
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	g.mesh = sm
	g.material_override = m_lamp
	g.position = pos + Vector3(0, 3.8, 0)
	add_child(g)
	if lit:
		var l := OmniLight3D.new()
		l.position = pos + Vector3(0, 3.7, 0)
		l.omni_range = 13.0
		l.light_energy = 1.3
		l.light_color = Color(1.0, 0.92, 0.78)
		add_child(l)
		lamp_lights.append(l)


func _tree(pos: Vector3, s := 1.0) -> void:
	_solid(self, pos + Vector3(0, 0.6 * s, 0), Vector3(0.3, 1.2 * s, 0.3), m_wood)
	for k in range(3):
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = (2.0 - k * 0.5) * s
		cm.height = 2.4 * s
		c.mesh = cm
		c.material_override = m_spruce
		c.position = pos + Vector3(0, (1.4 + k * 1.3) * s, 0)
		add_child(c)


func _playground(p: Vector3) -> void:
	var pl := Node3D.new()
	pl.position = p
	add_child(pl)
	var green := _mat(Color(0.1, 0.5, 0.2))
	var red := _mat(Color(0.8, 0.12, 0.1))
	var yellow := _mat(Color(0.95, 0.75, 0.1))
	_vis(pl, Vector3(0, 0.95, 0), Vector3(4.4, 0.12, 2.2), m_wood)
	for sx in [-2.1, 2.1]:
		for sz in [-1.0, 1.0]:
			_solid(pl, Vector3(sx, 1.2, sz), Vector3(0.15, 2.4, 0.15), m_wood)
	for tx in [-1.3, 1.3]:
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(2.0, 0.9, 2.4)
		roof.mesh = pm
		roof.material_override = green
		roof.position = Vector3(tx, 2.85, 0)
		pl.add_child(roof)
	_vis(pl, Vector3(0, 1.3, 1.1), Vector3(4.4, 0.5, 0.06), red)
	_solid(pl, Vector3(-2.5, 0.9, 0), Vector3(1.0, 1.8, 0.12), yellow)
	var slide := _vis(pl, Vector3(3.3, 0.55, 0), Vector3(2.8, 0.08, 0.8), red)
	slide.rotation.z = -0.5


func _build_courtyard() -> void:
	shelters.append({"aabb": AABB(Vector3(-31.0, -1.0, -27.5), Vector3(62.0, 9.0, 41.5)), "f": 0.7})
	var pts := _build_path()
	for i in range(2, pts.size(), 4):
		var p: Vector3 = pts[i]
		_lamp(Vector3(p.x + 2.4, 0.0, p.z))
	for x in [-24.0, -8.0, 18.0, 26.0]:
		_lamp(Vector3(x, 0.0, -23.0))
	for tp in [Vector2(-22, -14), Vector2(-26, 2), Vector2(20, -6), Vector2(24, 6), Vector2(-8, 8), Vector2(14, 10), Vector2(18, -16)]:
		_tree(Vector3(tp.x, 0, tp.y), rng.randf_range(0.9, 1.3))
	_playground(Vector3(-14, 0, -8))
	for sp in [Vector3(-9, 0.2, -5), Vector3(-10, 0.2, -10), Vector3(-6, 0.2, -8)]:
		_vis(self, sp, Vector3(0.5, 0.4, 0.5), m_dark)
	# памятник
	_solid(self, Vector3(14, 0.6, -12), Vector3(1.2, 1.2, 1.2), m_white)
	var bust := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	bust.mesh = sm
	bust.material_override = _mat(Color(0.2, 0.17, 0.12), 0.4)
	bust.position = Vector3(14, 1.75, -12)
	add_child(bust)
	_vis(self, Vector3(14, 1.4, -12), Vector3(0.55, 0.5, 0.35), bust.material_override)
	# заборчики и барбарис вдоль крыльев
	var b1 := _mat(Color(0.5, 0.45, 0.15))
	var b2 := _mat(Color(0.55, 0.15, 0.12))
	for sgn in [-1.0, 1.0]:
		var fx: float = 30.4 * sgn
		for z0 in range(-26, 12, 10):
			_solid(self, Vector3(fx, 0.5, z0 + 3.5), Vector3(0.06, 1.0, 7.0), m_metal)
		for z in range(-25, 12, 4):
			var bush := MeshInstance3D.new()
			var bm := SphereMesh.new()
			bm.radius = 0.6
			bm.height = 1.1
			bush.mesh = bm
			bush.material_override = b1 if rng.randf() < 0.6 else b2
			bush.position = Vector3(fx - sgn * 0.8, 0.5, z + rng.randf_range(-0.5, 0.5))
			add_child(bush)
	# машины у подъезда
	_solid(self, Vector3(6.5, 0.7, -25.8), Vector3(1.9, 1.4, 4.2), _mat(Color(0.12, 0.12, 0.14), 0.4))
	_solid(self, Vector3(13.5, 0.7, -25.8), Vector3(1.9, 1.4, 4.2), _mat(Color(0.85, 0.85, 0.82), 0.4))


# ---------- улицы, почта, переулки ----------

func _build_streets() -> void:
	_vis(self, Vector3(0, 0.02, 35), Vector3(240, 0.04, 10), m_road)
	_vis(self, Vector3(-68, 0.02, 20), Vector3(5, 0.04, 160), m_road)
	_vis(self, Vector3(68, 0.02, 20), Vector3(5, 0.04, 160), m_road)
	for x in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		_lamp(Vector3(x, 0.0, 29.0))
	# остановка
	var glass := _mat(Color(0.55, 0.7, 0.8), 0.2)
	_vis(self, Vector3(-20, 2.6, 28.4), Vector3(4.4, 0.15, 2.4), m_metal)
	_vis(self, Vector3(-20, 1.2, 29.4), Vector3(4.0, 2.2, 0.08), glass)
	_vis(self, Vector3(-22, 1.2, 28.5), Vector3(0.08, 2.2, 2.0), glass)
	_solid(self, Vector3(-20, 0.3, 29.0), Vector3(3.0, 0.45, 0.5), m_wood)
	shelters.append({"aabb": AABB(Vector3(-22.1, 0.0, 27.2), Vector3(4.2, 2.6, 2.2)), "f": 0.25})


func _build_post_office() -> void:
	var wall := _mat(Color(0.55, 0.65, 0.8), 0.9)
	_solid(self, Vector3(-58, 2.5, 62), Vector3(14, 5, 10), wall)
	blocks.append(Rect2(-65, 57, 14, 10))
	_vis(self, Vector3(-58, 5.1, 62), Vector3(14.6, 0.3, 10.6), m_white)
	var door := _item(self, "post", "Забрать посылку", Vector3(-58, 1.1, 56.9), Vector3(1.6, 2.2, 0.2), _mat(Color(0.15, 0.3, 0.7), 0.5), true)
	door.set_meta("main", false)
	_vis(self, Vector3(-58, 3.0, 55.6), Vector3(4.0, 0.2, 2.6), m_canopy)
	var wm := _mat(Color(1.0, 0.85, 0.5), 0.5, 1.5)
	for wx in [-62.0, -54.0]:
		_vis(self, Vector3(wx, 1.8, 56.95), Vector3(1.6, 1.4, 0.05), wm)
	var lb := Label3D.new()
	lb.text = "ПОЧТА"
	lb.font_size = 140
	lb.pixel_size = 0.01
	lb.position = Vector3(-58, 4.0, 56.9)
	lb.rotation.y = PI
	add_child(lb)
	var l := OmniLight3D.new()
	l.position = Vector3(-58, 3.2, 54.8)
	l.omni_range = 14.0
	l.light_energy = 2.0
	l.light_color = Color(1.0, 0.85, 0.55)
	add_child(l)
	shelters.append({"aabb": AABB(Vector3(-60.0, 0.0, 54.0), Vector3(4.0, 3.0, 3.0)), "f": 0.4})


func _build_garages_and_clutter() -> void:
	var gcols := [Color(0.45, 0.5, 0.55), Color(0.5, 0.42, 0.35), Color(0.36, 0.42, 0.38), Color(0.55, 0.2, 0.18)]
	for row in [75.0, 96.0]:
		var x := -105.0
		while x < 105.0:
			var gw := 4.5
			_solid(self, Vector3(x + gw / 2.0, 1.4, row), Vector3(gw, 2.8, 7.0), _mat(gcols[rng.randi() % 4], 0.8))
			blocks.append(Rect2(x, row - 3.5, gw, 7.0))
			x += gw
			if rng.randf() < 0.6:
				shelters.append({"aabb": AABB(Vector3(x, 0.0, row - 3.5), Vector3(3.2, 3.0, 7.0)), "f": 0.5})
				x += 3.2
	for i in range(14):
		var p := _rand_edge_point()
		if _free(p):
			var d := _solid(self, p + Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 1.0), _mat(Color(0.12, 0.3, 0.2), 0.7))
			d.rotation.y = float(rng.randi() % 4) * PI / 2.0
	for i in range(8):
		var p := _rand_edge_point()
		if _free(p):
			_solid(self, p + Vector3(0, 1.2, 0), Vector3(4.0, 2.4, 2.4), _mat(Color(0.35, 0.4, 0.5), 0.7))
	for i in range(22):
		var p := Vector3(rng.randf_range(-100, 100), 0, rng.randf_range(-95, 95))
		if _free(p):
			_tree(p, rng.randf_range(0.8, 1.4))
	for i in range(40):
		var p := Vector3(rng.randf_range(-100, 100), 0, rng.randf_range(-95, 95))
		if _free(p):
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			mi.mesh = sm
			mi.material_override = m_white
			mi.scale = Vector3(rng.randf_range(1.5, 3.0), 0.35, rng.randf_range(1.0, 2.0))
			mi.position = p
			add_child(mi)


func _free(p: Vector3) -> bool:
	if absf(p.x) > 100.0 or absf(p.z) > 100.0:
		return false
	var q := Vector2(p.x, p.z)
	if q.distance_to(Vector2(10, -25.5)) < 4.0:
		return false
	for b in blocks:
		if (b as Rect2).grow(1.0).has_point(q):
			return false
	if Rect2(-31, -28, 62, 42).has_point(q) and rng.randf() < 0.7:
		return false
	return true


func _rand_edge_point() -> Vector3:
	var r: Rect2 = blocks[rng.randi() % blocks.size()]
	var off := rng.randf_range(1.6, 3.2)
	match rng.randi() % 4:
		0:
			return Vector3(rng.randf_range(r.position.x, r.end.x), 0, r.position.y - off)
		1:
			return Vector3(rng.randf_range(r.position.x, r.end.x), 0, r.end.y + off)
		2:
			return Vector3(r.position.x - off, 0, rng.randf_range(r.position.y, r.end.y))
		_:
			return Vector3(r.end.x + off, 0, rng.randf_range(r.position.y, r.end.y))


# ---------- предметы ----------

func _scatter_pickups() -> void:
	var plan := {"wood": 26, "pallet": 8, "box": 10, "paper": 10, "choco": 5}
	for k in plan:
		var n: int = plan[k]
		var placed := 0
		var tries := 0
		while placed < n and tries < 3000:
			tries += 1
			var p := _rand_edge_point()
			if not _free(p):
				continue
			_make_pickup(k, p)
			placed += 1


func _make_pickup(what: String, p: Vector3) -> void:
	var node: StaticBody3D
	match what:
		"wood":
			node = _item(self, "wood", "Взять доску", p + Vector3(0, 0.08, 0), Vector3(1.1, 0.14, 0.2), _mat(Color(0.55, 0.36, 0.18), 0.9, 0.25), false, {"amount": 1})
		"pallet":
			node = _item(self, "wood", "Разобрать поддон (+3 доски)", p + Vector3(0, 0.1, 0), Vector3(1.1, 0.16, 0.9), _mat(Color(0.65, 0.5, 0.28), 0.9, 0.25), false, {"amount": 3})
		"box":
			node = _item(self, "wood", "Разломать ящик (+2 доски)", p + Vector3(0, 0.25, 0), Vector3(0.6, 0.5, 0.6), _mat(Color(0.6, 0.42, 0.22), 0.9, 0.25), false, {"amount": 2})
		"paper":
			node = _item(self, "paper", "Взять газеты (для розжига)", p + Vector3(0, 0.03, 0), Vector3(0.4, 0.05, 0.3), _mat(Color(0.9, 0.9, 0.85), 0.9, 0.4))
		_:
			node = _item(self, "choco", "Взять шоколадку", p + Vector3(0, 0.03, 0), Vector3(0.22, 0.05, 0.14), _mat(Color(0.2, 0.5, 0.9), 0.5, 0.8))
	node.rotation.y = rng.randf() * TAU


func _build_bounds() -> void:
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.position = dir * 110.0 + Vector3(0, 5, 0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(224, 10, 2) if dir.z != 0.0 else Vector3(2, 10, 224)
		cs.shape = bs
		sb.add_child(cs)
		add_child(sb)


# ---------- квартира (сверху), лестница, холл (x ~ 300) ----------

func _hinged_door(hinge: Vector3, width: float, height: float, kind: String, label: String, mat: Material) -> Array:
	var pivot := Node3D.new()
	pivot.position = hinge
	add_child(pivot)
	var door := _item(pivot, kind, label, Vector3(0, height / 2.0, width / 2.0), Vector3(0.12, height, width), mat, true)
	return [pivot, door]


func _swing(pivot: Node3D, angle: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(pivot, "rotation:y", angle, dur)


func open_flat_door() -> void:
	flat_door.set_meta("kind", "flat_open")
	flat_door.set_meta("label", "")
	_swing(flat_pivot, PI / 2.0, 0.5)


func close_flat_door() -> void:
	flat_door.set_meta("kind", "flat_back")
	flat_door.set_meta("label", "Дверь захлопнулась — заперто")
	_swing(flat_pivot, 0.0, 0.12)


func open_hall_door() -> void:
	hall_door.set_meta("kind", "door_locked")
	hall_door.set_meta("label", "")
	_swing(hall_pivot, PI / 2.0, 0.5)


func close_hall_door() -> void:
	hall_door.set_meta("kind", "door_locked")
	hall_door.set_meta("label", "Дверь подъезда захлопнулась")
	_swing(hall_pivot, 0.0, 0.1)


func _lamp_in(pos: Vector3, rng_m: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = rng_m
	l.light_energy = energy
	l.light_color = Color(1.0, 0.9, 0.72)
	add_child(l)


func _build_interior() -> void:
	var wall_a := _tex_mat(t_plaster, 0.4, 0.95, Color(0.86, 0.8, 0.68))
	var floor_a := _tex_mat(t_wood, 0.5, 0.8, Color(0.85, 0.7, 0.55))
	var wall_s := _tex_mat(t_plaster, 0.4, 0.95, Color(0.62, 0.72, 0.66))
	var wall_h := _tex_mat(t_plaster, 0.4, 0.95, Color(0.8, 0.78, 0.66))
	var doorm := _mat(Color(0.35, 0.22, 0.12), 0.8)
	var doorh := _mat(Color(0.07, 0.07, 0.08), 0.5)
	# --- квартира: x 300..309, z -2..2, пол на высоте FY ---
	_solid(self, Vector3(304.5, FY - 0.1, 0), Vector3(9.4, 0.2, 4.4), floor_a)
	_solid(self, Vector3(304.5, FY + 2.9, 0), Vector3(9.4, 0.2, 4.4), wall_a)
	_solid(self, Vector3(299.9, FY + 1.4, 0), Vector3(0.2, 2.8, 4.4), wall_a)
	_solid(self, Vector3(304.5, FY + 1.4, -2.1), Vector3(9.4, 2.8, 0.2), wall_a)
	_solid(self, Vector3(304.5, FY + 1.4, 2.1), Vector3(9.4, 2.8, 0.2), wall_a)
	_solid(self, Vector3(309.1, FY + 1.4, -1.35), Vector3(0.2, 2.8, 1.7), wall_a)
	_solid(self, Vector3(309.1, FY + 1.4, 1.35), Vector3(0.2, 2.8, 1.7), wall_a)
	_solid(self, Vector3(309.1, FY + 2.45, 0), Vector3(0.2, 0.7, 1.0), wall_a)
	_lamp_in(Vector3(304.5, FY + 2.4, 0), 12.0, 1.4)
	_solid(self, Vector3(302, FY + 0.3, -1.3), Vector3(2.0, 0.5, 1.0), _mat(Color(0.3, 0.4, 0.6)))
	_solid(self, Vector3(304.5, FY + 0.4, 1.4), Vector3(1.2, 0.8, 0.6), m_wood)
	_solid(self, Vector3(300.5, FY + 1.0, 1.5), Vector3(0.6, 2.0, 1.0), m_wood)
	_vis(self, Vector3(304.5, FY + 1.5, -1.95), Vector3(1.6, 1.2, 0.05), _mat(Color(0.5, 0.6, 0.8), 0.5, 1.2))
	_item(self, "jacket", "Надеть куртку", Vector3(308.6, FY + 1.3, -1.6), Vector3(0.4, 0.9, 0.15), _mat(Color(0.2, 0.35, 0.25)))
	_vis(self, Vector3(308.6, FY + 1.45, 1.5), Vector3(0.4, 0.05, 0.6), m_wood)
	_item(self, "hat", "Надеть шапку", Vector3(308.6, FY + 1.6, 1.5), Vector3(0.3, 0.2, 0.3), _mat(Color(0.75, 0.15, 0.15)))
	_item(self, "boots", "Надеть ботинки", Vector3(308.2, FY + 0.12, 1.5), Vector3(0.45, 0.25, 0.3), _mat(Color(0.25, 0.15, 0.08)))
	# тумбочка с ключами (ключи — декор, их нельзя взять)
	_solid(self, Vector3(308.4, FY + 0.5, -1.2), Vector3(0.5, 1.0, 0.5), m_wood)
	_vis(self, Vector3(308.4, FY + 1.03, -1.2), Vector3(0.12, 0.02, 0.2), _mat(Color(0.9, 0.8, 0.3), 0.3, 0.5))
	# дверь квартиры (открывается кнопкой, потом захлопывается)
	var fd := _hinged_door(Vector3(309.1, FY, -0.5), 1.0, 2.1, "flat_door", "Открыть дверь", doorm)
	flat_pivot = fd[0]
	flat_door = fd[1]
	# --- лестничная клетка и холл: x 309..325, пол 0, потолок 5.8 ---
	_solid(self, Vector3(317.1, -0.1, 0), Vector3(16.2, 0.2, 3.4), m_step)
	_solid(self, Vector3(317.1, 5.9, 0), Vector3(16.2, 0.2, 3.4), wall_s)
	_solid(self, Vector3(317.1, 2.9, -1.6), Vector3(16.2, 5.8, 0.2), wall_s)
	_solid(self, Vector3(317.1, 2.9, 1.6), Vector3(16.2, 5.8, 0.2), wall_s)
	_solid(self, Vector3(325.1, 2.9, -1.2), Vector3(0.2, 5.8, 1.0), wall_h)
	_solid(self, Vector3(325.1, 2.9, 1.2), Vector3(0.2, 5.8, 1.0), wall_h)
	_solid(self, Vector3(325.1, 4.05, 0), Vector3(0.2, 3.5, 1.4), wall_h)
	# площадка перед лестницей (на уровне квартиры)
	_solid(self, Vector3(310.85, FY / 2.0, 0), Vector3(3.3, FY, 3.0), m_step)
	# ступени (14 штук по 0.2 м) — видимые, а ходим по невидимому пандусу
	for i in range(14):
		var h: float = FY - 0.2 * (i + 1)
		_vis(self, Vector3(312.5 + 0.28 * i + 0.14, h / 2.0, 0), Vector3(0.28, h, 3.0), m_step)
	var slope: float = 2.8 / 3.92
	var ang: float = atan(slope)
	var p0 := Vector2(312.5, 2.8 + slope * (312.64 - 312.5))
	var p1 := Vector2(316.8, 2.8 - slope * (316.8 - 312.64))
	var mid: Vector2 = (p0 + p1) / 2.0
	var rlen: float = p0.distance_to(p1)
	var nrm := Vector2(sin(ang), cos(ang))
	var thick := 0.6
	var cc: Vector2 = mid - nrm * (thick / 2.0)
	var ramp := _solid(self, Vector3(cc.x, cc.y, 0), Vector3(rlen, thick, 3.0), m_step)
	ramp.rotation.z = -ang
	(ramp.get_child(1) as MeshInstance3D).visible = false
	# перила
	for rz in [-1.35, 1.35]:
		var rc: Vector2 = mid + nrm * 0.95
		var rail := _vis(self, Vector3(rc.x, rc.y, rz), Vector3(rlen, 0.06, 0.06), m_metal)
		rail.rotation.z = -ang
	_lamp_in(Vector3(311.4, FY + 2.2, 0), 9.0, 1.2)
	_lamp_in(Vector3(315.0, 3.6, 0), 9.0, 1.1)
	_lamp_in(Vector3(321.5, 2.5, 0), 9.0, 1.3)
	# почтовые ящики в холле
	for i in range(4):
		_vis(self, Vector3(319.5 + i * 0.7, 1.3, -1.47), Vector3(0.5, 0.6, 0.05), _mat(Color(0.2, 0.35, 0.7)))
	# дверь на улицу
	var hd := _hinged_door(Vector3(325.1, 0, -0.7), 1.4, 2.3, "hall_door", "Открыть дверь", doorh)
	hall_pivot = hd[0]
	hall_door = hd[1]
