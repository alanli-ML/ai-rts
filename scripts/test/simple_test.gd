# simple_test.gd - Simple test for procedural generation system
extends Node

func _ready():
	print("=== SIMPLE ROAD INTERSECTION TEST ===")
	test_road_network_intersection_detection()

func test_road_network_intersection_detection():
	print("Testing road network intersection detection...")
	
	# Create a minimal road network for testing
	var road_network = RoadNetwork.new()
	road_network.name = "TestRoadNetwork"
	add_child(road_network)
	
	# Mock dependencies
	var mock_logger = MockLogger.new()
	var mock_tile_system = MockTileSystem.new()
	var mock_asset_loader = MockAssetLoader.new()
	var mock_asset_dimension_manager = MockAssetDimensionManager.new()
	
	road_network.setup(mock_logger, mock_tile_system, mock_asset_loader, mock_asset_dimension_manager)
	
	# Create test control points that will form intersections
	var control_points = [
		Vector2i(0, 0),  # Top-left
		Vector2i(2, 0),  # Top-right
		Vector2i(1, 1),  # Center (should be intersection)
		Vector2i(0, 2),  # Bottom-left
		Vector2i(2, 2)   # Bottom-right
	]
	
	var districts = {}  # Empty for this test
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	
	# Generate network
	var road_data = road_network.generate_network(control_points, districts, rng)
	
	# Analyze results
	print("Road segments generated: %d" % road_data.segments.size())
	print("Intersections generated: %d" % road_data.intersections.size())
	
	# Print intersection details
	for i in range(road_data.intersections.size()):
		var intersection = road_data.intersections[i]
		print("Intersection %d: position=%s, type=%s, directions=%s" % [
			i, 
			intersection.position, 
			intersection.asset_type,
			intersection.directions
		])
	
	# Print segment details (should have overlapping segments removed)
	for i in range(road_data.segments.size()):
		var segment = road_data.segments[i]
		print("Segment %d: position=%s, direction=%s, type=%s" % [
			i,
			segment.position,
			segment.direction,
			segment.asset_type
		])
	
	print("=== TEST COMPLETE ===")

# Mock classes for testing
class MockLogger:
	func info(tag: String, message: String):
		print("[%s] %s" % [tag, message])

class MockTileSystem:
	var tile_size: float = 1.25
	
class MockAssetLoader:
	pass

class MockAssetDimensionManager:
	func calculate_optimal_asset_scale(type: String, subtype: String, size: Vector2i) -> Vector3:
		return Vector3(1.0, 1.0, 1.0)
	
	func validate_asset_connectivity(pos: Vector3, type: String, subtype: String) -> bool:
		return true 