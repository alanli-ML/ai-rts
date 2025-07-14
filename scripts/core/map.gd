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
	Logger.info("Map", "Loading map: %s" % map_name)
	setup_capture_nodes()
	setup_spawn_points()

func setup_capture_nodes() -> void:
	# Create a 3x3 grid of capture nodes
	var spacing = map_size.x / 4  # Divide map into quarters
	var center = Vector3(map_size.x / 2, 0, map_size.y / 2)
	
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
	var area = Area3D.new()
	area.name = node_name
	area.position = pos
	
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = 5.0
	shape.height = 0.5
	collision.shape = shape
	area.add_child(collision)
	
	# Visual representation
	var mesh_instance = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.radial_segments = 16
	cylinder_mesh.rings = 1
	cylinder_mesh.top_radius = 5.0
	cylinder_mesh.bottom_radius = 5.0
	cylinder_mesh.height = 0.5
	mesh_instance.mesh = cylinder_mesh
	area.add_child(mesh_instance)
	
	capture_nodes.add_child(area)

func setup_spawn_points() -> void:
	for child in spawn_points.get_children():
		if child is Marker3D:
			var team_name = child.name.replace("Spawn", "")
			team_spawns[team_name] = child.position
			Logger.debug("Map", "Registered spawn point for %s at %s" % [team_name, child.position])

func get_spawn_position(team: String) -> Vector3:
	return team_spawns.get(team, Vector3.ZERO)

func get_random_node_position() -> Vector3:
	if node_positions.is_empty():
		return Vector3.ZERO
	return node_positions.pick_random() 
