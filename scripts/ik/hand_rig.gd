@tool
extends Node3D
## El rig ustasi (weapon-in-hand mimarisi).
##
## Kontrol zinciri (silah master, eller silaha gider):
##   player_controller -> WeaponMount -> silah
##   silah RightHandTarget -> r_arm_marker (sag el IK hedefi)
##   silah LeftHandTarget  -> l_arm_marker (sol el IK hedefi)
##   silah FingersRight/FingersLeft -> parmak uclari (kod IK)
##   silah marker'i yoksa -> eski GripLeft / karakterin dogal parmak uclari
##
## IK kemikleri kilitlemez: arm_ik_influence / finger_ik_influence 0 olunca
## kemikler animasyonun biraktigi yerden devam eder. auto_anim_yield acikken
## oynayan animasyon el/kol/parmak kemiklerine dokunuyorsa IK kendiliginden
## cekilir (tetik, reload, rack animasyonlari kendi pozunu gosterir).
##
## El hedefleri silahin RecoilPivot'u altindaki marker'lardan okunur; iki el
## de recoil ile ayni rigid govdede kalir. Boylece sag/sol el silahtan ayrilmaz
## ve WeaponMount her karede guncellense bile IK hedefi bir kare geride kalmaz.

const SIDES := ["r", "l"]
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]
const SIDE_LONG := {"r": "Right", "l": "Left"}
## Oynayan animasyonda bu kemik adlarindan biri gecerse ilgili tarafin IK'si
## cekilir. "mixamorig_RightHand" ayni zamanda tum parmak adlarini kapsar.
const ANIM_WATCH := {
	"r": ["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"],
	"l": ["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"],
}
const FABRIK_ITERS := 8


class FingerChain:
	var bones: Array[int] = []
	var rest: Array[Transform3D] = []
	var segs: Array[float] = []


## 0..1. Animasyon yoksa 1 kalir; auto_anim_yield bunu otomatik dusurur.
@export_range(0.0, 1.0) var arm_ik_influence := 1.0
@export_range(0.0, 1.0) var finger_ik_influence := 1.0
## Animasyon el/kol/parmak kemiklerini suruyorsa IK kendiliginden cekilsin.
@export var auto_anim_yield := true
## Animasyon adi -> zorlanan etki. Ornek: {"reload": 0.0, "fire": 0.5}
@export var anim_influence: Dictionary = {}
## Sol el hedefini grip'e hizalarken uygulanan sabit duzeltme. Silah isterse
## weapon_controller.left_hand_offset ile bunu gecersiz kilar.
@export var left_hand_offset := Transform3D.IDENTITY
## Sag el hedefini silahin RightHandTarget marker'ina hizalar. Varsayilan
## identity: marker authored pozunu birebir kullanir.
@export var right_hand_offset := Transform3D.IDENTITY
## Silah kendi RightHandTarget/LeftHandTarget marker'larini tasiyorsa onlari
## kullan. Kapaliyken eski authored marker davranisi korunur.
@export var use_weapon_hand_targets := true
## Silahin tutusu etrafina parmak kavramasi. Acikken parmak uclari tutusun
## geometrisinden uretilir (el lokalinde) ve el marker'lari ezilir. Kapaliyken
## sahnedeki <side>_<stem>_target marker'lari otoritedir: editorde surukle,
## parmak canli takip eder (kalibrasyon boyle yapilir).
@export var grip_wrap := false
## Kavrama yaricapi (tutus merkezinden parmak ucuna, metre).
@export var grip_wrap_radius := 0.018
## Parmak basina kavrama carpani: [Thumb, Index, Middle, Ring, Pinky].
@export var grip_wrap_reach := [0.55, 1.0, 1.0, 1.0, 0.95]
## Kol pole (dirsek ipucu) hedefleri el hedefini takip etsin. Sabit pole
## marker'i silah donerken dirsek duzlemini kaydiriyordu (kollar ters kivriliyor).
@export var auto_pole := true
## Pole ofseti, karakter cercevesinde: x disari (oyuncunun sag/sol), y asagi,
## z geri. El hedefine eklenir; elin donusunden bagimsizdir.
@export var pole_offset_r := Vector3(-0.16, -0.30, -0.05)
@export var pole_offset_l := Vector3(0.16, -0.30, -0.05)
@export var debug_prints := false
## Yalnizca editor: bu sahne tek basina acildiginda silah elde gorunsun diye
## ele gecici olarak orneklenir (oyunda kullanilmaz, sahne kaydina yazilmaz).
@export var preview_weapon: PackedScene

