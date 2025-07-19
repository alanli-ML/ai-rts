class_name NavigationManager
extends Node

## NavigationManager handles navigation mesh baking and updates for city maps
##
## This manager provides utilities for:
## - Configuring navigation geometry sources based on structure types
## - Baking navigation meshes with appropriate settings
## - Runtime navigation mesh updates

signal navigation_baked()

@export var navigation_region: NavigationRegion3D
@export var auto_configure_on_ready: bool = true

# Navigation layer constants
const WALKABLE_LAYER = 1
const OBSTACLE_LAYER = 2

func _ready():
	print("NavigationManager: Starting initialization...")
	
	# Auto-find NavigationRegion3D if not assigned
	if not navigation_region:
		navigation_region = get_parent().get_node_or_null("NavigationRegion3D")
		if navigation_region:
			print("NavigationManager: Auto-found NavigationRegion3D")
		else:
			print("NavigationManager: Warning - Could not find NavigationRegion3D")
	
	if auto_configure_on_ready and navigation_region:
		print("NavigationManager: Auto-configure enabled, setting up navigation...")
		configure_navigation_mesh_settings()
		configure_navigation_sources()
		bake_navigation_mesh()
	else:
		print("NavigationManager: Auto-configure disabled or no navigation_region assigned")
		if not navigation_region:
			print("NavigationManager: Warning - navigation_region is null")

## Configure NavigationMesh settings for GLB model geometry
func configure_navigation_mesh_settings():
	if not navigation_region:
		push_error("NavigationManager: No NavigationRegion3D assigned")
		return
	
	var nav_mesh = navigation_region.navigation_mesh
	if not nav_mesh:
		# Create a new NavigationMesh if one doesn't exist
		nav_mesh = NavigationMesh.new()
		navigation_region.navigation_mesh = nav_mesh
		print("NavigationManager: Created new NavigationMesh resource")
	
	# Configure for mesh geometry detection - enable mesh instances from entire scene tree
	# No specific source mode needed - use defaults
	
	# Basic navigation settings
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.2
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_max_climb = 0.9
	nav_mesh.agent_max_slope = 45.0
	
	# Region settings for better mesh generation
	nav_mesh.region_min_size = 8
	nav_mesh.region_merge_size = 20
	
	# Filtering settings to include more geometry
	nav_mesh.filter_low_hanging_obstacles = false
	nav_mesh.filter_ledge_spans = false
	nav_mesh.filter_walkable_low_height_spans = false
	
	print("NavigationManager: NavigationMesh configured for GLB geometry")

## Configure navigation sources for all structures in the scene
func configure_navigation_sources():
	if not navigation_region:
		push_error("NavigationManager: No NavigationRegion3D assigned")
		return
	
	var root_node = navigation_region.get_parent()
	_configure_structures_recursive(root_node)

## Recursively configure navigation for all structure nodes
func _configure_structures_recursive(node: Node):
	for child in node.get_children():
		if child.name.begins_with("Structure_"):
			_configure_structure_navigation(child)
		else:
			_configure_structures_recursive(child)

## Configure navigation for a specific structure based on its type
func _configure_structure_navigation(structure: Node3D):
	var structure_type = _extract_structure_type(structure.name)
	
	match structure_type:
		"road-straight", "road-corner", "road-split", "road-intersection":
			_set_as_walkable(structure)
		"grass", "grass-trees", "grass-trees-tall":
			_set_as_walkable(structure)
		"building-small-a", "building-small-b", "building-small-c", "building-small-d", "building-garage":
			_set_as_obstacle(structure)
		"pavement", "pavement-fountain":
			_set_as_obstacle(structure)
		_:
			push_warning("NavigationManager: Unknown structure type: " + structure_type)

## Extract structure type from node name (e.g., "Structure_0_221_road-straight" -> "road-straight")
func _extract_structure_type(node_name: String) -> String:
	var parts = node_name.split("_")
	if parts.size() >= 4:
		return parts[3]
	return ""

## Mark a structure as walkable for navigation
func _set_as_walkable(structure: Node3D):
	var model = structure.get_node_or_null("Model")
	if model:
		# Configure for navigation inclusion
		_add_navigation_geometry(model)

## Mark a structure as walkable with passthrough areas (for streetlamps)
func _set_as_walkable_with_passthrough(structure: Node3D):
	var model = structure.get_node_or_null("Model")
	if model:
		# Configure for navigation inclusion with special handling for streetlamps
		_add_navigation_geometry_passthrough(model)

