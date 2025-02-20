extends Node3D

@onready var cutt_edge = $"MeshInstance3D2/Cutting Edge"
@onready var swoosh_sound = $swoosh
@onready var charge_particles = $ChargeParticles
@onready var charge_sound = $charge_sound

const SWORD_ANGLE = 75.0
const SWIPE_DURATION = 0.15
const RETURN_DURATION = 0.1
const CHARGE_TIME = 1.0
const SPIN_ATTACK_DURATION = 0.35  # Much faster spin
const AERIAL_STRIKE_SPEED = 2.0
const CHARGE_MOVEMENT_SPEED_MULT = 0.4
const CHARGE_SCALE_MAX = 1.2

# Attack Types
enum AttackType {
	SLASH_RIGHT_TO_LEFT,
	SLASH_LEFT_TO_RIGHT,
	SPIN,
	AERIAL
}

const SCALE_DEFAULT = Vector3(1.0, 1.0, 1.0)
const SCALE_SPIN = Vector3(1.4, 1.0, 1.4)
const Y_OFFSET_DEFAULT = 0.0

const PLAYER_SCALE_DEFAULT = Vector3(1.0, 1.0, 1.0)
const PLAYER_SCALE_ATTACK = Vector3(1.1, 0.9, 1.1)
const PLAYER_SCALE_SPIN = Vector3(1.2, 0.8, 1.2)

var is_animating = false
var is_charging = false
var charge_time = 0.0
var animation_time = 0.0
var start_y_rotation = 0.0
var target_y_rotation = 0.0
var current_attack_type = AttackType.SLASH_RIGHT_TO_LEFT
var last_attack_was_right = true

var start_scale = SCALE_DEFAULT
var target_scale = SCALE_DEFAULT
var start_y_pos = Y_OFFSET_DEFAULT
var target_y_pos = Y_OFFSET_DEFAULT
var player_start_scale = PLAYER_SCALE_DEFAULT
var player_target_scale = PLAYER_SCALE_DEFAULT

var level_loader
var player

func _ready() -> void:
	level_loader = find_root()
	player = level_loader.find_child("player")
	reset_sword_state()
	if charge_particles:
		charge_particles.emitting = false

func reset_sword_state():
	rotation.z = 0.0
	rotation.y = 0.0
	scale = SCALE_DEFAULT
	position.y = Y_OFFSET_DEFAULT
	if player:
		player.find_child("mesh").scale = PLAYER_SCALE_DEFAULT

func start_slash() -> void:
	if not is_animating and not is_charging:
		is_animating = true
		animation_time = 0.0
		swoosh_sound.play()
		
		current_attack_type = AttackType.SLASH_LEFT_TO_RIGHT if last_attack_was_right else AttackType.SLASH_RIGHT_TO_LEFT
		last_attack_was_right = !last_attack_was_right
		
		setup_slash_animation()

func setup_slash_animation():
	rotation.z = deg_to_rad(SWORD_ANGLE)
	
	match current_attack_type:
		AttackType.SLASH_RIGHT_TO_LEFT:
			start_y_rotation = 0.0
			target_y_rotation = PI
		AttackType.SLASH_LEFT_TO_RIGHT:
			start_y_rotation = PI
			target_y_rotation = 0.0
	
	rotation.y = start_y_rotation
	
	start_scale = scale
	target_scale = SCALE_DEFAULT
	if player:
		player_start_scale = player.find_child("mesh").scale
		player_target_scale = PLAYER_SCALE_ATTACK

func _process(delta: float) -> void:
	if is_charging:
		handle_charge(delta)
	
	if is_animating:
		handle_animation(delta)

func handle_charge(delta: float) -> void:
	charge_time += delta
	var charge_progress = min(charge_time / CHARGE_TIME, 1.0)
	
	if player:
		var mesh_scale = player.find_child("mesh").scale
		mesh_scale.z = lerp(1.0, CHARGE_SCALE_MAX, charge_progress)
		player.find_child("mesh").scale = mesh_scale
	
	if charge_time >= CHARGE_TIME and charge_particles:
		charge_particles.amount = 20.0


