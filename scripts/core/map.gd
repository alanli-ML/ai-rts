# Map.gd
class_name Map
extends Node3D

# Map resource loading using Starter-Kit-City structure definitions

@export var map_name: String = "Test Map"
@export var map_size: Vector2 = Vector2(100, 100)
@export var node_count: int = 9
@export var load_exported_scene: bool = true
@export var exported_scene_path: String = "res://scenes/maps/exported_map.tscn"

@onready var capture_nodes: Node3D = $CaptureNodes
@onready var spawn_points: Node3D = $SpawnPoints

var node_positions: Array[Vector3] = []
var team_spawns: Dictionary = {}

# Map scene loading
var loaded_map_scene: Node3D = null
var map_structures_container: Node3D = null

# Structure type mappings based on Starter-Kit-City structure array order
# These correspond to the structure IDs saved in map.res
const STRUCTURE_MODELS = {
	0: "res://assets/kenney/Starter-Kit-City/models/road-straight.glb",
	1: "res://assets/kenney/Starter-Kit-City/models/road-straight-lightposts.glb",
	2: "res://assets/kenney/Starter-Kit-City/models/road-corner.glb",
	3: "res://assets/kenney/Starter-Kit-City/models/road-split.glb",
	4: "res://assets/kenney/Starter-Kit-City/models/road-intersection.glb",
	5: "res://assets/kenney/Starter-Kit-City/models/pavement.glb",
	6: "res://assets/kenney/Starter-Kit-City/models/pavement-fountain.glb",
	7: "res://assets/kenney/Starter-Kit-City/models/building-small-a.glb",
	8: "res://assets/kenney/Starter-Kit-City/models/building-small-b.glb",
	9: "res://assets/kenney/Starter-Kit-City/models/building-small-c.glb",
	10: "res://assets/kenney/Starter-Kit-City/models/building-small-d.glb",
	11: "res://assets/kenney/Starter-Kit-City/models/building-garage.glb",
	12: "res://assets/kenney/Starter-Kit-City/models/grass.glb",
	13: "res://assets/kenney/Starter-Kit-City/models/grass-trees.glb",
	14: "res://assets/kenney/Starter-Kit-City/models/grass-trees-tall.glb"
}

# Structure type categories for gameplay mechanics
const STRUCTURE_TYPES = {
	"roads": [0, 1, 2, 3, 4],           # Road pieces
	"pavement": [5, 6],                  # Pavement/plaza areas
	"buildings": [7, 8, 9, 10, 11],     # Buildings that block movement
	"landscaping": [12, 13, 14]         # Grass/trees (decorative)
}

func _ready() -> void:
	print("Map: Loading map: %s" % map_name)
	
	# Create structures container
	map_structures_container = Node3D.new()
	map_structures_container.name = "MapStructures"
	add_child(map_structures_container)
	
	if load_exported_scene:
		load_exported_scene_data()
	else:
		setup_capture_nodes()
	
	setup_spawn_points()

func load_exported_scene_data() -> void:
	"""Load and instantiate the exported city map scene"""
	print("Map: Loading exported scene from: %s" % exported_scene_path)
	
	if not ResourceLoader.exists(exported_scene_path):
		print("Map: Warning - exported scene not found, falling back to procedural generation")
		setup_capture_nodes()
		return
	
	var scene_resource = ResourceLoader.load(exported_scene_path)
	if not scene_resource:
		print("Map: Error - failed to load exported scene, falling back to procedural generation")
		setup_capture_nodes()
		return
	
	# Instantiate the scene
	loaded_map_scene = scene_resource.instantiate()
	if not loaded_map_scene:
		print("Map: Error - failed to instantiate exported scene, falling back to procedural generation")
		setup_capture_nodes()
		return
	
	# Add the map scene to our structures container
	map_structures_container.add_child(loaded_map_scene)
	
	# Scale up the entire map by 7x
	loaded_map_scene.scale = Vector3(7.0, 7.0, 7.0)
	
	# Adjust position: raise up slightly (Y+) and move to the left (X-)
	loaded_map_scene.position = Vector3(-20.0, 0, 0.0)
	
	print("Map: Successfully loaded exported city map scene with %d structure nodes (scaled 7x, repositioned)" % loaded_map_scene.get_child_count())
	
	# Load actual 3D models for each structure node
	load_structure_models()
	
	# Set up collision and navigation for all structures
	setup_scene_collision_and_navigation()
	
	# CRITICAL: Rebake navigation mesh after adding all NavigationObstacle3D nodes
	call_deferred("_rebake_navigation_mesh")
	
	# Create capture nodes positioned around the loaded structures
	setup_capture_nodes_for_loaded_map()

