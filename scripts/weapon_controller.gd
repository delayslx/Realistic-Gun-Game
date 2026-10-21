extends Node3D
## Procedural G18 controller: every moving part is driven per-frame through
## the gun rig's bones (slide / magazine / trigger) plus a spring-driven
## recoil pivot. No baked weapon clips; IK hand targets live on RecoilPivot.
##
## Bone-space note: pose offsets are authored in parent-bone space. The G18
## rig's COM rest basis maps them into skeleton space as
##     M(v) = (-v.z, -v.y, -v.x)   (M is its own inverse).
## _to_bone() converts desired skeleton-space offsets, so call sites can
## think in world-aligned axes (verified empirically on-device).

enum State { IDLE, FIRING, EJECTING, INSERTING, RACKING, CLEARING }

## ADS tepmesi: hip-fire'a gore daha yumusak kick, sifira tam donus.
@export_range(0.0, 1.0) var ads_recoil_multiplier := 0.40
## ADS yay frekansi: dusuk deger = daha yavas, daha kontrollu donus.
@export var ads_recoil_recovery_speed := 7.0
## Bu esigin altinda kalan recoil tamamen sifirlanir (kalici offset yok).
@export var ads_recoil_return_epsilon := 0.0006

const MAG_CAPACITY := 12
const SLIDE_TRAVEL := 0.035
const SLIDE_JAM_HOLD := 0.03
const FIRE_TIME := 0.08
const EJECT_TIME := 0.55
const INSERT_TIME := 0.55
const RACK_TIME := 0.45
const CLEAR_TIME := 0.9
# Desired skeleton-space magazine poses (down + toward shooter on eject).
const MAG_EJECT_POS := Vector3(0.0, -0.13, 0.07)
const MAG_WIGGLE_POS := Vector3(0.0, -0.05, 0.04)
const MAG_EJECT_TILT := 0.9
const MAG_WIGGLE_TILT := 0.35

var state: State = State.IDLE
var state_time := 0.0

var magazine_count := MAG_CAPACITY
var has_mag := true
var chambered := true
var slide_locked := false
var jammed := false
var shots_fired := 0
var jam_chance := 0.004
const JAM_ABUSE_CHANCE := 0.05
## Manuel slide kapatma bayragi: bosken F ile slide kapatilirsa true olur.
## Sonraki sarjor degisiminde slide geriye OTOMATIK acilmaz, kapali kalir.
## Hane bos oldugu icin ates etmez; sonraki F rack ile namluya mermi surulur.
var slide_closed_manually := false

var gun: Skeleton3D
var recoil_pivot: Node3D
var mag_mesh: MeshInstance3D
var bullet_mesh: MeshInstance3D
var eject_port: Node3D
var muzzle: Node3D
var camera_node: Camera3D
var player: Node
var scope_point: Node3D
## Her kare _process'te guncellenir; ADS dalini secmek icin cache.
var aiming := false
## Kalici tepme sapmasi: yay hedefi sifir degil anchor'dir. Ates basina
## birikir, yavas cozulur -> silah tam eski yerine gelmez.
var recoil_anchor := Vector3.ZERO
## Kovan / mermi telemetrisi (test araclari okur).
var casings_ejected := 0
var live_ejected := 0
var empty_ejected := 0
var last_eject_vel := Vector3.ZERO
var last_eject_pos := Vector3.ZERO
var last_eject_live := false
var last_shot_hit := Vector3.ZERO
var last_shot_hit_ok := false
var last_shot_dist := 0.0
var shots_hit := 0
var last_casing: RigidBody3D
var last_casing_y0 := 0.0

var bone_slide := -1
var bone_mag := -1
var bone_trigger := -1
var mag_rest_basis := Basis.IDENTITY
var trig_rest_basis := Basis.IDENTITY

var slide_offset := 0.0
var slide_target := 0.0
var trigger_press := 0.0
var trigger_target := 0.0

var mag_offset := Vector3.ZERO
var mag_offset_target := Vector3.ZERO
var mag_tilt := 0.0
var mag_tilt_target := 0.0

