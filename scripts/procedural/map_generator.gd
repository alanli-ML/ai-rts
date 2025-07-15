# MapGenerator.gd - Server-sided procedural map generation system
class_name MapGenerator
extends Node

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Component dependencies
var logger
var asset_loader: Node
var asset_dimension_manager: Node
var tile_system: Node
var district_generator: Node
var road_network: Node
var building_placer: Node
var lod_manager: Node

# Map generation state
var map_seed: int = 0
var generation_progress: float = 0.0
var is_generating: bool = false
var generated_map_data: Dictionary = {}

# Map configuration
const MAP_SIZE: Vector2i = Vector2i(60, 60)  # 60x60 tile grid (3x expansion from 20x20)
var dynamic_tile_size: float = 3.0  # Dynamic tile size based on assets
const DISTRICT_SIZE: int = 18  # 18x18 tiles per district (3x expansion from 6x6)
const CONTROL_POINT_COUNT: int = 25  # 25 control points in 5x5 grid (was 9 in 3x3)

# District types for variety
enum DistrictType {
    COMMERCIAL,
    INDUSTRIAL,
    MIXED,
    RESIDENTIAL,
    MILITARY
}

# Signals
signal map_generation_started(seed: int)
signal map_generation_progress(progress: float)
signal map_generation_complete(map_data: Dictionary)
signal district_generated(district_id: String, district_data: Dictionary)

func _ready() -> void:
    # Initialize components will be done via dependency injection
    pass

func setup(logger_ref, asset_loader_ref) -> void:
    """Setup the MapGenerator with dependencies"""
    logger = logger_ref
    asset_loader = asset_loader_ref
    
    # Initialize sub-systems
    _initialize_subsystems()
    
    # Connect to asset dimension analysis completion
    if asset_dimension_manager:
        asset_dimension_manager.dimensions_analyzed.connect(_on_asset_dimensions_analyzed)
    
    if logger:
        logger.info("MapGenerator", "Map generation system initialized")

func _initialize_subsystems() -> void:
    """Initialize all procedural generation subsystems"""
    
    # Create asset dimension manager
    var AssetDimensionManagerClass = preload("res://scripts/procedural/asset_dimension_manager.gd")
    asset_dimension_manager = AssetDimensionManagerClass.new()
    asset_dimension_manager.name = "AssetDimensionManager"
    asset_dimension_manager.setup(logger, asset_loader)
    add_child(asset_dimension_manager)
    
    # Start asset dimension analysis in the background
    asset_dimension_manager.analyze_asset_dimensions()
    
    # Use default tile size for now, will be updated after analysis
    dynamic_tile_size = 3.0  # Default fallback
    
    # Create tile system with initial tile size
    var TileSystemClass = preload("res://scripts/procedural/tile_system.gd")
    tile_system = TileSystemClass.new()
    tile_system.name = "TileSystem"
    tile_system.setup(logger, MAP_SIZE, dynamic_tile_size)
    add_child(tile_system)
    
    # Create district generator
    var DistrictGeneratorClass = preload("res://scripts/procedural/district_generator.gd")
    district_generator = DistrictGeneratorClass.new()
    district_generator.name = "DistrictGenerator"
    district_generator.setup(logger, tile_system, asset_loader, asset_dimension_manager)
    add_child(district_generator)
    
    # Create road network generator
    var RoadNetworkClass = preload("res://scripts/procedural/road_network.gd")
    road_network = RoadNetworkClass.new()
    road_network.name = "RoadNetwork"
    road_network.setup(logger, tile_system, asset_loader, asset_dimension_manager)
    add_child(road_network)
    
    # Create building placer
    var BuildingPlacerClass = preload("res://scripts/procedural/building_placer.gd")
    building_placer = BuildingPlacerClass.new()
    building_placer.name = "BuildingPlacer"
    building_placer.setup(logger, tile_system, asset_loader, asset_dimension_manager)
    add_child(building_placer)
    
    # Create LOD manager
    var LODManagerClass = preload("res://scripts/procedural/lod_manager.gd")
    lod_manager = LODManagerClass.new()
    lod_manager.name = "LODManager"
    lod_manager.setup(logger)
    add_child(lod_manager)
    
    # Connect signals
    district_generator.district_generated.connect(_on_district_generated)
    road_network.road_network_complete.connect(_on_road_network_complete)
    building_placer.building_placement_complete.connect(_on_building_placement_complete)

