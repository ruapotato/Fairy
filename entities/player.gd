extends CharacterBody3D

@onready var cam_piv = $piv
@onready var camera_arm = $piv/SpringArm3D
@onready var camera = $piv/SpringArm3D/Camera3D
@onready var mesh = $mesh
@onready var leg_animator = $mesh/LegAnimator
@onready var sword = $mesh/sword
@onready var collision_shape = $CollisionShape3D
@onready var fairy = $fairy
@onready var jump_sound = $mesh/player_sounds/jump
@onready var land_sound = $mesh/player_sounds/land
@onready var dash_sound = $mesh/player_sounds/dash
@onready var hurt_sound = $mesh/player_sounds/hurt

# Movement constants
const SPEED = 5.0
const ACCELERATION = 20.0
const FRICTION = 60.0
const AIR_FRICTION = 10.0
const ROTATION_SPEED = 15.0
const MIN_STRETCH = 1.0
const MAX_STRETCH = 1.1
const STRETCH_SPEED = 8.0

# Movement States
enum ActionState {IDLE, WALK, JUMP, TRIPLE_JUMP, GROUND_POUND, ROLL, ATTACK, HURT}

# Jump mechanics - Mario-style values
const JUMP_VELOCITY = 7.0  # Initial jump velocity
const TRIPLE_JUMP_VELOCITY = 11.0  # Higher jump for triple jump
const SUPER_JUMP_VELOCITY = 13.0  # Upward dash jump
const JUMP_BUFFER_TIME = 0.15
const COYOTE_TIME = 0.15
const JUMP_CUT_POWER = 0.4
const MIN_JUMP_HEIGHT = 0.2
const GROUND_POUND_VELOCITY = 25.0
const GROUND_POUND_RECOVERY_JUMP = 8.0
const MAX_JUMPS = 3

# Triple jump timing
const TRIPLE_JUMP_WINDOW = 0.5  # Time window to chain jumps
var jump_count = 0  # For tracking triple jump
var last_jump_time = 0.0
var can_triple_jump = false

# Ground pound state
var is_ground_pounding = false
var ground_pound_recovery = false

# Combat and movement abilities
const DASH_SPEED = 12.0
const DASH_DURATION = .4
const DASH_COOLDOWN = 0.8
const ROLL_SPEED = 8.0
const ROLL_DURATION = 0.5
const KNOCKBACK_FORCE = 10.0
const DAMAGE_INVULNERABILITY_TIME = 1.5

# Get the gravity from project settings (should be positive as gravity pulls down)
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var terminal_velocity = 30.0

# State handling
var action_state = ActionState.IDLE
var jumps_remaining = MAX_JUMPS
var jump_buffer_timer = 0.0
var coyote_timer = 0.0
var was_on_floor = false
var current_stretch = 1.0
var base_mesh_scale: Vector3

# Movement and combat variables
var input_dir = Vector2.ZERO
var direction = Vector3.ZERO
var last_safe_position = Vector3.ZERO
var horizontal_velocity = Vector3.ZERO
var last_movement_direction = Vector3.FORWARD  # Initialize facing forward
var is_attacking = false
var attack_combo = 0
var attack_cooldown = 0.0
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var can_dash = true
var roll_timer = 0.0
var is_rolling = false
var is_invulnerable = false
var damage_invulnerability_timer = 0.0
var is_knocked_down = false

func _ready():
	# Initialize camera and controls
	camera_arm.add_excluded_object(self)
	camera_arm.add_excluded_object(mesh)
	camera_arm.add_excluded_object(sword)
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	cam_piv.top_level = true
	cam_piv.position = Vector3.ZERO
	
	base_mesh_scale = mesh.scale
	
	# Initialize leg animator if not present
	if !leg_animator:
		var leg_anim = preload("res://entities/legs.gd").new()
		leg_anim.name = "LegAnimator"
		mesh.add_child(leg_anim)
		leg_animator = leg_anim

func _physics_process(delta):
	handle_movement(delta)
	handle_abilities(delta)
	handle_combat(delta)
	update_timers(delta)
	update_mesh_visuals(delta)
	move_and_slide()

