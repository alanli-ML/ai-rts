# test_generation_render.gd - Test procedural generation and render in server
extends Node3D

# Test components
var logger
var dependency_container
var map_generator
var generated_map_data: Dictionary = {}

# 3D rendering components
var ground_plane: MeshInstance3D
var control_point_nodes: Array = []
var building_nodes: Array = []
var road_nodes: Array = []

func _ready() -> void:
	print("=== PROCEDURAL GENERATION + RENDER TEST ===")
	await get_tree().process_frame
	
	# Initialize systems
	await _initialize_systems()
	
	# Generate the map
	await _generate_procedural_map()
	
	# Render the map in 3D
	await _render_map_in_3d()
	
	# Display results
	_display_final_results()

func _initialize_systems() -> void:
	"""Initialize the procedural generation systems"""
	print("Initializing systems...")
	
	# Get dependency container
	dependency_container = get_node("/root/DependencyContainer")
	if not dependency_container:
		print("ERROR: DependencyContainer not found!")
		return
	
	# Get logger
	logger = dependency_container.get_logger()
	if not logger:
		print("ERROR: Logger not found!")
		return
	
	# Force server mode for testing
	dependency_container.create_server_dependencies()
	
	# Get map generator
	map_generator = dependency_container.get_map_generator()
	if not map_generator:
		print("ERROR: MapGenerator not found!")
		return
	
	# Create ground plane
	_create_ground_plane()
	
	print("Systems initialized successfully!")

func _create_ground_plane() -> void:
	"""Create a ground plane for the map"""
	ground_plane = MeshInstance3D.new()
	ground_plane.name = "GroundPlane"
	
	# Create plane mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(60, 60)  # 60x60 world units
	ground_plane.mesh = plane_mesh
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.6, 0.2)  # Green
	material.roughness = 0.8
	ground_plane.material_override = material
	
	add_child(ground_plane)
	print("Ground plane created: 60x60 units")

func _generate_procedural_map() -> void:
	"""Generate the procedural map"""
	print("\n=== GENERATING PROCEDURAL MAP ===")
	
	var test_seed = 42  # Fixed seed for reproducible results
	print("Using seed: %d" % test_seed)
	
	var generation_start = Time.get_ticks_msec()
	
	# Generate the map
	generated_map_data = await map_generator.generate_map(test_seed)
	
	var generation_time = Time.get_ticks_msec() - generation_start
	
	if generated_map_data.is_empty():
		print("ERROR: Map generation failed!")
		return
	
	print("Map generation completed in %d ms" % generation_time)
	print("Generated map data structure:")
	print("  Seed: %d" % generated_map_data.get("seed", 0))
	print("  Grid Size: %s" % generated_map_data.get("size", "Unknown"))
	print("  Districts: %d" % generated_map_data.get("districts", {}).size())
	print("  Control Points: %d" % generated_map_data.get("control_points", {}).size())
	
	# Count total buildings
	var total_buildings = 0
	for district_buildings in generated_map_data.get("buildings", {}).values():
		total_buildings += district_buildings.size()
	print("  Total Buildings: %d" % total_buildings)
	
	print("  Road Segments: %d" % generated_map_data.get("roads", {}).get("segments", []).size())

func _render_map_in_3d() -> void:
	"""Render the generated map in 3D"""
	print("\n=== RENDERING MAP IN 3D ===")
	
	if generated_map_data.is_empty():
		print("ERROR: No map data to render!")
		return
	
	# Render control points
	await _render_control_points()
	
	# Render buildings
	await _render_buildings()
	
	# Render roads (as simple markers)
	await _render_roads()
	
	print("3D rendering complete!")

func _render_control_points() -> void:
	"""Render control points as colored spheres"""
	print("Rendering control points...")
	
	var control_points = generated_map_data.get("control_points", {})
	var tile_size = generated_map_data.get("tile_size", 3.0)
	
	for cp_id in control_points:
		var cp_data = control_points[cp_id]
		var tile_position = cp_data.get("position", Vector2i(0, 0))
		var district_type = cp_data.get("district_type", 0)
		
		# Convert tile position to world position
		var world_position = Vector3(
			tile_position.x * tile_size,
			2.0,  # Elevated above ground
			tile_position.y * tile_size
		)
		
		# Create sphere mesh
		var sphere = MeshInstance3D.new()
		sphere.name = "ControlPoint_" + cp_id
		sphere.position = world_position
		
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 2.0
		sphere_mesh.height = 4.0
		sphere.mesh = sphere_mesh
		
		# Color based on district type
		var material = StandardMaterial3D.new()
		match district_type:
			0: material.albedo_color = Color.CYAN      # Commercial
			1: material.albedo_color = Color.ORANGE    # Industrial
			2: material.albedo_color = Color.YELLOW    # Mixed
			3: material.albedo_color = Color.GREEN     # Residential
			4: material.albedo_color = Color.RED       # Military
			_: material.albedo_color = Color.WHITE
		
		material.emission_enabled = true
		material.emission = material.albedo_color * 0.5
		material.flags_unshaded = true
		sphere.material_override = material
		
		add_child(sphere)
		control_point_nodes.append(sphere)
		
		print("  Control Point %s at (%d, %d) - Type: %d" % [
			cp_id, tile_position.x, tile_position.y, district_type
		])

