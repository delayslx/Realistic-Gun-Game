extends CharacterBody3D
## First-person controller: strict Bodycam-style wrist aim.
## Mouse ALWAYS turns the head/camera directly (hip + ADS, ADS = lower sens).
## The gun is a heavy object pivoted at the WRIST (WristPivot on GripRight):
## fast turns swing gun+arms EXTRA in the SAME direction, springs settle it
## back; plus breathing / step sway. Aim is fully
## player-managed: no auto-centering, no camera assist, bullet leaves the
## MUZZLE direction so wrist misalignment = miss. Stop moving to let the
## wrist settle before firing accurately.
## LMB (fire) NEVER aims — it only shoots.
## Movement basis: forward is -Z rotated by yaw. Input.get_vector() returns
## y = backward - forward, so world move = right * x - fwd * y.

const GRAVITY := 9.8
var move_speed := 1.0
@export var mouse_sensitivity := 0.0025
@export var ads_sensitivity_mult := 0.55
## ADS gecis hizi (exp smoothing): dusuk = daha yavas, daha yumusak.
@export var ads_transition_speed := 8.0
## Silah sahnesindeki ScopeCameraPoint'e kamerayi tasi.
@export var use_scope_camera := true
## Scope kamerasi icin near plane; silah geometrisi kirpilmasin.
@export var ads_camera_near := 0.01
## Editorde ince ayar: scope noktasina ek offset.
@export var ads_scope_offset := Transform3D.IDENTITY
var hip_fov := 80.0
var ads_fov := 55.0
var ads_weight := 0.0
var yaw := 0.0
var pitch := 0.0
var kick_offset := 0.0 # legacy: kept so external callers don't break; unused
## Kamera tepkisi: hizli kick (cabuk doner) + kalici drift (yavas doner).
## Silah tam eski yerine gelmez, nisan dagilir; kamera hafif sarsilir.
var cam_kick_pitch := 0.0
var cam_kick_yaw := 0.0
var cam_drift_pitch := 0.0
var cam_drift_yaw := 0.0
var cam_trauma := 0.0
var cam_shake_phase := 0.0
## ---- BILEK (wrist) nisani: donus bilekten ----
## WristPivot, GripRight noktasinda durur; silah onun etrafinda doner.
## Fare kamerayi dondurur, bilek ataletle TERSINE geride kalir (agirlik hissi),
## sonra yavasca yerine oturur. Nefes + hareket sway'i anchor'a biner.
var wrist_rot := Vector3.ZERO
var wrist_vel := Vector3.ZERO
var wrist_anchor := Vector3.ZERO
var wrist_follow := 3.0 # donusle AYNI yon agirlik: kamera sola -> silah sola fazla doner, yay toplar
var wrist_stiffness := 90.0 # yaya sertligi (dusuk = daha agir silah)
var wrist_damping := 12.0
var wrist_yaw_limit := 0.38
var wrist_pitch_min := -0.30
var wrist_pitch_max := 0.32
var wrist_roll_limit := 0.10
## ---- FREE-AIM border (Faz A: silah offset, Faz B: kamera donusu) ----
## Border birimi: silah offset metresi (ekran pikseli DEGIL).
## free_aim: Weapon taban pozisyonundan sapma, x sag, y yukari.
var free_aim := Vector2.ZERO
@export var free_gain := 0.0085
@export var free_border_hip := Vector2(0.036, 0.026)
## ADS border: neredeyse kilitli dürbün. 0.08 = hip border'ın %8'i (~3mm).
## 0.0 yapma: free_aim/free_target bölme sıfıra düşer, hip'e dönüşte snap olur.
var free_border_ads_mult := 0.08
var free_yaw_max := deg_to_rad(65.0)
var free_pitch_max := deg_to_rad(65.0)
## Idle drift fix: hiz-genislemesi kapatildi (0.0). Eskiden fare durunca
## eff border kuculup free_n buyuyor, bilek kendiliginden kayiyordu.
var border_speed_tol := 0.0
var turn_mult := 1.0
## Faz A mikro-eslik: border icinde bile kamera cok az doner (toplam hassasiyet korunur).
@export_range(0.0, 0.4) var micro_turn := 0.18
var free_mouse_speed := 0.0
var sway_breath_amp := Vector2(0.012, 0.010)
var sway_move_amp := 0.035
var sway_breath_speed := 1.6
var sway_phase := 0.0
## Konum suruklenmesi: silah tutusu donus yonune kisa sureli kayar, IK kollari oynar.
var gun_pos_lag := Vector3.ZERO
var gun_pos_vel := Vector3.ZERO
@export var gun_pos_gain := 1.0
var gun_pos_max := 0.028
## Ekran donusune eslik eden konumsal suruklenme (Faz B): kamera sola
## donerken silah da ayni yone kisa sureli kayar + namlu donusu korunur.
var turn_lean := Vector2.ZERO
var turn_lean_vel := Vector2.ZERO
@export var turn_lean_gain := 6.0
var turn_lean_max := Vector2(0.018, 0.013)
## Prosedurel yurume: character.glb'de yurume klibi YOK (tek statik poz),
## adim dongusu kodla yazilir: kafa/kamera bob + govde salinim + kol pompasi.
var char_visual: Node3D
var char_base_pos := Vector3.ZERO
var char_base_rot := Vector3.ZERO
var cursor_free := false
## Eye offset from the head bone in yaw-only space (forward is -Z).
## Measured: head bone sits ~10cm below/behind the eyes (idle anim).
var eye_offset := Vector3(0.0, 0.08, -0.10)
var head_bone := -1
var skel: Skeleton3D
var anim_player: AnimationPlayer
var camera_pivot: Node3D
var camera: Camera3D
var camera_rest_local := Transform3D.IDENTITY
var hip_camera_near := 0.03
var weapon: Node3D
var weapon_mount: Node3D
var scope_point: Node3D
## Silah kendi el hedeflerini tasiyorsa recoil'i sadece silah marker'ina uygula.
var weapon_has_hand_targets := false
var wrist_pivot: Node3D
## Sahnedeki authored el hedefi (IK_character/r_arm_marker); silah kendi
## RightHandTarget marker'ini tasiyorsa asil hedefi hand_rig surer.
var hand_marker: Node3D
## El pozunun GOZ cercevesindeki karsiligi; sahne verisinden (EyeAnchor +
## r_arm_marker) okunur. Boylece editorde ayarlanan tutus oyunda birebir ayni.
var hand_rel := Transform3D.IDENTITY
## Nisan (ADS) alirken elin goz cercevesindeki kaymasi: merkeze + biraz yukari.
var ads_hand_delta := Vector3(-0.12, 0.075, 0.01)
## Sahnedeki authored el pozu okundu mu (ilk fizik karesinde okunur).
var _hand_pose_ready := false
## Tepmenin sag kola yansima orani: silahin tepme kaymasi (recoil_pos_cur) el
## hedefine de eklenir, boylece sag kol + el + parmaklar tepmeye birlikte gider.
## 0 = tepme yalniz silahta kalir (kol hic oynamaz), 1 = el silahla birebir gider.
@export_range(0.0, 1.0) var hand_recoil := 0.55

