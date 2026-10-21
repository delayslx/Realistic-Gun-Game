extends Node

func _verify() -> void:
	var w := get_node("/root/World/Player/CameraPivot/Weapon")
	var rp := get_node("/root/World/Player/CameraPivot/Weapon/WristPivot/RecoilPivot") as Node3D
	var gsk := get_node("/root/World/Player/CameraPivot/Weapon/WristPivot/RecoilPivot/GunVisual/G18_rig/Skeleton3D") as Skeleton3D
	var sk := get_node("/root/World/Player/IK_character/Armature/Skeleton3D") as Skeleton3D
	var gripr := get_node("/root/World/Player/CameraPivot/Weapon/WristPivot/RecoilPivot/GripRight")
	var gripl := get_node("/root/World/Player/CameraPivot/Weapon/WristPivot/RecoilPivot/GripLeft")
	w.jam_chance = 0.0
	for i in range(60):
		await get_tree().process_frame
	var dstr := "ik_r=%.4f ik_l=%.4f" % [(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin).distance_to(gripr.global_position), (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin).distance_to(gripl.global_position)]
	print("VFY ", dstr, " mag=", w.magazine_count, " ch=", w.chambered)
	w.try_fire()
	var peakx := -99.0
	var peakz := -99.0
	for i in range(40):
		await get_tree().process_frame
		peakx = maxf(peakx, rp.rotation.x)
		peakz = maxf(peakz, rp.position.z)
	print("VFY peak_recoil_x=", peakx, " (want >0, muzzle up) peak_pos_z=", peakz, " (want >0, rearward)")
	await get_tree().create_timer(0.5).timeout
	for i in range(12):
		w.try_fire()
		await get_tree().create_timer(0.55).timeout
	print("VFY empty: mag=", w.magazine_count, " ch=", w.chambered, " locked=", w.slide_locked, " shots=", w.shots_fired)
	w.start_eject()
	await get_tree().create_timer(0.8).timeout
	w.start_insert()
	await get_tree().create_timer(0.8).timeout
	w.start_rack()
	await get_tree().create_timer(0.8).timeout
	print("VFY final: mag=", w.magazine_count, " ch=", w.chambered, " locked=", w.slide_locked)
	await _shot("verify_fps")
	get_node("/root/World/Player").set("position", Vector3(2.5, 0.85, -3.5))
	get_node("/root/World/Player").set("yaw", 2.52)
	get_node("/root/World/Player").set("pitch", -0.14)
	get_node("/root/World/Player/CameraPivot/Camera").position = Vector3.ZERO
	for i in range(60):
		await get_tree().process_frame
	await _shot("verify_wide")
	print("VFY DONE")
	get_tree().quit()

var kill_override := false

func _process(_delta: float) -> void:
	if kill_override:
		var skx := get_node_or_null("/root/World/Player/IK_character/Armature/Skeleton3D") as Skeleton3D
		if skx != null:
			skx.clear_bones_global_pose_override()

