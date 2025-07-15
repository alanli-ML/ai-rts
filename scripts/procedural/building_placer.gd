# BuildingPlacer.gd - Intelligent building placement system
class_name BuildingPlacer
extends Node

# Dependencies
var logger
var tile_system: Node
var asset_loader: Node

# Building placement configuration
var placement_rules: Dictionary = {}
var building_density: float = 0.6

# Signals
signal building_placement_complete(district_id: String, building_count: int)

func _ready() -> void:
    pass

func setup(logger_ref, tile_system_ref: Node, asset_loader_ref: Node) -> void:
    """Setup the building placer with dependencies"""
    logger = logger_ref
    tile_system = tile_system_ref
    asset_loader = asset_loader_ref
    
    if logger:
        logger.info("BuildingPlacer", "Building placement system initialized")

func place_buildings(district_data: Dictionary, road_data: Dictionary, rng: RandomNumberGenerator) -> Array:
    """Place buildings in a district with intelligent placement"""
    var buildings = []
    var district_bounds = district_data.bounds
    var district_type = district_data.type
    
    # Calculate number of buildings based on district size and density
    var max_buildings = int(district_bounds.size.x * district_bounds.size.y * building_density)
    var building_count = rng.randi_range(max_buildings / 2, max_buildings)
    
    # Place buildings
    for i in range(building_count):
        var building_pos = _find_suitable_building_position(district_bounds, buildings, rng)
        
        if building_pos != Vector2i(-1, -1):
            var building_data = {
                "position": building_pos,
                "type": _select_building_type(district_type, rng),
                "size": _select_building_size(district_type, rng),
                "asset_path": _select_building_asset(district_type, rng),
                "rotation": rng.randi_range(0, 3) * 90,  # Rotate in 90-degree increments
                "metadata": {
                    "placement_time": Time.get_ticks_msec(),
                    "district_id": district_data.get("id", "unknown")
                }
            }
            
            buildings.append(building_data)
    
    if logger:
        logger.info("BuildingPlacer", "Placed %d buildings in district" % buildings.size())
    
    building_placement_complete.emit(district_data.get("id", "unknown"), buildings.size())
    return buildings

func _find_suitable_building_position(district_bounds: Rect2i, existing_buildings: Array, rng: RandomNumberGenerator) -> Vector2i:
    """Find a suitable position for a building"""
    var max_attempts = 50
    var attempts = 0
    
    while attempts < max_attempts:
        var candidate_pos = Vector2i(
            rng.randi_range(district_bounds.position.x + 1, district_bounds.position.x + district_bounds.size.x - 2),
            rng.randi_range(district_bounds.position.y + 1, district_bounds.position.y + district_bounds.size.y - 2)
        )
        
        if _is_position_valid(candidate_pos, existing_buildings):
            return candidate_pos
        
        attempts += 1
    
    return Vector2i(-1, -1)  # No suitable position found

func _is_position_valid(position: Vector2i, existing_buildings: Array) -> bool:
    """Check if a position is valid for building placement"""
    var min_distance = 3  # Minimum distance between buildings
    
    for building in existing_buildings:
        var building_pos = building.position
        var distance = position.distance_to(building_pos)
        
        if distance < min_distance:
            return false
    
    return true

func _select_building_type(district_type: int, rng: RandomNumberGenerator) -> String:
    """Select building type based on district type"""
    match district_type:
        0: # Commercial
            var commercial_types = ["shop", "office", "restaurant", "bank"]
            return commercial_types[rng.randi() % commercial_types.size()]
        1: # Industrial
            var industrial_types = ["factory", "warehouse", "power_plant", "refinery"]
            return industrial_types[rng.randi() % industrial_types.size()]
        2: # Mixed
            var mixed_types = ["shop", "office", "factory", "warehouse", "apartment"]
            return mixed_types[rng.randi() % mixed_types.size()]
        3: # Residential
            var residential_types = ["house", "apartment", "townhouse"]
            return residential_types[rng.randi() % residential_types.size()]
        4: # Military
            var military_types = ["barracks", "command_center", "depot"]
            return military_types[rng.randi() % military_types.size()]
        _:
            return "generic"

func _select_building_size(district_type: int, rng: RandomNumberGenerator) -> Vector2i:
    """Select building size based on district type"""
    match district_type:
        0: # Commercial
            return Vector2i(rng.randi_range(2, 4), rng.randi_range(2, 4))
        1: # Industrial
            return Vector2i(rng.randi_range(3, 6), rng.randi_range(3, 6))
        2: # Mixed
            return Vector2i(rng.randi_range(2, 5), rng.randi_range(2, 5))
        3: # Residential
            return Vector2i(rng.randi_range(2, 3), rng.randi_range(2, 3))
        4: # Military
            return Vector2i(rng.randi_range(3, 5), rng.randi_range(3, 5))
        _:
            return Vector2i(2, 2)

func _select_building_asset(district_type: int, rng: RandomNumberGenerator) -> String:
    """Select building asset path based on district type"""
    match district_type:
        0: # Commercial
            var commercial_assets = ["building-a.glb", "building-b.glb", "building-c.glb"]
            return commercial_assets[rng.randi() % commercial_assets.size()]
        1: # Industrial
            var industrial_assets = ["building-factory-a.glb", "building-factory-b.glb", "building-warehouse.glb"]
            return industrial_assets[rng.randi() % industrial_assets.size()]
        2: # Mixed
            var mixed_assets = ["building-a.glb", "building-factory-a.glb", "building-apartment.glb"]
            return mixed_assets[rng.randi() % mixed_assets.size()]
        _:
            return "building-a.glb"

func validate_building_placement(position: Vector3, building_size: Vector2) -> bool:
    """Validate building can be placed without conflicts"""
    # Check if position is within bounds
    if position.x < 0 or position.z < 0:
        return false
    
    # Check if there's enough space
    var tile_pos = Vector2i(int(position.x), int(position.z))
    
    for x in range(building_size.x):
        for y in range(building_size.y):
            var check_pos = tile_pos + Vector2i(x, y)
            
            if tile_system and tile_system.has_method("is_tile_empty"):
                if not tile_system.is_tile_empty(check_pos):
                    return false
    
    return true

func select_building_asset(district_type: String, position: Vector3) -> PackedScene:
    """Select appropriate building asset based on context"""
    # This would integrate with the AssetLoader to get appropriate 3D models
    # For now, return null as placeholder
    return null

func get_building_placement_rules() -> Dictionary:
    """Get current building placement rules"""
    return placement_rules

func set_building_density(density: float) -> void:
    """Set building density (0.0 to 1.0)"""
    building_density = clamp(density, 0.0, 1.0)
    
    if logger:
        logger.info("BuildingPlacer", "Building density set to %.2f" % building_density)

func get_building_density() -> float:
    """Get current building density"""
    return building_density 