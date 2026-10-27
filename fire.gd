extends Node3D
# Костёр: греет рядом, со временем гаснет (в открытом месте при метели — быстрее).

var main
var life := 70.0
var expo := 1.0
var burning := true
var dead_t := 0.0
var light: OmniLight3D
var flames: GPUParticles3D
var body: StaticBody3D


func _ready() -> void:
	add_to_group("fires")
	expo = main.world.exposure(global_position)

	var logm := StandardMaterial3D.new()
	logm.albedo_color = Color(0.25, 0.14, 0.07)
	for i in range(3):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.12, 0.14)
		mi.mesh = bm
		mi.material_override = logm
		mi.position = Vector3(0, 0.08 + i * 0.05, 0)
		mi.rotation.y = i * 1.05
		add_child(mi)

	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.3
	glow.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(1.0, 0.4, 0.1)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.4, 0.1)
	gm.emission_energy_multiplier = 2.0
	glow.material_override = gm
	glow.position = Vector3(0, 0.15, 0)
	add_child(glow)

	flames = GPUParticles3D.new()
	flames.amount = 40
	flames.lifetime = 0.9
	flames.position = Vector3(0, 0.2, 0)
	flames.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 0.85, 0.3, 1.0), Color(1.0, 0.35, 0.05, 0.8), Color(0.3, 0.05, 0.0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	flames.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.vertex_color_use_as_albedo = true
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = qm
	flames.draw_pass_1 = q
	add_child(flames)

	light = OmniLight3D.new()
	light.position = Vector3(0, 0.8, 0)
	light.omni_range = 9.0
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.0
	add_child(light)

	body = StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.0
	cs.shape = sh
	cs.position = Vector3(0, 0.5, 0)
	body.add_child(cs)
	body.set_meta("kind", "fire")
	body.set_meta("label", "Подбросить доску в костёр")
	add_child(body)


func add_life(x: float) -> void:
	life = minf(life + x, 150.0)


func _process(delta: float) -> void:
	if not burning:
		dead_t += delta
		if dead_t > 25.0:
			queue_free()
		return
	var storm: float = main.storm
	life -= delta * (1.0 + 2.0 * storm * expo)
	var f := clampf(life / 15.0, 0.0, 1.0)
	light.light_energy = (1.6 + randf() * 0.9) * f
	flames.amount_ratio = maxf(f, 0.05)
	if life <= 0.0:
		burning = false
		flames.emitting = false
		light.visible = false
		remove_from_group("fires")
		body.set_meta("kind", "ash")
		body.set_meta("label", "Остывшие угли")