var sk: Skeleton3D
var anim_player: AnimationPlayer
var weapon: Node3D

var _attach: Dictionary = {}
var _arm_mod: Dictionary = {}
var _hand_copy: Dictionary = {}
var _arm_target: Dictionary = {}
var _hand_bone: Dictionary = {}
var _finger_mod: Node
var _chain: Dictionary = {}
var _anim_sides: Dictionary = {}
var _grip_cache: Dictionary = {}
var _right_target: Node3D
var _left_target: Node3D
var _ed_tick := 0
var _dbg_tick := 0
var _preview_weapon_node: Node3D
var _preview_src: PackedScene
var _eff_arm: Dictionary = {"r": 1.0, "l": 1.0}
var _eff_finger: Dictionary = {"r": 1.0, "l": 1.0}
## Test/olcum: debug_prints acikken cozulen parmak uclarinin dunya konumu.
## (Kemik pozlari disaridan guvenilir okunamadigi icin cozumun icinden kaydedilir.)
var debug_tips: Dictionary = {}
## Test/olcum: debug_prints acikken kol kemiklerinin (omuz/dirsek/el) dunya pozu.
var debug_arm: Dictionary = {}


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	# Editorde iskeletin modifier zinciri (kol IK) kendiliginden islenmez;
	# guncellemeyi _editor_process icinde her karede elle tetikliyoruz.
	set_process(true)


func _ready() -> void:
	# Silah recoil'i (-10) ve hedef marker'lari guncellendikten sonra el IK'si.
	process_priority = 10
	_cache()
	var wm := get_node_or_null("/root/WeaponManager")
	if wm != null and wm.has_signal("weapon_changed"):
		if not wm.weapon_changed.is_connected(_on_weapon_changed):
			wm.weapon_changed.connect(_on_weapon_changed)
		_on_weapon_changed(String(wm.current_id), wm.get_weapon() as Node3D)
	if weapon == null:
		# WeaponManager yoksa (orn. tek sahne testi) mount'a yerlestirilmis silahi kullan.
		var att := get_node_or_null("WeaponMount")
		if att == null:
			att = get_node_or_null("RightHandAttach")
		if att != null:
			for c in att.get_children():
				var w := c as Node3D
				if w != null and _find_child_named(w, "GripRight") != null:
					_on_weapon_changed("", w)
					break
	_resolve_hand_targets()
	if debug_prints:
		print("HAND_RIG ready chains=%d attach=%s weapon=%s" % [_chain.size(), str(_attach.keys()), str(weapon)])


func _cache() -> void:
	sk = get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	# Sozlukler bastan kurulur: editorde script yeniden yuklendiginde ornek
	# yasamaya devam eder ve yeni uyeler (orn. _hand_bone) bos kalir.
	_attach = {}
	_arm_mod = {}
	_hand_copy = {}
	_arm_target = {}
	_hand_bone = {}
	_chain = {}
	_anim_sides = {}
	_grip_cache = {}
	_eff_arm = {"r": 1.0, "l": 1.0}
	_eff_finger = {"r": 1.0, "l": 1.0}
	if typeof(_dbg_tick) != TYPE_INT:
		_dbg_tick = 0
	if sk == null:
		push_warning("HandRig: Armature/Skeleton3D bulunamadi")
		return
	for side in SIDES:
		var lname: String = SIDE_LONG[side]
		var att := get_node_or_null(lname + "HandAttach") as BoneAttachment3D
		if att == null:
			push_warning("HandRig: %sHandAttach yok" % lname)
		_attach[side] = att
		_arm_mod[side] = sk.get_node_or_null("r_arm" if side == "r" else "l_arm")
		_hand_copy[side] = sk.get_node_or_null("r_hand_copy_trans" if side == "r" else "l_hand_copy_trans")
		_arm_target[side] = get_node_or_null("r_arm_marker" if side == "r" else "l_arm_marker")
		_hand_bone[side] = sk.find_bone("mixamorig_" + lname + "Hand")
	# Parmak cozumu iskelet modifier zincirinde calisir (editorde de uygulanir).
	_finger_mod = sk.get_node_or_null("fingers_ik")
	if _finger_mod != null:
		_finger_mod.set("rig", self)
	# Eski SkeletonIK3D parmak cozuculeri devre disi: parmaklari artik bu script cozer.
	for c in sk.get_children():
		var old := c as SkeletonIK3D
		if old != null:
			old.stop()
	for side in SIDES:
		for stem in FINGERS:
			_collect_finger(side, stem)
	if get_tree() != null:
		anim_player = _find_anim(get_tree().current_scene)


