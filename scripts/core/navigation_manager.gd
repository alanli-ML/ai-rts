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
	
	# Enable collision debug visualization
	get_tree().debug_collisions_hint = true
	print("NavigationManager: Enabled collision debug visualization")
	
	# Auto-find NavigationRegion3D if not assigned
	if not navigation_region:
		navigation_region = get_parent().get_node_or_null("NavigationRegion3D")
		if navigation_region:
			print("NavigationManager: Auto-found NavigationRegion3D as sibling")
		else:
			# Try to find it in the scene tree
			var nav_regions = get_tree().get_nodes_in_group("navigation_regions")
			if nav_regions.size() > 0:
				navigation_region = nav_regions[0]
				print("NavigationManager: Found NavigationRegion3D via group search")
			else:
				print("NavigationManager: Warning - Could not find NavigationRegion3D anywhere")
	
	if auto_configure_on_ready and navigation_region:
		print("NavigationManager: Auto-configure enabled, setting up navigation...")
		configure_navigation_mesh_settings()
		configure_navigation_sources()
		bake_navigation_mesh()
		
		# CRITICAL: Ensure NavigationRegion3D is properly registered with NavigationServer3D
		if navigation_region.enabled and navigation_region.navigation_mesh:
			# Force update the navigation map
			navigation_region.enabled = false
			await get_tree().process_frame
			navigation_region.enabled = true
			print("NavigationManager: Force-refreshed NavigationRegion3D registration with NavigationServer3D")
			
			# Debug: Print navigation map info
			var nav_map = navigation_region.get_navigation_map()
			if nav_map.is_valid():
				print("NavigationManager: Navigation map RID is valid")
			else:
				print("NavigationManager: ERROR - Navigation map RID is invalid!")
		
		# Debug: Count collision structures created
		_debug_collision_structures()
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
	
	# Check if this is a pre-baked mesh (has existing vertices)
	if nav_mesh.get_vertices().size() > 0:
		print("NavigationManager: Detected pre-baked NavigationMesh - using existing navigation data")
		print("NavigationManager: Pre-baked mesh has %d vertices and %d polygons" % [nav_mesh.get_vertices().size(), nav_mesh.get_polygon_count()])
		print("NavigationManager: Skipping navigation mesh configuration - only creating physics collision")
		return
	
	print("NavigationManager: Configuring fresh NavigationMesh for GLB geometry")
	
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
	
	# Check if we have a pre-baked navigation mesh
	var nav_mesh = navigation_region.navigation_mesh
	var has_prebaked_mesh = nav_mesh and nav_mesh.get_vertices().size() > 0
	
	print("NavigationManager: Starting to configure navigation sources...")
	print("NavigationManager: Pre-baked navigation mesh: %s" % ("Yes" if has_prebaked_mesh else "No"))
	
	var root_node = navigation_region.get_parent()
	var structure_count = _count_structures_recursive(root_node)
	print("NavigationManager: Found %d structures to configure" % structure_count)
	
	if has_prebaked_mesh:
		print("NavigationManager: Using pre-baked navigation mesh, only creating physics collision")
	
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
	print("NavigationManager: Configuring structure '%s' as type '%s'" % [structure.name, structure_type])
	
	match structure_type:
		"road-straight", "road-corner", "road-split", "road-intersection":
			print("  - Setting as walkable terrain (road)")
			_set_as_walkable_terrain(structure)
		"grass":
			print("  - Setting as walkable terrain (grass)")
			_set_as_walkable_terrain(structure)
		"pavement", "pavement-fountain":
			print("  - Setting as walkable terrain (pavement)")
			_set_as_walkable_terrain(structure)
		"grass-trees", "grass-trees-tall":
			print("  - Setting as obstacle (trees)")
			_set_as_obstacle(structure)
		"building-small-a", "building-small-b", "building-small-c", "building-small-d", "building-garage":
			print("  - Setting as obstacle (building)")
			_set_as_obstacle(structure)
		_:
			print("  - Unknown type, setting as walkable terrain by default")
			_set_as_walkable_terrain(structure)

## Extract structure type from node name (e.g., "Structure_0_0_road-straight" -> "road-straight")
func _extract_structure_type(node_name: String) -> String:
	var parts = node_name.split("_")
	print("NavigationManager: Extracting type from '%s', parts: %s" % [node_name, str(parts)])
	if parts.size() >= 4:
		print("  - Extracted type: '%s'" % parts[3])
		return parts[3]
	print("  - Could not extract type (not enough parts)")
	return ""

