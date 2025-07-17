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
			# Raise control points to sit on top of the ground plane (at y=0.5)
			var pos = Vector3(center.x + x_offset, 0.5, center.z + z_offset)
			
			node_positions.append(pos)
			
			var node_name = "Node%d" % (node_index + 1)
			
			# Position existing nodes or create new ones
			if node_index < capture_nodes.get_child_count():
				var node = capture_nodes.get_child(node_index) as ControlPoint
				node.position = pos
				node.name = node_name
				node.control_point_id = node_name
				node.control_point_name = node_name
			else:
				create_capture_node(pos, node_name)

func create_capture_node(pos: Vector3, node_name: String) -> void:
	var ControlPointScript = load("res://scripts/gameplay/control_point.gd")
	var control_point = ControlPointScript.new()
	
	control_point.name = node_name
	control_point.control_point_name = node_name
	control_point.control_point_id = node_name
	
	capture_nodes.add_child(control_point) # Add to scene tree FIRST
	control_point.global_position = pos # THEN set global position
	

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