func handle_movement(delta):
	# Ground pound takes priority
	if is_ground_pounding:
		velocity.y = -GROUND_POUND_VELOCITY
		if is_on_floor():
			is_ground_pounding = false
			ground_pound_recovery = true
			velocity.y = GROUND_POUND_RECOVERY_JUMP
			return
	elif ground_pound_recovery and is_on_floor():
		ground_pound_recovery = false
	
	# Mario-style jump physics
	if not is_on_floor():
		# Don't apply any gravity during dash/super jump
		if dash_timer > 0:
			# Keep current velocity
			pass
		# Apply normal gravity physics
		else:
			if velocity.y > 0:
				velocity.y = velocity.y - gravity * delta
				# Apply jump cut when jump is released
				if not Input.is_action_pressed("jump"):
					velocity.y *= JUMP_CUT_POWER
			else:
				# Apply stronger gravity when falling
				velocity.y = max(velocity.y - gravity * 1.5 * delta, -terminal_velocity)
			
		# Handle coyote time
		if was_on_floor:
			coyote_timer = COYOTE_TIME
	else:
		# Reset jump mechanics when landing
		if !was_on_floor:
			land_sound.play()
			jumps_remaining = MAX_JUMPS
			
			# Handle triple jump timing
			if jump_count > 0 and Time.get_ticks_msec() - last_jump_time > TRIPLE_JUMP_WINDOW * 1000:
				jump_count = 0
			
			# Handle jump buffer
			if jump_buffer_timer > 0:
				perform_jump()
				jump_buffer_timer = 0
	
	was_on_floor = is_on_floor()
	
	# Handle movement
	if !is_rolling and !is_attacking and !is_ground_pounding and !is_knocked_down:
		input_dir = Input.get_vector("left", "right", "up", "down")
		direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
		direction = direction.rotated(Vector3.UP, cam_piv.rotation.y)
		
		if direction:
			# Update last_movement_direction for mesh rotation
			last_movement_direction = direction
			
			# Accelerate towards target velocity
			var target_velocity = direction * SPEED
			horizontal_velocity = horizontal_velocity.move_toward(target_velocity, ACCELERATION * delta)
			
			if is_on_floor():
				action_state = ActionState.WALK
		else:
			# Apply friction
			var friction = FRICTION if is_on_floor() else AIR_FRICTION
			horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, friction * delta)
			
			if is_on_floor():
				action_state = ActionState.IDLE
		
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z

func handle_abilities(delta):
	# Update dash
	if dash_timer > 0:
		dash_timer -= delta
		if input_dir.length_squared() < 0.1:
			# Vertical dash (super jump)
			velocity.y = SUPER_JUMP_VELOCITY
			velocity.x = 0
			velocity.z = 0
		else:
			# Normal horizontal dash
			velocity = direction * DASH_SPEED
		
		if dash_timer <= 0:
			can_dash = false
			dash_cooldown_timer = DASH_COOLDOWN
	
	# Update dash cooldown
	if !can_dash:
		dash_cooldown_timer -= delta
		if dash_cooldown_timer <= 0:
			can_dash = true
	
	# Update roll
	if is_rolling:
		roll_timer -= delta
		velocity = -mesh.global_transform.basis.z * ROLL_SPEED
		if roll_timer <= 0:
			is_rolling = false

func handle_combat(delta):
	if is_attacking:
		attack_cooldown -= delta
		if attack_cooldown <= 0:
			is_attacking = false
			attack_combo = 0

func perform_jump():
	if is_on_floor() or coyote_timer > 0:
		jump_sound.play()
		var current_time = Time.get_ticks_msec()
		
		# Handle triple jump mechanics
		if is_on_floor():
			if jump_count > 0 and (current_time - last_jump_time) <= TRIPLE_JUMP_WINDOW * 1000:
				jump_count += 1
				if jump_count >= 3:
					# Triple jump!
					velocity.y = TRIPLE_JUMP_VELOCITY
					action_state = ActionState.TRIPLE_JUMP
					jump_count = 0
					return
			else:
				jump_count = 1
			
			last_jump_time = current_time
		
		# Normal jump with Mario-style momentum
		var jump_force = JUMP_VELOCITY
		var forward_boost = 1.0
		action_state = ActionState.JUMP
			
		# Mario-style running jump
		if horizontal_velocity.length() > SPEED * 0.7:
			jump_force *= 1.2
			forward_boost = 1.4  # More forward momentum for running jumps
		
		# Apply the jump
		velocity.y = jump_force
		
		# Apply forward momentum boost
		if horizontal_velocity.length() > 0:
			var current_speed = horizontal_velocity.length()
			horizontal_velocity = horizontal_velocity.normalized() * (current_speed * forward_boost)
		
		coyote_timer = 0

