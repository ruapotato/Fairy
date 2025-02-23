extends RigidBody3D

# Core nodes
@onready var body = $imported_mesh/body
@onready var audio_player = $imported_mesh/AudioStreamPlayer3D
@onready var wing_left = $imported_mesh/wing2
@onready var wing_right = $imported_mesh/wing1
@onready var spring_arm_pivot = $piv
@onready var camera_arm = $piv/SpringArm3D
@onready var camera = $piv/SpringArm3D/Camera3D

# Basic parameters
var player
var possession_speed = 5.0
var acceleration = 15.0
var deceleration = 8.0
var wing_flap_speed = 15.0
var wing_flap_amplitude = 0.5

# Circle following parameters
var circle_radius = 1.0
var circle_time = 0.0
var circle_bob_time = 0.0
var max_speed = 3.0
var trail_distance = 1.5
var last_player_pos = Vector3.ZERO
var target_pos = Vector3.ZERO

# State
var is_possessed = false
var wing_time = 0.0
var is_speaking = false

func _ready():
	# Get player reference
	player = get_parent()
	var level_loader = player.get_parent()
	player.call_deferred("remove_child", self)
	level_loader.call_deferred("add_child", self)
	
	# Setup physics
	lock_rotation = true
	gravity_scale = 0
	linear_damp = 1.0
	
	# Camera setup
	spring_arm_pivot.top_level = true
	camera.current = false
	camera_arm.add_excluded_object(self)

func start_possession():
	is_possessed = true
	camera.current = true
	spring_arm_pivot.position = global_position + Vector3(0, 0.5, 0)
	spring_arm_pivot.rotation = Vector3.ZERO
	camera_arm.rotation = Vector3.ZERO

func end_possession():
	is_possessed = false
	camera.current = false
	linear_velocity = Vector3.ZERO
	spring_arm_pivot.rotation = Vector3.ZERO
	camera_arm.rotation = Vector3.ZERO

func _physics_process(delta):
	if is_possessed:
		handle_possessed_movement(delta)
	else:
		handle_following_movement(delta)
	update_wings(delta)

func handle_possessed_movement(delta):
	# Update camera position to follow fairy
	spring_arm_pivot.global_position = global_position 
	
	# Get input
	var input_dir = Input.get_vector("left", "right", "up", "down")
	
	# Get camera's forward and right vectors
	var cam_basis = camera.global_transform.basis
	var forward = cam_basis.z
	var right = cam_basis.x
	
	# Combine input with camera directions
	var direction = (forward * input_dir.y + right * input_dir.x).normalized()
	
	# Apply movement
	if direction:
		linear_velocity = linear_velocity.lerp(direction * possession_speed, delta * acceleration)
	else:
		linear_velocity = linear_velocity.move_toward(Vector3.ZERO, deceleration * delta)

func handle_following_movement(delta):
	var player_pos = player.global_position
	var player_moving = (player_pos - last_player_pos).length() > 0.01
	last_player_pos = player_pos
	circle_bob_time += delta * 3.0
	
	if is_speaking:
		# When speaking, stay directly in front of player
		var player_facing = -player.transform.basis.z
		target_pos = player_pos + player_facing * 1.0
		target_pos.y = player_pos.y + 1.0
	else:
		if player_moving:
			# Stay slightly behind and above player when moving
			var player_facing = -player.transform.basis.z
			target_pos = player_pos + player_facing * (trail_distance * 0.5)
			target_pos.y = player_pos.y + 1.2
		else:
			# Continuous circular motion when player is still
			circle_time += delta * (1.0 + sin(circle_bob_time) * 0.2)
			var circle_offset = Vector3(
				cos(circle_time) * (circle_radius * 0.7),
				0.8 + sin(circle_bob_time) * 0.1,
				sin(circle_time) * (circle_radius * 0.7)
			)
			target_pos = player_pos + circle_offset
	
	# Calculate target velocity
	var direction = target_pos - global_position
	var target_velocity = direction * max_speed
	
	# Smoothly move towards target
	linear_velocity = linear_velocity.lerp(target_velocity, delta * acceleration)
	
	# Update rotation to look at player
	var look_target = player_pos + Vector3.UP * 0.5
	var target_transform = transform.looking_at(look_target, Vector3.UP)
	transform.basis = transform.basis.slerp(target_transform.basis, delta * 5.0)

func update_wings(delta):
	# Simple wing flapping animation
	wing_time += delta * wing_flap_speed
	var wing_rotation = sin(wing_time) * wing_flap_amplitude
	wing_left.rotation.y = wing_rotation
	wing_right.rotation.y = -wing_rotation

func _unhandled_input(event):
	if is_possessed:
		if event is InputEventMouseMotion:
			spring_arm_pivot.rotate_y(-event.relative.x * 0.005)
			camera_arm.rotate_x(-event.relative.y * 0.005)
			camera_arm.rotation.x = clamp(camera_arm.rotation.x, -PI/4, PI/4)
			camera_arm.rotation.y = 0
			camera_arm.rotation.z = 0
		
		if event.is_action_pressed("play_flute"):
			player.end_possession()
