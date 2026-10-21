extends SceneTree
## DEV-ONLY test araci (oyuna bagli degil).
## Kullanim (PowerShell):
##   & "<Godot_console>" --path "<proje>" --resolution 1280x720 \
##     --script "res://dev_test/verify_bodycam.gd" [-- --diag=left|--diag=rthumb]
## Ekran goruntuleri %TEMP%/opencode/*.png altina duser.
## Kapsar: tuslar (R/F, G/T yok), ates/ADS ayrimi, iki eksen silah donusu,
## 4-yon kamera-donus simetrisi, ADS zoom, R/F zinciri, mag sabiti, jam,
## 3-eksen tepme olcumu (5 el), el/parmak yakin cekimleri.

var out_dir := "C:/Users/tunac/AppData/Local/Temp/opencode"
var frame := 0
var t0_ms := 0
var player: Node
var weapon: Node
var cam: Camera3D
var peak_rot := Vector3.ZERO
var peak_z := 0.0
var sampling := false

func check(tag: String, ok: bool, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + tag + " | " + detail)

func _key_list(action: String) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(int((ev as InputEventKey).keycode))
		elif ev is InputEventMouseButton:
			out.append(-int((ev as InputEventMouseButton).button_index))
	return out

func _key_text(action: String) -> String:
	var parts: Array[String] = []
	for e in _key_list(action):
		if e < 0:
			parts.append("Mouse%d" % -e)
		elif e > 0:
			parts.append(OS.get_keycode_string(e))
	return "/".join(parts) if not parts.is_empty() else "(unbound)"

