# minimal_generation_test.gd - Minimal test that bypasses control point issues
extends Node3D

func _ready() -> void:
	print("=== MINIMAL PROCEDURAL GENERATION TEST ===")
	await get_tree().process_frame
	
	# Create logger directly
	var LoggerClass = preload("res://scripts/shared/utils/logger.gd")
	var logger = LoggerClass.new()
	logger.name = "Logger"
	add_child(logger)
	
	# Create asset loader directly
	var AssetLoaderClass = preload("res://scripts/procedural/asset_loader.gd")
	var asset_loader = AssetLoaderClass.new()
	asset_loader.name = "AssetLoader"
	add_child(asset_loader)
	asset_loader.setup(logger)
	
	# Create map generator directly
	var MapGeneratorClass = preload("res://scripts/procedural/map_generator.gd")
	var map_generator = MapGeneratorClass.new()
	map_generator.name = "MapGenerator"
	add_child(map_generator)
	map_generator.setup(logger, asset_loader)
	
	print("Direct component initialization complete!")
	
	# Test the generation
	await _test_generation(map_generator)

func _test_generation(map_generator) -> void:
	print("\n=== TESTING PROCEDURAL GENERATION ===")
	
	var test_seed = 123
	print("Generating map with seed: %d" % test_seed)
	
	var start_time = Time.get_ticks_msec()
	var map_data = await map_generator.generate_map(test_seed)
	var generation_time = Time.get_ticks_msec() - start_time
	
	print("Generation completed in %d ms" % generation_time)
	
	if map_data.is_empty():
		print("ERROR: Map generation failed!")
		return
	
	# Display results
	_display_results(map_data)
	
	# Render in 3D
	_render_simple_3d(map_data)

func _display_results(map_data: Dictionary) -> void:
	print("\n=== GENERATION RESULTS ===")
	print("Map Data Structure:")
	print("  Seed: %d" % map_data.get("seed", 0))
	print("  Grid Size: %s" % map_data.get("size", "Unknown"))
	print("  Tile Size: %.1f" % map_data.get("tile_size", 0.0))
	print("  Generation Time: %d ms" % map_data.get("metadata", {}).get("generation_time", 0))
	
	# Control Points
	var control_points = map_data.get("control_points", {})
	print("\nControl Points (%d):" % control_points.size())
	for cp_id in control_points:
		var cp_data = control_points[cp_id]
		var pos = cp_data.get("position", Vector2i(0, 0))
		var type = cp_data.get("district_type", 0)
		var value = cp_data.get("strategic_value", 0)
		print("  %s: (%d, %d) Type:%d Value:%d" % [cp_id, pos.x, pos.y, type, value])
	
	# Districts
	var districts = map_data.get("districts", {})
	print("\nDistricts (%d):" % districts.size())
	for district_id in districts:
		var district_data = districts[district_id]
		var center = district_data.get("center", Vector2i(0, 0))
		var type = district_data.get("type", 0)
		var buildings = district_data.get("buildings", [])
		print("  %s: Center(%d, %d) Type:%d Buildings:%d" % [district_id, center.x, center.y, type, buildings.size()])
	
	# Roads
	var roads = map_data.get("roads", {})
	var segments = roads.get("segments", [])
	print("\nRoads: %d segments" % segments.size())
	
	# Buildings
	var buildings_data = map_data.get("buildings", {})
	var total_buildings = 0
	for district_buildings in buildings_data.values():
		total_buildings += district_buildings.size()
	print("Total Buildings: %d" % total_buildings)

func _render_simple_3d(map_data: Dictionary) -> void:
	print("\n=== RENDERING 3D VISUALIZATION ===")
	
	# Create ground
	var ground = MeshInstance3D.new()
	ground.name = "Ground"
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(60, 60)
	ground.mesh = plane_mesh
	
	var ground_material = StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.2, 0.6, 0.2)
	ground.material_override = ground_material
	
	add_child(ground)
	
	# Create camera
	var camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(25, 30, 25)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	add_child(camera)
	
	# Create lighting
	var light = DirectionalLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, 10, 0)
	light.rotation_degrees = Vector3(-45, -45, 0)
	add_child(light)
	
	# Render control points
	var control_points = map_data.get("control_points", {})
	var tile_size = map_data.get("tile_size", 3.0)
	
	print("Rendering %d control points..." % control_points.size())
	
	for cp_id in control_points:
		var cp_data = control_points[cp_id]
		var tile_pos = cp_data.get("position", Vector2i(0, 0))
		var district_type = cp_data.get("district_type", 0)
		
		var world_pos = Vector3(tile_pos.x * tile_size, 2, tile_pos.y * tile_size)
		
		var sphere = MeshInstance3D.new()
		sphere.name = "CP_" + cp_id
		sphere.position = world_pos
		
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 2.0
		sphere_mesh.height = 4.0
		sphere.mesh = sphere_mesh
		
		var material = StandardMaterial3D.new()
		match district_type:
			0: material.albedo_color = Color.CYAN
			1: material.albedo_color = Color.ORANGE
			2: material.albedo_color = Color.YELLOW
			3: material.albedo_color = Color.GREEN
			4: material.albedo_color = Color.RED
			_: material.albedo_color = Color.WHITE
		
		material.emission_enabled = true
		material.emission = material.albedo_color * 0.3
		sphere.material_override = material
		
		add_child(sphere)
		print("  Control Point %s rendered at %s" % [cp_id, world_pos])
	
	# Render some buildings
	var buildings_data = map_data.get("buildings", {})
	var building_count = 0
	
	print("Rendering buildings...")
	for district_buildings in buildings_data.values():
		for building in district_buildings:
			if building_count >= 20:  # Limit for performance
				break
			
			var tile_pos = building.get("position", Vector2i(0, 0))
			var building_type = building.get("type", "unknown")
			var size = building.get("size", Vector2i(2, 2))
			
			var world_pos = Vector3(tile_pos.x * tile_size, 1, tile_pos.y * tile_size)
			
			var cube = MeshInstance3D.new()
			cube.name = "Building_%d" % building_count
			cube.position = world_pos
			
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(size.x * tile_size * 0.8, randf_range(2, 5), size.y * tile_size * 0.8)
			cube.mesh = box_mesh
			
			var material = StandardMaterial3D.new()
			match building_type:
				"commercial": material.albedo_color = Color.LIGHT_BLUE
				"industrial": material.albedo_color = Color.DARK_GRAY
				"shop": material.albedo_color = Color.CYAN
				"factory": material.albedo_color = Color.BROWN
				_: material.albedo_color = Color.WHITE
			
			cube.material_override = material
			add_child(cube)
			
			building_count += 1
		
		if building_count >= 20:
			break
	
	print("  Rendered %d buildings" % building_count)
	
	print("\n=== 3D VISUALIZATION COMPLETE ===")
	print("SUCCESS: Procedural generation tested and rendered!")
	print("Generated and rendered a complete procedural map with:")
	print("  - %d control points" % control_points.size())
	print("  - %d districts" % map_data.get("districts", {}).size())
	print("  - %d buildings (showing first 20)" % building_count)
	print("  - %d road segments" % map_data.get("roads", {}).get("segments", []).size())
	
	# Keep running briefly to see results
	await get_tree().create_timer(3.0).timeout
	print("Test complete!") 