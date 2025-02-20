extends CharacterBody3D

@onready var cam_piv = $piv
@onready var camera_arm = $piv/SpringArm3D
@onready var camera = $piv/SpringArm3D/Camera3D
@onready var mesh = $mesh
@onready var leg_animator = $mesh/LegAnimator
@onready var sword = $mesh/sword
@onready var shield = $mesh/shield  # New shield node
@onready var collision_shape = $CollisionShape3D
@onready var fairy = $fairy
@onready var jump_sound = $mesh/player_sounds/jump
@onready var land_sound = $mesh/player_sounds/land
@onready var shield_sound = $mesh/player_sounds/shield
@onready var hurt_sound = $mesh/player_sounds/hurt

# Movement constants
const SPEED = 4.0  # Slightly slower base speed for more deliberate movement
const ACCELERATION = 30.0  # Faster acceleration for responsive controls
const FRICTION = 60.0
const ROTATION_SPEED = 20.0  # Faster rotation for responsive targeting
const AERIAL_STRIKE_GRAVITY_MULT = 1.5  # Faster falling during strike
const AERIAL_STRIKE_SPEED = 3.0
# Movement States
enum ActionState {IDLE, WALK, JUMP, ROLL, ATTACK, BLOCK, HURT}

# Basic movement mechanics
const JUMP_VELOCITY = 6.0
const JUMP_BUFFER_TIME = 0.1
const COYOTE_TIME = 0.1

# Combat and movement abilities
const ROLL_SPEED = 8.0
const ROLL_DURATION = 0.4
const KNOCKBACK_FORCE = 8.0
const DAMAGE_INVULNERABILITY_TIME = 0.8
const TARGETING_DISTANCE = 10.0

# Get the gravity from project settings
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# State handling
var action_state = ActionState.IDLE
var jump_buffer_timer = 0.0
var coyote_timer = 0.0
var was_on_floor = false

# Movement and combat variables
var input_dir = Vector2.ZERO
var direction = Vector3.ZERO
var last_safe_position = Vector3.ZERO
var target_enemy = null  # For Z-targeting
var is_targeting = false
var is_blocking = false
var is_attacking = false
var is_rolling = false
var roll_timer = 0.0
var is_invulnerable = false
var damage_invulnerability_timer = 0.0

func _ready():
	# Initialize camera and controls
	camera_arm.add_excluded_object(self)
	camera_arm.add_excluded_object(mesh)
	camera_arm.add_excluded_object(sword)
	camera_arm.add_excluded_object(shield)
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	cam_piv.top_level = true
	cam_piv.position = Vector3.ZERO

func _physics_process(delta):
	handle_movement(delta)
	handle_targeting(delta)
	handle_combat(delta)
	update_timers(delta)
	move_and_slide()

func start_aerial_strike():
	velocity.y = -AERIAL_STRIKE_SPEED
	velocity.x = 0.0
	velocity.z = 0.0
	is_attacking = true
	action_state = ActionState.ATTACK

func handle_movement(delta):
	if not is_on_floor():
		# Apply increased gravity during aerial strike
		if is_attacking and sword.current_attack_type == sword.AttackType.AERIAL:
			velocity.y -= gravity * AERIAL_STRIKE_GRAVITY_MULT * delta
			velocity.x = 0.0
			velocity.z = 0.0
			return  # Lock all movement during aerial strike
		else:
			velocity.y -= gravity * delta
		
		# Handle coyote time
		if was_on_floor:
			coyote_timer = COYOTE_TIME
	else:
		if !was_on_floor:
			land_sound.play()
			
			# If we landed from aerial strike
			if is_attacking and sword.current_attack_type == sword.AttackType.AERIAL:
				is_attacking = false
				action_state = ActionState.IDLE
			
		# Handle jump buffer
		if jump_buffer_timer > 0.0:
			perform_jump()
			jump_buffer_timer = 0.0
	
	was_on_floor = is_on_floor()
	
	# Don't process regular movement if rolling or blocking
	if !is_rolling:
		input_dir = Input.get_vector("left", "right", "up", "down")
		
		if is_targeting and target_enemy:
			# Strafe movement when targeting
			var target_dir = (target_enemy.global_position - global_position).normalized()
			var right = target_dir.cross(Vector3.UP)
			direction = right * input_dir.x + target_dir * -input_dir.y
		else:
			# Normal movement relative to camera
			direction = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
			direction = direction.rotated(Vector3.UP, cam_piv.rotation.y)
		
		if direction:
			# Set base speed and modify based on state
			var current_speed = SPEED
			
			# Handle different movement states
			if is_attacking and !sword.is_charging:
				current_speed = 0.0  # No movement during attack
			elif sword.is_charging:
				current_speed *= sword.CHARGE_MOVEMENT_SPEED_MULT
			elif is_blocking:
				current_speed *= 0.4  # 40% speed while blocking
			
			# Apply movement
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
			
			# Handle rotation - same logic whether charging or not
			if !is_targeting and !is_attacking:  # Don't rotate during attack
				var target_basis = Basis.looking_at(direction, Vector3.UP)
				mesh.transform.basis = mesh.transform.basis.slerp(target_basis, get_physics_process_delta_time() * ROTATION_SPEED)
			
			if is_on_floor():
				action_state = ActionState.WALK
				
			# Animate legs based on actual movement speed
			var speed = Vector2(velocity.x, velocity.z).length() / SPEED
			leg_animator.animate_legs(delta, speed)
		else:
			# Stop movement when no direction
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
			velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
			
			if is_on_floor():
				action_state = ActionState.IDLE
			
			# Animate legs with zero speed to return to neutral
			leg_animator.animate_legs(delta, 0.0)