var recoil_rot_cur := Vector3.ZERO
var recoil_pos_cur := Vector3.ZERO
var recoil_rot_vel := Vector3.ZERO
var recoil_pos_vel := Vector3.ZERO
## Sustained-fire heat: consecutive shots stack extra flip/climb (realistic
## muzzle rise), decays when not firing. Camera is never touched.
var heat := 0.0
## Smart-reload chain flag: R ejects then auto-inserts a fresh mag.
## Gercek hayat mantigi: sarjor degistirmek haneyi DOLDURMAZ. Hane bossa
## (son mermi atilmis / surgu geride kilitli), ates icin F ile surguyu
## cekmek gerekir. Hane doluysa (taktiksel degisim) silah hazirdir.
var auto_reload := false

## Ses sistemi: res://sounds/glock/*.wav dosyalari _ready'de yuklenir,
## ates / eject / insert / rack / lock / dry-fire anlarinda calinir.
const SFX_SHOT := "res://sounds/glock/shot_9mm.wav"
const SFX_EJECT_LOADED := "res://sounds/glock/mag_eject_loaded.wav"
const SFX_EJECT_EMPTY := ["res://sounds/glock/mag_eject_empty_01.wav", "res://sounds/glock/mag_eject_empty_02.wav"]
const SFX_INSERT_LOADED := "res://sounds/glock/mag_insert_loaded.wav"
const SFX_DRY := "res://sounds/glock/dry_fire.wav"
const SFX_EMPTY := "res://sounds/glock/empty_click.wav"
const SFX_JAM := "res://sounds/glock/jam_clunk.wav"
const SFX_SLIDE_PULL := "res://sounds/glock/slide_pull.wav"
const SFX_SLIDE_RELEASE := "res://sounds/glock/slide_release.wav"
## Surgi arkaya kilit sesi: geriye gidis oldugu icin pull dosyasi kullanilir.
const SFX_SLIDE_LOCK := "res://sounds/glock/slide_pull.wav"

