extends SceneTree
## DEV-ONLY olcum araci (oyuna bagli degil). Beta_Surface'in uc parmak
## bolumlerinin (bone *3'e agirlikli vertexler)bone-3 lokal y uzunlugunu
## olcer. Kullanim:
##   Godot --headless --path <proje> --script res://dev_test/measure_fingertips.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://character.glb")
	var rootn := packed.instantiate()
	var sk: Skeleton3D = null
	for n in _all_nodes(rootn):
		if n is Skeleton3D:
			sk = n
			break
	if sk == null:
		print("MEASURE FAIL: skeleton yok")
		quit(1)
		return
	var surf: MeshInstance3D = null
	for c in sk.get_children():
		if c.name == "Beta_Surface":
			surf = c
	if surf == null:
		print("MEASURE FAIL: Beta_Surface yok")
		quit(1)
		return
	var mesh := surf.mesh
	var skinx: Skin = surf.get("skin")
	# bind k -> bone index (importer bind'orphan' olabilir; GLB joints sirasi Eq.)
	var jnodes := _glb_joints()
	var bind_to_bone := []
	for k in range(skinx.get_bind_count()):
		var bi := skinx.get_bind_bone(k)
		if bi < 0 and k < jnodes.size():
			bi = sk.find_bone(String(jnodes[k]).replace(":", "_"))
		bind_to_bone.append(bi)
	# rest global'lar (parents once gelir)
	var nb := sk.get_bone_count()
	var rg: Array[Transform3D] = []
	rg.resize(nb)
	for b in range(nb):
		var t: Transform3D = sk.get_bone_rest(b)
		var p := sk.get_bone_parent(b)
		rg[b] = t if p < 0 else rg[p] * t
	var fingers := ["Index", "Middle", "Ring", "Pinky", "Thumb"]
	var acc := {}
	for f in fingers:
		acc[f] = {"n": 0, "ymin": 1e9, "ymax": -1e9, "cap": 0}
	var non_thumb := {}
	var total := 0
	## SENSE-CHECK: her bind k icin joints[k] adi ile find_bone UYUSUYOR MU,
	## yoksa bind poz orijinine en yakin bone baska mi? (importer sirala karisikligi)
	print("MEASURE sensecheck bindname matched? dist ibmorigin")
	for k in range(skinx.get_bind_count()):
		var bn_k := ""
		if k < jnodes.size():
			bn_k = String(jnodes[k]).replace(":", "_")
		var bi := sk.find_bone(bn_k)
		var ig: Transform3D = skinx.get_bind_pose(k).affine_inverse()
		var best := -1
		var bestd := 1e30
		for b in range(nb):
			var dd: float = (rg[b].origin - ig.origin).length()
			if dd < bestd:
				bestd = dd
				best = b
		var nearest := String(sk.get_bone_name(best)) if best >= 0 else "?"
		var claimed := String(sk.get_bone_name(bi)) if bi >= 0 else "ORPHAN"
		if nearest != claimed or bestd > 0.5:
			print("MEASURE sense k=", k, " claimed=", claimed, " nearest=", nearest, " d=%.2f" % bestd)
	
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		if verts.size() == 0 or bones.size() != verts.size() * 4:
			continue
		total += verts.size()
		for v in range(verts.size()):
			var bi4 := 0
			for q in range(1, 4):
				if weights[v * 4 + q] > weights[v * 4 + bi4]:
					bi4 = q
			if weights[v * 4 + bi4] < 0.4:
				continue
			var bone: int = int(bind_to_bone[int(bones[v * 4 + bi4])])
			if bone < 0:
				continue
			var bn := String(sk.get_bone_name(bone))
			var nm := _finger_of(bn, fingers)
			if nm == "":
				continue
			var rg3: Transform3D = _rest_global_of(sk, rg, bn, 3)
			var loc: Vector3 = rg3.affine_inverse() * _bind_global(sk, skinx, bind_to_bone, int(bones[v * 4 + bi4])) * verts[v]
			var a: Dictionary = acc[nm]
			a["n"] = int(a["n"]) + 1
			a["ymin"] = minf(a["ymin"], loc.y)
			a["ymax"] = maxf(a["ymax"], loc.y)
			# joint4 (bone3 lokal y'de) oncesi/sonrasi sayimi
			var d4 := _rest_offset_to_child(sk, rg, bn, 3)
			if loc.y > d4 * 0.98:
				a["cap"] = int(a["cap"]) + 1
	print("MEASURE totalverts=", total, " surfaces=", mesh.get_surface_count())
	for f: String in fingers:
		for sd: String in ["Right", "Left"]:
			var bn2 := "mixamorig_" + sd + "Hand" + f + "3"
			var b3 := sk.find_bone(bn2)
			var b4 := sk.find_bone("mixamorig_" + sd + "Hand" + f + "4")
			var span := 0.0
			if b3 >= 0 and b4 >= 0:
				span = (rg[b4].origin - rg[b3].origin).length()
			var a2: Dictionary = acc[f]
			print("MEASURE ", sd, "/", f, " n=", a2["n"], " y=[%.2f..%.2f]" % [a2["ymin"], a2["ymax"]], " seg3len=%.2f" % span, " cap_over_j4=", a2["cap"])
	print("MEASURE DONE")
	quit(0)

func _all_nodes(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out

func _finger_of(bn: String, fingers: Array) -> String:
	for f in fingers:
		if bn.contains("Hand" + str(f) + "3"):
			return str(f)
	return ""

func _rest_global_of(sk: Skeleton3D, rg: Array[Transform3D], bn: String, seg: int) -> Transform3D:
	var b := sk.find_bone(bn.replace(str(seg), str(seg)))
	return rg[b]

func _rest_offset_to_child(sk: Skeleton3D, rg: Array[Transform3D], bn: String, seg: int) -> float:
	var b3 := sk.find_bone(bn)
	var kids := sk.get_bone_children(b3)
	if kids.size() > 0:
		return (rg[int(kids[0])].origin - rg[b3].origin).length()
	return 0.0

func _bind_global(sk: Skeleton3D, skinx: Skin, bind_to_bone: Array, k: int) -> Transform3D:
	var bi: int = bind_to_bone[k]
	if bi < 0:
		return Transform3D()
	return skinx.get_bind_pose(k).affine_inverse()

func _glb_joints() -> Array:
	var f := FileAccess.open("res://character.glb", FileAccess.READ)
	if f == null:
		return []
	f.seek(12)
	var clen := f.get_32()
	f.seek(20)
	var jraw := f.get_buffer(clen).get_string_from_utf8()
	f.close()
	var j: Variant = JSON.parse_string(jraw)
	if j == null:
		return []
	var joints: Array = j["skins"][0]["joints"]
	var nodes: Array = j["nodes"]
	var names := []
	for k in range(joints.size()):
		names.append(nodes[int(joints[k])]["name"])
	return names