func load_structure_models() -> void:
	"""Load actual 3D models for each structure node based on metadata"""
	if not loaded_map_scene:
		return
	
	print("Map: Loading 3D models for structures...")
	var models_loaded = 0
	
	# Iterate through all structure nodes in the exported scene
	for child in loaded_map_scene.get_children():
		if child.name.begins_with("Structure_") and child.has_meta("structure_id"):
			var structure_id = child.get_meta("structure_id")
			var model_path = get_model_path_for_structure_id(structure_id)
			
			if model_path and ResourceLoader.exists(model_path):
				# Load the model resource
				var model_resource = ResourceLoader.load(model_path)
				if model_resource:
					# Instantiate the model
					var model_instance = model_resource.instantiate()
					if model_instance:
						# Add the model as a child of the structure node
						child.add_child(model_instance)
						
						# Add collision and navigation for buildings only
						setup_structure_collision(child, structure_id)
						setup_structure_navigation_obstacle(child, structure_id)
						
						models_loaded += 1
					else:
						print("Map: Warning - failed to instantiate model: %s" % model_path)
				else:
					print("Map: Warning - failed to load model: %s" % model_path)
			else:
				print("Map: Warning - model not found for structure_id %d: %s" % [structure_id, model_path])
	
	print("Map: Successfully loaded %d 3D models" % models_loaded)

func get_model_path_for_structure_id(structure_id: int) -> String:
	"""Get the correct model path for a structure ID"""
	# Map structure IDs to actual Kenney asset paths
	match structure_id:
		0: return "res://assets/kenney/Starter-Kit-City/models/road-straight.glb"
		1: return "res://assets/kenney/Starter-Kit-City/models/road-straight-lightposts.glb"
		2: return "res://assets/kenney/Starter-Kit-City/models/road-corner.glb"
		3: return "res://assets/kenney/Starter-Kit-City/models/road-split.glb"
		4: return "res://assets/kenney/Starter-Kit-City/models/road-intersection.glb"
		5: return "res://assets/kenney/Starter-Kit-City/models/pavement.glb"
		6: return "res://assets/kenney/Starter-Kit-City/models/pavement-fountain.glb"
		7: return "res://assets/kenney/Starter-Kit-City/models/building-small-a.glb"
		8: return "res://assets/kenney/Starter-Kit-City/models/building-small-b.glb"
		9: return "res://assets/kenney/Starter-Kit-City/models/building-small-c.glb"
		10: return "res://assets/kenney/Starter-Kit-City/models/building-small-d.glb"
		11: return "res://assets/kenney/Starter-Kit-City/models/building-garage.glb"
		12: return "res://assets/kenney/Starter-Kit-City/models/grass.glb"
		13: return "res://assets/kenney/Starter-Kit-City/models/grass-trees.glb"
		14: return "res://assets/kenney/Starter-Kit-City/models/grass-trees-tall.glb"
		_: return ""

func setup_scene_collision_and_navigation() -> void:
	"""Set up collision and navigation for all structures in the loaded scene"""
	if not loaded_map_scene:
		return
	
	# Iterate through all structure nodes in the exported scene
	for child in loaded_map_scene.get_children():
		if child.name.begins_with("Structure_"):
			# Extract structure type from the name (e.g., "Structure_7_71" -> structure_id = 7)
			var name_parts = child.name.split("_")
			if name_parts.size() >= 2:
				var structure_id = int(name_parts[1])
				setup_structure_collision(child, structure_id)
				setup_structure_navigation_obstacle(child, structure_id)

