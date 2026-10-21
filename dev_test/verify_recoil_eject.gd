extends SceneTree
## Detayli dogrulama: namlu-ekran hizasi, slider, tepme dengesi,
## kalici sapma, kamera efekti, kovan (bos/canli) yonu + dususu, isabet.
## Kullanim (PowerShell):
##   & godot --headless --path <proje> --script res://dev_test/verify_recoil_eject.gd
## Cikis: PASS/FAIL + TURN/SLIDE/EJECT/HIT loglari.

var out_dir := "C:/Users/tunac/AppData/Local/Temp/opencode"
var frame := 0
var player: Node
var weapon: Node
var cam: Camera3D
var muzzle: Node3D
var eject_port: Node3D
var fails := 0
var slide_peak := 0.0
var rot_peak := Vector3.ZERO
var sampling_slide := false
var sampling_recoil := false
var casing_y0 := 0.0
var base_empty := 0
var base_live := 0
var align_samples: Array = []

func check(tag: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + tag + " | " + detail)

func _initialize() -> void:
	var packed: PackedScene = load("res://main.tscn")
	root.add_child(packed.instantiate())
	print("VERIFY_RECOIL_EJECT booted")

func _aim_dot() -> float:
	return float(weapon.call("get_aim_alignment"))

func _muzzle_fwd() -> Vector3:
	return -muzzle.global_transform.basis.z.normalized()

func _cam_fwd() -> Vector3:
	return -cam.global_transform.basis.z.normalized()