var _sfx_streams := {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _sfx_warned := {}

func _sfx_load(path: String) -> AudioStream:
	if _sfx_streams.has(path):
		return _sfx_streams[path]
	if not ResourceLoader.exists(path):
		if not _sfx_warned.get(path, false):
			_sfx_warned[path] = true
			push_warning("SFX yok: " + path)
		return null
	var st := load(path) as AudioStream
	_sfx_streams[path] = st
	return st

func _sfx_init() -> void:
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_pool.append(p)
	for path in [SFX_SHOT, SFX_EJECT_LOADED, SFX_EJECT_EMPTY[0], SFX_EJECT_EMPTY[1], SFX_INSERT_LOADED, SFX_DRY, SFX_EMPTY, SFX_JAM, SFX_SLIDE_PULL, SFX_SLIDE_RELEASE, SFX_SLIDE_LOCK]:
		_sfx_load(path)

func _play_sfx(path: String, vol_db := -10.0) -> void:
	var st := _sfx_load(path)
	if st == null:
		return
	var p := _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = st
	p.volume_db = vol_db
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play()

func _to_bone(v: Vector3) -> Vector3:
	return Vector3(-v.z, -v.y, -v.x)

func _muzzle_forward_global() -> Vector3:
	if muzzle != null:
		return -muzzle.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()

func _camera_forward_global() -> Vector3:
	if camera_node != null:
		return -camera_node.global_transform.basis.z.normalized()
	return _muzzle_forward_global()

func _is_aiming() -> bool:
	if player != null and player.has_method("is_aiming"):
		return bool(player.call("is_aiming"))
	return false

## Test/olcum icin: scope noktasi dunya transformu.
func get_scope_point_global() -> Transform3D:
	if scope_point != null:
		return scope_point.global_transform
	return global_transform

## Test/olcum icin: namlu ileri yonu (dunya).
func get_muzzle_forward_global() -> Vector3:
	return _muzzle_forward_global()

func get_aim_alignment() -> float:
	# Namlu ileri vs kamera ileri nokta carpimi (1.0 = mukemmel ayni yon).
	# Silah WeaponMount altinda oldugu icin ekran donusuyle birlikte doner;
	# kucuk procedural offset (hipfire sway + tepme) yuzunden 1.0'in biraz
	# altinda kalmasi normaldir (>0.94 beklenir).
	return _muzzle_forward_global().dot(_camera_forward_global())

func get_eject_dir_gunspace() -> Vector3:
	if eject_port == null:
		return Vector3.ZERO
	var b: Basis = eject_port.global_transform.basis.orthonormalized()
	if last_eject_vel.length() < 0.001:
		return Vector3.ZERO
	return Vector3(last_eject_vel.dot(b.x), last_eject_vel.dot(b.y), last_eject_vel.dot(b.z)).normalized()

func _fire_hitscan() -> void:
	# Mermi namlunun baktigi yere gider: isin Muzzle konumundan namlu
	# ileri yonuyle cikar (donus + sway + tepme sapmasi dahildir).
	last_shot_hit_ok = false
	last_shot_dist = 0.0
	if camera_node == null or muzzle == null:
		return
	var mz_from: Vector3 = muzzle.global_position
	var mz_dir: Vector3 = _muzzle_forward_global()
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var q := PhysicsRayQueryParameters3D.create(mz_from, mz_from + mz_dir * 100.0)
	q.exclude = [get_node_or_null("../../").get_rid()] if get_node_or_null("../../") is CollisionObject3D else []
	var hit: Dictionary = space.intersect_ray(q)
	var end_p: Vector3 = mz_from + mz_dir * 100.0
	if not hit.is_empty():
		end_p = hit["position"]
		last_shot_hit = end_p
		last_shot_hit_ok = true
		last_shot_dist = mz_from.distance_to(end_p)
		shots_hit += 1
	else:
		last_shot_hit = end_p
	_spawn_tracer(muzzle.global_position, end_p)

func _spawn_tracer(a: Vector3, b: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	if scene == null:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.006, 0.006, 1.0)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mi.material_override = mat
	scene.add_child(mi)
	var mid: Vector3 = (a + b) * 0.5
	mi.global_position = mid
	var d: Vector3 = b - a
	var dist: float = maxf(d.length(), 0.001)
	mi.scale = Vector3(1.0, 1.0, dist)
	if d.length() > 0.0001:
		mi.look_at(b, Vector3.UP)
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(mi.queue_free)

func _spawn_casing(live: bool) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	if scene == null or eject_port == null:
		return
	var rb := RigidBody3D.new()
	rb.mass = 0.005
	rb.gravity_scale = 1.0
	rb.linear_damp = 0.4
	rb.angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.7
	rb.physics_material_override = pm
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, 0.028) if not live else Vector3(0.013, 0.013, 0.045)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	if live:
		mat.albedo_color = Color(0.85, 0.62, 0.15)
	else:
		mat.albedo_color = Color(0.72, 0.53, 0.20)
	mat.metallic = 0.8
	mat.roughness = 0.35
	mi.material_override = mat
	rb.add_child(mi)
	if live:
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.007
		sm.height = 0.018
		tip.mesh = sm
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.75, 0.60, 0.25)
		tmat.metallic = 0.9
		tmat.roughness = 0.25
		tip.material_override = tmat
		tip.position = Vector3(0.0, 0.0, -0.028)
		rb.add_child(tip)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.014, 0.014, 0.046)
	col.shape = shape
	rb.add_child(col)
	scene.add_child(rb)
	rb.global_position = eject_port.global_position
	# Firlama yonu (silah-uzayi): saga +X, yukari +Y, geriye +Z.
	var dir_local := Vector3(1.6 + randf() * 0.7, 2.1 + randf() * 0.9, 1.0 + randf() * 0.6)
	var basis_g: Basis = eject_port.global_transform.basis.orthonormalized()
	var vel: Vector3 = basis_g * dir_local
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-14.0, 14.0), randf_range(-18.0, 18.0), randf_range(-14.0, 14.0))
	casings_ejected += 1
	if live:
		live_ejected += 1
	else:
		empty_ejected += 1
	last_eject_vel = vel
	last_eject_pos = rb.global_position
	last_eject_live = live
	last_casing = rb
	last_casing_y0 = rb.global_position.y
	print("EJECT live=%s pos=%s vel=%s gun_right=%.2f gun_up=%.2f gun_back=%.2f" % [str(live), str(rb.global_position), str(vel), vel.dot(basis_g.x), vel.dot(basis_g.y), vel.dot(basis_g.z)])
	var rb_ref := rb
	var tw2 := create_tween()
	tw2.tween_interval(4.0)
	tw2.tween_callback(rb_ref.queue_free)