## Silah artik WeaponManager tarafindan degistirilebilir (her silah kendi
## sahnesi: res://weapons/<ad>/<ad>.tscn). Bu yuzden referanslar takma
## sirasinda yeniden cozulur.
func _bind_weapon() -> void:
	var wm_node: Node = get_node_or_null("/root/WeaponManager")
	if wm_node != null:
		weapon = wm_node.call("mounted_weapon", self) as Node3D
		weapon_mount = wm_node.call("weapon_mount", self) as Node3D
	else:
		weapon_mount = get_node_or_null("IK_character/WeaponMount") as Node3D
		if weapon_mount == null:
			weapon_mount = get_node_or_null("CameraPivot") as Node3D
		weapon = weapon_mount.get_node_or_null("Weapon") as Node3D if weapon_mount != null else null
	wrist_pivot = null
	scope_point = null
	weapon_has_hand_targets = false
	if weapon != null:
		wrist_pivot = weapon.get_node_or_null("WristPivot") as Node3D
		# Her silah kendi ScopeCameraPoint'ini tasir; aktif silahin marker'i okunur.
		scope_point = weapon.get_node_or_null("WristPivot/RecoilPivot/ScopeCameraPoint") as Node3D
		if scope_point == null:
			scope_point = weapon.find_child("ScopeCameraPoint", true, false) as Node3D
		weapon_has_hand_targets = weapon.get_node_or_null("WristPivot/RecoilPivot/RightHandTarget") != null
	if hand_marker == null:
		hand_marker = get_node_or_null("IK_character/r_arm_marker") as Node3D
	var wm := get_node_or_null("/root/WeaponManager")
	if wm != null and not wm.weapon_changed.is_connected(_on_weapon_changed):
		wm.weapon_changed.connect(_on_weapon_changed)