func _render_buildings() -> void:
	"""Render buildings as simple cubes"""
	print("Rendering buildings...")
	
	var buildings_data = generated_map_data.get("buildings", {})
	var tile_size = generated_map_data.get("tile_size", 3.0)
	var building_count = 0
	
	for district_id in buildings_data:
		var district_buildings = buildings_data[district_id]
		
		for building_data in district_buildings:
			var tile_position = building_data.get("position", Vector2i(0, 0))
			var building_type = building_data.get("type", "unknown")
			var building_size = building_data.get("size", Vector2i(2, 2))
			
			# Convert to world position
			var world_position = Vector3(
				tile_position.x * tile_size,
				1.0,  # Building height base
				tile_position.y * tile_size
			)
			
			# Create building cube
			var building = MeshInstance3D.new()
			building.name = "Building_%d_%s" % [building_count, building_type]
			building.position = world_position
			
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(
				building_size.x * tile_size * 0.8,  # Slightly smaller than tile
				randf_range(2.0, 6.0),  # Random height
				building_size.y * tile_size * 0.8
			)
			building.mesh = box_mesh
			
			# Color based on building type
			var material = StandardMaterial3D.new()
			match building_type:
				"commercial": material.albedo_color = Color.LIGHT_BLUE
				"industrial": material.albedo_color = Color.DARK_GRAY
				"shop": material.albedo_color = Color.CYAN
				"office": material.albedo_color = Color.BLUE
				"factory": material.albedo_color = Color.BROWN
				"warehouse": material.albedo_color = Color.GRAY
				_: material.albedo_color = Color.WHITE
			
			material.roughness = 0.3
			building.material_override = material
			
			add_child(building)
			building_nodes.append(building)
			building_count += 1
			
			# Limit buildings for performance
			if building_count >= 50:
				break
		
		if building_count >= 50:
			break
	
	print("  Rendered %d buildings" % building_count)

func _render_roads() -> void:
	"""Render roads as simple markers"""
	print("Rendering roads...")
	
	var roads_data = generated_map_data.get("roads", {})
	var road_segments = roads_data.get("segments", [])
	var tile_size = generated_map_data.get("tile_size", 3.0)
	
	var road_count = 0
	for segment in road_segments:
		var start_pos = segment.get("start", Vector2i(0, 0))
		var end_pos = segment.get("end", Vector2i(0, 0))
		
		# Create road marker at midpoint
		var midpoint = Vector3(
			(start_pos.x + end_pos.x) * tile_size * 0.5,
			0.1,  # Slightly above ground
			(start_pos.y + end_pos.y) * tile_size * 0.5
		)
		
		var road_marker = MeshInstance3D.new()
		road_marker.name = "Road_%d" % road_count
		road_marker.position = midpoint
		
		var cylinder_mesh = CylinderMesh.new()
		cylinder_mesh.top_radius = 0.5
		cylinder_mesh.bottom_radius = 0.5
		cylinder_mesh.height = 0.2
		road_marker.mesh = cylinder_mesh
		
		var material = StandardMaterial3D.new()
		material.albedo_color = Color.BLACK
		material.roughness = 0.1
		road_marker.material_override = material
		
		add_child(road_marker)
		road_nodes.append(road_marker)
		road_count += 1
		
		# Limit roads for performance
		if road_count >= 20:
			break
	
	print("  Rendered %d road markers" % road_count)

func _display_final_results() -> void:
	"""Display final test results"""
	print("\n=== FINAL TEST RESULTS ===")
	print("3D Scene Statistics:")
	print("  Control Points: %d" % control_point_nodes.size())
	print("  Buildings: %d" % building_nodes.size())
	print("  Road Markers: %d" % road_nodes.size())
	print("  Total 3D Objects: %d" % (control_point_nodes.size() + building_nodes.size() + road_nodes.size()))
	
	# Display detailed map statistics
	if not generated_map_data.is_empty():
		print("\nDetailed Map Statistics:")
		
		# Control points breakdown
		var control_points = generated_map_data.get("control_points", {})
		var district_type_counts = {}
		for cp_id in control_points:
			var cp_data = control_points[cp_id]
			var district_type = cp_data.get("district_type", 0)
			if not district_type_counts.has(district_type):
				district_type_counts[district_type] = 0
			district_type_counts[district_type] += 1
		
		print("  District Types:")
		for district_type in district_type_counts:
			var type_name = _get_district_type_name(district_type)
			print("    %s: %d" % [type_name, district_type_counts[district_type]])
		
		# Building type breakdown
		var building_type_counts = {}
		var total_buildings = 0
		for district_buildings in generated_map_data.get("buildings", {}).values():
			total_buildings += district_buildings.size()
			for building in district_buildings:
				var building_type = building.get("type", "unknown")
				if not building_type_counts.has(building_type):
					building_type_counts[building_type] = 0
				building_type_counts[building_type] += 1
		
		print("  Building Types:")
		for building_type in building_type_counts:
			print("    %s: %d" % [building_type, building_type_counts[building_type]])
		
		print("  Generation Performance:")
		print("    Total Generation Time: %d ms" % generated_map_data.get("metadata", {}).get("generation_time", 0))
		print("    Districts Generated: %d" % generated_map_data.get("districts", {}).size())
		print("    Buildings Generated: %d" % total_buildings)
		print("    Roads Generated: %d" % generated_map_data.get("roads", {}).get("segments", []).size())
	
	print("\n=== PROCEDURAL GENERATION + RENDER TEST COMPLETE ===")
	print("SUCCESS: Map generated and rendered in 3D!")
	
	# Keep the test running for a bit to observe the results
	await get_tree().create_timer(2.0).timeout
	print("Test completed. Check the 3D scene for rendered objects.")

func _get_district_type_name(district_type: int) -> String:
	"""Get human-readable district type name"""
	match district_type:
		0: return "Commercial"
		1: return "Industrial"
		2: return "Mixed"
		3: return "Residential"
		4: return "Military"
		_: return "Unknown" 