func handle_animation(delta: float) -> void:
	cut_stuff()
	animation_time += delta
	
	var duration = SWIPE_DURATION
	if current_attack_type == AttackType.SPIN:
		duration = SPIN_ATTACK_DURATION
	elif current_attack_type == AttackType.AERIAL:
		# Don't end aerial strike animation until landing
		if not player.is_on_floor():
			animation_time = min(animation_time, duration)
	
	if animation_time <= duration:
		var t = animation_time / duration
		t = ease_out_quad(t)
		
		rotation.y = lerp(start_y_rotation, target_y_rotation, t)
		scale = start_scale.lerp(target_scale, t)
		
		if player:
			player.find_child("mesh").scale = player_start_scale.lerp(player_target_scale, t)
	else:
		# Only end aerial strike when on ground
		if current_attack_type == AttackType.AERIAL and not player.is_on_floor():
			return
		handle_animation_end(delta, duration)

func handle_animation_end(delta: float, duration: float):
	var return_progress = (animation_time - duration) / RETURN_DURATION
	rotation.x = deg_to_rad(0.0)
	if return_progress >= 1.0:
		is_animating = false
		rotation.y = 0.0
		rotation.z = 0.0
		scale = SCALE_DEFAULT
		if player:
			player.find_child("mesh").scale = PLAYER_SCALE_DEFAULT
			player.is_attacking = false
	else:
		var t = ease_in_out_quad(return_progress)
		rotation.y = lerp(target_y_rotation, 0.0, t)
		rotation.z = lerp(deg_to_rad(SWORD_ANGLE), 0.0, t)
		scale = target_scale.lerp(SCALE_DEFAULT, t)
		if player:
			player.find_child("mesh").scale = player_target_scale.lerp(PLAYER_SCALE_DEFAULT, t)

func cut_stuff():
	for obj in cutt_edge.get_overlapping_bodies():
		if "take_damage" in obj and obj != player:
			var hit_direction = (obj.global_position - player.global_position).normalized()
			var damage = 1.0
			
			if current_attack_type == AttackType.SPIN:
				damage = 2.0
			elif current_attack_type == AttackType.AERIAL:
				damage = 2.0
			
			obj.take_damage(damage, hit_direction)
		elif "die" in obj and obj != player:
			obj.die()

func start_charge():
	if not is_charging and not is_animating and player.is_on_floor():
		is_charging = true
		charge_time = 0.0
		
		rotation.y = 0.0
		rotation.z = deg_to_rad(SWORD_ANGLE)
		
		if charge_particles:
			charge_particles.emitting = true
		if charge_sound:
			charge_sound.play()

func release_charge():
	if is_charging:
		is_charging = false
		if charge_particles:
			charge_particles.emitting = false
		
		# Only do spin attack if fully charged
		if charge_time >= CHARGE_TIME:
			start_spin_attack()
		else:
			# Not fully charged, do a regular slash
			# Don't reset the direction, let start_slash() handle the alternation
			start_slash()

func start_spin_attack():
	current_attack_type = AttackType.SPIN
	is_animating = true
	animation_time = 0.0
	swoosh_sound.play()
	
	start_y_rotation = rotation.y
	rotation.z = deg_to_rad(SWORD_ANGLE)
	target_y_rotation = start_y_rotation + PI * 2.0
	
	start_scale = scale
	target_scale = SCALE_SPIN
	if player:
		player_start_scale = player.find_child("mesh").scale
		player_target_scale = PLAYER_SCALE_SPIN

func start_aerial_strike():
	if not is_animating and not player.is_on_floor():
		current_attack_type = AttackType.AERIAL
		is_animating = true
		animation_time = 0.0
		swoosh_sound.play()
		
		# Lock rotation for downward thrust
		start_y_rotation = rotation.y
		rotation.z = deg_to_rad(70.0)
		rotation.x = deg_to_rad(90.0)
		target_y_rotation = deg_to_rad(90.0)
		
		# Set downward velocity
		player.start_aerial_strike()
		
func find_root(node=get_tree().root) -> Node:
	if node.name.to_lower() == "level_loader":
		return node
	for child in node.get_children():
		var found = find_root(child)
		if found:
			return found
	return null

func ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

func ease_in_out_quad(t: float) -> float:
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