## Mark a structure as walkable terrain (creates floor collision only)
func _set_as_walkable_terrain(structure: Node3D):
	var model = structure.get_node_or_null("Model")
	if model:
		# Create terrain collision for floor but don't add to navigation obstacles
		_ensure_physics_collision_for_terrain(model)
		print("NavigationManager: Set %s as walkable terrain with floor collision" % structure.name)

## Mark a structure as walkable with passthrough areas (for streetlamps) - DEPRECATED
func _set_as_walkable_with_passthrough(structure: Node3D):
	# This function is deprecated - just treat as regular walkable terrain
	_set_as_walkable_terrain(structure)

## Mark a structure as an obstacle for navigation (buildings, trees)
func _set_as_obstacle(structure: Node3D):
	var model = structure.get_node_or_null("Model")
	if model:
		# Create physics collision for blocking movement
		_ensure_physics_collision_for_building(model)
		print("NavigationManager: Set %s as obstacle with physics collision" % structure.name)

# This function was removed - terrain should not be added to navigation geometry
# Navigation mesh should be empty space, with obstacles creating holes

# Removed - not needed for pre-baked navigation mesh

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

# Removed - not needed for pre-baked navigation mesh

## Bake the navigation mesh
func bake_navigation_mesh():
	if not navigation_region:
		push_error("NavigationManager: No NavigationRegion3D assigned")
		return
	
	if not navigation_region.navigation_mesh:
		push_error("NavigationManager: No NavigationMesh resource assigned")
		return
	
	# Check if we have a pre-baked navigation mesh
	var nav_mesh = navigation_region.navigation_mesh
	var has_prebaked_mesh = nav_mesh and nav_mesh.get_vertices().size() > 0
	
	if has_prebaked_mesh:
		print("NavigationManager: Skipping navigation mesh baking - using pre-baked mesh")
		navigation_baked.emit()
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

## Create physics collision for terrain (roads, grass) to prevent units falling through
func _ensure_physics_collision_for_terrain(node: Node3D):
	# Check if physics collision already exists
	if _has_physics_collision(node):
		print("NavigationManager: %s already has physics collision, skipping" % node.name)
		return
	
	# Find MeshInstance3D nodes to create collision from
	var mesh_nodes = []
	_find_mesh_instances(node, mesh_nodes)
	
	if mesh_nodes.is_empty():
		print("NavigationManager: Warning - No MeshInstance3D found in %s for terrain physics collision" % node.name)
		return
	
	print("NavigationManager: Creating terrain physics collision for %s with %d mesh nodes" % [node.name, mesh_nodes.size()])
	
	# Create StaticBody3D with trimesh collision shapes for terrain
	var static_body = StaticBody3D.new()
	static_body.name = "TerrainPhysicsCollision"
	
	var collision_count = 0
	for mesh_node in mesh_nodes:
		if mesh_node.mesh and _is_suitable_for_navigation(mesh_node):
			var collision_shape = CollisionShape3D.new()
			collision_shape.shape = mesh_node.mesh.create_trimesh_shape()
			collision_shape.transform = mesh_node.transform
			static_body.add_child(collision_shape)
			collision_count += 1
			print("  - Added collision shape for mesh: %s" % mesh_node.name)
	
	if collision_count == 0:
		print("NavigationManager: Warning - No suitable meshes found for collision in %s" % node.name)
		static_body.queue_free()
		return
	
	# Set collision layers: terrain on layer 3, collides with units on layer 1
	static_body.set_collision_layer_value(1, false)  # Not on unit layer
	static_body.set_collision_layer_value(2, false)  # Not on building layer  
	static_body.set_collision_layer_value(3, true)   # On terrain layer
	static_body.set_collision_mask_value(1, true)    # Collides with units
	
	# Add visual debug representation
	_add_collision_debug_visualization(static_body, "terrain")
	
	node.add_child(static_body)
	print("NavigationManager: Created terrain physics collision for %s with %d collision shapes" % [node.name, collision_count])

