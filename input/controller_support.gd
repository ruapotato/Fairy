extends Node

# Adjust these sensitivity values to match your preferences
const CONTROLLER_SENSITIVITY = 10.0
const CONTROLLER_DEADZONE = 0.05

# References to player nodes
var level_loader
var player
var chicken_spirit

# Track the previous frame's stick positions to calculate relative movement
var prev_right_stick_x = 0.0
var prev_right_stick_y = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Optional: Capture the mouse for camera movement
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Find the necessary nodes
	level_loader = find_root()
	if level_loader:
		player = level_loader.find_child("player")
		if player:
			chicken_spirit = player.find_child("chicken_spirit")

func find_root(node=get_tree().root) -> Node:
	if node.name.to_lower() == "level_loader":
		return node
	for child in node.get_children():
		var found = find_root(child)
		if found:
			return found
	return null
	
func _process(delta):
	# Safety check - make sure we have player reference
	if not player:
		return
		
	# Get current stick positions
	var right_stick_x = Input.get_axis("camera_look_left", "camera_look_right")
	var right_stick_y = Input.get_axis("camera_look_up", "camera_look_down")
	
	# Apply deadzone
	right_stick_x = 0.0 if abs(right_stick_x) < CONTROLLER_DEADZONE else right_stick_x
	right_stick_y = 0.0 if abs(right_stick_y) < CONTROLLER_DEADZONE else right_stick_y
	
	# Only generate events if there's meaningful stick movement
	if abs(right_stick_x) > 0 or abs(right_stick_y) > 0:
		# Convert controller input to simulated mouse motion
		var relative_x = right_stick_x * CONTROLLER_SENSITIVITY
		
		# Apply different Y-axis handling depending on if player is possessing
		var relative_y = 0.0
		if player.is_possessing:
			# Player is possessing (fairy/flying mode) - inverted Y-axis
			relative_y = -right_stick_y * CONTROLLER_SENSITIVITY
		else:
			# Normal player mode - standard Y-axis
			relative_y = right_stick_y * CONTROLLER_SENSITIVITY
		
		# Create a synthetic mouse motion event
		var mouse_event = InputEventMouseMotion.new()
		mouse_event.relative = Vector2(relative_x, relative_y)
		mouse_event.velocity = Vector2(relative_x, relative_y) / delta
		
		# Send the event to the input system
		Input.parse_input_event(mouse_event)
	
	# Store current values for next frame
	prev_right_stick_x = right_stick_x
	prev_right_stick_y = right_stick_y