func _collect_finger(side: String, stem: String) -> void:
	var prefix: String = "mixamorig_" + String(SIDE_LONG[side]) + "Hand"
	var bones: Array[int] = []
	for n in [1, 2, 3, 4]:
		var b := sk.find_bone(prefix + stem + str(n))
		if b < 0:
			return
		bones.append(b)
	var rest_l: Array[Transform3D] = []
	var acc := Transform3D.IDENTITY
	for b in bones:
		acc = acc * sk.get_bone_rest(b)
		rest_l.append(acc)
	var segs: Array[float] = []
	for i in range(rest_l.size() - 1):
		segs.append(rest_l[i].origin.distance_to(rest_l[i + 1].origin))
	var ch := FingerChain.new()
	ch.bones = bones
	ch.rest = rest_l
	ch.segs = segs
	_chain["%s|%s" % [side, stem]] = ch


func _find_anim(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var ap := root as AnimationPlayer
	if ap != null:
		return ap
	for c in root.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _on_weapon_changed(_id: String, w: Node3D) -> void:
	weapon = w
	_anim_sides.clear()
	_grip_cache.clear()
	_resolve_hand_targets()
	if debug_prints:
		print("HAND_RIG weapon=", weapon)


## Aktif silahin kendi el hedef marker'larini cozer. Yeni silah takildiginda
## yeniden cagrilir; sahne hiyerarsisi farkli olsa da isimle bulunur.
func _resolve_hand_targets() -> void:
	if not use_weapon_hand_targets:
		_right_target = null
		_left_target = null
		return
	_right_target = _weapon_node("RightHandTarget")
	_left_target = _weapon_node("LeftHandTarget")


## Onbellek gecersiz mi? Editor script reload'u yeni uyeleri bos birakir
## (orn. _hand_bone) veya onbellegi yarim birakir (orn. _chain bos kalir);
## o durumda _cache() bastan kurar. Aksi halde editorde parmak cozumu sessizce
## hicbir sey yazmaz (hata da vermez).
func _cache_stale() -> bool:
	if sk == null or typeof(_hand_bone) != TYPE_DICTIONARY:
		return true
	return _chain.is_empty()


func _process(_delta: float) -> void:
	if _cache_stale():
		_cache()
	if sk == null:
		return
	if Engine.is_editor_hint():
		_editor_process()
		return
	_update_influence()
	for side in SIDES:
		var am := _arm_mod[side] as SkeletonModifier3D
		if am != null:
			am.influence = float(_eff_arm[side])
		var hc := _hand_copy[side] as SkeletonModifier3D
		if hc != null:
			hc.influence = float(_eff_arm[side])
	_drive_right_hand()
	_drive_left_hand()
	_drive_poles()
	if _finger_mod == null:
		# Modifier dugumu olmayan sahneler icin guvenlik agi.
		solve_fingers_in_modifier()


## Editorde canli onizleme: hedef/marker suruklenince kol ve parmaklar aninda
## takip eder. Iskeletin modifier zinciri editorde kendiliginden islemedigi icin
## NOTIFICATION_UPDATE_SKELETON'i her karede elle gonderiyoruz; surucu
## dugumler (pole, sol el hedefi) gonderimden ONCE guncellenir. Motor, skin
## guncellemesinden sonra kemik pozlarini geri yazdigi icin sahne kaydi kirlenmez.
func _editor_process() -> void:
	_ed_tick += 1
	if _ed_tick == 1 or _cache_stale():
		_cache()
	if sk == null:
		return
	_resolve_editor_weapon()
	_editor_wrap_to_markers()
	_drive_right_hand()
	_drive_left_hand()
	_drive_poles()
	if _finger_mod == null:
		solve_fingers_in_modifier()
	sk.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


## Editorde silahi bul: sahneye yerlestirilmisse onu, yoksa preview_weapon'i
## ele gecici olarak ornekler (owner atanmaz -> sahne kaydina yazilmaz).
func _resolve_editor_weapon() -> void:
	var att := get_node_or_null("WeaponMount")
	if att == null:
		att = get_node_or_null("RightHandAttach")
	if att == null:
		return
	if weapon == null:
		for c in att.get_children():
			var w := c as Node3D
			if w != null and _find_child_named(w, "GripRight") != null:
				weapon = w
				_resolve_hand_targets()
				return
	if preview_weapon != _preview_src:
		_clear_preview_weapon()
		_preview_src = preview_weapon
		if preview_weapon != null and not preview_weapon.changed.is_connected(_on_preview_weapon_changed):
			preview_weapon.changed.connect(_on_preview_weapon_changed)
	if weapon == null and preview_weapon != null:
		var n3 := preview_weapon.instantiate() as Node3D
		if n3 != null:
			n3.name = "__PreviewWeapon"
			att.add_child(n3)
			_preview_weapon_node = n3
			weapon = n3
			_resolve_hand_targets()


func _clear_preview_weapon() -> void:
	if _preview_weapon_node != null and is_instance_valid(_preview_weapon_node):
		if weapon == _preview_weapon_node:
			weapon = null
			_resolve_hand_targets()
		_preview_weapon_node.queue_free()
	_preview_weapon_node = null
	_grip_cache.clear()


func _on_preview_weapon_changed() -> void:
	# Silah sahnesi diskte degisti: onizlemeyi yeniden kur.
	_clear_preview_weapon()


func _update_influence() -> void:
	var anim := ""
	if anim_player != null and anim_player.is_playing():
		anim = String(anim_player.current_animation)
	var sides := {"r": false, "l": false}
	if anim != "" and auto_anim_yield:
		sides = _anim_sides_for(anim)
	for side in SIDES:
		var arm_w := arm_ik_influence
		var fing_w := finger_ik_influence
		if anim != "" and anim_influence.has(anim):
			var v := float(anim_influence[anim])
			arm_w = minf(arm_w, v)
			fing_w = minf(fing_w, v)
		elif bool(sides.get(side, false)):
			arm_w = 0.0
			fing_w = 0.0
		_eff_arm[side] = arm_w
		_eff_finger[side] = fing_w


func _anim_sides_for(anim_name: String) -> Dictionary:
	var cached: Variant = _anim_sides.get(anim_name)
	if cached != null:
		return cached
	var out := {"r": false, "l": false}
	if anim_player != null:
		var a := anim_player.get_animation(anim_name)
		if a != null:
			for i in a.get_track_count():
				var p := String(a.track_get_path(i))
				for side in SIDES:
					if bool(out[side]):
						continue
					for bn in ANIM_WATCH[side]:
						if p.contains(bn):
							out[side] = true
							break
	_anim_sides[anim_name] = out
	return out


## Sag el hedefi silahin RightHandTarget marker'ini birebir takip eder.
## Marker RecoilPivot altinda oldugu icin sag el/kol recoil'e birlikte gider.
func _drive_right_hand() -> void:
	if not use_weapon_hand_targets:
		return
	if _right_target == null or float(_eff_arm["r"]) <= 0.0:
		return
	var marker := _arm_target["r"] as Node3D
	if marker == null:
		return
	marker.global_transform = _right_target.global_transform * right_hand_offset


## Sol el hedefi: once silahin LeftHandTarget marker'i, yoksa eski GripLeft
## fallback'i. Marker ve GripLeft ayni RecoilPivot altinda oldugu icin
## sol el her durumda silahta kalir.
func _drive_left_hand() -> void:
	if float(_eff_arm["l"]) <= 0.0:
		return
	var target := _arm_target["l"] as Node3D
	if target == null:
		return
	if use_weapon_hand_targets and _left_target != null:
		target.global_transform = _left_target.global_transform * _left_offset()
		return
	var grip := _grip("l")
	if grip == null:
		return
	target.global_transform = grip.global_transform * _left_offset()


func _left_offset() -> Transform3D:
	if weapon != null and is_instance_valid(weapon):
		var o: Variant = weapon.get("left_hand_offset")
		if o is Transform3D:
			return o
	return left_hand_offset


func _weapon_node(rel: String) -> Node3D:
	if weapon == null or not is_instance_valid(weapon):
		return null
	var direct := weapon.get_node_or_null(rel) as Node3D
	if direct != null:
		return direct
	# Silah sahneleri dugumu farkli derinlikte tutabilir; isimle ara.
	return _find_child_named(weapon, rel.get_file())


func _find_child_named(root: Node, child_name: String) -> Node3D:
	for c in root.get_children():
		if String(c.name) == child_name:
			return c as Node3D
	for c in root.get_children():
		var r := _find_child_named(c, child_name)
		if r != null:
			return r
	return null


## Silahin parmak marker grubu (FingersRight/FingersLeft); varsa.
func _finger_group(side: String) -> Node:
	var key := "grp_" + side
	var cached: Node = _grip_cache.get(key)
	if cached != null and is_instance_valid(cached):
		return cached
	var n := _weapon_node("Fingers" + String(SIDE_LONG[side]))
	_grip_cache[key] = n
	return n


## Tutus hedefi (GripRight/GripLeft) -- silah basina bir kez cozulur.
func _grip(side: String) -> Node3D:
	var cached: Node3D = _grip_cache.get(side)
	if cached != null and is_instance_valid(cached):
		return cached
	var n := _weapon_node("GripRight" if side == "r" else "GripLeft")
	_grip_cache[side] = n
	return n


## El cercevesi (dunya uzayi). Parmak cozumu bunun uzerinden kurulur.
##
## BoneAttachment3D'nin kendi transform'una guvenilmez: o dugum kemik pozunu
## bir kare gecikmeli tasir (modifier gecisi icinde guncellenmez), bu da kol
## hizli hareket ederken (tepmе) parmaklarin eli bir kare geriden takip etmesi
## demek olurdu. Kemigin guncel global pozu dogrudan iskeletten okunur.
func _hand_frame(side: String, att: BoneAttachment3D) -> Transform3D:
	var bi := -1
	if typeof(_hand_bone) == TYPE_DICTIONARY:
		bi = int((_hand_bone as Dictionary).get(side, -1))
	if bi < 0 or sk == null:
		return att.global_transform
	return sk.global_transform * sk.get_bone_global_pose(bi)


## Parmak cozumu. fingers_ik (SkeletonModifier3D) cagirir; kol IK'si ve el
## kopyalama modifier'i onceden calistigi icin el burada gunceldir.
##
## Iskelet modifier zinciri icinde calistigi icin hem oyunda hem editorde
## ayni sonucu verir: kemik pozu dogrudan yazilir (global pose override
## editorde render'a yansimiyordu).
func solve_fingers_in_modifier() -> void:
	if sk == null:
		return
	for side in SIDES:
		var amount: float = float(_eff_finger[side])
		if amount <= 0.0:
			continue
		var att := _attach[side] as BoneAttachment3D
		if att == null:
			continue
		var inv := sk.global_transform.affine_inverse()
		var hand := _hand_frame(side, att)
		var hb := hand.basis
		var to_hand := att.global_transform.affine_inverse()
		for stem in FINGERS:
			var ch := _chain.get("%s|%s" % [side, stem]) as FingerChain
			if ch == null:
				continue
			var tl: Variant = _finger_target_local(side, stem, att, ch, to_hand)
			if tl == null:
				continue
			var target_w: Vector3 = hand * (tl as Vector3)
			# Zincir tamamen el cercevesinden turetilir: el nereye giderse parmaklar oraya.
			var pts: Array[Vector3] = []
			for r in ch.rest:
				pts.append((hand * r).origin)
			var solved: Array[Vector3] = _fabrik(pts, ch.segs, target_w)
			solved[0] = pts[0]
			for i in ch.bones.size():
				var b: int = ch.bones[i]
				var rw_basis := hb * ch.rest[i].basis
				var seg_dir: Vector3 = _dir(solved[i], solved[i + 1], rw_basis.y) if i + 1 < solved.size() else _dir(solved[i - 1], solved[i], rw_basis.y)
				var rest_axis := rw_basis.y
				if rest_axis.length() < 0.00001:
					rest_axis = Vector3.UP
				var q := Quaternion(rest_axis.normalized(), seg_dir)
				var bnew := Basis(q * rw_basis.get_rotation_quaternion()).orthonormalized()
				var want := inv * Transform3D(bnew, solved[i])
				var cur := sk.get_bone_global_pose(b)
				sk.set_bone_global_pose(b, cur.interpolate_with(want, amount))
			if debug_prints and not ch.bones.is_empty():
				var tip_b: int = ch.bones[ch.bones.size() - 1]
				debug_tips["%s|%s" % [side, stem]] = (sk.global_transform * sk.get_bone_global_pose(tip_b)).origin
		if debug_prints:
			# Kol olcumu: dirsek/pole sapmasi disaridan guvenilir okunamaz (kemik
			# pozlari modifier gecisi disinda temel poza doner), bu yuzden cozumun
			# ICINDEN kaydedilir. Sira dogru: kol IK'si bu modifier'dan once calisti.
			var pre := "mixamorig_" + ("Right" if side == "r" else "Left")
			for bn in ["Arm", "ForeArm"]:
				var bi := sk.find_bone(pre + bn)
				if bi >= 0:
					debug_arm["%s|%s" % [side, bn]] = (sk.global_transform * sk.get_bone_global_pose(bi)).origin
			debug_arm["%s|Hand" % side] = hand.origin
	if debug_prints:
		_dbg_tick += 1
		if _dbg_tick % 120 == 0:
			var a0 := _attach.get("r") as BoneAttachment3D
			if a0 != null:
				var inv_rig := global_transform.affine_inverse()
				var hf := _hand_frame("r", a0)
				print("HAND_RIG dbg el_kemigi_local=", inv_rig * hf.origin,
					" attachment_local=", inv_rig * a0.global_position,
					" fark=", hf.origin.distance_to(a0.global_position))


## Parmak ucu hedefi, EL LOKALINDE (attachment cercevesi). Oncelik:
##  1) silahin kendi Fingers<Side>/<stem> marker'i -> silah basina kalibrasyon
##  2) grip_wrap acikken tutus geometrisinden kavrama, kapaliyken el marker'i
##  3) kalan yol (kavrama yoksa / marker yoksa)
## Boylece editorde marker suruklemek kavrama acik olmadikca dogrudan etki eder.
func _finger_target_local(side: String, stem: String, att: BoneAttachment3D, ch: FingerChain, to_hand: Transform3D) -> Variant:
	var grp := _finger_group(side)
	if grp != null:
		var fm := grp.get_node_or_null(stem) as Node3D
		if fm != null:
			return (to_hand * fm.global_transform).origin
	var fb := att.get_node_or_null("%s_%s_target" % [side, stem]) as Node3D
	if not grip_wrap and fb != null:
		return fb.transform.origin
	var wrapped: Variant = _wrap_local(side, stem, att, ch)
	if wrapped != null:
		return wrapped
	if fb != null:
		return fb.transform.origin
	return null


## Arac: kavrama hedeflerini el lokalinde dondurur (marker kalibrasyonu icin).
func wrap_targets_local() -> Dictionary:
	var out := {}
	for side in SIDES:
		var att := _attach[side] as BoneAttachment3D
		for stem in FINGERS:
			var ch := _chain.get("%s|%s" % [side, stem]) as FingerChain
			if att == null or ch == null:
				continue
			var t: Variant = _wrap_local(side, stem, att, ch)
			if t != null:
				out["%s_%s" % [side, stem]] = t
	return out


## Parmak ucunu silahin tutusu etrafina dolayan hedef (el lokalinde). Tutus
## merkezi ve ekseni silahtan (GripRight/GripLeft + govde Y'si) alinir; boylece
## yeni silah eklendiginde kalibrasyon silahin kendisiyle gelir.
func _wrap_local(side: String, stem: String, att: BoneAttachment3D, ch: FingerChain) -> Variant:
	var grip := _grip(side)
	if grip == null:
		return null
	var to_hand := att.global_transform.affine_inverse()
	var grip_local: Transform3D = to_hand * grip.global_transform
	var knuckle: Vector3 = ch.rest[0].origin
	# Tutus ekseni: parmaklarin yan yana dizildigi eksen (isaret-serce
	# knuckle cizgisi). Once silahin govde Y'si kullaniliyordu; sol elde bu
	# eksen elin parmak yonune dusuyor ve hedef bilek seviyesine cokuyordu.
	var axis := Vector3.RIGHT
	var ki: Variant = _knuckle_origin(side, "Index")
	var kp: Variant = _knuckle_origin(side, "Pinky")
	if ki != null and kp != null:
		axis = (ki as Vector3) - (kp as Vector3)
	if axis.length() < 0.0001:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	var d: Vector3 = grip_local.origin - knuckle
	d = d - axis * d.dot(axis)
	if d.length() < 0.0001:
		return null
	var idx: int = FINGERS.find(stem)
	var reach: float = grip_wrap_radius
	if idx >= 0 and idx < grip_wrap_reach.size():
		reach *= float(grip_wrap_reach[idx])
	var tip: Vector3 = grip_local.origin + d.normalized() * reach
	# Kendi eksen konumunu koru: parmaklar tutus boyunca yan yana kalsin.
	var k_axis: float = knuckle.dot(axis)
	tip = tip - axis * tip.dot(axis) + axis * k_axis
	if debug_prints:
		print("HAND_RIG wrap ", side, "/", stem,
			" knuckle=", knuckle, " grip=", grip_local.origin,
			" axis=", axis, " k_axis=", k_axis, " tip=", tip)
	return tip


## Editorde kalibrasyon modu: grip_wrap acikken parmak marker'lari tutustan
## uretilen hedefe yazilir. Akis: grip_wrap'i ac -> marker'lar tutusa oturur ->
## kapat -> marker'lari surukleyerek ince ayar yap (parmaklar canli takip eder).
func _editor_wrap_to_markers() -> void:
	if not grip_wrap:
		return
	for side in SIDES:
		var att := _attach[side] as BoneAttachment3D
		if att == null:
			continue
		for stem in FINGERS:
			var ch := _chain.get("%s|%s" % [side, stem]) as FingerChain
			var mk := att.get_node_or_null("%s_%s_target" % [side, stem]) as Node3D
			if ch == null or mk == null:
				continue
			var t: Variant = _wrap_local(side, stem, att, ch)
			if t != null:
				mk.position = t as Vector3


## Parmak kokunun (1. kemik) el lokalindeki konumu.
func _knuckle_origin(side: String, stem: String) -> Variant:
	var ch := _chain.get("%s|%s" % [side, stem]) as FingerChain
	if ch == null or ch.rest.is_empty():
		return null
	return ch.rest[0].origin


## Kol pole (dirsek ipucu) hedeflerini el hedefine baglar. Sabit marker el
## uzaklasinca dirsek duzlemini kaydiriyordu: silah donunce kollar ters
## kivriliyordu. Ofset karakter cercevesindedir, elin donusunden etkilenmez.
func _drive_poles() -> void:
	if not auto_pole:
		return
	for side in SIDES:
		var pole := get_node_or_null("r_arm_pole" if side == "r" else "l_arm_pole") as Node3D
		var target := _arm_target[side] as Node3D
		if pole == null or target == null:
			continue
		var off: Vector3 = pole_offset_r if side == "r" else pole_offset_l
		pole.global_position = target.global_position + global_transform.basis * off


static func _dir(from: Vector3, to: Vector3, fallback: Vector3) -> Vector3:
	var d := to - from
	if d.length() < 0.00001:
		var f := fallback.normalized()
		return f if f.length() > 0.00001 else Vector3.UP
	return d.normalized()


static func _fabrik(pts: Array[Vector3], lengths: Array[float], target: Vector3) -> Array[Vector3]:
	var n := pts.size()
	var p: Array[Vector3] = []
	for v in pts:
		p.append(v)
	var base: Vector3 = p[0]
	var total := 0.0
	for l in lengths:
		total += l
	var reach := base.distance_to(target)
	if reach >= total:
		var d := _dir(base, target, Vector3.UP)
		var acc := base
		for i in range(1, n):
			acc += d * lengths[i - 1]
			p[i] = acc
		return p
	for _it in FABRIK_ITERS:
		p[n - 1] = target
		for i in range(n - 2, -1, -1):
			p[i] = p[i + 1] + _dir(p[i + 1], p[i], Vector3.UP) * lengths[i]
		p[0] = base
		for i in range(1, n):
			p[i] = p[i - 1] + _dir(p[i - 1], p[i], Vector3.UP) * lengths[i - 1]
		if p[n - 1].distance_to(target) < 0.0005:
			break
	return p
