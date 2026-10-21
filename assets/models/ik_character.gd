@tool
extends Node3D

@onready var r_index: SkeletonIK3D = $Armature/Skeleton3D/r_Index
@onready var r_middle: SkeletonIK3D = $Armature/Skeleton3D/r_Middle
@onready var r_thumb: SkeletonIK3D = $Armature/Skeleton3D/r_Thumb
@onready var r_ring: SkeletonIK3D = $Armature/Skeleton3D/r_Ring
@onready var r_pinky: SkeletonIK3D = $Armature/Skeleton3D/r_Pinky
@onready var l_thumb: SkeletonIK3D = $Armature/Skeleton3D/l_Thumb
@onready var l_index: SkeletonIK3D = $Armature/Skeleton3D/l_Index
@onready var l_middle: SkeletonIK3D = $Armature/Skeleton3D/l_Middle
@onready var l_ring: SkeletonIK3D = $Armature/Skeleton3D/l_Ring
@onready var l_pinky: SkeletonIK3D = $Armature/Skeleton3D/l_Pinky

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	r_thumb.start()
	r_index.start()
	r_middle.start()
	r_ring.start()
	r_pinky.start()
	l_thumb.start()
	l_index.start()
	l_middle.start()
	l_ring.start()
	l_pinky.start()