func _on_weapon_changed(_id: String, _w: Node3D) -> void:
	_bind_weapon()

## El pozunu sahne verisinden okur: r_arm_marker'in SAHNEDE yazili (authored)
## pozu, kamera (goz) cercevesine cevrilir. Editor ayni pozu gosterdigi icin
## "editorde ne gorunuyorsa oyunda o" garantisi burada kurulur; sabit sayi yok.
## Ilk fizik karesinde cagrilir: kamera o an gercek goz konumuna oturmustur.
func _capture_hand_pose() -> void:
	if _hand_pose_ready:
		return
	if hand_marker == null:
		hand_marker = get_node_or_null("IK_character/r_arm_marker") as Node3D
	var rig := get_node_or_null("IK_character") as Node3D
	if hand_marker == null or camera_pivot == null or rig == null:
		return
	var eye: Transform3D = rig.global_transform.affine_inverse() * camera_pivot.global_transform
	hand_rel = eye.affine_inverse() * hand_marker.transform
	_hand_pose_ready = true

func _ready() -> void:
	camera_pivot = $CameraPivot
	camera = $CameraPivot/Camera
	camera_rest_local = camera.transform
	hip_camera_near = camera.near
	# WeaponMount hand IK'den once, kamera ayni karede guncellensin.
	process_priority = 0
	_bind_weapon()
	char_visual = $IK_character
	if char_visual != null:
		char_base_pos = char_visual.position
		char_base_rot = char_visual.rotation
	# Animasyonsuz (demo IK_character): AnimationPlayer oynatilmaz, rest/T-pose + IK.
	anim_player = null
	skel = $IK_character/Armature/Skeleton3D as Skeleton3D
	if skel != null:
		head_bone = skel.find_bone("mixamorig_Head")
	_ensure_key_bindings()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Guvenlik agi: project.godot disaridan eski haline dondurulurse bile
## (editor / bulut senkronu) oyun ici tuslar calisir. Eksik R/F'yi ekler,
## istenmeyen G/T'yi temizler: R = sarjor, F = surgu+jam (SADECE F).
func _ensure_key_bindings() -> void:
	_ensure_key("eject_mag", KEY_R)
	_ensure_key("rack_slide", KEY_F)
	_ensure_key("clear_jam", KEY_F)
	_remove_key("rack_slide", KEY_G)
	_remove_key("clear_jam", KEY_G)
	_remove_key("clear_jam", KEY_C)
	_remove_key("insert_mag", KEY_T)

func _ensure_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and int((ev as InputEventKey).keycode) == keycode:
			return
	var nev := InputEventKey.new()
	nev.keycode = keycode as Key
	InputMap.action_add_event(action, nev)

func _remove_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	var doomed: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and int((ev as InputEventKey).keycode) == keycode:
			doomed.append(ev)
	for ev in doomed:
		InputMap.action_erase_event(action, ev)

func add_recoil_kick(up: float = 0.012, side: float = 0.0) -> void:
	# Hizli kick + kalici drift + kisa sarsinti. Drift yavas cozulur:
	# silah/kamera tam eski noktaya donmez, seri atista nisan dagilir.
	cam_kick_pitch += up
	cam_kick_yaw += side * 0.6
	cam_drift_pitch += up * 0.35
	cam_drift_yaw += side * 0.45
	cam_drift_pitch = clampf(cam_drift_pitch, -0.20, 0.30)
	cam_drift_yaw = clampf(cam_drift_yaw, -0.20, 0.20)
	cam_trauma = minf(cam_trauma + 0.25 + absf(up) * 8.0, 1.0)
	# Bilek de tepmeden yukari/ yana savrulur (namlu yukari kacar).
	wrist_vel.x += up * 28.0
	wrist_vel.y += side * 18.0

func is_aiming() -> bool:
	if cursor_free:
		return false
	# ONLY RMB aims. LMB (fire) must never trigger ADS.
	return Input.is_action_pressed("look_hold")