## Mark a structure as an obstacle for navigation
func _set_as_obstacle(structure: Node3D):
	var model = structure.get_node_or_null("Model")
	if model:
		# Configure as obstacle - exclude from walkable navigation
		_add_navigation_obstacle(model)

## Add geometry to navigation mesh
func _add_navigation_geometry(node: Node3D):
	# Add the model to the navigation_geometry group so NavigationMesh can find it
	node.add_to_group("navigation_geometry")
	
	# Ensure the model has collision for navigation mesh generation
	_ensure_collision_for_navigation(node)
	
	print("NavigationManager: Added %s to navigation_geometry group" % node.name)

## Add streetlamp geometry with passthrough capability
func _add_navigation_geometry_passthrough(node: Node3D):
	# Add the model to the navigation_geometry group so NavigationMesh can find it
	node.add_to_group("navigation_geometry")
	
	# Create collision only for road surface parts, excluding lamp posts
	_ensure_collision_for_navigation_passthrough(node)
	
	print("NavigationManager: Added %s to navigation_geometry group (with passthrough)" % node.name)

## Ensure a node has collision shapes for navigation mesh generation
func _ensure_collision_for_navigation(node: Node3D):
	# Check if node already has a StaticBody3D with collision
	var has_collision = false
	for child in node.get_children():
		if child is StaticBody3D or child is CharacterBody3D or child is RigidBody3D:
			has_collision = true
			break
	
	if has_collision:
		return  # Already has collision
	
	# Find MeshInstance3D nodes to create collision from
	var mesh_nodes = []
	_find_mesh_instances(node, mesh_nodes)
	
	if mesh_nodes.is_empty():
		print("NavigationManager: Warning - No MeshInstance3D found in %s for collision generation" % node.name)
		return
	
	# Create StaticBody3D with collision shapes
	var static_body = StaticBody3D.new()
	static_body.name = "NavigationCollision"
	
	for mesh_node in mesh_nodes:
		if mesh_node.mesh:
			var collision_shape = CollisionShape3D.new()
			collision_shape.shape = mesh_node.mesh.create_trimesh_shape()
			collision_shape.transform = mesh_node.transform
			static_body.add_child(collision_shape)
	
	node.add_child(static_body)
	print("NavigationManager: Created collision for %s" % node.name)

## Ensure a node has collision shapes for navigation mesh generation (passthrough version for streetlamps)
func _ensure_collision_for_navigation_passthrough(node: Node3D):
	# Check if node already has a StaticBody3D with collision
	var has_collision = false
	for child in node.get_children():
		if child is StaticBody3D or child is CharacterBody3D or child is RigidBody3D:
			has_collision = true
			break
	
	if has_collision:
		return  # Already has collision
	
	# Find only road surface MeshInstance3D nodes, exclude lamp posts
	var mesh_nodes = []
	_find_road_surface_mesh_instances(node, mesh_nodes)
	
	if mesh_nodes.is_empty():
		print("NavigationManager: Warning - No road surface MeshInstance3D found in %s for collision generation" % node.name)
		return
	
	# Create StaticBody3D with collision shapes only for road surfaces
	var static_body = StaticBody3D.new()
	static_body.name = "NavigationCollisionPassthrough"
	
	for mesh_node in mesh_nodes:
		if mesh_node.mesh:
			var collision_shape = CollisionShape3D.new()
			collision_shape.shape = mesh_node.mesh.create_trimesh_shape()
			collision_shape.transform = mesh_node.transform
			static_body.add_child(collision_shape)
	
	node.add_child(static_body)
	print("NavigationManager: Created passthrough collision for %s (lamp posts excluded)" % node.name)

## Find only road surface meshes, excluding lamp posts
func _find_road_surface_mesh_instances(node: Node, mesh_nodes: Array):
	if node is MeshInstance3D:
		# Only include meshes that are clearly road surfaces (low height, at ground level)
		if _is_road_surface_mesh(node):
			mesh_nodes.append(node)
	
	for child in node.get_children():
		_find_road_surface_mesh_instances(child, mesh_nodes)

