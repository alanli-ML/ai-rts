# DistrictGenerator.gd - Generate urban districts around control points
class_name DistrictGenerator
extends Node

# Dependencies
var logger
var tile_system: Node
var asset_loader: Node

# District generation configuration
var district_types: Array = ["commercial", "industrial", "mixed", "residential", "military"]

# Signals
signal district_generated(district_id: String, district_data: Dictionary)

func _ready() -> void:
    pass

func setup(logger_ref, tile_system_ref: Node, asset_loader_ref: Node) -> void:
    """Setup the district generator with dependencies"""
    logger = logger_ref
    tile_system = tile_system_ref
    asset_loader = asset_loader_ref
    
    if logger:
        logger.info("DistrictGenerator", "District generator initialized")

func generate_district(center_pos: Vector2i, district_type: int, size: int, rng: RandomNumberGenerator) -> Dictionary:
    """Generate a district around a center position"""
    var district_data = {
        "center": center_pos,
        "type": district_type,
        "size": size,
        "bounds": Rect2i(center_pos.x - size/2, center_pos.y - size/2, size, size),
        "buildings": [],
        "roads": [],
        "metadata": {
            "generated_at": Time.get_ticks_msec(),
            "seed": rng.get_seed()
        }
    }
    
    # Generate basic district layout
    _generate_district_layout(district_data, rng)
    
    if logger:
        logger.info("DistrictGenerator", "Generated district at %s with %d buildings" % [center_pos, district_data.buildings.size()])
    
    return district_data

func _generate_district_layout(district_data: Dictionary, rng: RandomNumberGenerator) -> void:
    """Generate the basic layout for a district"""
    var bounds = district_data.bounds
    var building_count = rng.randi_range(3, 8)
    
    # Generate some sample buildings
    for i in range(building_count):
        var building_pos = Vector2i(
            rng.randi_range(bounds.position.x, bounds.position.x + bounds.size.x - 1),
            rng.randi_range(bounds.position.y, bounds.position.y + bounds.size.y - 1)
        )
        
        var building_data = {
            "position": building_pos,
            "type": _select_building_type(district_data.type, rng),
            "size": Vector2i(rng.randi_range(2, 4), rng.randi_range(2, 4)),
            "asset_path": ""
        }
        
        district_data.buildings.append(building_data)

func _select_building_type(district_type: int, rng: RandomNumberGenerator) -> String:
    """Select appropriate building type based on district type"""
    match district_type:
        0: # Commercial
            return "commercial"
        1: # Industrial
            return "industrial"
        2: # Mixed
            return "commercial" if rng.randf() < 0.5 else "industrial"
        _:
            return "commercial"

func create_district_roads(district_area: Rect2i) -> Array:
    """Create internal road network for district"""
    var roads = []
    
    # Create a simple cross pattern for now
    var center = Vector2i(district_area.position.x + district_area.size.x/2, district_area.position.y + district_area.size.y/2)
    
    # Horizontal road
    for x in range(district_area.position.x, district_area.position.x + district_area.size.x):
        roads.append({
            "position": Vector2i(x, center.y),
            "type": "road_straight",
            "direction": "horizontal"
        })
    
    # Vertical road
    for y in range(district_area.position.y, district_area.position.y + district_area.size.y):
        roads.append({
            "position": Vector2i(center.x, y),
            "type": "road_straight",
            "direction": "vertical"
        })
    
    return roads

func place_district_buildings(district_area: Rect2i, roads: Array) -> Array:
    """Place buildings with proper road access"""
    var buildings = []
    
    # Simple placement algorithm - place buildings adjacent to roads
    for road in roads:
        var road_pos = road.position
        var adjacent_positions = [
            road_pos + Vector2i(1, 0),
            road_pos + Vector2i(-1, 0),
            road_pos + Vector2i(0, 1),
            road_pos + Vector2i(0, -1)
        ]
        
        for pos in adjacent_positions:
            if district_area.has_point(pos):
                buildings.append({
                    "position": pos,
                    "type": "building",
                    "size": Vector2i(2, 2),
                    "asset_path": ""
                })
    
    return buildings 