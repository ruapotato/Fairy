extends Node3D

const SHIELD_CARRY = 66.6
const SHIELD_ACTIVE = 0.0
const SHIELD_BACK = 180.0

# Much faster rotation speed for more immediate response
const ROTATION_SPEED: float = 25.0

var current_angle: float = SHIELD_CARRY
var target_angle: float = SHIELD_CARRY

func _ready() -> void:
	rotation.y = deg_to_rad(SHIELD_CARRY)

func _process(delta: float) -> void:
	# More immediate rotation with faster interpolation
	current_angle = move_toward(current_angle, target_angle, delta * ROTATION_SPEED * 45.0)
	rotation.y = deg_to_rad(current_angle)

func stow() -> void:
	target_angle = SHIELD_BACK
	print("Shield: Stowing ", current_angle, " -> ", target_angle)

func shield() -> void:
	target_angle = SHIELD_ACTIVE
	print("Shield: Blocking ", current_angle, " -> ", target_angle)

func equip() -> void:
	target_angle = SHIELD_CARRY
	print("Shield: Equipping ", current_angle, " -> ", target_angle)
