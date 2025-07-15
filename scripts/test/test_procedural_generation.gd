# test_procedural_generation.gd - Test script for procedural generation system
extends Node

# This script tests the procedural generation system directly
var logger
var dependency_container
var map_generator
var test_results: Dictionary = {}

func _ready() -> void:
	print("=== PROCEDURAL GENERATION TEST ===")
	
	# Wait for autoloads to be available
	await get_tree().process_frame
	
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
	
	# Start the test
	await _run_procedural_generation_test()

func _run_procedural_generation_test() -> void:
	"""Run the procedural generation test"""
	print("\n=== STARTING PROCEDURAL GENERATION TEST ===")
	
	# Test seed for reproducible results
	var test_seed = 12345
	print("Using test seed: %d" % test_seed)
	
	# Generate the map
	print("Generating procedural map...")
	var generation_start_time = Time.get_ticks_msec()
	
	var map_data = await map_generator.generate_map(test_seed)
	
	var generation_end_time = Time.get_ticks_msec()
	var generation_time = generation_end_time - generation_start_time
	
	print("Map generation completed in %d ms" % generation_time)
	
	# Analyze and display results
	_display_generation_results(map_data)
	
	print("\n=== PROCEDURAL GENERATION TEST COMPLETE ===")

func _display_generation_results(map_data: Dictionary) -> void:
	"""Display the results of the procedural generation"""
	print("\n=== GENERATION RESULTS ===")
	
	if map_data.is_empty():
		print("ERROR: Map generation failed - no data returned")
		return
	
	# Display basic map info
	print("Map Info:")
	print("  Seed: %d" % map_data.get("seed", 0))
	print("  Grid Size: %s" % map_data.get("size", "Unknown"))
	print("  Tile Size: %.1f" % map_data.get("tile_size", 0.0))
	print("  Generation Time: %d ms" % map_data.get("metadata", {}).get("generation_time", 0))
	print("  Version: %s" % map_data.get("metadata", {}).get("version", "Unknown"))
	
	# Display control points
	var control_points = map_data.get("control_points", {})
	print("\nControl Points (%d):" % control_points.size())
	for cp_id in control_points:
		var cp_data = control_points[cp_id]
		var position = cp_data.get("position", Vector2i(0, 0))
		var district_type = cp_data.get("district_type", 0)
		var strategic_value = cp_data.get("strategic_value", 0)
		
		print("  %s: Position(%d, %d), Type:%d, Value:%d" % [
			cp_id, position.x, position.y, district_type, strategic_value
		])
	
	# Display districts
	var districts = map_data.get("districts", {})
	print("\nDistricts (%d):" % districts.size())
	for district_id in districts:
		var district_data = districts[district_id]
		var center = district_data.get("center", Vector2i(0, 0))
		var district_type = district_data.get("type", 0)
		var building_count = district_data.get("buildings", []).size()
		
		print("  %s: Center(%d, %d), Type:%d, Buildings:%d" % [
			district_id, center.x, center.y, district_type, building_count
		])
		
		# Show a few buildings in each district
		var buildings = district_data.get("buildings", [])
		for i in range(min(3, buildings.size())):
			var building = buildings[i]
			var pos = building.get("position", Vector2i(0, 0))
			var type = building.get("type", "unknown")
			print("    Building %d: %s at (%d, %d)" % [i + 1, type, pos.x, pos.y])
		
		if buildings.size() > 3:
			print("    ... and %d more buildings" % (buildings.size() - 3))
	
	# Display road network
	var roads = map_data.get("roads", {})
	var road_segments = roads.get("segments", [])
	print("\nRoad Network:")
	print("  Total segments: %d" % road_segments.size())
	
	if road_segments.size() > 0:
		print("  Sample segments:")
		for i in range(min(5, road_segments.size())):
			var segment = road_segments[i]
			var start = segment.get("start", Vector2i(0, 0))
			var end = segment.get("end", Vector2i(0, 0))
			var road_type = segment.get("type", "unknown")
			print("    %d: %s from (%d, %d) to (%d, %d)" % [
				i + 1, road_type, start.x, start.y, end.x, end.y
			])
	
	# Display building statistics
	var buildings_data = map_data.get("buildings", {})
	var total_buildings = 0
	var buildings_by_type = {}
	
	for district_buildings in buildings_data.values():
		total_buildings += district_buildings.size()
		for building in district_buildings:
			var building_type = building.get("type", "unknown")
			if not buildings_by_type.has(building_type):
				buildings_by_type[building_type] = 0
			buildings_by_type[building_type] += 1
	
	print("\nBuilding Statistics:")
	print("  Total buildings: %d" % total_buildings)
	print("  Buildings by type:")
	for building_type in buildings_by_type:
		print("    %s: %d" % [building_type, buildings_by_type[building_type]])
	
	# Display spawn points
	var spawn_points = map_data.get("spawn_points", {})
	print("\nSpawn Points: %d" % spawn_points.size())
	
	# Create a visual representation
	_create_ascii_map_visualization(map_data)

func _create_ascii_map_visualization(map_data: Dictionary) -> void:
	"""Create a simple ASCII visualization of the generated map"""
	print("\n=== ASCII MAP VISUALIZATION ===")
	
	var grid_size = map_data.get("size", Vector2i(20, 20))
	var control_points = map_data.get("control_points", {})
	var districts = map_data.get("districts", {})
	
	# Create visualization grid
	var vis_grid = []
	for x in range(grid_size.x):
		var row = []
		for y in range(grid_size.y):
			row.append(".")
		vis_grid.append(row)
	
	# Mark control points
	for cp_id in control_points:
		var cp_data = control_points[cp_id]
		var pos = cp_data.get("position", Vector2i(0, 0))
		var district_type = cp_data.get("district_type", 0)
		
		# Use different symbols for different district types
		var symbol = "?"
		match district_type:
			0: symbol = "C"  # Commercial
			1: symbol = "I"  # Industrial
			2: symbol = "M"  # Mixed
			3: symbol = "R"  # Residential
			4: symbol = "X"  # Military
		
		if pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y:
			vis_grid[pos.x][pos.y] = symbol
	
	# Mark district boundaries
	for district_id in districts:
		var district_data = districts[district_id]
		var bounds = district_data.get("bounds", Rect2i(0, 0, 6, 6))
		var district_type = district_data.get("type", 0)
		
		# Different characters for different district types
		var boundary_char = "?"
		match district_type:
			0: boundary_char = "c"  # Commercial
			1: boundary_char = "i"  # Industrial
			2: boundary_char = "m"  # Mixed
			3: boundary_char = "r"  # Residential
			4: boundary_char = "x"  # Military
		
		# Mark district area
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
				if x >= 0 and x < grid_size.x and y >= 0 and y < grid_size.y:
					if vis_grid[x][y] == ".":
						vis_grid[x][y] = boundary_char
	
	# Print the visualization
	print("Legend:")
	print("  . = Empty space")
	print("  C/c = Commercial district/area")
	print("  I/i = Industrial district/area")
	print("  M/m = Mixed district/area")
	print("  R/r = Residential district/area")
	print("  X/x = Military district/area")
	print("  Capital letters = Control points")
	print("  Lowercase letters = District areas")
	print("")
	
	# Print grid with coordinates
	var header = "   "
	for y in range(grid_size.y):
		header += str(y % 10)
	print(header)
	
	for x in range(grid_size.x):
		var row = "%2d " % x
		for y in range(grid_size.y):
			row += vis_grid[x][y]
		print(row) 