func _ready() -> void:
	# Recoil ve hedef marker'lari, el IK'sinden ONCE guncellensin.
	process_priority = -10
	recoil_pivot = $WristPivot/RecoilPivot
	gun = $WristPivot/RecoilPivot/GunVisual/G18_rig/Skeleton3D
	mag_mesh = gun.get_node_or_null("G18_mag") as MeshInstance3D
	bullet_mesh = gun.get_node_or_null("G18_bullet") as MeshInstance3D
	eject_port = $WristPivot/RecoilPivot/EjectPort as Node3D
	if eject_port == null:
		eject_port = $WristPivot/RecoilPivot/Muzzle as Node3D
	muzzle = $WristPivot/RecoilPivot/Muzzle as Node3D
	scope_point = $WristPivot/RecoilPivot/ScopeCameraPoint as Node3D
	# Weapon artik IK_character/WeaponMount/Weapon altinda; sabit "../.." yolu
	# IK_character'a dusuyordu. Player'i yetenegiyle (is_aiming) yukari dogru ara.
	player = null
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor.has_method("is_aiming"):
			player = ancestor
			break
		ancestor = ancestor.get_parent()
	if player != null:
		camera_node = player.get_node_or_null("CameraPivot/Camera") as Camera3D
	bone_slide = gun.find_bone("G18_slide")
	bone_mag = gun.find_bone("G18_mag_2")
	bone_trigger = gun.find_bone("G18_trigger")
	if bone_mag >= 0:
		mag_rest_basis = gun.get_bone_rest(bone_mag).basis
	if bone_trigger >= 0:
		trig_rest_basis = gun.get_bone_rest(bone_trigger).basis
	_sfx_init()

func try_fire() -> void:
	if state != State.IDLE:
		return
	if jammed:
		trigger_target = 0.12
		_play_sfx(SFX_JAM, -10.0)
		return
	if slide_locked or not chambered:
		trigger_target = 0.12
		_play_sfx(SFX_EMPTY, -12.0)
		return
	chambered = false
	shots_fired += 1
	trigger_target = 0.18
	slide_target = SLIDE_TRAVEL
	# Tepme dengesi: dikey ~%60 azaltildi, yatay ~2.6x artirildi.
	# Kalici anchor birikir: silah tam eski yerine gelmez, nisan dagilir.
	# Kameraya da hafif kick + sarsinti gider (player.add_recoil_kick).
	heat = minf(heat + 0.25, 1.0)
	var flyer := 1.35 if randf() < 0.20 else 1.0
	var aiming_now := _is_aiming()
	var recoil_scale := ads_recoil_multiplier if aiming_now else 1.0
	var kick := (1.0 + heat * 0.7) * flyer * recoil_scale
	var yaw_kick := randf_range(-3.4, 3.4) * kick
	recoil_rot_vel += Vector3(
		(2.6 + randf() * 0.8) * kick,
		yaw_kick,
		randf_range(-0.8, 0.8) * recoil_scale)
	recoil_pos_vel += Vector3(
		randf_range(-0.35, 0.35) * recoil_scale,
		(0.12 + randf() * 0.08) * kick,
		(0.60 + randf() * 0.25) * kick)
	if aiming_now:
		# ADS: kalici sapma birikmez; yay sifira doner.
		recoil_anchor = Vector3.ZERO
	else:
		recoil_anchor += Vector3(0.030 * kick, yaw_kick * 0.020, randf_range(-0.008, 0.008))
		recoil_anchor = recoil_anchor.clamp(-Vector3(0.22, 0.35, 0.12), Vector3(0.22, 0.35, 0.12))
	if player != null and player.has_method("add_recoil_kick"):
		player.call("add_recoil_kick", 0.010 * kick, yaw_kick * 0.004)
	_fire_hitscan()
	_spawn_casing(false)
	_play_sfx(SFX_SHOT, -14.0)
	state = State.FIRING
	state_time = FIRE_TIME
	# Nadir gercekci tutukluk + istismar: atesle ayni karede slide cekilirse ek risk.
	var abuse := Input.is_action_just_pressed("rack_slide") or Input.is_action_just_pressed("clear_jam")
	var jam_roll := jam_chance + (JAM_ABUSE_CHANCE if abuse else 0.0)
	if randf() < jam_roll:
		jammed = true

