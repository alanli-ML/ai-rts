# simple_test.gd - Simple test for procedural generation system
extends Node

func _ready() -> void:
	print("=== SIMPLE PROCEDURAL GENERATION TEST ===")
	await get_tree().process_frame
	
	var dependency_container = get_node("/root/DependencyContainer")
	if not dependency_container:
		print("ERROR: DependencyContainer not found!")
		return
	
	var logger = dependency_container.get_logger()
	if not logger:
		print("ERROR: Logger not found!")
		return
	
	dependency_container.create_server_dependencies()
	
	var map_generator = dependency_container.get_map_generator()
	if not map_generator:
		print("ERROR: MapGenerator not found!")
		return
	
	print("Starting procedural generation...")
	var map_data = await map_generator.generate_map(12345)
	
	if map_data.is_empty():
		print("ERROR: Map generation failed!")
		return
	
	print("SUCCESS: Map generated!")
	print("  Seed: %d" % map_data.get("seed", 0))
	print("  Grid Size: %s" % map_data.get("size", "Unknown"))
	print("  Districts: %d" % map_data.get("districts", {}).size())
	print("  Control Points: %d" % map_data.get("control_points", {}).size())
	print("  Roads: %d segments" % map_data.get("roads", {}).get("segments", []).size())
	
	var total_buildings = 0
	for district_buildings in map_data.get("buildings", {}).values():
		total_buildings += district_buildings.size()
	
	print("  Total Buildings: %d" % total_buildings)
	print("  Generation Time: %d ms" % map_data.get("metadata", {}).get("generation_time", 0))
	
	print("=== TEST COMPLETE ===")
	get_tree().quit() 