# Map.gd
class_name Map
extends Node3D

@export var map_name: String = "Test Map"
@export var map_size: Vector2 = Vector2(100, 100)
@export var node_count: int = 9

@onready var capture_nodes: Node3D = $CaptureNodes
@onready var spawn_points: Node3D = $SpawnPoints

var node_positions: Array[Vector3] = []
var team_spawns: Dictionary = {}

func _ready() -> void:
	print("Map: Loading map: %s" % map_name)
	setup_capture_nodes()
	setup_spawn_points()

func setup_capture_nodes() -> void:
	# Create a 3x3 grid of capture nodes
	var spacing = map_size.x / 4  # Divide map into quarters
	var center = Vector3.ZERO # Center the nodes on the ground plane at origin
	
	for i in range(3):
		for j in range(3):
			var node_index = i * 3 + j
			var x_offset = (i - 1) * spacing
			var z_offset = (j - 1) * spacing
			var pos = Vector3(center.x + x_offset, 0, center.z + z_offset)
			
			node_positions.append(pos)
			
			# Position existing nodes or create new ones
			if node_index < capture_nodes.get_child_count():
				var node = capture_nodes.get_child(node_index)
				node.position = pos
			else:
				create_capture_node(pos, "Node%d" % (node_index + 1))

func create_capture_node(pos: Vector3, node_name: String) -> void:
	var ControlPointScript = load("res://scripts/gameplay/control_point.gd")
	var control_point = ControlPointScript.new()
	
	control_point.name = node_name
	control_point.control_point_name = node_name
	control_point.global_position = pos
	
	capture_nodes.add_child(control_point)

func setup_spawn_points() -> void:
	for child in spawn_points.get_children():
		if child is Marker3D:
			var team_name = child.name.replace("Spawn", "")
			team_spawns[team_name] = child.position
			print("Map: Registered spawn point for %s at %s" % [team_name, child.position])

func get_spawn_position(team: String) -> Vector3:
	return team_spawns.get(team, Vector3.ZERO)

func get_random_node_position() -> Vector3:
	if node_positions.is_empty():
		return Vector3.ZERO
	return node_positions.pick_random() 