func perform_ground_pound():
	if not is_on_floor() and not is_ground_pounding:
		is_ground_pounding = true
		velocity.y = 0  # Stop vertical movement
		velocity.x = 0  # Stop horizontal movement
		velocity.z = 0
		action_state = ActionState.GROUND_POUND

func perform_super_jump():
	if is_on_floor():
		jump_sound.play()
		velocity.y = SUPER_JUMP_VELOCITY
		# Reset horizontal velocity for pure vertical jump
		velocity.x = 0
		velocity.z = 0
		# Start the dash timer to prevent gravity from immediately affecting the jump
		dash_timer = DASH_DURATION
		can_dash = false
		dash_cooldown_timer = DASH_COOLDOWN   
func start_dash():
	if can_dash:
		dash_sound.play()
		dash_timer = DASH_DURATION

func start_roll():
	if !is_rolling and is_on_floor():
		is_rolling = true
		roll_timer = ROLL_DURATION

func perform_attack():
	if !is_attacking and !is_rolling:
		is_attacking = true
		attack_combo = (attack_combo + 1) % 3
		sword.swipe()
		attack_cooldown = 0.5

func take_damage(amount: int, knockback_direction: Vector3):
	if !is_invulnerable:
		hurt_sound.play()
		is_invulnerable = true
		damage_invulnerability_timer = DAMAGE_INVULNERABILITY_TIME
		velocity = knockback_direction * KNOCKBACK_FORCE
		velocity.y = JUMP_VELOCITY * 0.5  # Add some upward force
		action_state = ActionState.HURT

func update_mesh_visuals(delta):
	# Update target mesh transform based on movement
	if velocity.length_squared() > 0.01:
		# Create the base transform for movement direction
		var look_basis = Basis.looking_at(last_movement_direction, Vector3.UP)
		
		# Create stretch transform
		var stretch = Transform3D()
		stretch = stretch.scaled(Vector3(1, 1, current_stretch))
		
		# Combine transformations
		var target_mesh_transform = Transform3D(look_basis, mesh.position) * stretch
		
		# Smoothly interpolate to target transform
		mesh.transform = mesh.transform.interpolate_with(target_mesh_transform, delta * ROTATION_SPEED)
	
	# Calculate mesh stretch based on movement
	var speed = velocity.length() / SPEED
	current_stretch = lerp(current_stretch, lerp(MIN_STRETCH, MAX_STRETCH, speed), delta * STRETCH_SPEED)
	
	# Only animate legs when grounded
	if is_on_floor():
		leg_animator.animate_legs(delta, speed)
	
	# Flash mesh during invulnerability
	if is_invulnerable:
		mesh.visible = fmod(damage_invulnerability_timer * 4, 1) > 0.5
	else:
		mesh.visible = true  # Make sure mesh is visible when not invulnerable


func update_timers(delta):
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	
	if coyote_timer > 0:
		coyote_timer -= delta
	
	if damage_invulnerability_timer > 0:
		damage_invulnerability_timer -= delta
		if damage_invulnerability_timer <= 0:
			is_invulnerable = false

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		cam_piv.rotate_y(-event.relative.x * 0.005)
		camera_arm.rotate_x(-event.relative.y * 0.005)
		camera_arm.rotation.x = clamp(camera_arm.rotation.x, -PI/2.1, PI/2.1)
	
	elif event.is_action_pressed("jump"):
		if is_on_floor() or coyote_timer > 0:
			perform_jump()
		else:
			jump_buffer_timer = JUMP_BUFFER_TIME
			
		# Allow jump to cancel ground pound
		if is_ground_pounding:
			is_ground_pounding = false
			velocity.y = JUMP_VELOCITY
	
	elif event.is_action_pressed("attack"):
		perform_attack()
	
	elif event.is_action_pressed("roll"):
		if is_on_floor():
			start_roll()
		else:
			perform_ground_pound()
	
	elif event.is_action_pressed("dash"):
		# Super jump if no direction input
		if input_dir.length_squared() < 0.1 and is_on_floor():
			perform_super_jump()
		else:
			start_dash()

func _process(delta):
	# Update camera
	var target_pos = global_position + Vector3(0, 0.44, 0)
	cam_piv.global_position = cam_piv.global_position.lerp(target_pos, 0.1)
