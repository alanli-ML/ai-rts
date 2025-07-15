# RoadNetwork.gd - Generate road networks connecting districts
class_name RoadNetwork
extends Node

# Dependencies
var logger
var tile_system: Node
var asset_loader: Node

# Road network data
var road_graph: Dictionary = {}
var road_segments: Array = []

# Signals
signal road_network_complete(road_data: Dictionary)

func _ready() -> void:
    pass

func setup(logger_ref, tile_system_ref: Node, asset_loader_ref: Node) -> void:
    """Setup the road network generator with dependencies"""
    logger = logger_ref
    tile_system = tile_system_ref
    asset_loader = asset_loader_ref
    
    if logger:
        logger.info("RoadNetwork", "Road network generator initialized")

func generate_network(control_points: Array, districts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
    """Generate road network connecting districts"""
    var road_data = {
        "segments": [],
        "intersections": [],
        "metadata": {
            "generated_at": Time.get_ticks_msec(),
            "seed": rng.get_seed()
        }
    }
    
    # Generate main roads connecting control points
    _generate_main_roads(control_points, road_data, rng)
    
    # Generate district internal roads
    _generate_district_roads(districts, road_data, rng)
    
    if logger:
        logger.info("RoadNetwork", "Generated road network with %d segments" % road_data.segments.size())
    
    road_network_complete.emit(road_data)
    return road_data

func _generate_main_roads(control_points: Array, road_data: Dictionary, rng: RandomNumberGenerator) -> void:
    """Generate primary roads connecting districts"""
    
    # Connect adjacent control points with roads
    for i in range(control_points.size()):
        var current_point = control_points[i]
        
        # Connect to adjacent points in grid
        var adjacent_indices = _get_adjacent_indices(i, 3, 3)  # 3x3 grid
        
        for adj_index in adjacent_indices:
            if adj_index < control_points.size():
                var target_point = control_points[adj_index]
                
                # Create road segment
                var road_segment = {
                    "start": current_point,
                    "end": target_point,
                    "type": "main_road",
                    "asset_type": "road_straight",
                    "direction": _calculate_direction(current_point, target_point)
                }
                
                road_data.segments.append(road_segment)

func _generate_district_roads(districts: Dictionary, road_data: Dictionary, rng: RandomNumberGenerator) -> void:
    """Generate internal district street networks"""
    
    for district_id in districts.keys():
        var district_data = districts[district_id]
        var district_roads = _create_district_street_network(district_data, rng)
        
        for road in district_roads:
            road["district_id"] = district_id
            road_data.segments.append(road)

func _create_district_street_network(district_data: Dictionary, rng: RandomNumberGenerator) -> Array:
    """Create street network within a district"""
    var streets = []
    var center = district_data.center
    var bounds = district_data.bounds
    
    # Create a simple cross pattern
    # Horizontal street
    for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
        streets.append({
            "position": Vector2i(x, center.y),
            "type": "street",
            "asset_type": "road_straight",
            "direction": "horizontal"
        })
    
    # Vertical street
    for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
        streets.append({
            "position": Vector2i(center.x, y),
            "type": "street",
            "asset_type": "road_straight",
            "direction": "vertical"
        })
    
    return streets

func _get_adjacent_indices(index: int, width: int, height: int) -> Array:
    """Get adjacent indices in a grid"""
    var adjacent = []
    var x = index % width
    var y = index / width
    
    # Check all 8 directions
    var directions = [
        Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
        Vector2i(-1, 0),                   Vector2i(1, 0),
        Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1)
    ]
    
    for direction in directions:
        var new_x = x + direction.x
        var new_y = y + direction.y
        
        if new_x >= 0 and new_x < width and new_y >= 0 and new_y < height:
            adjacent.append(new_y * width + new_x)
    
    return adjacent

func _calculate_direction(start: Vector2i, end: Vector2i) -> String:
    """Calculate direction between two points"""
    var diff = end - start
    
    if abs(diff.x) > abs(diff.y):
        return "horizontal"
    else:
        return "vertical"

func generate_main_roads(control_points: Array) -> Array:
    """Generate primary roads connecting districts"""
    var roads = []
    
    for i in range(control_points.size() - 1):
        var start = control_points[i]
        var end = control_points[i + 1]
        
        roads.append({
            "start": start,
            "end": end,
            "type": "main_road"
        })
    
    return roads

func generate_district_roads(district_area: Rect2i) -> Array:
    """Generate internal district street network"""
    var roads = []
    var center = Vector2i(district_area.position.x + district_area.size.x/2, district_area.position.y + district_area.size.y/2)
    
    # Simple cross pattern
    for x in range(district_area.position.x, district_area.position.x + district_area.size.x):
        roads.append({
            "position": Vector2i(x, center.y),
            "type": "road_straight",
            "direction": "horizontal"
        })
    
    for y in range(district_area.position.y, district_area.position.y + district_area.size.y):
        roads.append({
            "position": Vector2i(center.x, y),
            "type": "road_straight",
            "direction": "vertical"
        })
    
    return roads

func optimize_road_connections() -> void:
    """Optimize road network for gameplay and performance"""
    # Remove duplicate segments
    var unique_segments = []
    
    for segment in road_segments:
        var is_duplicate = false
        for existing in unique_segments:
            if _are_segments_duplicate(segment, existing):
                is_duplicate = true
                break
        
        if not is_duplicate:
            unique_segments.append(segment)
    
    road_segments = unique_segments
    
    if logger:
        logger.info("RoadNetwork", "Optimized road network to %d segments" % road_segments.size())

func _are_segments_duplicate(segment1: Dictionary, segment2: Dictionary) -> bool:
    """Check if two road segments are duplicates"""
    var start1 = segment1.get("start", Vector2i.ZERO)
    var end1 = segment1.get("end", Vector2i.ZERO)
    var start2 = segment2.get("start", Vector2i.ZERO)
    var end2 = segment2.get("end", Vector2i.ZERO)
    
    return (start1 == start2 and end1 == end2) or (start1 == end2 and end1 == start2) 