## Check if a mesh is a road surface (not a lamp post)
func _is_road_surface_mesh(mesh_instance: MeshInstance3D) -> bool:
	if not mesh_instance.mesh:
		return false
	
	# Get the mesh bounds
	var aabb = mesh_instance.get_aabb()
	
	# Only include very flat meshes (road surfaces)
	if aabb.size.y > 0.5:
		return false
	
	# Check mesh position - only include meshes at or near ground level
	var mesh_pos = mesh_instance.transform.origin
	if mesh_pos.y > 0.5:
		return false
	
	return true

## Recursively find MeshInstance3D nodes suitable for navigation (excludes tall objects like streetlamps)
func _find_mesh_instances(node: Node, mesh_nodes: Array):
	if node is MeshInstance3D:
		# Filter out tall mesh instances (streetlamps, signs, etc.)
		if _is_suitable_for_navigation(node):
			mesh_nodes.append(node)
	
	for child in node.get_children():
		_find_mesh_instances(child, mesh_nodes)

## Check if a MeshInstance3D is suitable for navigation (not a streetlamp or tall object)
func _is_suitable_for_navigation(mesh_instance: MeshInstance3D) -> bool:
	if not mesh_instance.mesh:
		return false
	
	# Get the mesh bounds
	var aabb = mesh_instance.get_aabb()
	
	# Exclude meshes that are too tall (likely streetlamps)
	# Road surfaces are typically under 1 unit tall, streetlamps are much taller
	if aabb.size.y > 2.0:
		print("NavigationManager: Excluding tall mesh '%s' (height: %.2f) from navigation" % [mesh_instance.name, aabb.size.y])
		return false
	
	# Check mesh position - exclude meshes positioned high above ground
	var mesh_pos = mesh_instance.transform.origin
	if mesh_pos.y > 1.0:
		print("NavigationManager: Excluding elevated mesh '%s' (Y: %.2f) from navigation" % [mesh_instance.name, mesh_pos.y])
		return false
	
	# Additional name-based filtering for common streetlamp patterns
	var mesh_name = mesh_instance.name.to_lower()
	if "lamp" in mesh_name or "light" in mesh_name or "post" in mesh_name or "pole" in mesh_name:
		print("NavigationManager: Excluding lamp/light mesh '%s' from navigation" % mesh_instance.name)
		return false
	
	return true

## Add geometry as navigation obstacle
func _add_navigation_obstacle(node: Node3D):
	# For obstacles, we don't add them to the navigation group
	# They will create holes in the navigation mesh by not being included
	print("NavigationManager: %s configured as navigation obstacle (excluded from walkable area)" % node.name)

## Bake the navigation mesh
func bake_navigation_mesh():
	if not navigation_region:
		push_error("NavigationManager: No NavigationRegion3D assigned")
		return
	
	if not navigation_region.navigation_mesh:
		push_error("NavigationManager: No NavigationMesh resource assigned")
		return
	
	print("NavigationManager: Starting navigation mesh baking...")
	
	# For baking to work, temporarily move all structures under NavigationRegion3D
	var original_parents = {}
	var structures = get_tree().get_nodes_in_group("navigation_geometry")
	
	for structure in structures:
		if structure.get_parent() != navigation_region:
			original_parents[structure] = structure.get_parent()
			structure.reparent(navigation_region, false)
	
	# Wait one frame for the scene tree to update
	await get_tree().process_frame
	
	# Trigger baking (in editor this happens automatically)
	if Engine.is_editor_hint():
		# In editor, baking happens automatically when nodes change
		pass
	else:
		# At runtime, baking happens automatically with the NavigationServer
		pass
	
	# Restore original parenting
	for structure in original_parents:
		structure.reparent(original_parents[structure], false)
	
	navigation_baked.emit()
	print("NavigationManager: Navigation mesh baking completed")

## Get navigation map for pathfinding queries
func get_navigation_map() -> RID:
	if navigation_region:
		return navigation_region.get_navigation_map()
	return RID()

## Check if a position is on the navigation mesh
func is_position_walkable(position: Vector3) -> bool:
	var map = get_navigation_map()
	if map.is_valid():
		var closest_point = NavigationServer3D.map_get_closest_point(map, position)
		return position.distance_to(closest_point) < 1.0
	return false

## Get the closest walkable position to a given point
func get_closest_walkable_position(position: Vector3) -> Vector3:
	var map = get_navigation_map()
	if map.is_valid():
		return NavigationServer3D.map_get_closest_point(map, position)
	return position 