func generate_map(seed: int = 0, control_points: Array = []) -> Dictionary:
    """Generate a complete procedural map"""
    
    if is_generating:
        logger.warning("MapGenerator", "Map generation already in progress")
        return {}
    
    is_generating = true
    map_seed = seed if seed != 0 else randi()
    generation_progress = 0.0
    
    logger.info("MapGenerator", "Starting map generation with seed: %d" % map_seed)
    map_generation_started.emit(map_seed)
    
    # Set random seed for deterministic generation
    var rng = RandomNumberGenerator.new()
    rng.seed = map_seed
    
    # Initialize map data structure
    generated_map_data = {
        "seed": map_seed,
        "size": MAP_SIZE,
        "tile_size": dynamic_tile_size,
        "districts": {},
        "roads": {},
        "buildings": {},
        "control_points": {},
        "spawn_points": {},
        "metadata": {
            "generation_time": Time.get_ticks_msec(),
            "version": "1.0",
            "asset_dimensions": asset_dimension_manager.get_dimension_statistics()
        }
    }
    
    # Phase 1: Initialize grid system
    _update_progress(0.1, "Initializing tile system...")
    tile_system.initialize_grid()
    
    # Phase 2: Generate control point positions
    _update_progress(0.2, "Generating control points...")
    var control_point_positions = _generate_control_point_positions(rng)
    
    # Phase 3: Generate districts around control points
    _update_progress(0.3, "Generating districts...")
    await _generate_districts(control_point_positions, rng)
    
    # Phase 4: Generate road network
    _update_progress(0.5, "Generating road network...")
    await _generate_road_network(control_point_positions, rng)
    
    # Phase 5: Place buildings
    _update_progress(0.7, "Placing buildings...")
    await _place_buildings(rng)
    
    # Phase 6: Generate unit spawn points
    _update_progress(0.8, "Generating spawn points...")
    _generate_spawn_points(rng)
    
    # Phase 7: Apply LOD optimization
    _update_progress(0.9, "Applying LOD optimization...")
    _apply_lod_optimization()
    
    # Phase 8: Finalize map data
    _update_progress(1.0, "Finalizing map data...")
    _finalize_map_data()
    
    is_generating = false
    logger.info("MapGenerator", "Map generation complete")
    map_generation_complete.emit(generated_map_data)
    
    return generated_map_data

func _generate_control_point_positions(rng: RandomNumberGenerator) -> Array:
    """Generate positions for control points in a 5x5 grid with slight randomization"""
    var positions: Array = []
    var grid_spacing = MAP_SIZE.x / 6  # Spacing between control points (divide by 6 for 5x5 grid)
    var center_offset = Vector2i(MAP_SIZE.x / 2, MAP_SIZE.y / 2)
    
    for i in range(5):  # 5x5 grid instead of 3x3
        for j in range(5):
            var base_pos = Vector2i(
                center_offset.x + (i - 2) * grid_spacing,  # Center around -2 to +2
                center_offset.y + (j - 2) * grid_spacing
            )
            
            # Add slight randomization while keeping grid structure
            var random_offset = Vector2i(
                rng.randi_range(-3, 3),  # Slightly larger randomization for bigger map
                rng.randi_range(-3, 3)
            )
            
            var final_pos = base_pos + random_offset
            
            # Ensure position is within bounds
            final_pos.x = clamp(final_pos.x, 5, MAP_SIZE.x - 5)  # Larger buffer for bigger map
            final_pos.y = clamp(final_pos.y, 5, MAP_SIZE.y - 5)
            
            positions.append(final_pos)
    
    return positions

func _generate_districts(control_point_positions: Array, rng: RandomNumberGenerator) -> void:
    """Generate districts around each control point"""
    
    for i in range(control_point_positions.size()):
        var position = control_point_positions[i]
        var district_type = _select_district_type(i, rng)
        
        var district_data = district_generator.generate_district(
            position,
            district_type,
            DISTRICT_SIZE,
            rng
        )
        
        generated_map_data.districts["district_%d" % i] = district_data
        generated_map_data.control_points["cp_%d" % i] = {
            "position": position,
            "district_type": district_type,
            "strategic_value": _calculate_strategic_value(position, district_type)
        }
        
        # Emit signal for progress tracking
        district_generated.emit("district_%d" % i, district_data)
        
        # Small delay to prevent frame drops
        await get_tree().process_frame