func _process(_delta: float) -> bool:
	frame += 1
	if sampling_slide and weapon != null:
		slide_peak = maxf(slide_peak, float(weapon.get("slide_offset")))
	if sampling_recoil and weapon != null:
		var rr: Vector3 = weapon.get("recoil_rot_cur")
		rot_peak.x = maxf(rot_peak.x, absf(rr.x))
		rot_peak.y = maxf(rot_peak.y, absf(rr.y))
		rot_peak.z = maxf(rot_peak.z, absf(rr.z))
	match frame:
		5:
			player = root.get_node("World/Player")
			weapon = root.get_node("World/Player/CameraPivot/Weapon")
			cam = root.get_node("World/Player/CameraPivot/Camera")
			muzzle = root.get_node("World/Player/CameraPivot/Weapon/RecoilPivot/Muzzle")
			eject_port = root.get_node("World/Player/CameraPivot/Weapon/RecoilPivot/EjectPort")
			weapon.set("jam_chance", 0.0)
			player.set("yaw", 0.0)
			player.set("pitch", 0.0)
			check("scene_refs", player != null and weapon != null and cam != null and muzzle != null and eject_port != null, "namlu/surgu/kamera bulundu")
		10:
			# Yon logu: duz bakis hizasi
			var d0 := _aim_dot()
			align_samples.append(d0)
			print("AIM yaw=0 pitch=0 dot=%.4f muzzle=%s cam=%s" % [d0, str(_muzzle_fwd()), str(_cam_fwd())])
			check("aim_center", d0 > 0.94, "dot=%.4f" % d0)
			player.set("yaw", 0.6)
			player.set("pitch", 0.2)
		30:
			var d1 := _aim_dot()
			align_samples.append(d1)
			print("AIM yaw=0.6 pitch=0.2 dot=%.4f muzzle=%s cam=%s" % [d1, str(_muzzle_fwd()), str(_cam_fwd())])
			check("aim_turns_with_screen", d1 > 0.94, "dot=%.4f (ekran dondu, namlu takip etti mi?)" % d1)
			player.set("yaw", -0.6)
			player.set("pitch", -0.25)
		50:
			var d2 := _aim_dot()
			align_samples.append(d2)
			print("AIM yaw=-0.6 pitch=-0.25 dot=%.4f muzzle=%s cam=%s" % [d2, str(_muzzle_fwd()), str(_cam_fwd())])
			check("aim_turns_other_way", d2 > 0.94, "dot=%.4f" % d2)
			var wrong := 0
			for d in align_samples:
				if float(d) < 0.5:
					wrong += 1
			check("aim_dirs_not_wrong", wrong == 0, "ornekler=%s (ters yon yok)" % str(align_samples))
			player.set("yaw", 0.0)
			player.set("pitch", 0.0)
			# Ates oncesi durum: dolu hane + dolu sarjor
			weapon.set("magazine_count", 12)
			weapon.set("has_mag", true)
			weapon.set("chambered", true)
			base_empty = int(weapon.get("empty_ejected"))
			base_live = int(weapon.get("live_ejected"))
			var _sk0 = root.get_node("World/Player/CameraPivot/Weapon/RecoilPivot/GunVisual/G18_rig/Skeleton3D")
			player.set_meta("bs", _sk0.find_bone("G18_slide"))
			player.set_meta("bc", _sk0.find_bone("G18_COM"))
			player.set_meta("p0", _sk0.global_transform * _sk0.get_bone_global_pose(int(player.get_meta("bs"))).origin)
			player.set_meta("c0", _sk0.global_transform * _sk0.get_bone_global_pose(int(player.get_meta("bc"))).origin)
			player.set_meta("mp0", muzzle.global_position)
			player.set_meta("mf0", -muzzle.global_transform.basis.z.normalized())
			slide_peak = 0.0
			sampling_slide = true
			sampling_recoil = true
			rot_peak = Vector3.ZERO
			weapon.call("try_fire")
		70:
			sampling_slide = false
			print("SLIDE peak=%.4f (travel=0.06)" % slide_peak)
			check("slide_moves_on_fire", slide_peak > 0.04, "slider oynadi peak=%.4f" % slide_peak)
			check("empty_casing_on_fire", int(weapon.get("empty_ejected")) == base_empty + 1, "bos kovan dustu bos=%d" % int(weapon.get("empty_ejected")))
			var gv: Vector3 = weapon.call("get_eject_dir_gunspace")
			var raw: Vector3 = weapon.get("last_eject_vel")
			print("EJECT empty gunspace_dir=%s raw_vel=%s pos=%s" % [str(gv), str(raw), str(weapon.get("last_eject_pos"))])
			check("eject_dir_right", gv.x > 0.3, "saga x=%.2f" % gv.x)
			check("eject_dir_up", gv.y > 0.3, "yukari y=%.2f" % gv.y)
			check("eject_dir_back", gv.z > 0.2, "geriye z=%.2f" % gv.z)
			check("eject_not_wrong_way", gv.x > 0.0 and gv.y > 0.0, "ters yone gitmedi")
			var _sk1 = root.get_node("World/Player/CameraPivot/Weapon/RecoilPivot/GunVisual/G18_rig/Skeleton3D")
			var _dz: float = ((_sk1.global_transform * _sk1.get_bone_global_pose(int(player.get_meta("bs"))).origin - (_sk1.global_transform * _sk1.get_bone_global_pose(int(player.get_meta("bc"))).origin)) - (player.get_meta("p0") as Vector3 - (player.get_meta("c0") as Vector3))).z
			print("SLIDE dir dz=%.4f (want >0, rearward)" % _dz)
			check("slide_goes_rearward", _dz > 0.02, "surgu arkaya gitti dz=%.4f" % _dz)
			var _mp0: Vector3 = player.get_meta("mp0")
			var _mf0: Vector3 = player.get_meta("mf0")
			var _hit: Vector3 = weapon.get("last_shot_hit")
			var _cos: float = ((_hit - _mp0).normalized().dot(_mf0)) if _mp0.distance_to(_hit) > 0.01 else -9.0
			print("MUZZLE cos=%.6f (want ~1.0, mermi namlu yonunde)" % _cos)
			check("shot_follows_muzzle", _cos > 0.9999, "mermi namlunun baktigi yere gitti")
			if weapon.get("last_casing") != null:
				casing_y0 = (weapon.get("last_casing") as Node3D).global_position.y
			else:
				casing_y0 = 0.0
			# Tepme dengesi: dikey az, yatay belirgin (yeni hedef: x<0.30, y>0.02)
			print("RECOIL peak_flip=%.3f peak_yaw=%.3f peak_roll=%.3f" % [rot_peak.x, rot_peak.y, rot_peak.z])
			check("recoil_vertical_reduced", rot_peak.x < 0.30 and rot_peak.x > 0.03, "dikey azaldi ama hissediliyor x=%.3f" % rot_peak.x)
			check("recoil_horizontal_up", rot_peak.y > 0.02, "yatay artti y=%.3f" % rot_peak.y)
			# Kalici sapma + kamera efekti (hemen ates sonrasi)
			var anchor: Vector3 = weapon.get("recoil_anchor")
			var drift := Vector2(float(player.get("cam_drift_pitch")), float(player.get("cam_drift_yaw")))
			var kick := Vector2(float(player.get("cam_kick_pitch")), float(player.get("cam_kick_yaw")))
			print("DRIFT anchor=%s cam_drift=%s cam_kick=%s trauma=%.3f" % [str(anchor), str(drift), str(kick), float(player.get("cam_trauma"))])
			check("recoil_not_full_return", anchor.length() > 0.01, "silah tam geri gelmedi anchor=%s" % str(anchor))
			check("camera_effect", (kick.length() > 0.001 or drift.length() > 0.0005) and float(player.get("cam_trauma")) > 0.01, "kameraya tepme yansidi")
			# Isabet: kamera isinindan cikan tracer hedefe/uzaga gitti mi?
			print("HIT ok=%s dist=%.2f point=%s" % [str(weapon.get("last_shot_hit_ok")), float(weapon.get("last_shot_dist")), str(weapon.get("last_shot_hit"))])
			check("shot_goes_forward", float(weapon.get("last_shot_dist")) > 1.0, "mermi ileri gitti")
		130:
			# Kovan dustu mu? (yercekimi: y ilk konuma gore dustu veya hizi negatife dondu)
			if weapon.get("last_casing") != null:
				var c := weapon.get("last_casing") as RigidBody3D
				print("CASING y0=%.3f y1=%.3f vy=%.3f" % [casing_y0, c.global_position.y, c.linear_velocity.y])
				check("casing_falls", c.global_position.y < casing_y0 + 0.35, "kovan havada asili kalmadi")
			else:
				check("casing_falls", false, "kovan bulunamadi")
			# Slider + dolu kovan testi: hane dolu, F'e bas -> canli mermi cikmali
			weapon.set("magazine_count", 5)
			weapon.set("has_mag", true)
			weapon.set("chambered", true)
			base_live = int(weapon.get("live_ejected"))
			weapon.call("start_rack")
		150:
			print("RACK slide=%.4f bullet_visible=%s" % [float(weapon.get("slide_offset")), str((weapon.get("bullet_mesh") as MeshInstance3D).visible if weapon.get("bullet_mesh") != null else false)])
			check("slide_moves_on_rack", float(weapon.get("slide_offset")) > 0.02, "slider cekildi offset=%.4f" % float(weapon.get("slide_offset")))
			check("live_round_on_rack", int(weapon.get("live_ejected")) == base_live + 1 and bool(weapon.get("last_eject_live")), "dolu kovan cikti live=%d" % int(weapon.get("live_ejected")))
			var gv2: Vector3 = weapon.call("get_eject_dir_gunspace")
			print("EJECT live gunspace_dir=%s raw_vel=%s" % [str(gv2), str(weapon.get("last_eject_vel"))])
			check("live_eject_dir", gv2.x > 0.3 and gv2.y > 0.3, "dolu kovan saga-yukari")
			var _skL = root.get_node("World/Player/IK_character/Armature/Skeleton3D")
			var _gsk = root.get_node("World/Player/CameraPivot/Weapon/RecoilPivot/GunVisual/G18_rig/Skeleton3D")
			var _handL: Vector3 = _skL.global_transform * _skL.get_bone_global_pose(_skL.find_bone("mixamorig_LeftHand")).origin
			var _slide: Vector3 = _gsk.global_transform * _gsk.get_bone_global_pose(_gsk.find_bone("G18_slide")).origin
			var _grabd: float = _handL.distance_to(_slide)
			print("RACKHAND sol-el surgu mesafesi=%.3f (want <0.08: el surgu cekti)" % _grabd)
			check("rack_hand_pulls_slide", _grabd < 0.08, "sol el surgunun ustunde")
			player.set("weapon_aim_offset", Vector2.ZERO)
			player.set("weapon_aim_raw", Vector2(-0.28, 0.0))
			weapon.set("magazine_count", 12)
			weapon.set("has_mag", true)
			weapon.set("chambered", true)
		200:
			var _wr: Vector3 = (weapon as Node3D).rotation
			print("GUNROT weapon.rotation=%s (want y~+0.78: ham -0.28 x 2.8)" % str(_wr))
			check("gun_rotates_always", absf(_wr.y - 0.78) < 0.10, "silah govdesi dondu")
			player.set_meta("r_mp0", muzzle.global_position)
			player.set_meta("r_mf0", -muzzle.global_transform.basis.z.normalized())
			player.set_meta("r_cf0", -cam.global_transform.basis.z.normalized())
			player.set_meta("r_cam0", cam.global_transform.origin)
			weapon.call("try_fire")
		240:
			var _mp0: Vector3 = player.get_meta("r_mp0")
			var _mf0: Vector3 = player.get_meta("r_mf0")
			var _cf0: Vector3 = player.get_meta("r_cf0")
			var _cam0: Vector3 = player.get_meta("r_cam0")
			var _rhit: Vector3 = weapon.get("last_shot_hit")
			var _yang: float = rad_to_deg(_mf0.signed_angle_to(_cf0, Vector3.UP))
			var _rcos: float = ((_rhit - _mp0).normalized().dot(_mf0)) if _mp0.distance_to(_rhit) > 0.01 else -9.0
			var _roff: float = rad_to_deg(((_rhit - _cam0).normalized()).angle_to(_cf0)) if _cam0.distance_to(_rhit) > 0.01 else -9.0
			print("ROT yang=%.1f rcos=%.5f cross_off=%.1f (donus balistigi yonetiyor)" % [_yang, _rcos, _roff])
			check("rot_steers_muzzle", absf(_yang) > 10.0, "namlu kameradan ayrildi")
			check("rot_shot_follows_muzzle", _rcos > 0.9995, "mermi donmus namluyu izledi")
			check("rot_moves_impact", _roff > 10.0, "isabet nisangahtan donus yonune kaydi")
			player.set("weapon_aim_offset", Vector2.ZERO)
			player.set("weapon_aim_raw", Vector2.ZERO)
		300:
			print("VERIFY_RECOIL_EJECT DONE fails=%d" % fails)
			return true
	return false
