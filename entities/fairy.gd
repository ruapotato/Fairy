extends Node3D

@onready var body = $imported_mesh/body
@onready var mesh = $imported_mesh
@onready var audio_player = $imported_mesh/AudioStreamPlayer3D
@onready var wing_left = $imported_mesh/wing2
@onready var wing_right = $imported_mesh/wing1

var rng = RandomNumberGenerator.new()
var player
var level_loader
var target_pos := Vector3.ZERO
var velocity := Vector3.ZERO
var trail_distance = 1.5
var circle_radius = 1.0
var max_speed = 3.0
var acceleration = 15.0
var deceleration = 8.0
var idle_time = 0.0
var circle_time = 0.0
var last_player_pos = Vector3.ZERO
var circle_bob_time = 0.0
var is_speaking = false
var current_insult = 1
var total_insults = 44
var color_shift_time = 0.0

# Wing flapping variables
var wing_flap_speed = 15.0  # Speed of wing flapping
var wing_flap_amplitude = 0.5  # Maximum rotation in radians (about 30 degrees)
var wing_time = 0.0  # Time tracker for wing animation

func _ready() -> void:
	player = get_parent()
	level_loader = player.get_parent()
	remove_child(mesh)
	level_loader.call_deferred("add_child", mesh)
	rng.randomize()
	
	# Setup 3D audio system
	audio_player.finished.connect(_on_audio_finished)
	
	call_deferred("init_message")

func insult():
	is_speaking = true
	var audio_stream = load("res://AI_GEN/insult/" + str(current_insult) + ".wav")
	if current_insult >= total_insults:
		audio_stream = load("res://AI_GEN/just_wow.wav")
		current_insult = 1
	else:
		current_insult += 1
	
	audio_player.stream = audio_stream
	audio_player.play()

func init_message():
	is_speaking = true
	audio_player.stream = load("res://AI_GEN/start_up.wav")
	audio_player.play()
	print("Hi")

func key_spawn_message():
	is_speaking = true
	audio_player.stream = load("res://AI_GEN/100_clover.wav")
	audio_player.play()

func _on_audio_finished():
	is_speaking = false

func hsv_to_rgb(h: float, s: float, v: float) -> Color:
	var hi = int(h * 6.0) % 6
	var f = h * 6.0 - float(hi)
	var p = v * (1.0 - s)
	var q = v * (1.0 - f * s)
	var t = v * (1.0 - (1.0 - f) * s)
	
	match hi:
		0: return Color(v, t, p)
		1: return Color(q, v, p)
		2: return Color(p, v, t)
		3: return Color(p, q, v)
		4: return Color(t, p, v)
		_: return Color(v, p, q)

func update_color(delta: float):
	if not is_speaking:
		return
		
	# Shift color while speaking
	color_shift_time += delta * 0.5
	var hue = fmod(color_shift_time, 1.0)
	var color = hsv_to_rgb(hue, 0.7, 0.9)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_color.a = 0.7
	material.emission_enabled = true
	material.emission = color * 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	
	body.set_surface_override_material(0, material)

func update_wings(delta: float):
	# Update wing animation time
	wing_time += delta * wing_flap_speed
	
	# Calculate wing rotation using sine wave
	var wing_rotation = sin(wing_time) * wing_flap_amplitude
	
	# Apply rotations to wings (opposite directions)
	wing_left.rotation.y = wing_rotation
	wing_right.rotation.y = -wing_rotation  # Negative for opposite direction

func _process(delta: float) -> void:
	update_color(delta)
	update_wings(delta)  # Add wing flapping update
	
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
			# Reset idle time when player moves
			idle_time = 0.0
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
			
	# Apply movement towards target position
	var direction = target_pos - mesh.global_position
	var target_velocity = direction * 5.0
	velocity = velocity.lerp(target_velocity, delta * 10.0)
	
	mesh.global_position += velocity * delta
	
	var look_target = player_pos + Vector3.UP * 0.5
	var current_look = mesh.global_transform.looking_at(look_target, Vector3.UP)
	mesh.transform = mesh.transform.interpolate_with(current_look, delta * 5.0)