func _select_district_type(index: int, rng: RandomNumberGenerator) -> DistrictType:
    """Select district type based on position and randomization for 5x5 grid"""
    
    # Central district (index 12 in 5x5 grid) is always mixed for balance
    if index == 12:  # Center of 5x5 grid (2,2 position)
        return DistrictType.MIXED
    
    # Corner districts favor industrial (0,0), (0,4), (4,0), (4,4)
    if index in [0, 4, 20, 24]:  # Corners of 5x5 grid
        return DistrictType.INDUSTRIAL if rng.randf() < 0.6 else DistrictType.COMMERCIAL
    
    # Edge districts (first/last row/column but not corners) favor commercial
    var row = index / 5
    var col = index % 5
    var is_edge = (row == 0 or row == 4 or col == 0 or col == 4) and index != 12
    var is_corner = index in [0, 4, 20, 24]
    
    if is_edge and not is_corner:
        return DistrictType.COMMERCIAL if rng.randf() < 0.6 else DistrictType.MIXED
    
    # Inner districts favor mixed development
    if abs(row - 2) <= 1 and abs(col - 2) <= 1:  # Districts close to center
        return DistrictType.MIXED if rng.randf() < 0.5 else DistrictType.COMMERCIAL
    
    # Default to mixed for remaining districts
    return DistrictType.MIXED

func _calculate_strategic_value(position: Vector2i, district_type: DistrictType) -> int:
    """Calculate strategic value based on position and type for expanded map"""
    var base_value = 1
    
    # Center positions are more valuable
    var center = Vector2i(MAP_SIZE.x / 2, MAP_SIZE.y / 2)
    var distance_from_center = position.distance_to(center)
    
    # Adjust thresholds for larger map (3x scale)
    if distance_from_center < 9:  # Was 3, now 9 for 3x map
        base_value = 3  # Center districts
    elif distance_from_center < 18:  # Was 6, now 18 for 3x map
        base_value = 2  # Adjacent to center
    else:
        base_value = 1  # Edge districts
    
    # District type modifiers
    match district_type:
        DistrictType.INDUSTRIAL:
            base_value += 1  # Industrial districts provide more resources
        DistrictType.MIXED:
            base_value += 2  # Mixed districts are most valuable
        DistrictType.COMMERCIAL:
            base_value += 0  # Commercial districts are standard
    
    return base_value

func _generate_road_network(control_point_positions: Array, rng: RandomNumberGenerator) -> void:
    """Generate road network connecting districts"""
    
    var road_data = road_network.generate_network(
        control_point_positions,
        generated_map_data.districts,
        rng
    )
    
    generated_map_data.roads = road_data
    await get_tree().process_frame

func _place_buildings(rng: RandomNumberGenerator) -> void:
    """Place buildings in each district"""
    
    for district_id in generated_map_data.districts.keys():
        var district_data = generated_map_data.districts[district_id]
        
        var building_data = building_placer.place_buildings(
            district_data,
            generated_map_data.roads,
            rng
        )
        
        generated_map_data.buildings[district_id] = building_data
        await get_tree().process_frame

func _generate_spawn_points(rng: RandomNumberGenerator) -> void:
    """Generate unit spawn points near appropriate buildings for 5x5 grid"""
    
    var spawn_points = {
        "team_1": [],
        "team_2": []
    }
    
    # Find suitable spawn locations in different districts for 5x5 grid
    # Team 1: Left side and top-left corner districts (indices 0,1,2,5,10,15,20,21,22)
    var team_1_districts = [0, 1, 2, 5, 10, 15, 20, 21, 22]  # Left side of 5x5 grid
    # Team 2: Right side and bottom-right corner districts (indices 2,3,4,9,14,19,22,23,24)
    var team_2_districts = [2, 3, 4, 9, 14, 19, 22, 23, 24]  # Right side of 5x5 grid
    
    for team_district in team_1_districts:
        if team_district < 25:  # Ensure valid district index for 5x5 grid
            var district_key = "district_%d" % team_district
            if district_key in generated_map_data.districts:
                var district_data = generated_map_data.districts[district_key]
                var spawn_pos = _find_spawn_position_in_district(district_data, rng)
                spawn_points.team_1.append(spawn_pos)
    
    for team_district in team_2_districts:
        if team_district < 25:  # Ensure valid district index for 5x5 grid
            var district_key = "district_%d" % team_district
            if district_key in generated_map_data.districts:
                var district_data = generated_map_data.districts[district_key]
                var spawn_pos = _find_spawn_position_in_district(district_data, rng)
                spawn_points.team_2.append(spawn_pos)
    
    generated_map_data.spawn_points = spawn_points