func start_reload_smart() -> void:
	# R: tek tusta gercekci sarjor degisimi. Bos sarjoru dusurur, yeniyi
	# takar; hane isi OTOMATIK surulmez (asagidaki _state_complete'e bak).
	if state != State.IDLE:
		return
	if has_mag:
		auto_reload = true
		start_eject()
	elif not has_mag:
		auto_reload = false
		start_insert()

func start_eject() -> void:
	if state != State.IDLE or not has_mag:
		return
	state = State.EJECTING
	state_time = EJECT_TIME
	if magazine_count > 0:
		_play_sfx(SFX_EJECT_LOADED, -10.0)
	else:
		_play_sfx(SFX_EJECT_EMPTY[randi() % SFX_EJECT_EMPTY.size()], -10.0)
	var was_locked := slide_locked
	has_mag = false
	magazine_count = 0
	slide_locked = false
	# Surgi geride kilitliyse mag degisiminde arkada kalir (gercekci);
	# degilse surgi onde durur.
	slide_target = SLIDE_TRAVEL if was_locked else 0.0
	mag_offset_target = _to_bone(MAG_EJECT_POS)
	mag_tilt_target = MAG_EJECT_TILT

func start_insert() -> void:
	if state != State.IDLE or has_mag:
		return
	state = State.INSERTING
	state_time = INSERT_TIME
	_play_sfx(SFX_INSERT_LOADED, -10.0)
	mag_offset = _to_bone(MAG_EJECT_POS)
	mag_tilt = MAG_EJECT_TILT
	mag_offset_target = Vector3.ZERO
	mag_tilt_target = 0.0

func start_rack() -> void:
	# F: surgu cek. Tutuklukta da calisir (jam'i temizler), sarjoru
	# ASLA oynatmaz (mag bug fix: rack sirasinda mag hedefleri sifirlanir).
	# Hanede dolu (canli) mermi varsa slider'dan disari atilir.
	if state != State.IDLE:
		return
	if jammed:
		jammed = false
	if chambered:
		_spawn_casing(true)
		chambered = false
	# Surgi zaten gerideyse (kilitli / offset arkada) cekme sesi YOK:
	# sadece birakma sesi duyulur (RACKING bitiminde).
	var slide_back := slide_locked or slide_offset > 0.04
	# Bosken (kilitli + hane bos + mag bos ya da magsiz) manuel kapatma:
	# rack bitince slide onde kalacak, bayrak sonraki sarjorde otomatik acilmayi engeller.
	var empty_close := slide_locked and not chambered and (not has_mag or magazine_count == 0)
	if empty_close:
		slide_closed_manually = true
	state = State.RACKING
	state_time = RACK_TIME
	slide_target = SLIDE_TRAVEL
	if not slide_back:
		_play_sfx(SFX_SLIDE_PULL, -10.0)
	mag_offset_target = Vector3.ZERO
	mag_tilt_target = 0.0

func start_clear() -> void:
	# Geriye uyumluluk: eski C tusu da F ile ayni isi yapar — surgu cek,
	# mag yerinde kalir. Jam yoksa ve hane doluysa ise yaramaz.
	if state != State.IDLE:
		return
	if not jammed and (chambered or not has_mag or magazine_count <= 0):
		if not jammed and not slide_locked and chambered:
			return
	if jammed:
		jammed = false
	if chambered:
		_spawn_casing(true)
		chambered = false
	var slide_back_c := slide_locked or slide_offset > 0.04
	state = State.RACKING
	state_time = RACK_TIME
	slide_target = SLIDE_TRAVEL
	if not slide_back_c:
		_play_sfx(SFX_SLIDE_PULL, -10.0)
	mag_offset_target = Vector3.ZERO
	mag_tilt_target = 0.0