func instantiate_structure(structure_data) -> void:
	"""Instantiate a single structure from the map data"""
	var structure_id = structure_data.structure
	var position_2d = structure_data.position
	var orientation = structure_data.orientation
	
	# Get model path for this structure type
	var model_path = STRUCTURE_MODELS.get(structure_id)
	if not model_path:
		print("Map: Warning - no model defined for structure ID %d" % structure_id)
		return
	
	# Check if model exists
	if not ResourceLoader.exists(model_path):
		print("Map: Warning - model not found: %s" % model_path)
		return
	
	# Load and instantiate the model
	var model_scene = ResourceLoader.load(model_path)
	if not model_scene:
		print("Map: Error - failed to load model: %s" % model_path)
		return
	
	var structure_instance = model_scene.instantiate()
	if not structure_instance:
		print("Map: Error - failed to instantiate model: %s" % model_path)
		return
	
	# Position the structure (convert 2D grid to 3D world coordinates)
	var world_position = Vector3(position_2d.x, 0, position_2d.y)
	structure_instance.global_position = world_position
	
	# Apply orientation (convert Godot's orthogonal index to rotation)
	var rotation_y = orientation * 90.0  # Each orientation step is 90 degrees
	structure_instance.rotation_degrees.y = rotation_y
	
	# Add collision and navigation obstacles for buildings (make them non-traversable)
	setup_structure_collision(structure_instance, structure_id)
	setup_structure_navigation_obstacle(structure_instance, structure_id)
	
	# Name and add to scene
	structure_instance.name = "Structure_%d_%d_%d" % [structure_id, position_2d.x, position_2d.y]
	map_structures_container.add_child(structure_instance)
	
	print("Map: Placed structure %d at (%d, %d) with rotation %d°" % [structure_id, position_2d.x, position_2d.y, rotation_y])

func setup_structure_collision(structure: Node3D, structure_id: int) -> void:
	"""Add collision to structures to make them non-traversable"""
	# Only add collision to buildings, not roads/pavement/landscaping
	if structure_id in STRUCTURE_TYPES["roads"] or \
	   structure_id in STRUCTURE_TYPES["pavement"] or \
	   structure_id in STRUCTURE_TYPES["landscaping"]:
		print("Map: Skipping collision for non-building structure ID %d" % structure_id)
		return

	# Only buildings need collision
	if not structure_id in STRUCTURE_TYPES["buildings"]:
		print("Map: Warning - structure ID %d not found in buildings list" % structure_id)
		return
	
	print("Map: Adding collision for building structure ID %d" % structure_id)
	
	# Find the actual 3D model in the structure to get its bounds
	var model_node: Node3D = null
	for child in structure.get_children():
		if child is Node3D and child.name != "Collision" and child.name != "NavigationObstacle":
			model_node = child
			break
	
	if not model_node:
		print("Map: Warning - no 3D model found in structure for collision")
		return
	
	# Get the actual bounding box of the model
	var aabb = get_node_aabb(model_node)
	if aabb.size == Vector3.ZERO:
		print("Map: Warning - could not get valid AABB for structure %d" % structure_id)
		return
	
	# Use original model dimensions since the structure nodes are already scaled
	var collision_size = aabb.size * 1.1  # 10% padding for safety
	var collision_center = aabb.get_center()
	
	print("Map: Structure %d collision setup: size=%s, center=%s" % [structure_id, collision_size, collision_center])
	
	# Create a StaticBody3D for collision
	var static_body = StaticBody3D.new()
	static_body.name = "Collision"
	
	# Create a collision shape using the scaled model bounds
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	
	# Use the actual model size (with padding already applied)
	box_shape.size = collision_size
	
	collision_shape.shape = box_shape
	collision_shape.position = collision_center  # Position at the model's center
	
	# Set collision layer to 2 (buildings) - won't collide with units on layer 1
	static_body.set_collision_layer_value(1, false)  # Not on unit layer
	static_body.set_collision_layer_value(2, true)   # On building layer
	
	static_body.add_child(collision_shape)
	
	# Add debug visualization
	add_collision_debug_visualization(static_body, collision_size, collision_center)
	
	structure.add_child(static_body)