func _find_spawn_position_in_district(district_data: Dictionary, rng: RandomNumberGenerator) -> Vector3:
    """Find a suitable spawn position within a district"""
    
    if "buildings" in district_data and district_data.buildings.size() > 0:
        # Spawn near a building
        var random_building = district_data.buildings[rng.randi() % district_data.buildings.size()]
        var building_pos = random_building.position
        return Vector3(building_pos.x * dynamic_tile_size, 0, building_pos.y * dynamic_tile_size) + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
    else:
        # Spawn in district center
        return Vector3(district_data.center.x * dynamic_tile_size, 0, district_data.center.y * dynamic_tile_size)

func _apply_lod_optimization() -> void:
    """Apply LOD optimization to generated content"""
    
    if lod_manager:
        lod_manager.optimize_map_data(generated_map_data)

func _finalize_map_data() -> void:
    """Finalize map data with metadata"""
    
    generated_map_data.metadata.generation_time = Time.get_ticks_msec() - generated_map_data.metadata.generation_time
    generated_map_data.metadata.districts_count = generated_map_data.districts.size()
    generated_map_data.metadata.buildings_count = 0
    
    # Count total buildings
    for district_buildings in generated_map_data.buildings.values():
        generated_map_data.metadata.buildings_count += district_buildings.size()

func _update_progress(progress: float, status: String) -> void:
    """Update generation progress"""
    generation_progress = progress
    map_generation_progress.emit(progress)
    
    if logger:
        logger.info("MapGenerator", "Generation progress: %.1f%% - %s" % [progress * 100, status])

func get_map_data() -> Dictionary:
    """Get the current generated map data"""
    return generated_map_data

func is_map_generated() -> bool:
    """Check if map has been generated"""
    return not generated_map_data.is_empty()

func get_generation_progress() -> float:
    """Get current generation progress"""
    return generation_progress

func _on_asset_dimensions_analyzed() -> void:
    """Called when asset dimension analysis is complete"""
    if asset_dimension_manager:
        var new_tile_size = asset_dimension_manager.get_optimal_tile_size()
        if new_tile_size != dynamic_tile_size:
            dynamic_tile_size = new_tile_size
            
            # Update tile system with new tile size
            if tile_system:
                tile_system.tile_size = dynamic_tile_size
                
                if logger:
                    logger.info("MapGenerator", "Updated tile size to %.2f based on asset dimensions" % dynamic_tile_size)
            
            # Update already generated map data if available
            if not generated_map_data.is_empty():
                generated_map_data["tile_size"] = dynamic_tile_size
                
                if logger:
                    logger.info("MapGenerator", "Updated generated map data with new tile size")

# Signal handlers
func _on_district_generated(district_id: String, district_data: Dictionary) -> void:
    """Handle district generation completion"""
    if logger:
        logger.debug("MapGenerator", "District %s generated with %d buildings" % [district_id, district_data.get("buildings", []).size()])

func _on_road_network_complete(road_data: Dictionary) -> void:
    """Handle road network generation completion"""
    if logger:
        logger.debug("MapGenerator", "Road network generated with %d segments" % road_data.get("segments", []).size())

func _on_building_placement_complete(district_id: String, building_count: int) -> void:
    """Handle building placement completion"""
    if logger:
        logger.debug("MapGenerator", "Building placement complete for %s: %d buildings" % [district_id, building_count])

# Utility functions
func world_to_tile(world_pos: Vector3) -> Vector2i:
    """Convert world position to tile coordinates"""
    if tile_system:
        return tile_system.world_to_tile(world_pos)
    return Vector2i.ZERO

func tile_to_world(tile_pos: Vector2i) -> Vector3:
    """Convert tile coordinates to world position"""
    if tile_system:
        return tile_system.tile_to_world(tile_pos)
    return Vector3.ZERO

func get_district_at_position(world_pos: Vector3) -> String:
    """Get district ID at world position"""
    var tile_pos = world_to_tile(world_pos)
    
    for district_id in generated_map_data.districts.keys():
        var district_data = generated_map_data.districts[district_id]
        var district_bounds = district_data.get("bounds", Rect2i())
        
        if district_bounds.has_point(tile_pos):
            return district_id
    
    return ""

func get_buildings_in_district(district_id: String) -> Array:
    """Get all buildings in a specific district"""
    return generated_map_data.buildings.get(district_id, [])

func get_roads_in_district(district_id: String) -> Array:
    """Get all roads in a specific district"""
    var district_roads = []
    
    for road_segment in generated_map_data.roads.get("segments", []):
        if road_segment.get("district_id") == district_id:
            district_roads.append(road_segment)
    
    return district_roads 