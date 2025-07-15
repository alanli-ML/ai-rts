# RoadNetwork.gd - Generate road networks connecting districts
class_name RoadNetwork
extends Node

# Dependencies
var logger
var tile_system: Node
var asset_loader: Node
var asset_dimension_manager: Node

# Road network data
var road_segments: Array = []
var road_grid: Dictionary = {}  # Track which tiles have roads

# Signals
signal road_network_complete(road_data: Dictionary)

func _ready() -> void:
    pass

func setup(logger_ref, tile_system_ref: Node, asset_loader_ref: Node, asset_dimension_manager_ref: Node) -> void:
    """Setup the road network generator with dependencies"""
    logger = logger_ref
    tile_system = tile_system_ref
    asset_loader = asset_loader_ref
    asset_dimension_manager = asset_dimension_manager_ref
    
    if logger:
        logger.info("RoadNetwork", "Road network generator initialized")

func generate_network(control_points: Array, districts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
    """Generate road network connecting districts using only square road tiles"""
    road_grid.clear()  # Reset road tracking
    
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
    
    # Generate edge roads to fill map borders
    _generate_edge_roads(road_data, rng)
    
    # Generate additional grid roads for better connectivity
    _generate_grid_roads(road_data, rng)
    
    # Convert grid to final road segments using square tiles
    _create_square_road_segments(road_data)
    
    if logger:
        logger.info("RoadNetwork", "Generated comprehensive road network with %d square road tiles extending to map edges" % road_data.segments.size())
    
    road_network_complete.emit(road_data)
    return road_data

func _generate_main_roads(control_points: Array, road_data: Dictionary, _rng: RandomNumberGenerator) -> void:
    """Generate primary roads connecting districts in 5x5 grid"""
    
    # Connect adjacent control points with roads
    for i in range(control_points.size()):
        var current_point = control_points[i]
        
        # Connect to adjacent points in grid (cardinal directions only)
        var adjacent_indices = _get_adjacent_indices(i, 5, 5)  # 5x5 grid instead of 3x3
        
        for adj_index in adjacent_indices:
            if adj_index < control_points.size():
                var target_point = control_points[adj_index]
                
                # Create road path between points
                _create_road_path(current_point, target_point)

func _create_road_path(start: Vector2i, end: Vector2i) -> void:
    """Create a path of road tiles between two points"""
    var current = start
    
    # Simple path: go horizontal first, then vertical
    while current.x != end.x:
        _add_road_tile(current)
        current.x += 1 if end.x > current.x else -1
    
    while current.y != end.y:
        _add_road_tile(current)
        current.y += 1 if end.y > current.y else -1
    
    # Add the final destination
    _add_road_tile(end)

func _generate_district_roads(districts: Dictionary, road_data: Dictionary, _rng: RandomNumberGenerator) -> void:
    """Generate internal district street networks"""
    
    for district_id in districts.keys():
        var district_data = districts[district_id]
        _create_district_street_network(district_data)

func _create_district_street_network(district_data: Dictionary) -> void:
    """Create street network within a district using square tiles"""
    var center = district_data.center
    var bounds = district_data.bounds
    
    # Create horizontal street through center
    for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
        _add_road_tile(Vector2i(x, center.y))
    
    # Create vertical street through center  
    for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
        _add_road_tile(Vector2i(center.x, y))

func _add_road_tile(position: Vector2i) -> void:
    """Add a road tile to the grid"""
    var key = str(position.x) + "," + str(position.y)
    road_grid[key] = position

func _create_square_road_segments(road_data: Dictionary) -> void:
    """Convert road grid to final segments using square road assets"""
    
    for grid_key in road_grid.keys():
        var position = road_grid[grid_key]
        
        # Determine asset type based on connectivity
        var asset_type = _determine_square_asset_type(position)
        
        # Create road segment
        var segment = {
            "position": position,
            "type": "road",
            "asset_type": asset_type,
            "world_position": Vector3(
                position.x * tile_system.tile_size,
                0,
                position.y * tile_system.tile_size
            )
        }
        
        # Add asset dimension information if available
        if asset_dimension_manager:
            # Calculate scale to fill tile properly for connectivity
            var road_dims = asset_dimension_manager.get_asset_dimensions("road", "square")
            if road_dims.has("size") and road_dims.size.x > 0 and road_dims.size.z > 0:
                # Scale road to fill the tile for proper connectivity
                var scale_x = tile_system.tile_size / road_dims.size.x
                var scale_z = tile_system.tile_size / road_dims.size.z
                segment["optimal_scale"] = Vector3(scale_x, 1.0, scale_z)
            else:
                # Fallback: scale to fill tile assuming 1.0 unit base size
                var scale_factor = tile_system.tile_size / 1.0
                segment["optimal_scale"] = Vector3(scale_factor, 1.0, scale_factor)
            
            segment["connectivity_valid"] = true  # Scaled roads should connect properly
        else:
            segment["optimal_scale"] = Vector3(1.0, 1.0, 1.0)  # Default scale
            segment["connectivity_valid"] = true
        
        road_data.segments.append(segment)

func _determine_square_asset_type(position: Vector2i) -> String:
    """Determine which square asset to use based on connectivity"""
    var connections = _count_connections(position)
    
    # Use square tiles for everything to ensure consistent sizing
    if connections >= 3:
        return "road_square"  # Use square tile for intersections
    elif connections == 2:
        return "road_square"  # Use square tile for straight roads
    else:
        return "road_square"  # Use square tile for everything

func _count_connections(position: Vector2i) -> int:
    """Count how many adjacent tiles have roads"""
    var count = 0
    var directions = [
        Vector2i(0, -1),  # North
        Vector2i(1, 0),   # East
        Vector2i(0, 1),   # South
        Vector2i(-1, 0)   # West
    ]
    
    for direction in directions:
        var neighbor = position + direction
        var key = str(neighbor.x) + "," + str(neighbor.y)
        if road_grid.has(key):
            count += 1
    
    return count

func _get_adjacent_indices(index: int, width: int, height: int) -> Array:
    """Get adjacent indices in a grid (cardinal directions only)"""
    var adjacent = []
    var x = index % width
    var y = index / width
    
    # Check cardinal directions only
    var directions = [
        Vector2i(0, -1),  # North
        Vector2i(1, 0),   # East
        Vector2i(0, 1),   # South
        Vector2i(-1, 0)   # West
    ]
    
    for direction in directions:
        var new_x = x + direction.x
        var new_y = y + direction.y
        
        if new_x >= 0 and new_x < width and new_y >= 0 and new_y < height:
            adjacent.append(new_y * width + new_x)
    
    return adjacent

func _generate_edge_roads(road_data: Dictionary, _rng: RandomNumberGenerator) -> void:
    """Generate roads around the entire map perimeter"""
    var map_size = tile_system.grid_size
    
    # Top edge (y = 0)
    for x in range(map_size.x):
        _add_road_tile(Vector2i(x, 0))
    
    # Bottom edge (y = map_size.y - 1)
    for x in range(map_size.x):
        _add_road_tile(Vector2i(x, map_size.y - 1))
    
    # Left edge (x = 0)
    for y in range(map_size.y):
        _add_road_tile(Vector2i(0, y))
    
    # Right edge (x = map_size.x - 1)
    for y in range(map_size.y):
        _add_road_tile(Vector2i(map_size.x - 1, y))
    
    if logger:
        logger.info("RoadNetwork", "Generated perimeter roads around map edges")

func _generate_grid_roads(road_data: Dictionary, rng: RandomNumberGenerator) -> void:
    """Generate a grid of roads across the entire map for better connectivity"""
    var map_size = tile_system.grid_size
    var grid_spacing = 8  # Road every 8 tiles for good coverage
    
    # Vertical grid roads
    for x in range(0, map_size.x, grid_spacing):
        for y in range(map_size.y):
            _add_road_tile(Vector2i(x, y))
    
    # Horizontal grid roads
    for y in range(0, map_size.y, grid_spacing):
        for x in range(map_size.x):
            _add_road_tile(Vector2i(x, y))
    
    # Add some random connecting roads for variety
    var connection_count = rng.randi_range(5, 15)
    for i in range(connection_count):
        var start = Vector2i(
            rng.randi_range(1, map_size.x - 2),
            rng.randi_range(1, map_size.y - 2)
        )
        var end = Vector2i(
            rng.randi_range(1, map_size.x - 2),
            rng.randi_range(1, map_size.y - 2)
        )
        _create_road_path(start, end)
    
    if logger:
        logger.info("RoadNetwork", "Generated grid roads with %d tile spacing and %d random connections" % [grid_spacing, connection_count])

# Legacy functions for compatibility
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
    
    # Simple cross pattern using square tiles
    for x in range(district_area.position.x, district_area.position.x + district_area.size.x):
        roads.append({
            "position": Vector2i(x, center.y),
            "type": "road_square",
            "direction": "horizontal"
        })
    
    for y in range(district_area.position.y, district_area.position.y + district_area.size.y):
        roads.append({
            "position": Vector2i(center.x, y),
            "type": "road_square",
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
    var pos1 = segment1.get("position", Vector2i.ZERO)
    var pos2 = segment2.get("position", Vector2i.ZERO)
    
    return pos1 == pos2 