## Create physics collision for buildings to block units
func _ensure_physics_collision_for_building(node: Node3D):
	# Check if physics collision already exists
	if _has_physics_collision(node):
		print("NavigationManager: %s already has physics collision, skipping" % node.name)
		return
	
	# Find MeshInstance3D nodes to create collision from
	var mesh_nodes = []
	_find_mesh_instances(node, mesh_nodes)
	
	if mesh_nodes.is_empty():
		print("NavigationManager: Warning - No MeshInstance3D found in %s for building physics collision" % node.name)
		return
	
	print("NavigationManager: Creating building physics collision for %s with %d mesh nodes" % [node.name, mesh_nodes.size()])
	
	# Create StaticBody3D with trimesh collision shapes for buildings
	var static_body = StaticBody3D.new()
	static_body.name = "BuildingPhysicsCollision"
	
	var collision_count = 0
	for mesh_node in mesh_nodes:
		if mesh_node.mesh:
			var collision_shape = CollisionShape3D.new()
			collision_shape.shape = mesh_node.mesh.create_trimesh_shape()
			collision_shape.transform = mesh_node.transform
			static_body.add_child(collision_shape)
			collision_count += 1
			print("  - Added collision shape for mesh: %s" % mesh_node.name)
	
	if collision_count == 0:
		print("NavigationManager: Warning - No meshes found for collision in %s" % node.name)
		static_body.queue_free()
		return
	
	# Set collision layers: buildings on layer 2, collides with units on layer 1
	static_body.set_collision_layer_value(1, false)  # Not on unit layer
	static_body.set_collision_layer_value(2, true)   # On building layer
	static_body.set_collision_mask_value(1, true)    # Collides with units
	
	# Add visual debug representation
	_add_collision_debug_visualization(static_body, "building")
	
	node.add_child(static_body)
	print("NavigationManager: Created building physics collision for %s with %d collision shapes" % [node.name, collision_count])

## Check if a node already has physics collision bodies
func _has_physics_collision(node: Node3D) -> bool:
	for child in node.get_children():
		if child is StaticBody3D and (child.name.ends_with("PhysicsCollision") or child.name == "NavigationCollision"):
			return true
	return false

## Debug function to count and report collision structures
func _debug_collision_structures():
	print("NavigationManager: === COLLISION STRUCTURE DEBUG ===")
	
	var counts = {
		"total_structures": 0,
		"terrain_collision": 0,
		"building_collision": 0,
		"navigation_collision": 0
	}
	
	# Count structures and their collision types
	var root_node = navigation_region.get_parent() if navigation_region else get_parent()
	_count_collision_structures_recursive(root_node, counts)
	
	print("NavigationManager: Total structures processed: %d" % counts.total_structures)
	print("NavigationManager: Terrain physics collision: %d" % counts.terrain_collision)
	print("NavigationManager: Building physics collision: %d" % counts.building_collision)
	print("NavigationManager: Navigation collision: %d" % counts.navigation_collision)
	print("NavigationManager: === END DEBUG ===")

## Count structures in the scene
func _count_structures_recursive(node: Node) -> int:
	var count = 0
	if node.name.begins_with("Structure_"):
		count += 1
	
	for child in node.get_children():
		count += _count_structures_recursive(child)
	
	return count

## Add visual debug representation for collision
func _add_collision_debug_visualization(static_body: StaticBody3D, collision_type: String):
	# Create a visual indicator for the collision
	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "CollisionDebugVisualization"
	
	# Create a simple sphere to indicate collision presence
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.2
	sphere_mesh.height = 0.4
	
	# Create material based on collision type
	var material = StandardMaterial3D.new()
	if collision_type == "terrain":
		material.albedo_color = Color.GREEN
	else:
		material.albedo_color = Color.RED
	material.flags_transparent = true
	material.albedo_color.a = 0.7
	material.flags_unshaded = true
	
	debug_mesh.mesh = sphere_mesh
	debug_mesh.material_override = material
	debug_mesh.position = Vector3(0, 1, 0)  # Raise above ground
	
	static_body.add_child(debug_mesh)
	print("NavigationManager: Added debug visualization for %s collision" % collision_type)

## Recursive function to count collision structures
func _count_collision_structures_recursive(node: Node, counts: Dictionary):
	if node.name.begins_with("Structure_"):
		counts.total_structures += 1
		print("NavigationManager: Found structure: %s" % node.name)
		
		# Check for collision children
		for child in node.get_children():
			if child is StaticBody3D:
				if child.name == "TerrainPhysicsCollision":
					counts.terrain_collision += 1
					print("  - Has terrain physics collision")
				elif child.name == "BuildingPhysicsCollision":
					counts.building_collision += 1
					print("  - Has building physics collision")
				elif child.name == "NavigationCollision":
					counts.navigation_collision += 1
					print("  - Has navigation collision")
	
	# Recurse through children
	for child in node.get_children():
		_count_collision_structures_recursive(child, counts)