func _shot(tag: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	print("SHOT " + tag + " err=" + str(img.save_png(out_dir + "/" + tag + ".png")))

func _initialize() -> void:
	var packed: PackedScene = load("res://main.tscn")
	root.add_child(packed.instantiate())
	root.size = Vector2i(1280, 720)
	t0_ms = Time.get_ticks_msec()
	print("VERIFY booted")

func _turn_probe(dx: float, dy: float) -> void:
	player.set_meta("pre_yaw", float(player.get("yaw")))
	player.set_meta("pre_pitch", float(player.get("pitch")))
	player.set("weapon_aim_offset", Vector2.ZERO)
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	Input.parse_input_event(ev)

func _read_turn(tag: String) -> void:
	var off: Vector2 = player.get("weapon_aim_offset")
	var dyaw: float = float(player.get("yaw")) - float(player.get_meta("pre_yaw"))
	var dpitch: float = float(player.get("pitch")) - float(player.get_meta("pre_pitch"))
	player.set_meta("lag_" + tag, off)
	player.set_meta("dyaw_" + tag, dyaw)
	player.set_meta("dpitch_" + tag, dpitch)
	print("TURN " + tag + " lag=" + str(off) + " dyaw=%.4f dpitch=%.4f" % [dyaw, dpitch])

func _process(_delta: float) -> bool:
	frame += 1
	if sampling and weapon != null:
		var rr: Vector3 = weapon.get("recoil_rot_cur")
		peak_rot.x = maxf(peak_rot.x, absf(rr.x))
		peak_rot.y = maxf(peak_rot.y, absf(rr.y))
		peak_rot.z = maxf(peak_rot.z, absf(rr.z))
		peak_z = maxf(peak_z, (weapon.get("recoil_pos_cur") as Vector3).z)
	match frame:
		5:
			player = root.get_node("World/Player")
			weapon = root.get_node("World/Player/CameraPivot/Weapon")
			cam = root.get_node("World/Player/CameraPivot/Camera")
			player.set("yaw", 0.0)
			player.set("pitch", -0.05)
			weapon.set("jam_chance", 0.0)
			for a in OS.get_cmdline_user_args():
				if a == "--diag=left":
					root.get_node("World/Player/IK_character").set("dbg_hide_left_fingers", true)
					print("DIAG left fingers hidden")
				elif a == "--diag=rthumb":
					root.get_node("World/Player/IK_character").set("dbg_hide_right_thumb", true)
					print("DIAG right thumb hidden")
			print("KEYS eject_mag=" + _key_text("eject_mag") + " insert_mag=" + _key_text("insert_mag") + " rack_slide=" + _key_text("rack_slide") + " clear_jam=" + _key_text("clear_jam") + " fire=" + _key_text("fire") + " look_hold=" + _key_text("look_hold"))
			var rk: Array = _key_list("rack_slide")
			var ck: Array = _key_list("clear_jam")
			var g_gone := not rk.has(71) and not ck.has(67) and not ck.has(71)
			var t_gone := _key_list("insert_mag").is_empty()
			check("keys", _key_list("eject_mag").has(82) and rk.has(70) and ck.has(70) and g_gone and t_gone, "R/F, G yok=%s T yok=%s" % [str(g_gone), str(t_gone)])
		20:
			Input.action_press("fire")
		28:
			check("fire_no_ads", player.call("is_aiming") == false and float(player.get("ads_weight")) < 0.05, "is_aiming=%s ads_weight=%.3f shots=%d" % [str(player.call("is_aiming")), float(player.get("ads_weight")), int(weapon.get("shots_fired"))])
			Input.action_release("fire")
			check("fire_shoots", int(weapon.get("shots_fired")) >= 1, "shots=%d" % int(weapon.get("shots_fired")))
		32:
			player.set("weapon_aim_offset", Vector2(0.10, 0.08))
			player.set("weapon_aim_raw", Vector2(0.10, 0.08))
		90:
			var rot: Vector3 = (weapon as Node3D).rotation
			check("gun_two_axis", absf(rot.x) > 0.03 and absf(rot.y) > 0.03, "weapon.rotation=" + str(rot))
			_shot("hip_aimed")
		100:
			player.set("weapon_aim_offset", Vector2.ZERO)
		120:
			_shot("hip")
		130:
			Input.action_press("look_hold")
		200:
			var ads_w: float = player.get("ads_weight")
			check("ads_zooms", ads_w > 0.9 and cam.fov < 60.0, "ads_weight=%.3f fov=%.1f wpos=%s" % [ads_w, cam.fov, str((weapon as Node3D).position)])
		206:
			player.set("weapon_aim_offset", Vector2.ZERO)
		208:
			_turn_probe(80.0, 0.0)
		213:
			_read_turn("R")
		215:
			player.set("weapon_aim_offset", Vector2.ZERO)
		217:
			_turn_probe(-80.0, 0.0)
		222:
			_read_turn("L")
		224:
			player.set("weapon_aim_offset", Vector2.ZERO)
		226:
			_turn_probe(0.0, -60.0)
		231:
			_read_turn("U")
		233:
			player.set("weapon_aim_offset", Vector2.ZERO)
		235:
			_turn_probe(0.0, 60.0)
		240:
			_read_turn("D")
			var lag_r: Vector2 = player.get_meta("lag_R")
			var lag_l: Vector2 = player.get_meta("lag_L")
			var lag_u: Vector2 = player.get_meta("lag_U")
			var lag_d: Vector2 = player.get_meta("lag_D")
			var sym_x: float = absf(absf(lag_r.x) - absf(lag_l.x)) / maxf(absf(lag_r.x), 0.001)
			var sym_y: float = absf(absf(lag_u.y) - absf(lag_d.y)) / maxf(absf(lag_u.y), 0.001)
			check("turn_x_both_dirs", lag_r.x < -0.02 and lag_l.x > 0.02 and absf(lag_r.y) < 0.03 and absf(lag_l.y) < 0.03, "R=%s L=%s" % [str(lag_r), str(lag_l)])
			check("turn_y_both_dirs", lag_u.y < -0.02 and lag_d.y > 0.02 and absf(lag_u.x) < 0.03 and absf(lag_d.x) < 0.03, "U=%s D=%s" % [str(lag_u), str(lag_d)])
			check("turn_symmetry", sym_x < 0.4 and sym_y < 0.4, "sym_x=%.2f sym_y=%.2f" % [sym_x, sym_y])
			check("turn_camera", float(player.get_meta("dyaw_R")) < -0.05 and float(player.get_meta("dyaw_L")) > 0.05 and float(player.get_meta("dpitch_U")) > 0.03 and float(player.get_meta("dpitch_D")) < -0.03, "kamera 4 yone dondu")
			_shot("ads")
		250:
			Input.action_release("look_hold")
		330:
			check("ads_releases", float(player.get("ads_weight")) < 0.2, "ads_weight=%.3f" % float(player.get("ads_weight")))
			weapon.set("magazine_count", 0)
			weapon.set("chambered", false)
			weapon.set("slide_locked", false)
			weapon.call("start_reload_smart")
		590:
			check("reload_chain", bool(weapon.get("has_mag")) and int(weapon.get("magazine_count")) == 12 and not bool(weapon.get("chambered")) and bool(weapon.get("slide_locked")) and int(weapon.get("state")) == 0, "has_mag=%s mag=%d chambered=%s slide_locked=%s state=%d" % [str(weapon.get("has_mag")), int(weapon.get("magazine_count")), str(weapon.get("chambered")), str(weapon.get("slide_locked")), int(weapon.get("state"))])
			player.set_meta("mag_before", weapon.get("mag_offset"))
			weapon.call("start_rack")
		730:
			var mag_after: Vector3 = weapon.get("mag_offset")
			var mag_before: Vector3 = player.get_meta("mag_before")
			check("rack_chambers", bool(weapon.get("chambered")) and not bool(weapon.get("slide_locked")) and int(weapon.get("state")) == 0, "chambered=%s slide_locked=%s mag=%d state=%d" % [str(weapon.get("chambered")), str(weapon.get("slide_locked")), int(weapon.get("magazine_count")), int(weapon.get("state"))])
			check("rack_mag_stays", mag_before.length() < 0.01 and mag_after.length() < 0.01, "before=%s after=%s" % [str(mag_before), str(mag_after)])
			weapon.set("jammed", true)
			weapon.call("start_rack")
		872:
			check("rack_clears_jam", not bool(weapon.get("jammed")) and int(weapon.get("state")) == 0, "jammed=%s state=%d" % [str(weapon.get("jammed")), int(weapon.get("state"))])
			peak_rot = Vector3.ZERO
			peak_z = 0.0
			sampling = true
			weapon.call("try_fire")
		910:
			weapon.call("try_fire")
		935:
			weapon.call("try_fire")
		960:
			weapon.call("try_fire")
		985:
			weapon.call("try_fire")
		1020:
			sampling = false
			check("recoil_strong_3axis", peak_rot.x > 0.08 and peak_rot.x < 0.45 and peak_rot.y > 0.02, "peak_flip=%.3f peak_yaw=%.3f peak_roll=%.3f (5 shots, dikey dusuk/yatay yuksek denge)" % [peak_rot.x, peak_rot.y, peak_rot.z])
			check("recoil_no_facelunge", peak_z < 0.085, "peak_rear=%.3f" % peak_z)
			var dbg := Camera3D.new()
			root.get_node("World").add_child(dbg)
			player.set_meta("dbg", dbg)
			var gp: Vector3 = (weapon as Node3D).global_position
			dbg.global_position = gp + Vector3(-0.45, 0.12, 0.30)
			dbg.look_at(gp + Vector3(0.0, 0.02, -0.05))
			dbg.fov = 35.0
			dbg.current = true
		1030:
			_shot("hands_left")
		1040:
			var dbg2: Camera3D = player.get_meta("dbg") as Camera3D
			var gp2: Vector3 = (weapon as Node3D).global_position
			dbg2.global_position = gp2 + Vector3(0.40, 0.25, 0.15)
			dbg2.look_at(gp2)
		1050:
			_shot("hands_right")
		1060:
			print("VERIFY DONE fps=%.1f" % (float(frame) / (float(Time.get_ticks_msec() - t0_ms) / 1000.0)))
			return true
	return false