func add_collision_debug_visualization(static_body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	"""Add a visual debug representation of the collision box"""
	# Create a MeshInstance3D for visualization
	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "CollisionDebugVisualization"
	
	# Create a wireframe box mesh
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	
	# Create a material to make it visible
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.RED
	material.flags_transparent = true
	material.albedo_color.a = 0.3  # Semi-transparent
	material.flags_unshaded = true
	material.wireframe = true
	
	debug_mesh.mesh = box_mesh
	debug_mesh.material_override = material
	debug_mesh.position = center
	
	# Add to the static body
	static_body.add_child(debug_mesh)
	
	print("Map: Added debug visualization for collision box at %s with size %s" % [center, size])

func add_navigation_debug_visualization(nav_obstacle: NavigationObstacle3D, radius: float, height: float, center: Vector3) -> void:
	"""Add a visual debug representation of the navigation obstacle"""
	# Create a MeshInstance3D for visualization
	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "NavigationDebugVisualization"
	
	# Create a cylinder mesh to represent the circular navigation obstacle
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = radius
	cylinder_mesh.bottom_radius = radius
	cylinder_mesh.height = height
	
	# Create a material to make it visible
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.BLUE
	material.flags_transparent = true
	material.albedo_color.a = 0.2  # Semi-transparent
	material.flags_unshaded = true
	material.wireframe = true
	
	debug_mesh.mesh = cylinder_mesh
	debug_mesh.material_override = material
	# Position cylinder so its base matches the NavigationObstacle3D position (center + half height)
	debug_mesh.position = Vector3(center.x, center.y + (height / 2.0), center.z)
	
	# Add to the navigation obstacle
	nav_obstacle.add_child(debug_mesh)
	
	print("Map: Added debug visualization for navigation obstacle at %s with radius %.1f, height %.1f" % [center, radius, height])

func get_node_aabb(node: Node3D) -> AABB:
	"""Get the axis-aligned bounding box of a 3D node and all its children"""
	var combined_aabb = AABB()
	var has_aabb = false
	
	# Check if this node is a MeshInstance3D
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh:
			var mesh_aabb = mesh_instance.get_aabb()
			# Transform the AABB to global space
			mesh_aabb = mesh_instance.transform * mesh_aabb
			if not has_aabb:
				combined_aabb = mesh_aabb
				has_aabb = true
			else:
				combined_aabb = combined_aabb.merge(mesh_aabb)
	
	# Recursively check all children
	for child in node.get_children():
		if child is Node3D:
			var child_aabb = get_node_aabb(child)
			if child_aabb.size != Vector3.ZERO:
				# Transform to parent space
				child_aabb = child.transform * child_aabb
				if not has_aabb:
					combined_aabb = child_aabb
					has_aabb = true
				else:
					combined_aabb = combined_aabb.merge(child_aabb)
	
	return combined_aabb

func setup_structure_navigation_obstacle(structure: Node3D, structure_id: int) -> void:
	"""Add navigation obstacle to structures to prevent pathfinding through them"""
	# Only add navigation obstacles to buildings, not roads/pavement/landscaping
	if structure_id in STRUCTURE_TYPES["roads"] or \
	   structure_id in STRUCTURE_TYPES["pavement"] or \
	   structure_id in STRUCTURE_TYPES["landscaping"]:
		print("Map: Skipping navigation obstacle for non-building structure ID %d" % structure_id)
		return

	# Only buildings need navigation obstacles
	if not structure_id in STRUCTURE_TYPES["buildings"]:
		print("Map: Warning - structure ID %d not found in buildings list for navigation" % structure_id)
		return
	
	print("Map: Adding navigation obstacle for building structure ID %d" % structure_id)
	
	# Find the actual 3D model in the structure to get its bounds
	var model_node: Node3D = null
	for child in structure.get_children():
		if child is Node3D and child.name != "Collision" and child.name != "NavigationObstacle":
			model_node = child
			break
	
	if not model_node:
		print("Map: Warning - no 3D model found in structure for navigation obstacle")
		return
	
	# Get the actual bounding box of the model
	var aabb = get_node_aabb(model_node)
	if aabb.size == Vector3.ZERO:
		print("Map: Warning - could not get valid AABB for navigation obstacle %d" % structure_id)
		return
	
	# Use original model dimensions since the structure nodes are already scaled
	var nav_size = aabb.size
	var nav_center = aabb.get_center()
	
	# Create a NavigationObstacle3D
	var nav_obstacle = NavigationObstacle3D.new()
	nav_obstacle.name = "NavigationObstacle"
	
	# Use original model dimensions for navigation obstacle
	# For NavigationObstacle3D, we need radius and height
	# Use the larger of X or Z dimensions for radius, and Y for height
	var radius = max(nav_size.x, nav_size.z) / 2.0
	nav_obstacle.radius = radius * 1.0  # 10% padding like collision
	nav_obstacle.height = nav_size.y
	
	# Position the obstacle at the base of the model (NavigationObstacle3D positions from bottom)
	nav_obstacle.position = Vector3(nav_center.x, nav_center.y - (nav_size.y / 2.0), nav_center.z)
	
	# Note: NavigationObstacle3D doesn't support navigation layers in Godot 4.4
	# The obstacle will work on the default navigation layer with the navigation mesh
	
	print("Map: Navigation obstacle for structure %d: radius=%.1f, height=%.1f" % [structure_id, nav_obstacle.radius, nav_obstacle.height])
	
	# Enable the obstacle
	nav_obstacle.avoidance_enabled = true
	
	# Add debug visualization for navigation obstacle
	var nav_obstacle_position = Vector3(nav_center.x, nav_center.y - (nav_size.y / 2.0), nav_center.z)
	add_navigation_debug_visualization(nav_obstacle, nav_obstacle.radius, nav_obstacle.height, nav_obstacle_position)
	
	structure.add_child(nav_obstacle)

func setup_capture_nodes_for_loaded_map() -> void:
	"""Setup capture nodes positioned strategically around loaded map structures"""
	print("Map: Setting up capture nodes for loaded map")
	
	# For loaded maps, create fewer strategic capture points
	# Position them at key intersections or open areas
	var strategic_positions = [
		Vector3(-20, 0.5, -20),  # Corner positions
		Vector3(20, 0.5, -20),
		Vector3(-20, 0.5, 20),
		Vector3(20, 0.5, 20),
		Vector3(0, 0.5, 0),      # Center
		Vector3(-20, 0.5, 0),    # Sides
		Vector3(20, 0.5, 0),
		Vector3(0, 0.5, -20),
		Vector3(0, 0.5, 20)
	]
	
	for i in range(min(strategic_positions.size(), node_count)):
		var pos = strategic_positions[i]
		node_positions.append(pos)
		
		var node_name = "Node%d" % (i + 1)
		
		# Position existing nodes or create new ones
		if i < capture_nodes.get_child_count():
			var node = capture_nodes.get_child(i) as ControlPoint
			if node:
				node.position = pos
				node.name = node_name
				node.control_point_id = node_name
				node.control_point_name = node_name
		else:
			create_capture_node(pos, node_name)

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

func _rebake_navigation_mesh() -> void:
	"""Rebake the navigation mesh to include NavigationObstacle3D nodes"""
	print("Map: Rebaking navigation mesh to include building obstacles...")
	
	# Find NavigationRegion3D in the scene
	var nav_region = get_tree().get_first_node_in_group("navigation_regions")
	if not nav_region:
		# Try to find it by name if not in group
		nav_region = get_node("../Environment/NavigationRegion3D")
		if nav_region:
			# Add it to the group for future reference
			nav_region.add_to_group("navigation_regions")
			print("Map: Found NavigationRegion3D and added to navigation_regions group")
	
	if nav_region and nav_region is NavigationRegion3D:
		# Trigger navigation mesh baking
		nav_region.bake_navigation_mesh()
		print("Map: Navigation mesh rebaked successfully")
	else:
		print("Map: Warning - No NavigationRegion3D found, navigation obstacles may not work") 
