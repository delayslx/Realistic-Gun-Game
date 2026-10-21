extends Node
## Rig dogrulama probu (editorden bagimsiz, kabuktan calisir):
##   godot --path . res://dev_test/rig_probe.tscn
## Sonuc dosyasi: user://probe_out.txt
##
## Olcer:
##  - goz cercevesi (IK_character lokalinde CameraPivot)
##  - el marker'inin oyundaki lokal pozu (sahneye yazilacak "authored" poz)
##  - silahin el soketinde olmasi, GripRight/GripLeft kalibrasyonu

var out: PackedStringArray = []


func flush() -> void:
	var f := FileAccess.open("user://probe_out.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out))
		f.close()


func wline(text: String) -> void:
	out.append(text)
	flush()


func step(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func tf(t: Transform3D) -> String:
	return "Transform3D(%f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f)" % [
		t.basis.x.x, t.basis.y.x, t.basis.z.x,
		t.basis.x.y, t.basis.y.y, t.basis.z.y,
		t.basis.x.z, t.basis.y.z, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z]


func _ready() -> void:
	var ps := load("res://main.tscn") as PackedScene
	var scene := ps.instantiate() as Node3D
	add_child(scene)
	await step(12)
	var player := scene.get_node_or_null("Player") as Node3D
	var ch := player.get_node_or_null("IK_character") as Node3D
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	if player == null or ch == null or pivot == null:
		wline("HATA: player/ch/pivot bulunamadi")
		get_tree().quit()
		return
	var aR := ch.get_node_or_null("RightHandAttach") as BoneAttachment3D
	var aL := ch.get_node_or_null("LeftHandAttach") as BoneAttachment3D
	var mR := ch.get_node_or_null("r_arm_marker") as Node3D
	var mL := ch.get_node_or_null("l_arm_marker") as Node3D
	wline("1) rig_global " + tf(ch.global_transform))
	wline("2) eye_local  " + tf(ch.global_transform.affine_inverse() * pivot.global_transform))
	if mR != null:
		wline("3) r_marker_local " + tf(mR.transform))
	if mL != null:
		wline("4) l_marker_local " + tf(mL.transform))
	var wm := get_node_or_null("/root/WeaponManager")
	var w: Node3D = wm.get_weapon() if wm != null else null
	wline("5) silah=" + (str(w.name) if w != null else "yok")
		+ " parent=" + (str(w.get_parent().get_path()) if w != null else "-"))
	if w != null and aR != null:
		var to_hand := aR.global_transform.affine_inverse()
		var gr := w.get_node_or_null("WristPivot/RecoilPivot/GripRight") as Node3D
		var gl := w.get_node_or_null("WristPivot/RecoilPivot/GripLeft") as Node3D
		if gr != null:
			wline("6) GripRight hand_local " + str((to_hand * gr.global_transform).origin))
		if gl != null:
			wline("7) GripLeft hand_local " + str((to_hand * gl.global_transform).origin))
		wline("8) silah el lokal " + tf(to_hand * w.global_transform))
	if aR != null and aL != null:
		wline("9) soket mesafe " + str(aR.global_position.distance_to(aL.global_position)))
	# equip/unequip regresyon
	if wm != null:
		wm.unequip(player)
		await step(3)
		wline("10) unequip sonrasi silah=" + str(wm.get_weapon()))
		var w2: Node3D = wm.equip("g18", player)
		await step(4)
		wline("11) equip sonrasi parent=" + (str(w2.get_parent().get_path()) if w2 != null else "yok"))
		wline("12) list_weapons=" + str(wm.list_weapons()))
	# 13) Bilek eksen testi: fare yukari/asagi -> nisan (pitch), sag/sola -> donus (yaw).
	var w3: Node3D = wm.get_weapon() if wm != null else null
	if w3 != null:
		var muzzle := w3.get_node_or_null("WristPivot/RecoilPivot/Muzzle") as Node3D
		if muzzle != null:
			player.set("free_aim", Vector2(0.0, 0.0))
			await step(40)
			var b0 := (muzzle.global_position - w3.global_position).normalized()
			player.set("free_aim", Vector2(0.0, 0.030))
			await step(40)
			var bp := (muzzle.global_position - w3.global_position).normalized()
			player.set("free_aim", Vector2(0.040, 0.0))
			await step(40)
			var by := (muzzle.global_position - w3.global_position).normalized()
			wline("13) namlu dinlenme " + str(b0))
			wline("14) fare YUKARI -> dY=" + str(bp.y - b0.y) + " dX=" + str(bp.x - b0.x))
			wline("15) fare SAGA   -> dX=" + str(by.x - b0.x) + " dY=" + str(by.y - b0.y))
	# 16-19) cerceve / kalibrasyon / kol olcumleri
	rig_probe_extra(ch, aR, aL)
	# 21) Kavrama hedefleri ile sahnedeki marker'lar ozdes mi? (bake dogrulamasi)
	var wt2: Dictionary = ch.call("wrap_targets_local")
	var keys2: Array = wt2.keys()
	keys2.sort()
	var max_diff := 0.0
	for k in keys2:
		var parts := String(k).split("_")
		var side2 := parts[0]
		var stem2 := parts[1]
		var att2 := aR if side2 == "r" else aL
		if att2 == null:
			continue
		var mk2 := att2.get_node_or_null("%s_%s_target" % [side2, stem2]) as Node3D
		if mk2 == null:
			continue
		var d2: float = (wt2[k] as Vector3).distance_to(mk2.transform.origin)
		max_diff = maxf(max_diff, d2)
		wline("21) %s kavrama=%s marker=%s fark=%.6f" % [String(k), str(wt2[k]), str(mk2.transform.origin), d2])
	wline("21b) en buyuk fark = %.6f (0 => bake tam)" % max_diff)
	# 22) Marker -> parmak takibi: cozumun icinden kaydedilen uc pozlariyla.
	ch.set("debug_prints", true)
	await step(20)
	var tips_a: Dictionary = ch.get("debug_tips").duplicate()
	var mk3 := aR.get_node_or_null("r_Index_target") as Node3D if aR != null else null
	if mk3 != null:
		var old3 := mk3.position
		mk3.position = Vector3(0.031073, 0.17, 0.07)
		await step(20)
		var tips_b: Dictionary = ch.get("debug_tips").duplicate()
		mk3.position = old3
		await step(20)
		var kk := "r|Index"
		if tips_a.has(kk) and tips_b.has(kk):
			wline("22) r|Index ucu once=%s sonra=%s fark=%.5f" % [str(tips_a[kk]), str(tips_b[kk]), (tips_a[kk] as Vector3).distance_to(tips_b[kk] as Vector3)])
	# 25) Pole/dirsek: nisan uclarda dirsek el cizgisinin hangi tarafinda?
	# Dirsek beklenen tarafta (asagi/geri) ve isaret hep ayni olmali; ters donme
	# olursa isaret degisir ya da dirsek one cikar.
	if aR != null:
		for spec in [[0.0, 0.0], [0.06, 0.0], [-0.06, 0.0], [0.0, 0.06]]:
			player.set("free_aim", Vector2(spec[0], spec[1]))
			await step(30)
			var da: Dictionary = ch.get("debug_arm").duplicate()
			if da.has("r|Arm") and da.has("r|ForeArm") and da.has("r|Hand"):
				var sh: Vector3 = da["r|Arm"]
				var el: Vector3 = da["r|ForeArm"]
				var hd: Vector3 = da["r|Hand"]
				var dir := (hd - sh).normalized()
				var perp := (el - sh) - dir * (el - sh).dot(dir)
				var pl := ch.global_transform.basis.inverse() * perp
				wline("25) aim=(%.2f,%.2f) dirsek uzunluk=%.4f perp_rig=(%.4f, %.4f, %.4f)" % [spec[0], spec[1], (el - sh).length(), pl.x, pl.y, pl.z])
		player.set("free_aim", Vector2.ZERO)
		await step(30)
	# 24) Tepme sag ele yansiyor mu? (player.hand_recoil)
	if aR != null and player != null:
		var wp := aR.get_node_or_null("Weapon") as Node3D
		if wp != null and wp.has_method("try_fire"):
			player.set("hand_recoil", 0.55)
			await step(30)
			var p0: Vector3 = aR.global_position
			wp.call("try_fire")
			var mx1 := 0.0
			var mr1 := 0.0
			for i in range(24):
				await step(1)
				mx1 = maxf(mx1, p0.distance_to(aR.global_position))
				var rpv: Variant = wp.get("recoil_pos_cur")
				if typeof(rpv) == TYPE_VECTOR3:
					mr1 = maxf(mr1, (rpv as Vector3).length())
			player.set("hand_recoil", 0.0)
			await step(60)
			var p2: Vector3 = aR.global_position
			wp.call("try_fire")
			var mx2 := 0.0
			var mr2 := 0.0
			for i in range(24):
				await step(1)
				mx2 = maxf(mx2, p2.distance_to(aR.global_position))
				var rpv2: Variant = wp.get("recoil_pos_cur")
				if typeof(rpv2) == TYPE_VECTOR3:
					mr2 = maxf(mr2, (rpv2 as Vector3).length())
			wline("24) tepme: recoil=%.4f el_tepe=%.5f | recoil=%.4f el_tepe=%.5f" % [mr1, mx1, mr2, mx2])
			player.set("hand_recoil", 0.55)
			await step(40)
	# 23) Render dogrulamasi: yakin plan kamera ile 3 kare (yalniz pencereli modda).
	if DisplayServer.get_name() != "headless":
		player.set("free_aim", Vector2.ZERO)
		await step(45)
		var wnode := ch.get_node_or_null("RightHandAttach/Weapon")
		var gun_pos: Vector3 = wnode.global_position if wnode != null else ch.global_position + ch.global_transform.basis * Vector3(0, 1.5, 0.35)
		var cam := Camera3D.new()
		cam.name = "ProbeCam"
		add_child(cam)
		cam.global_position = gun_pos + ch.global_transform.basis * Vector3(-0.26, 0.12, 0.10)
		cam.look_at(gun_pos)
		cam.fov = 45.0
		cam.current = true
		await step(15)
		get_viewport().get_texture().get_image().save_png("user://probe_shot_a.png")
		var mk4 := aR.get_node_or_null("r_Index_target") as Node3D if aR != null else null
		if mk4 != null:
			var old4 := mk4.position
			mk4.position = Vector3(0.031073, 0.30, 0.20)
			await step(25)
			get_viewport().get_texture().get_image().save_png("user://probe_shot_b.png")
			mk4.position = old4
			await step(25)
			get_viewport().get_texture().get_image().save_png("user://probe_shot_c.png")
		wline("23) render kareleri kaydedildi (a: kavrama, b: isaret uzatilmis, c: geri)")
		# d/e) Nisan uclarda: dirsek/pole ve ters donme kontrolu.
		for spec in [["d", Vector2(0.06, 0.0)], ["e", Vector2(-0.06, 0.0)]]:
			player.set("free_aim", spec[1])
			await step(45)
			var gp2: Vector3 = wnode.global_position if wnode != null else ch.global_position
			cam.global_position = gp2 + ch.global_transform.basis * Vector3(-0.26, 0.12, 0.10)
			cam.look_at(gp2)
			await step(10)
			get_viewport().get_texture().get_image().save_png("user://probe_shot_%s.png" % str(spec[0]))
		wline("23b) nisan ucu kareleri kaydedildi (d: yaw +, e: yaw -)")
		player.set("free_aim", Vector2.ZERO)
		await step(30)
	wline("DONE")
	get_tree().quit()


## Parmak uclarini (4. kemik) el lokalinde dondurur.
func tips(att: BoneAttachment3D) -> Dictionary:
	var out := {}
	var sk := att.get_node_or_null("../Armature/Skeleton3D") as Skeleton3D
	if sk == null:
		return out
	var long_name := "Right" if String(att.name).begins_with("Right") else "Left"
	var to_att := att.global_transform.affine_inverse()
	for stem in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		var b := sk.find_bone("mixamorig_" + long_name + "Hand" + stem + "4")
		if b < 0:
			continue
		out[stem] = (to_att * ((sk.global_transform * sk.get_bone_global_pose(b)).origin))
	return out


## El kemigi ile BoneAttachment cercevesi ayni mi (parmak cozumu buna dayanir)?
func rig_probe_extra(ch: Node3D, aR: BoneAttachment3D, aL: BoneAttachment3D) -> void:
	var sk := ch.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if sk == null or aR == null:
		wline("16) HATA: skeleton/att yok")
		return
	for side in ["r", "l"]:
		var att := aR if side == "r" else aL
		if att == null:
			continue
		var bname := "mixamorig_" + ("Right" if side == "r" else "Left") + "Hand"
		var bi := sk.find_bone(bname)
		if bi < 0:
			wline("16) %s kemik yok" % side)
			continue
		var bg := sk.global_transform * sk.get_bone_global_pose(bi)
		wline("16) %s att-bone konum farki %.6f aci farki %.6f" % [
			side,
			att.global_transform.origin.distance_to(bg.origin),
			att.global_transform.basis.get_rotation_quaternion().angle_to(bg.basis.get_rotation_quaternion())])
	# 18) Kavrama hedefleri (el lokal): marker kalibrasyonu bu degerlerle yazilir.
	var wt: Dictionary = ch.call("wrap_targets_local")
	var keys: Array = wt.keys()
	keys.sort()
	for k in keys:
		var v: Vector3 = wt[k]
		wline("18) %s Vector3(%f, %f, %f)" % [String(k), v.x, v.y, v.z])
	# 19) Kol referans noktalari: pole ofseti secmek icin.
	for side in ["r", "l"]:
		var long_name := "Right" if side == "r" else "Left"
		var ai := sk.find_bone("mixamorig_" + long_name + "Arm")
		var ei := sk.find_bone("mixamorig_" + long_name + "ForeArm")
		var hi := sk.find_bone("mixamorig_" + long_name + "Hand")
		if ai < 0 or ei < 0 or hi < 0:
			continue
		var sh := (sk.global_transform * sk.get_bone_global_pose(ai)).origin
		var el := (sk.global_transform * sk.get_bone_global_pose(ei)).origin
		var hh := (sk.global_transform * sk.get_bone_global_pose(hi)).origin
		var rig_loc := ch.global_transform.affine_inverse()
		wline("19) %s omuz=%s dirsek=%s el=%s" % [side, str(sh), str(el), str(hh)])
		wline("19b) %s el lokal: omuz=%s dirsek=%s el=%s" % [
			side, str(rig_loc * sh), str(rig_loc * el), str(rig_loc * hh)])