func _feed_from_mag() -> void:
	slide_locked = false
	if has_mag and magazine_count > 0:
		chambered = true
		magazine_count -= 1
		# Basarili rack ile hane doldu, manuel-kapali bayragi temizlenir.
		slide_closed_manually = false
	else:
		chambered = false

func _update_slide_lock() -> void:
	var was_locked := slide_locked
	slide_locked = has_mag and magazine_count == 0 and not chambered and not jammed
	if slide_locked:
		# Dogal bosalma kilidi: manuel bayrak temizlenir (sonraki sarjor normalde geride kalir).
		slide_closed_manually = false
		slide_target = SLIDE_TRAVEL
		if not was_locked:
			_play_sfx(SFX_SLIDE_LOCK, -10.0)

func _state_complete() -> void:
	match state:
		State.FIRING:
			state = State.IDLE
			slide_target = 0.0
			if jammed:
				slide_target = SLIDE_JAM_HOLD
			elif has_mag and magazine_count > 0:
				magazine_count -= 1
				chambered = true
			else:
				chambered = false
			_update_slide_lock()
		State.EJECTING:
			state = State.IDLE
			if auto_reload:
				# R zinciri: bos sarjor dustu, simdi yeniyi tak.
				start_insert()
		State.INSERTING:
			state = State.IDLE
			has_mag = true
			magazine_count = MAG_CAPACITY
			mag_offset = Vector3.ZERO
			mag_tilt = 0.0
			mag_offset_target = Vector3.ZERO
			mag_tilt_target = 0.0
			auto_reload = false
			# Gercek hayat: yeni sarjor haneyi doldurmaz!
			# Hane bossa normalde surgu geride kalir, F ile cekmek gerekir.
			# ANCAK once bosken F ile manuel kapatildiysa slide KAPALI kalir
			# (ates etmez, cunku hane bos) — sonraki F rack ile doldurulur.
			if not chambered and not slide_closed_manually:
				slide_locked = true
				slide_target = SLIDE_TRAVEL
				_play_sfx(SFX_SLIDE_LOCK, -10.0)
			elif not chambered and slide_closed_manually:
				slide_locked = false
				slide_target = 0.0
			else:
				slide_closed_manually = false
				_update_slide_lock()
		State.RACKING:
			state = State.IDLE
			slide_target = 0.0
			_play_sfx(SFX_SLIDE_RELEASE, -10.0)
			# Rack mag'i oynatmaz (bug fix garantisi).
			mag_offset = Vector3.ZERO
			mag_tilt = 0.0
			mag_offset_target = Vector3.ZERO
			mag_tilt_target = 0.0
			_feed_from_mag()
		State.CLEARING:
			state = State.IDLE
			jammed = false
			slide_target = 0.0
			mag_offset = Vector3.ZERO
			mag_tilt = 0.0
			mag_offset_target = Vector3.ZERO
			mag_tilt_target = 0.0
			_feed_from_mag()

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	if Input.is_action_just_pressed("fire"):
		try_fire()
	if Input.is_action_just_pressed("eject_mag"):
		start_reload_smart()
	if Input.is_action_just_pressed("insert_mag"):
		start_insert()
	if Input.is_action_just_pressed("rack_slide"):
		start_rack()
	if Input.is_action_just_pressed("clear_jam"):
		start_clear()

	heat = maxf(heat - delta * 2.6, 0.0)

	if state_time > 0.0:
		state_time -= delta
		if state_time <= 0.0:
			_state_complete()

	if jammed and state == State.IDLE:
		slide_target = SLIDE_JAM_HOLD
	slide_offset = lerpf(slide_offset, slide_target, clampf(delta * 26.0, 0.0, 1.0))

	trigger_press = lerpf(trigger_press, trigger_target, clampf(delta * 24.0, 0.0, 1.0))
	if state != State.FIRING:
		trigger_target = lerpf(trigger_target, 0.0, clampf(delta * 8.0, 0.0, 1.0))

	mag_offset = mag_offset.lerp(mag_offset_target, clampf(delta * 7.0, 0.0, 1.0))
	mag_tilt = lerpf(mag_tilt, mag_tilt_target, clampf(delta * 7.0, 0.0, 1.0))
	# NOT: namlu rijit tutulur, bakis-noktasi yakinsamasi YOK — silahin
	# donusu balistigi yonetir (silahi dondurerek nisan alinir).

	# Hip-fire: mevcut kalici anchor + hizli spring davranisi aynen korunur.
	# ADS: hedef sifirdir; ads_recoil_recovery_speed ile kritik sonumlu,
	# daha yavas ve TAM sifira donen bir yay kullanilir.
	aiming = _is_aiming()
	var rot_target := Vector3.ZERO
	var pos_target := Vector3.ZERO
	var rot_k := 210.0
	var rot_c := 15.0
	var pos_k := 190.0
	var pos_c := 16.0
	if aiming:
		recoil_anchor = recoil_anchor.lerp(Vector3.ZERO, 1.0 - exp(-ads_recoil_recovery_speed * delta))
		if recoil_anchor.length() < ads_recoil_return_epsilon:
			recoil_anchor = Vector3.ZERO
		var w := maxf(ads_recoil_recovery_speed, 0.1)
		rot_k = w * w
		rot_c = 2.0 * w
		pos_k = w * w
		pos_c = 2.0 * w
	else:
		recoil_anchor = recoil_anchor.lerp(Vector3.ZERO, clampf(delta * 0.45, 0.0, 1.0))
		rot_target = recoil_anchor
		pos_target = recoil_anchor * 0.25
	var steps := maxi(1, int(delta / 0.0083333))
	var h := delta / float(steps)
	for i in range(steps):
		var rot_acc := (rot_target - recoil_rot_cur) * rot_k - recoil_rot_vel * rot_c
		recoil_rot_vel += rot_acc * h
		recoil_rot_cur += recoil_rot_vel * h
		var pos_acc := (pos_target - recoil_pos_cur) * pos_k - recoil_pos_vel * pos_c
		recoil_pos_vel += pos_acc * h
		recoil_pos_cur += recoil_pos_vel * h
	recoil_rot_cur = recoil_rot_cur.clamp(-Vector3.ONE * 0.50, Vector3.ONE * 0.50)
	recoil_pos_cur = recoil_pos_cur.clamp(-Vector3.ONE * 0.08, Vector3.ONE * 0.08)
	if aiming and recoil_anchor == Vector3.ZERO \
			and recoil_rot_cur.length() < ads_recoil_return_epsilon \
			and recoil_rot_vel.length() < ads_recoil_return_epsilon \
			and recoil_pos_cur.length() < ads_recoil_return_epsilon \
			and recoil_pos_vel.length() < ads_recoil_return_epsilon:
		recoil_rot_cur = Vector3.ZERO
		recoil_rot_vel = Vector3.ZERO
		recoil_pos_cur = Vector3.ZERO
		recoil_pos_vel = Vector3.ZERO
	recoil_pivot.rotation = recoil_rot_cur
	recoil_pivot.position = recoil_pos_cur

	if bone_slide >= 0:
		var rest_slide := gun.get_bone_rest(bone_slide)
		# Olcumle dogrulandi (slide-COM bagi dunya +Z'ye gider): bone +X
		# dunyada geriye (nisanciya dogru) gider. Ates/rack'te surgü arkaya.
		gun.set_bone_pose_position(bone_slide, rest_slide.origin + Vector3(slide_offset, 0.0, 0.0))
	if bone_trigger >= 0:
		gun.set_bone_pose_rotation(bone_trigger, trig_rest_basis * Basis(Quaternion.from_euler(Vector3(0.0, 0.0, trigger_press))))
	if bone_mag >= 0:
		var rest_mag := gun.get_bone_rest(bone_mag)
		gun.set_bone_pose_position(bone_mag, rest_mag.origin + mag_offset)
		gun.set_bone_pose_rotation(bone_mag, mag_rest_basis * Basis(Quaternion.from_euler(Vector3(0.0, 0.0, mag_tilt))))
	if bullet_mesh != null:
		# Slider gerideyken (rack) haznedeki siradaki mermi gorunur:
		# sarjorde mermi varsa pirinc gorunur, yoksa gorunmez.
		if state == State.RACKING and slide_offset > 0.02:
			bullet_mesh.visible = has_mag and magazine_count > 0
		else:
			bullet_mesh.visible = chambered
