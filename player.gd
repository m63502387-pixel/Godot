extends CharacterBody3D
# Игрок: ходьба, обзор, луч для взаимодействия.

const WALK := 3.2
const RUN := 5.4
const HEAD_Y := 1.6

var move_input := Vector2.ZERO   # x вправо, y вперёд (от джойстика)
var sprint := false
var stamina := 100.0
var wind_push := Vector3.ZERO
var locked := false
var shiver := 0.0
var pitch := 0.0
var sens := 0.0045
var bob_t := 0.0
var head: Node3D
var cam: Camera3D
var ray: RayCast3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	head = Node3D.new()
	head.position.y = HEAD_Y
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 160.0
	head.add_child(cam)
	cam.make_current()
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.8)
	ray.collision_mask = 2
	head.add_child(ray)


func look(rel: Vector2) -> void:
	if locked:
		return
	rotation.y -= rel.x * sens
	pitch = clampf(pitch - rel.y * sens, -1.4, 1.4)
	head.rotation.x = pitch


func get_target():
	if ray.is_colliding():
		var c = ray.get_collider()
		if c != null and c.has_meta("kind"):
			return c
	return null


func _physics_process(delta: float) -> void:
	var inp := move_input
	if Input.is_key_pressed(KEY_W):
		inp.y += 1.0
	if Input.is_key_pressed(KEY_S):
		inp.y -= 1.0
	if Input.is_key_pressed(KEY_D):
		inp.x += 1.0
	if Input.is_key_pressed(KEY_A):
		inp.x -= 1.0
	if locked:
		inp = Vector2.ZERO
	inp = inp.limit_length(1.0)
	var running := (sprint or Input.is_key_pressed(KEY_SHIFT)) and stamina > 4.0 and inp.length() > 0.2
	var spd := WALK
	if running:
		spd = RUN
		stamina = maxf(0.0, stamina - 20.0 * delta)
	else:
		stamina = minf(100.0, stamina + 12.0 * delta)
	var dir := global_transform.basis * Vector3(inp.x, 0.0, -inp.y)
	velocity.x = dir.x * spd + wind_push.x
	velocity.z = dir.z * spd + wind_push.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 20.0 * delta
	move_and_slide()
	if inp.length() > 0.1 and is_on_floor():
		bob_t += delta * spd * 2.2
		var amp: float = 0.035 if running else 0.022
		head.position.y = HEAD_Y + sin(bob_t) * amp
	else:
		head.position.y = lerpf(head.position.y, HEAD_Y, 8.0 * delta)
	head.rotation.z = sin(Time.get_ticks_msec() * 0.045) * 0.014 * shiver
