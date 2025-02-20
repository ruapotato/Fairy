extends Node3D

var target = Vector3(0,0,0)
var blocks = []
var num_blocks = 8
var block_spacing = 0.05
var lerp_speed = 10.0

func _ready():
	for i in range(num_blocks):
		var block = create_block("block_" + str(i))
		add_child(block)
		blocks.append(block)

func _physics_process(delta):
	var start_pos = global_position
	
	for i in range(num_blocks):
		var target_pos = start_pos.lerp(target, float(i) / (num_blocks - 1))
		var block = blocks[i]
		
		# Calculate distance from middle
		var middle = (num_blocks - 1) / 2.0
		var distance_from_middle = abs(i - middle)
		var speed_factor = remap(distance_from_middle, 0, middle, 0.5, 2.0)
		
		# Apply adjusted lerp speed based on distance from middle
		block.global_position = block.global_position.lerp(
			target_pos, 
			delta * lerp_speed * speed_factor
		)

func create_block(name: String) -> Node3D:
	var block = Node3D.new()
	block.name = name
	
	var mesh_instance = MeshInstance3D.new()
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3.ONE * block_spacing
	mesh_instance.mesh = cube_mesh
	block.add_child(mesh_instance)
	
	return block

# Helper function to remap a value from one range to another
func remap(value: float, old_min: float, old_max: float, new_min: float, new_max: float) -> float:
	var old_range = old_max - old_min
	var new_range = new_max - new_min
	return (((value - old_min) * new_range) / old_range) + new_min
