@tool
extends SkeletonModifier3D
## Parmak IK'sini iskelet modifier zincirine sokan sarmalayici dugum.
##
## Neden ayri bir modifier: SkeletonModifier3D zinciri editorde de islenir
## (hand_rig her karede NOTIFICATION_UPDATE_SKELETON gonderir). Elle yazilan
## set_bone_global_pose_override editorde render'a hic yansimiyor; modifier
## icinden kemik pozu yazmak hem oyunda hem editorde ayni sonucu verir.
##
## Cozumleyici hand_rig'dir; bu dugum yalnizca dogru sirada cagirir: kol IK ve
## el kopyalama modifier'larindan SONRA gelmelidir (kardes sirasi).

## Cozumleyici (hand_rig). ik_character.tscn'de hand_rig baglar.
var rig: Node


func _process_modification() -> void:
	if rig != null and rig.has_method("solve_fingers_in_modifier"):
		rig.call("solve_fingers_in_modifier")
