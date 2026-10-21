extends Node
## Silah yoneticisi (autoload).
##
## Her silah KENDI sahnesinde yasar: res://weapons/<ad>/<ad>.tscn
## Sahne koku "Weapon" (Node3D) olur ve karakterin EL SOKETINE instance edilir:
##
##   Player/IK_character/RightHandAttach   <- silah buraya takilir (el kemigi)
##     Weapon                              (silah sahnesi koku)
##       WristPivot              (bilek ekseni -- player_controller dondurur)
##         RecoilPivot           (geri tepme -- weapon_controller dondurur)
##           GunVisual           (silah modeli)
##           GripRight/GripLeft  (el tutus hedefleri)
##           FingersRight/Left   (parmak ucu hedefleri -- opsiyonel)
##           Muzzle / EjectPort
##
## MIMARI: silah eli takip eder (el = master). Silah el kemiginin cocugu
## oldugu icin el nereye giderse silah da oraya gider ve parmak hedefleri de
## el uzayinda kaldigi icin parmaklar elden kopmaz. RightHandAttach yoksa
## (el soketi olmayan sahneler) eski davranis olan Player/CameraPivot kullanilir.
##
## YENI SILAH EKLEMEK:
##   1) weapons/<ad>/ klasoru ac
##   2) <ad>.tscn dosyasini yukaridaki duzende olustur (g18.tscn'den kopyala)
##   3) kok dugume metadata/weapon_id = "<ad>" ekle
##   4) WeaponManager.equip("<ad>") ile tak. Baska degisiklik gerekmez.

signal weapon_changed(id: String, weapon: Node3D)

const WEAPONS_DIR := "res://weapons"
## El soketi (Player'a gore yol). Yoksa CameraPivot'a dusulur.
const HAND_MOUNT_PATH := "IK_character/WeaponMount"
const LEGACY_HAND_MOUNT_PATH := "IK_character/RightHandAttach"

## Sahne acilirken takilacak silah.
@export var default_weapon := "g18"
## Varsayilan silah sahnede zaten takiliysa yeniden olusturulmaz.
@export var equip_on_ready := true

var current_weapon: Node3D
var current_id := ""

func _ready() -> void:
	if equip_on_ready:
		call_deferred("_equip_default")

func _equip_default() -> void:
	var player := find_player()
	if player == null:
		push_warning("WeaponManager: Player bulunamadi")
		return
	var socket := player.get_node_or_null(HAND_MOUNT_PATH) as Node3D
	var mounted := mounted_weapon(player)
	# Soket varsa silah orada olmali (el = master): sahnede CameraPivot'ta
	# kalmis instance'i ele tasi.
	if mounted != null and socket != null and mounted.get_parent() != socket:
		var wid := String(mounted.get_meta("weapon_id", ""))
		equip(wid if wid != "" else default_weapon, player)
		return
	if mounted != null and String(mounted.get_meta("weapon_id", "")) == default_weapon:
		current_weapon = mounted
		current_id = default_weapon
		weapon_changed.emit(current_id, mounted)
		return
	equip(default_weapon, player)

## Silahin takilacagi dugum: el soketi varsa orasi (silah eli takip eder),
## yoksa CameraPivot (viewmodel).
func weapon_mount(player: Node3D) -> Node3D:
	if player == null:
		return null
	# Silah artik el kemigine degil, player_controller'in her karede
	# surdugu WeaponMount'a takilir. Boylece silah master olur; iki el de
	# silahin RightHandTarget/LeftHandTarget noktalarini takip eder.
	var socket := player.get_node_or_null(HAND_MOUNT_PATH) as Node3D
	if socket != null:
		return socket
	# Geriye uyumluluk: eski sahnelerde el kemigi soketi kullanilabilir.
	var legacy := player.get_node_or_null(LEGACY_HAND_MOUNT_PATH) as Node3D
	if legacy != null:
		return legacy
	return player.get_node_or_null("CameraPivot") as Node3D

## Sahnede herhangi bir montaj noktasinda duran silah.
func mounted_weapon(player: Node3D) -> Node3D:
	if player == null:
		return null
	# Yeni WeaponMount oncelikli; eski el soketi ve CameraPivot fallback.
	for mount in [weapon_mount(player), player.get_node_or_null(HAND_MOUNT_PATH), player.get_node_or_null(LEGACY_HAND_MOUNT_PATH), player.get_node_or_null("CameraPivot")]:
		if mount == null:
			continue
		var w := (mount as Node).get_node_or_null("Weapon") as Node3D
		if w != null:
			return w
	return null

## Silahi takar (player verilmezse sahnede aranir). Takilan dugumu dondurur.
func equip(id: String, player: Node3D = null) -> Node3D:
	if player == null:
		player = find_player()
	if player == null:
		push_warning("WeaponManager: Player bulunamadi, silah takilamadi")
		return null
	var mount := weapon_mount(player)
	if mount == null:
		push_warning("WeaponManager: silah montaj noktasi yok")
		return null
	var path := weapon_scene_path(id)
	if not ResourceLoader.exists(path):
		push_warning("WeaponManager: silah sahnesi yok: %s" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("WeaponManager: sahne yuklenemedi: %s" % path)
		return null
	var w := packed.instantiate() as Node3D
	if w == null:
		push_warning("WeaponManager: sahne koku Node3D degil: %s" % path)
		return null
	w.name = "Weapon"
	var old := mounted_weapon(player)
	if old != null and old.get_parent() != null:
		old.get_parent().remove_child(old)
		old.queue_free()
	mount.add_child(w)
	current_weapon = w
	current_id = id
	weapon_changed.emit(id, w)
	return w

func unequip(player: Node3D = null) -> void:
	if player == null:
		player = find_player()
	if player == null:
		return
	var old := mounted_weapon(player)
	if old != null and old.get_parent() != null:
		old.get_parent().remove_child(old)
		old.queue_free()
	current_weapon = null
	current_id = ""
	weapon_changed.emit("", null)

func get_weapon() -> Node3D:
	return current_weapon

## Sahnedeki (takili) silah dugumu.
func get_mounted(player: Node3D) -> Node3D:
	return mounted_weapon(player)

func weapon_scene_path(id: String) -> String:
	return "%s/%s/%s.tscn" % [WEAPONS_DIR, id, id]

## weapons/ altindaki kurulu silahlarin id listesi.
func list_weapons() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(WEAPONS_DIR)
	if d == null:
		return out
	for f in d.get_directories():
		if ResourceLoader.exists(weapon_scene_path(f)):
			out.append(f)
	return out

## Sahnede CameraPivot/Camera tasiyan dugumu (Player) bulur.
func find_player() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return _find_holder(scene)

func _find_holder(n: Node) -> Node3D:
	if n.get_node_or_null("CameraPivot/Camera") != null:
		return n as Node3D
	for c in n.get_children():
		var r := _find_holder(c)
		if r != null:
			return r
	return null