func handle_targeting(delta):
	if is_targeting and target_enemy:
		# Update camera to face target
		var target_pos = target_enemy.global_position
		var look_dir = (target_pos - global_position).normalized()
		
		if !is_attacking and !is_rolling:
			# Rotate mesh to face target
			var target_basis = Basis.looking_at(look_dir, Vector3.UP)
			mesh.transform.basis = mesh.transform.basis.slerp(target_basis, delta * ROTATION_SPEED)
		
		# Update camera position
		var camera_target = (global_position + target_pos) * 0.5
		cam_piv.global_position = cam_piv.global_position.lerp(camera_target, delta * 5.0)
	else:
		# Normal camera follow
		var target_pos = global_position + Vector3(0, 0.44, 0)
		cam_piv.global_position = cam_piv.global_position.lerp(target_pos, 0.1)

func handle_combat(delta):
	if is_rolling:
		roll_timer -= delta
		velocity = -mesh.global_transform.basis.z * ROLL_SPEED
		if roll_timer <= 0:
			is_rolling = false
			action_state = ActionState.IDLE

func perform_jump():
	if is_on_floor() or coyote_timer > 0:
		jump_sound.play()
		velocity.y = JUMP_VELOCITY
		action_state = ActionState.JUMP
		coyote_timer = 0

func perform_attack():
	if !is_attacking and !is_rolling and !is_blocking:
		is_attacking = true
		action_state = ActionState.ATTACK
		
		if is_on_floor():
			# Start charging if the button is held
			sword.start_charge()
		else:
			# Aerial attack if in the air
			sword.start_aerial_strike()

func start_roll():
	if !is_rolling and !is_attacking and !is_blocking and is_on_floor():
		is_rolling = true
		is_invulnerable = true
		shield.stow()  # Call stow function
		roll_timer = ROLL_DURATION
		action_state = ActionState.ROLL

func start_block():
	if !is_blocking and !is_rolling and !is_attacking and is_on_floor():
		is_blocking = true
		shield_sound.play()
		shield.shield()  # Call shield function
		action_state = ActionState.BLOCK


func end_block():
	if is_blocking:
		is_blocking = false
		shield.equip()  # Call equip function
		action_state = ActionState.IDLE

func toggle_targeting():
	if !is_targeting:
		# Find nearest targetable enemy
		var nearest_dist = TARGETING_DISTANCE
		target_enemy = null
		
		for enemy in get_tree().get_nodes_in_group("targetable"):
			var dist = global_position.distance_to(enemy.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				target_enemy = enemy
		
		is_targeting = target_enemy != null
	else:
		is_targeting = false
		target_enemy = null

func take_damage(amount: int, knockback_direction: Vector3):
	if !is_invulnerable and !is_rolling:
		if is_blocking and knockback_direction.dot(-mesh.global_transform.basis.z) > 0:
			# Successful block
			shield_sound.play()
			velocity = knockback_direction * KNOCKBACK_FORCE * 0.3  # Reduced knockback
		else:
			# Take damage
			hurt_sound.play()
			is_invulnerable = true
			damage_invulnerability_timer = DAMAGE_INVULNERABILITY_TIME
			velocity = knockback_direction * KNOCKBACK_FORCE
			velocity.y = JUMP_VELOCITY * 0.5
			action_state = ActionState.HURT

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
	if event is InputEventMouseMotion and !is_targeting:
		cam_piv.rotate_y(-event.relative.x * 0.005)
		camera_arm.rotate_x(-event.relative.y * 0.005)
		camera_arm.rotation.x = clamp(camera_arm.rotation.x, -PI/2.1, PI/2.1)
	
	elif event.is_action_pressed("jump"):
		if is_on_floor() or coyote_timer > 0:
			perform_jump()
		else:
			jump_buffer_timer = JUMP_BUFFER_TIME
	
	elif event.is_action_pressed("attack"):
		perform_attack()
	elif event.is_action_released("attack"):
		if sword.is_charging:
			sword.release_charge()
	
	elif event.is_action_pressed("roll"):
		start_roll()
	
	elif event.is_action_pressed("block"):
		start_block()
	elif event.is_action_released("block"):
		end_block()
	
	elif event.is_action_pressed("target"):
		toggle_targeting()