func _shot(tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "/tmp/opencode/probe_" + tag + ".png"
	img.save_png(path)
	print("PROBESHOT saved ", path)

func _rest_global(skx: Skeleton3D, b: int, cache: Dictionary) -> Transform3D:
	if cache.has(b):
		return cache[b]
	var t: Transform3D = skx.get_bone_rest(b)
	var p := skx.get_bone_parent(b)
	var res: Transform3D = t if p < 0 else _rest_global(skx, p, cache) * t
	cache[b] = res
	return res

func _fix_skin(skx: Skeleton3D, mesh: MeshInstance3D) -> void:
	var skinx: Skin = mesh.get("skin") as Skin
	if skinx == null:
		return
	var cache := {}
	var rest_inv := {}
	for b in range(skx.get_bone_count()):
		rest_inv[b] = _rest_global(skx, b, cache).affine_inverse()
	for k in range(skinx.get_bind_count()):
		var cur: Vector3 = skinx.get_bind_pose(k).origin
		var best := 0
		var bestd := 1e30
		for b in range(skx.get_bone_count()):
			var dd: float = (rest_inv[b].origin - cur).length()
			if dd < bestd:
				bestd = dd
				best = b
		skinx.set_bind_bone(k, best)
		skinx.set_bind_pose(k, rest_inv[best])
	print("RIGskin fixed ", mesh.name, " binds=", skinx.get_bind_count())

func _ready() -> void:
	await get_tree().process_frame
	var tag := "base"
	var anim := ""
	if OS.get_cmdline_user_args().has("--verify"):
		tag = "verify"
	var arm0 := get_node("/root/World/Player/IK_character/Armature") as Node3D
	print("RIGarm pos=", arm0.position, " rot=", arm0.rotation, " scl=", arm0.scale)
	var sk0 := get_node("/root/World/Player/IK_character/Armature/Skeleton3D") as Skeleton3D
	var border := []
	for bbi2 in range(sk0.get_bone_count()):
		border.append(str(sk0.get_bone_name(bbi2)))
	print("RIGboneorder=", border)
	print("RIGskel pos=", sk0.position, " rot=", sk0.rotation, " scl=", sk0.scale)
	var hb := sk0.find_bone("mixamorig_Hips")
	print("RIGhipsrest=", sk0.get_bone_rest(hb).origin, " basis_x=", sk0.get_bone_rest(hb).basis.x)
	var beta2 := get_node("/root/World/Player/IK_character/Armature/Skeleton3D/Beta_Surface") as MeshInstance3D
	print("RIGbeta pos=", beta2.position, " rot=", beta2.rotation, " scl=", beta2.scale, " aabb=", beta2.get_aabb())
	var gsk := get_node("/root/World/Player/CameraPivot/Weapon/WristPivot/RecoilPivot/GunVisual/G18_rig/Skeleton3D") as Skeleton3D
	var grig := get_node("/root/World/Player/CameraPivot/Weapon/WristPivot/RecoilPivot/GunVisual/G18_rig") as Node3D
	print("RIGgunrig pos=", grig.position, " rot=", grig.rotation, " scl=", grig.scale)
	var gcom := gsk.find_bone("G18_COM")
	print("RIGguncom rest=", gsk.get_bone_rest(gcom).origin, " basis=", gsk.get_bone_rest(gcom).basis.x, gsk.get_bone_rest(gcom).basis.y, gsk.get_bone_rest(gcom).basis.z)
	var ghandle := gsk.find_bone("G18_handle")
	print("RIGgunhandle rest=", gsk.get_bone_rest(ghandle).origin)
	var gmesh := gsk.get_node_or_null("G18") as MeshInstance3D
	print("RIGgunmesh pos=", gmesh.position, " scl=", gmesh.scale)
	var gskin: Skin = gmesh.get("skin") as Skin
	if gskin != null:
		var gb := []
		for k in range(gskin.get_bind_count()):
			gb.append([gskin.get_bind_bone(k), gskin.get_bind_pose(k).origin])
		print("RIGgunbinds=", gb)
	var skin: Skin = beta2.get("skin") as Skin
	if skin == null:
		print("RIGskin NULL")
	else:
		print("RIGskin binds=", skin.get_bind_count())
		for bn in ["mixamorig_Hips", "mixamorig_Head", "mixamorig_RightHand","mixamorig_RightUpLeg"]:
			var bbi: int = sk0.find_bone(bn)
			var bones_list := []
			for k in range(skin.get_bind_count()):
				bones_list.append(skin.get_bind_bone(k))
			print("RIGbindbones=", bones_list)
			for k in [0, 1, 2]:
				print("RIGbindpose", k, " origin=", skin.get_bind_pose(k).origin)
	var ap0b := get_node("/root/World/Player/IK_character/AnimationPlayer") as AnimationPlayer
	for i in range(60):
		await get_tree().process_frame
	var bad := 0
	var worst := 0.0
	var worstb := ""
	for bi in range(sk0.get_bone_count()):
		var p: Vector3 = (sk0.global_transform * sk0.get_bone_global_pose(bi).origin)
		if not is_finite(p.x) or not is_finite(p.y) or not is_finite(p.z):
			bad += 1
			if bad <= 5:
				print("RIGnan bone ", sk0.get_bone_name(bi), " =", p)
		var m: float = maxf(maxf(absf(p.x), absf(p.y)), absf(p.z))
		if m > worst:
			worst = m
			worstb = str(sk0.get_bone_name(bi))
	print("RIGbonescanned=", sk0.get_bone_count(), " bad=", bad, " worst=", worst, " bone=", worstb, " anim=", ap0b.current_animation)
	var badbasis := []
	for bi2 in range(sk0.get_bone_count()):
		var bb: Basis = sk0.get_bone_global_pose(bi2).basis
		for ax in [bb.x, bb.y, bb.z]:
			if not is_finite(ax.x) or not is_finite(ax.y) or not is_finite(ax.z):
				badbasis.append(str(sk0.get_bone_name(bi2)))
				break
	print("RIGbadbasis=", badbasis)
	for bi in range(sk0.get_bone_count()):
		var pw: Vector3 = (sk0.global_transform * sk0.get_bone_global_pose(bi).origin)
		var mw: float = maxf(maxf(absf(pw.x), absf(pw.y)), absf(pw.z))
		if mw > 2.5:
			print("RIGwild bone=", sk0.get_bone_name(bi), " pos=", pw)
	var ap0 := get_node("/root/World/Player/IK_character/AnimationPlayer") as AnimationPlayer
	var beta := get_node("/root/World/Player/IK_character/Armature/Skeleton3D/Beta_Surface") as MeshInstance3D
	print("RIGanim list=", ap0.get_animation_list())
	print("RIGblendcount surface=", beta.get_blend_shape_count())
	var ida := ap0.get_animation("idle")
	var blendtracks := 0
	for ti in range(ida.get_track_count()):
		var tp := str(ida.track_get_path(ti))
		if tp.contains("blend"):
			blendtracks += 1
			if blendtracks <= 5:
				print("RIGblendtrack idle: ", tp)
	print("RIGidle tracks=", ida.get_track_count(), " blendtracks=", blendtracks)
	for ti in range(ida.get_track_count()):
		print("RIGtrack idle[", ti, "]=", str(ida.track_get_path(ti)), " type=", ida.track_get_type(ti))
	for ti in range(ida.get_track_count()):
		var tp2 := str(ida.track_get_path(ti))
		if tp2.contains("Hips") and tp2.contains("position"):
			print("RIGhipstrack ", tp2, " keys=", ida.track_get_key_count(ti), " v0=", ida.track_get_key_value(ti, 0), " vlast=", ida.track_get_key_value(ti, ida.track_get_key_count(ti) - 1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			tag = a.get_slice("=", 1)
	var cam := get_node("/root/World/Player/CameraPivot/Camera") as Camera3D
	var player := get_node("/root/World/Player")
	var sk := get_node("/root/World/Player/IK_character/Armature/Skeleton3D") as Skeleton3D
	if tag == "nojoints" or tag == "side" or tag == "topdown":
		var joints := sk.get_node_or_null("Beta_Joints") as MeshInstance3D
		if joints != null:
			joints.visible = false
	if tag == "side":
		cam.position = Vector3(0.35, 0.05, -0.25)
	if tag == "topdown":
		cam.position = Vector3(0.0, 0.05, -0.25)
		player.set("pitch", -0.55)
	if tag == "bindwide":
		var apx := get_node("/root/World/Player/IK_character/AnimationPlayer") as AnimationPlayer
		apx.stop()
		var pl := get_node("/root/World/Player")
		pl.set_process(false)
		pl.set_physics_process(false)
		sk.clear_bones_global_pose_override()
		sk.reset_bone_poses()
		player.set("position", Vector3(2.5, 0.85, -3.5))
		player.set("yaw", 2.52)
		player.set("pitch", -0.14)
		cam.position = Vector3.ZERO
	if tag == "zoom":
		var apz := get_node("/root/World/Player/IK_character/AnimationPlayer") as AnimationPlayer
		apz.stop()
		var pl2 := get_node("/root/World/Player")
		pl2.set_process(false)
		pl2.set_physics_process(false)
		var cz := Camera3D.new()
		get_node("/root/World").add_child(cz)
		cz.global_position = Vector3(0.9, 1.55, -1.35)
		cz.look_at(Vector3(0.05, 1.42, -0.25))
		cz.current = true
		cz.fov = 40.0
		for i in range(100):
			await get_tree().process_frame
		await _shot(tag)
		print("RIG", tag, "done")
		get_tree().quit()
		return
	if tag == "extbind":
		var apx := get_node("/root/World/Player/IK_character/AnimationPlayer") as AnimationPlayer
		apx.stop()
		var pl := get_node("/root/World/Player")
		pl.set_process(false)
		pl.set_physics_process(false)
		var skb := get_node("/root/World/Player/IK_character/Armature/Skeleton3D") as Skeleton3D
		skb.clear_bones_global_pose_override()
		skb.reset_bone_poses()
		var c7 := Camera3D.new()
		get_node("/root/World").add_child(c7)
		c7.global_position = Vector3(2.5, 1.9, -3.2)
		c7.look_at(Vector3(0.0, 1.0, 0.0))
		c7.current = true
		c7.fov = 55.0
		for i in range(100):
			await get_tree().process_frame
		await _shot(tag)
		print("RIG", tag, "done")
		get_tree().quit()
		return
	if tag == "ext3":
		var c3 := Camera3D.new()
		get_node("/root/World").add_child(c3)
		c3.fov = 55.0
		c3.current = true
		for ai in range(3):
			var ang := deg_to_rad(35.0 + float(ai) * 40.0)
			c3.global_position = Vector3(sin(ang) * 4.2, 1.9, -cos(ang) * 4.2)
			c3.look_at(Vector3(0.0, 1.0, 0.0))
			for i in range(50):
				await get_tree().process_frame
			await _shot("extorb" + str(ai))
		print("RIGext3 done")
		get_tree().quit()
		return
	if tag == "extnoov":
		kill_override = true
	if tag == "armsonly" or tag == "fingersonly":
		var aik := get_node("/root/World/Player/IK_character")
		if tag == "armsonly":
			aik.set("do_fingers", false)
		else:
			aik.set("do_arms", false)
		var c4 := Camera3D.new()
		get_node("/root/World").add_child(c4)
		c4.global_position = Vector3(2.5, 1.9, -3.2)
		c4.look_at(Vector3(0.0, 1.0, 0.0))
		c4.current = true
		c4.fov = 55.0
		for i in range(100):
			await get_tree().process_frame
		await _shot(tag)
		print("RIG", tag, "done")
		get_tree().quit()
		return
	if tag == "skinew":
		var skn := get_node("/root/World/Player/IK_character/Armature/Skeleton3D") as Skeleton3D
		for mn in ["Beta_Surface", "Beta_Joints"]:
			var mm := get_node("/root/World/Player/IK_character/Armature/Skeleton3D/" + mn) as MeshInstance3D
			var oldskin: Skin = mm.get("skin") as Skin
			if oldskin != null:
				var dup := oldskin.duplicate() as Skin
				var cache := {}
				var rest_inv := {}
				for b in range(skn.get_bone_count()):
					rest_inv[b] = _rest_global(skn, b, cache).affine_inverse()
				var premean := 0.0
				for k in range(dup.get_bind_count()):
					var cur: Vector3 = dup.get_bind_pose(k).origin
					var best := 0
					var bestd := 1e30
					for b in range(skn.get_bone_count()):
						var dd: float = (rest_inv[b].origin - cur).length()
						if dd < bestd:
							bestd = dd
							best = b
					premean += bestd
					if k < 3 or k == 32:
						print("RIGpair bind", k, "-> bone ", skn.get_bone_name(best), " dist=", bestd)
				print("RIGpairmean_prefile ", mn, " ", premean / dup.get_bind_count())
				for k in range(dup.get_bind_count()):
					var cur2: Vector3 = dup.get_bind_pose(k).origin
					var best2 := 0
					var bestd2 := 1e30
					for b in range(skn.get_bone_count()):
						var dd2: float = (rest_inv[b].origin - cur2).length()
						if dd2 < bestd2:
							bestd2 = dd2
							best2 = b
					dup.set_bind_bone(k, best2)
					dup.set_bind_pose(k, rest_inv[best2])
				mm.set("skin", dup)
				print("RIGskin remapped for ", mn)
				var db := 0.0
				var dbn := 0
				for k in range(dup.get_bind_count()):
					var cur2: Vector3 = dup.get_bind_pose(k).origin
					var best2 := 0
					var bestd2 := 1e30
					for b in range(skn.get_bone_count()):
						var dd2: float = (rest_inv[b].origin - cur2).length()
						if dd2 < bestd2:
							bestd2 = dd2
							best2 = b
					db += bestd2
					dbn += 1
				print("RIGpairmean ", mn, " ", db / maxf(dbn, 1.0))
		var c5 := Camera3D.new()
		get_node("/root/World").add_child(c5)
		c5.global_position = Vector3(2.5, 1.9, -3.2)
		c5.look_at(Vector3(0.0, 1.0, 0.0))
		c5.current = true
		c5.fov = 55.0
		for i in range(100):
			await get_tree().process_frame
		await _shot(tag)
		print("RIG", tag, "done")
		get_tree().quit()
		return
	if tag == "nojoints2":
		var jn := get_node("/root/World/Player/IK_character/Armature/Skeleton3D/Beta_Joints") as MeshInstance3D
		if jn != null:
			jn.visible = false
		var c6 := Camera3D.new()
		get_node("/root/World").add_child(c6)
		c6.global_position = Vector3(2.5, 1.9, -3.2)
		c6.look_at(Vector3(0.0, 1.0, 0.0))
		c6.current = true
		c6.fov = 55.0
		for i in range(100):
			await get_tree().process_frame
		await _shot(tag)
		print("RIG", tag, "done")
		get_tree().quit()
		return
	if tag == "ext" or tag == "extnoov":
		var skf := get_node("/root/World/Player/IK_character/Armature/Skeleton3D") as Skeleton3D
		_fix_skin(skf, get_node("/root/World/Player/IK_character/Armature/Skeleton3D/Beta_Surface") as MeshInstance3D)
		_fix_skin(skf, get_node("/root/World/Player/IK_character/Armature/Skeleton3D/Beta_Joints") as MeshInstance3D)
		var c := Camera3D.new()
		get_node("/root/World").add_child(c)
		c.global_position = Vector3(2.5, 1.9, -3.2)
		c.look_at(Vector3(0.0, 1.0, 0.0))
		c.current = true
		c.fov = 55.0
	if tag == "wide":
		player.set("position", Vector3(2.5, 0.85, -3.5))
		player.set("yaw", 2.52)
		player.set("pitch", -0.14)
		cam.position = Vector3.ZERO
	if tag.begins_with("anim"):
		anim = tag.get_slice("_", 1)
		player.set("position", Vector3(2.5, 0.85, -3.5))
		player.set("yaw", 2.52)
		player.set("pitch", -0.14)
		cam.position = Vector3.ZERO
	if tag == "verify":
		await _verify()
		return
	for i in range(100):
		await get_tree().process_frame
	if anim != "":
		var ap := get_node("/root/World/Player/IK_character/AnimationPlayer") as AnimationPlayer
		ap.play(anim)
		for i in range(60):
			await get_tree().process_frame
	await _shot(tag)
	print("PROBESHOT done tag=", tag, " camworld=", cam.global_position)
	get_tree().quit()
