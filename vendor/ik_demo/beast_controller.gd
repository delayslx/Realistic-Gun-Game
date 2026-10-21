extends MeshInstance3D

@export var rotation_speed := 40
@export var movement_speed := 3

func _process(delta: float) -> void:
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	position += -basis.z * input_dir.y * delta * movement_speed
	rotation.y += deg_to_rad(-input_dir.x * delta * rotation_speed)
	