func _free_border() -> Vector2:
	var aiming_now: bool = is_aiming()
	var base: Vector2 = free_border_hip * (free_border_ads_mult if aiming_now else 1.0)
	var speed_norm: float = clampf(free_mouse_speed / 40.0, 0.0, 1.0)
	var eff: Vector2 = base * (1.0 + speed_norm * border_speed_tol)
	# ADS'de border neredeyse yok (~2-3mm): silah merkeze kilitli, dürbün direkt kamera.
	var floor_min := 0.0025 if aiming_now else 0.01
	eff.x = maxf(eff.x, floor_min)
	eff.y = maxf(eff.y, floor_min)
	return eff

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not cursor_free:
		# 2-fazli aim (HIP): Faz A cogunlukla silah + cok az kamera, Faz B border asimi kameraya.
		# ADS (dürbün): border YOK — fare direkt kameraya gider, silah merkezde kilitli.
		var aiming_now: bool = is_aiming()
		var s: float = mouse_sensitivity * (ads_sensitivity_mult if aiming_now else 1.0)
		free_mouse_speed = lerpf(free_mouse_speed, float(event.relative.length()), 0.15)
		var raw := Vector2(event.relative.x * s, event.relative.y * s)
		if aiming_now:
			yaw -= raw.x
			pitch -= raw.y
			pitch = clampf(pitch, deg_to_rad(-65.0), deg_to_rad(40.0))
			# ADS hafif duzeltme: border artigi yavas eritilir (snap yok),
			# bilek esligi minimumda tutulur, nisangah merkezde kilitli kalir.
			free_aim = free_aim.lerp(Vector2.ZERO, 0.15)
			if free_aim.length_squared() < 0.0000001:
				free_aim = Vector2.ZERO
			# Cok hafif bilek esligi: agir durbun hissi, nisani kaydirmaz.
			var ads_lag := 0.08
			wrist_vel.y += raw.x * wrist_follow * ads_lag * 0.35
			wrist_vel.x += raw.y * wrist_follow * ads_lag * 0.35
			return
		# Mikro-eslik (sadece HIP): border icinde bile ekran cok az doner.
		var micro: float = micro_turn
		yaw -= raw.x * micro
		pitch -= raw.y * micro
		pitch = clampf(pitch, deg_to_rad(-65.0), deg_to_rad(40.0))
		var eff: Vector2 = _free_border()
		var dm := Vector2(raw.x * (1.0 - micro) * free_gain, -raw.y * (1.0 - micro) * free_gain)
		var prev: Vector2 = free_aim
		# Tasan kisim SADECE taze mouse'tan gelir: border hizla daralip free_aim
		# disarida kalirsa o fark kameraya tekme olarak aktarilmaz (snap fix).
		var over_m := Vector2.ZERO
		if dm.x > 0.0:
			if prev.x >= eff.x:
				over_m.x = dm.x
			else:
				over_m.x = maxf(0.0, prev.x + dm.x - eff.x)
		elif dm.x < 0.0:
			if prev.x <= -eff.x:
				over_m.x = dm.x
			else:
				over_m.x = minf(0.0, prev.x + dm.x + eff.x)
		if dm.y > 0.0:
			if prev.y >= eff.y:
				over_m.y = dm.y
			else:
				over_m.y = maxf(0.0, prev.y + dm.y - eff.y)
		elif dm.y < 0.0:
			if prev.y <= -eff.y:
				over_m.y = dm.y
			else:
				over_m.y = minf(0.0, prev.y + dm.y + eff.y)
		free_aim = Vector2(clampf(prev.x + dm.x, -eff.x, eff.x), clampf(prev.y + dm.y, -eff.y, eff.y))
		if over_m.length_squared() > 0.0:
			# Lineer donus + event basina guvenlik siniri (free_gain'den bagimsiz his).
			var rad := Vector2(over_m.x / maxf(free_gain, 0.02), -over_m.y / maxf(free_gain, 0.02)) * turn_mult
			rad.x = clampf(rad.x, -0.06, 0.06)
			rad.y = clampf(rad.y, -0.06, 0.06)
			yaw -= rad.x
			pitch -= rad.y
			pitch = clampf(pitch, deg_to_rad(-65.0), deg_to_rad(40.0))
			# HIP fazı: tam lag (bu dala sadece hip girer, ADS yukarıda return eder).
			wrist_vel.y -= rad.x * wrist_follow
			wrist_vel.x -= rad.y * wrist_follow
			gun_pos_vel.x += rad.x * gun_pos_gain
			gun_pos_vel.y -= rad.y * gun_pos_gain
			# Ekran donusune eslik: ayni yone kayma (sola donus -> sola kayma, yukari -> yukari).
			turn_lean_vel.x += rad.x * turn_lean_gain
			turn_lean_vel.y += -rad.y * turn_lean_gain

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var move_dir := right * input_vec.x - fwd * input_vec.y
	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
	move_and_slide()

	if Input.is_action_just_pressed("toggle_cursor"):
		cursor_free = not cursor_free
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if cursor_free else Input.MOUSE_MODE_CAPTURED)

	kick_offset = 0.0 # always zero: recoil moves only the gun
	# Head-locked pivot: position tracks the animated head bone (eye height),
	# rotation stays yaw/pitch driven so anim head-tilt never induces nausea.
	# Pivot origin == eye, so the Camera child sits exactly at the eye.
	if skel != null and head_bone >= 0:
		var head_world: Vector3 = skel.global_transform * skel.get_bone_global_pose(head_bone).origin
		camera_pivot.global_position = head_world + Basis(Vector3.UP, yaw) * eye_offset
	var aiming_now: bool = is_aiming()
	# Kamera tepkisi cozumu: hizli kick cabuk, drift cok yavas doner.
	cam_kick_pitch = lerpf(cam_kick_pitch, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	cam_kick_yaw = lerpf(cam_kick_yaw, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	# Hip: kalici drift cok yavas cozulur. ADS: tamamen sifira doner.
	var drift_rate: float = 7.0 if aiming_now else 0.35
	cam_drift_pitch = lerpf(cam_drift_pitch, 0.0, clampf(delta * drift_rate, 0.0, 1.0))
	cam_drift_yaw = lerpf(cam_drift_yaw, 0.0, clampf(delta * drift_rate, 0.0, 1.0))
	if aiming_now:
		if absf(cam_drift_pitch) < 0.0005:
			cam_drift_pitch = 0.0
		if absf(cam_drift_yaw) < 0.0005:
			cam_drift_yaw = 0.0
	cam_trauma = maxf(cam_trauma - delta * 2.2, 0.0)
	cam_shake_phase += delta * 55.0
	var shake_amp: float = cam_trauma * cam_trauma * 0.018
	var sh_x: float = sin(cam_shake_phase * 1.13) * shake_amp
	var sh_y: float = cos(cam_shake_phase * 0.87) * shake_amp
	var sh_r: float = sin(cam_shake_phase * 0.53) * shake_amp * 0.6
	camera_pivot.rotation = Vector3(
		pitch + cam_kick_pitch + cam_drift_pitch + sh_x,
		yaw + cam_kick_yaw + cam_drift_yaw + sh_y,
		sh_r)
	# Kamera yerine oturdu: authored el pozunu bir kez oku (editor ile ayni veri).
	_capture_hand_pose()

	var _speed := Vector2(velocity.x, velocity.z).length()
	# Karakter sabit: idle/yurume anim gecisi kapatildi.
	# Tek statik poz (mixamo_com) korunur, IK kollar calismaya devam eder.
	_lock_static_pose()

	# ADS blend: hip base -> centered sight line, FOV zoom, sway shrinks.
	# Gecis her iki yonde de exp smoothing; ani sicrama yok.
	var ads_target: float = 1.0 if aiming_now else 0.0
	ads_weight = lerpf(ads_weight, ads_target, clampf(1.0 - exp(-ads_transition_speed * delta), 0.0, 1.0))
	if absf(ads_weight - ads_target) < 0.0001:
		ads_weight = ads_target
	if camera != null:
		camera.fov = lerpf(hip_fov, ads_fov, ads_weight) + cam_trauma * 1.0
	# Karakter sabit: yurume + nefes sway'i kapali; silah/bilek sadece
	# input + recoil ile oynar, bos dururken kipirdama yok.
	# Konum suruklenme yayi: tutus donus yonune kisa sureli kayar, IK kollari oynar.
	var psteps := maxi(1, int(delta / 0.0083333))
	var ph := delta / float(psteps)
	for pi in range(psteps):
		var pacc: Vector3 = -gun_pos_lag * 120.0 - gun_pos_vel * 11.0
		gun_pos_vel += pacc * ph
		gun_pos_lag += gun_pos_vel * ph
	gun_pos_lag.x = clampf(gun_pos_lag.x, -gun_pos_max, gun_pos_max)
	gun_pos_lag.y = clampf(gun_pos_lag.y, -gun_pos_max, gun_pos_max)
	gun_pos_lag.z = clampf(gun_pos_lag.z, -gun_pos_max, gun_pos_max)
	# Turn-lean yayi: donus yonune kayar, yavasca merkeze doner (gozle gorunur suruklenme).
	var tsteps := maxi(1, int(delta / 0.0083333))
	var th := delta / float(tsteps)
	for ti in range(tsteps):
		var tacc: Vector2 = -turn_lean * 90.0 - turn_lean_vel * 9.0
		turn_lean_vel += tacc * th
		turn_lean += turn_lean_vel * th
	turn_lean.x = clampf(turn_lean.x, -turn_lean_max.x, turn_lean_max.x)
	turn_lean.y = clampf(turn_lean.y, -turn_lean_max.y, turn_lean_max.y)
	free_mouse_speed = lerpf(free_mouse_speed, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	# ADS'de fare oynamasa bile border artigi yavas erir: durbun merkezde kilitli.
	if aiming_now:
		free_aim = free_aim.lerp(Vector2.ZERO, clampf(delta * 5.0, 0.0, 1.0))
		if free_aim.length_squared() < 0.0000001:
			free_aim = Vector2.ZERO
		turn_lean = turn_lean.lerp(Vector2.ZERO, clampf(delta * 4.0, 0.0, 1.0))
	var eff_b: Vector2 = _free_border()
	var free_n := Vector2(clampf(free_aim.x / eff_b.x, -1.0, 1.0), clampf(free_aim.y / eff_b.y, -1.0, 1.0))
	# Dogrusal uc donusu: border'da tam 65 derece, merkezde 0. ADS'de hedef ~0.
	var free_target := Vector3(free_n.y * free_pitch_max, -free_n.x * free_yaw_max, 0.0) * (1.0 - ads_weight * 0.95)
	# Silah artik elde: konum dogrudan silaha yazilmaz; _process'te WeaponMount surulur.
	# Bilek hedefi: sadece free_target. Nefes salinimi kapatildi (bos dururken kipirdama yok).
	# Recoil harici otomatik sifirlama yok; ates sirasinda weapon_controller namluyu kaldirir.
	wrist_anchor = free_target
	# Adim pompasi kapatildi: karakter sabit, bilek sadece input + recoil ile oynar.
	# ADS bileği daha sert + sönümlü: dürbünde gezme yok, recoil hariç kilitli.
	var stiff: float = wrist_stiffness * (2.2 if aiming_now else 1.0)
	var damp: float = wrist_damping * (1.6 if aiming_now else 1.0)
	var steps := maxi(1, int(delta / 0.0083333))
	var h := delta / float(steps)
	for i in range(steps):
		var acc: Vector3 = (wrist_anchor - wrist_rot) * stiff - wrist_vel * damp
		wrist_vel += acc * h
		wrist_rot += wrist_vel * h
	wrist_rot.x = clampf(wrist_rot.x, -free_pitch_max, free_pitch_max)
	wrist_rot.y = clampf(wrist_rot.y, -free_yaw_max, free_yaw_max)
	wrist_rot.z = clampf(wrist_rot.z, -wrist_roll_limit, wrist_roll_limit)
	# WeaponMount ve el hedefi _process'te (hand_rig'den once) guncellenir.
	# Karakter sabit: prosedurel adim dongusu kapatildi.
	# Kamera bob ve govde salinim yok, IK kollar/silah canli kalir.
	if char_visual != null:
		char_visual.position = char_base_pos
		char_visual.rotation = char_base_rot

## WeaponMount'u ve (fallback) r_arm_marker'i ayni karede, hand_rig'den once
## gunceller. Boylece hedef marker ile silahin tasiyicisi ayni transformu tasir.
func _update_weapon_mount() -> void:
	if not _hand_pose_ready or camera_pivot == null:
		return
	var sway_scale: float = 1.0 - ads_weight * 0.95
	var base_pos: Vector3 = hand_rel.origin + ads_hand_delta * ads_weight
	var free_aim_offset := Vector3(free_aim.x, free_aim.y, 0.0) * (1.0 - ads_weight * 0.92)
	var hand_local: Vector3 = base_pos + free_aim_offset + Vector3(turn_lean.x, turn_lean.y, 0.0) * sway_scale + gun_pos_lag * sway_scale
	# Silah kendi RightHandTarget'ini tasiyorsa recoil orada uygulanir; burada
	# ikinci kez eklenmez. Eski silahlar icin fallback davranisi korunur.
	if not weapon_has_hand_targets and weapon != null and hand_recoil > 0.0:
		var rp: Variant = weapon.get("recoil_pos_cur")
		if typeof(rp) == TYPE_VECTOR3:
			var wb: Basis = camera_pivot.global_transform.basis.inverse() * weapon.global_transform.basis
			hand_local += wb * (rp as Vector3) * hand_recoil
	# Bilek donusu KAMERA eksenlerinde uygulanir: X = yukari/asagi (pitch),
	# Y = saga/sola (yaw), Z = yatis (roll). Authored el yonelimi korunur.
	var hand_basis := camera_pivot.global_transform.basis * Basis.from_euler(wrist_rot) * hand_rel.basis
	var hand_xform := Transform3D(hand_basis.orthonormalized(), camera_pivot.global_transform * hand_local)
	# Silah hedef marker'i tasiyorsa r_arm_marker'in tek sahibi hand_rig'dir.
	if hand_marker != null and not weapon_has_hand_targets:
		hand_marker.global_transform = hand_xform
	if weapon_mount != null:
		weapon_mount.global_transform = hand_xform

## ADS/hip kamera gecisi. Silahin ScopeCameraPoint'i varsa kamera oraya
## yumusakca tasinir; yoksa eski goz kamerasi korunur.
## _process priority 0: weapon recoil (-10) sonrasi, hand IK (10) oncesi.
func _process(_delta: float) -> void:
	_update_weapon_mount()
	if camera == null or camera_pivot == null:
		return
	var eye_xform: Transform3D = camera_pivot.global_transform * camera_rest_local
	var w: float = smoothstep(0.0, 1.0, ads_weight)
	if scope_point != null and use_scope_camera and w > 0.0001:
		var scope_xform: Transform3D = scope_point.global_transform * ads_scope_offset
		camera.global_transform = eye_xform.interpolate_with(scope_xform, w)
		camera.near = lerpf(hip_camera_near, ads_camera_near, w)
	else:
		camera.transform = camera_rest_local
		camera.near = hip_camera_near

var _warned_missing: Dictionary = {}

## Karakter sabit tutulur: tek statik poz oynatilir, idle/yurume gecisi yok.
## IK (el/kol/silah) etkilenmez, cunku IK AnimationPlayer sonrasi kemiklere yazar.
func _lock_static_pose() -> void:
	if anim_player == null:
		return
	var anims := anim_player.get_animation_list()
	if anims.is_empty():
		return
	var static_id := "mixamo_com" if anim_player.has_animation("mixamo_com") else String(anims[0])
	if anim_player.current_animation != static_id:
		anim_player.play(static_id)

func _play_anim(anim_id: String) -> void:
	if anim_player == null:
		return
	if anim_id == "walking":
		# Yurume prosedurel (adim dongusu asagida); statik poz yeterli, uyari verme.
		anim_id = "mixamo_com" if anim_player.has_animation("mixamo_com") else anim_id
	if not anim_player.has_animation(anim_id):
		# The current character.glb only ships one clip (e.g. mixamo_com);
		# fall back to the first available clip as a stable base pose for IK
		# instead of erroring every physics frame.
		if not _warned_missing.has(anim_id):
			_warned_missing[anim_id] = true
			push_warning("player_controller: animation not found: " + anim_id
				+ ", falling back to " + str(anim_player.get_animation_list()))
		var anims := anim_player.get_animation_list()
		if anims.is_empty():
			return
		anim_id = anims[0]
	if anim_player.current_animation == anim_id:
		return
	anim_player.play(anim_id)
