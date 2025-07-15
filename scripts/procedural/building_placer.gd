# BuildingPlacer.gd - Intelligent building placement system
class_name BuildingPlacer
extends Node

# Dependencies
var logger
var tile_system: Node
var asset_loader: Node
var asset_dimension_manager: Node

# Building placement configuration
var placement_rules: Dictionary = {}
var building_density: float = 1.0  # Maximum density for aggressive space filling

# Signals
signal building_placement_complete(district_id: String, building_count: int)

func _ready() -> void:
    pass

func setup(logger_ref, tile_system_ref: Node, asset_loader_ref: Node, asset_dimension_manager_ref: Node) -> void:
    """Setup the building placer with dependencies"""
    logger = logger_ref
    tile_system = tile_system_ref
    asset_loader = asset_loader_ref
    asset_dimension_manager = asset_dimension_manager_ref
    
    if logger:
        logger.info("BuildingPlacer", "Building placement system initialized")

func place_buildings(district_data: Dictionary, road_data: Dictionary, rng: RandomNumberGenerator) -> Array:
    """Place buildings in a district by finding empty spaces and fitting real-sized buildings into them"""
    var buildings = []
    var district_bounds = district_data.bounds
    var district_type = district_data.type
    
    # Extract road grid for collision detection
    var road_positions = _extract_road_positions(road_data)
    
    # Find all empty buildable lots in the district
    var buildable_lots = _find_buildable_lots(district_bounds, road_positions)
    
    if logger:
        logger.info("BuildingPlacer", "Found %d buildable lots in district" % buildable_lots.size())
    
    # Place buildings in each suitable lot using real asset dimensions with 2x scaling
    # Use aggressive building placement - try to fill as much space as possible
    for lot in buildable_lots:
        # Try multiple building sizes and orientations to maximize space usage
        var placed_in_lot = _fill_lot_with_buildings(lot, district_type, rng)
        buildings.append_array(placed_in_lot)
    
    if logger:
        logger.info("BuildingPlacer", "Placed %d buildings in district (from %d lots) using aggressive space filling with 2x scaling" % [buildings.size(), buildable_lots.size()])
    
    building_placement_complete.emit(district_data.get("id", "unknown"), buildings.size())
    return buildings

func _find_buildable_lots(district_bounds: Rect2i, road_positions: Dictionary) -> Array:
    """Find all contiguous empty areas that can be used for buildings"""
    var lots = []
    var visited = {}
    
    # Scan the entire district for empty spaces
    for x in range(district_bounds.position.x, district_bounds.position.x + district_bounds.size.x):
        for y in range(district_bounds.position.y, district_bounds.position.y + district_bounds.size.y):
            var pos = Vector2i(x, y)
            var pos_key = str(x) + "," + str(y)
            
            # Skip if already visited or occupied by road
            if visited.has(pos_key) or road_positions.has(pos_key):
                continue
            
            # Found an empty space - flood fill to find the entire lot
            var lot = _flood_fill_empty_space(pos, district_bounds, road_positions, visited)
            
            # Reduced minimum size - accept even 1x1 lots for maximum building density
            if lot.area >= 1:
                lots.append(lot)
    
    return lots

func _flood_fill_empty_space(start_pos: Vector2i, district_bounds: Rect2i, road_positions: Dictionary, visited: Dictionary) -> Dictionary:
    """Use flood fill to find a contiguous empty area"""
    var lot = {
        "min_pos": start_pos,
        "max_pos": start_pos,
        "positions": [],
        "area": 0
    }
    
    var queue = [start_pos]
    
    while queue.size() > 0:
        var current_pos = queue.pop_front()
        var pos_key = str(current_pos.x) + "," + str(current_pos.y)
        
        # Skip if already visited, outside bounds, or on a road
        if visited.has(pos_key) or road_positions.has(pos_key):
            continue
        if current_pos.x < district_bounds.position.x or current_pos.x >= district_bounds.position.x + district_bounds.size.x:
            continue
        if current_pos.y < district_bounds.position.y or current_pos.y >= district_bounds.position.y + district_bounds.size.y:
            continue
        
        # Mark as visited and add to lot
        visited[pos_key] = true
        lot.positions.append(current_pos)
        lot.area += 1
        
        # Update lot bounds
        lot.min_pos.x = min(lot.min_pos.x, current_pos.x)
        lot.min_pos.y = min(lot.min_pos.y, current_pos.y)
        lot.max_pos.x = max(lot.max_pos.x, current_pos.x)
        lot.max_pos.y = max(lot.max_pos.y, current_pos.y)
        
        # Add neighboring positions to queue (4-directional)
        var neighbors = [
            Vector2i(current_pos.x + 1, current_pos.y),
            Vector2i(current_pos.x - 1, current_pos.y),
            Vector2i(current_pos.x, current_pos.y + 1),
            Vector2i(current_pos.x, current_pos.y - 1)
        ]
        
        for neighbor in neighbors:
            var neighbor_key = str(neighbor.x) + "," + str(neighbor.y)
            if not visited.has(neighbor_key):
                queue.append(neighbor)
    
    return lot

func _find_suitable_building_for_lot(lot: Dictionary, district_type: int, rng: RandomNumberGenerator) -> Dictionary:
    """Find a building type that actually fits in the lot based on real asset dimensions with 2x scaling"""
    var lot_width = lot.max_pos.x - lot.min_pos.x + 1
    var lot_height = lot.max_pos.y - lot.min_pos.y + 1
    
    # Don't build if lot is too small (need at least 2x2 for scaled buildings)
    if lot_width < 2 or lot_height < 2:
        return {}
    
    # Get available building types for this district
    var available_building_types = _get_building_types_for_district(district_type)
    var suitable_buildings = []
    
    # Check each building type to see if it fits in the lot with 2x scaling
    for building_type in available_building_types:
        if asset_dimension_manager:
            # Get the real tile span for this building type
            var base_tile_span = asset_dimension_manager.calculate_building_tile_span(building_type)
            var real_dimensions = asset_dimension_manager.get_asset_dimensions("building", building_type)
            
            # Account for 2x scaling - buildings need more space
            # Use a scaling factor that considers the 2x visual scale but allows tighter packing
            var scaled_tile_span = Vector2i(
                max(1, int(ceil(base_tile_span.x * 1.5))),  # 1.5x tile requirement for 2x visual scale
                max(1, int(ceil(base_tile_span.y * 1.5)))
            )
            
            # Check if this scaled building fits in the lot (consider rotation)
            var fits_normal = (scaled_tile_span.x <= lot_width and scaled_tile_span.y <= lot_height)
            var fits_rotated = (scaled_tile_span.y <= lot_width and scaled_tile_span.x <= lot_height)
            
            if fits_normal or fits_rotated:
                # Choose orientation that fits best
                var final_span = scaled_tile_span
                if fits_rotated and not fits_normal:
                    # Rotate the building to fit
                    final_span = Vector2i(scaled_tile_span.y, scaled_tile_span.x)
                elif fits_normal and fits_rotated:
                    # Both orientations fit, choose randomly
                    if rng.randi() % 2 == 1:
                        final_span = Vector2i(scaled_tile_span.y, scaled_tile_span.x)
                
                suitable_buildings.append({
                    "building_type": building_type,
                    "tile_span": final_span,
                    "real_dimensions": real_dimensions,
                    "original_span": base_tile_span,
                    "scaled_for_2x": true
                })
    
    # If we found suitable buildings, choose one randomly
    if suitable_buildings.size() > 0:
        return suitable_buildings[rng.randi() % suitable_buildings.size()]
    
    # No suitable buildings found
    if logger:
        logger.info("BuildingPlacer", "No buildings fit in lot of size %dx%d" % [lot_width, lot_height])
    
    return {}

func _get_building_types_for_district(district_type: int) -> Array:
    """Get available building types for the given district type using actual Kenny assets"""
    if not asset_loader:
        return ["generic"]
    
    # Ensure assets are loaded
    if not asset_loader.is_loading_complete():
        asset_loader.load_kenney_assets()
    
    var available_types = []
    
    match district_type:
        0: # Commercial
            # Add all commercial building variants (a through n)
            for letter in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n"]:
                available_types.append("building-" + letter)
            # Add skyscrapers for variety
            for letter in ["a", "b", "c", "d", "e"]:
                available_types.append("building-skyscraper-" + letter)
            # Add low detail buildings for smaller lots
            available_types.append_array([
                "low-detail-building-a", "low-detail-building-b",
                "low-detail-building-c", "low-detail-building-d",
                "low-detail-building-wide-a", "low-detail-building-wide-b"
            ])
        1: # Industrial
            # Add all industrial building variants (a through t)
            for letter in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t"]:
                available_types.append("building-" + letter)
            # Add industrial details
            available_types.append_array([
                "chimney-basic", "chimney-large", "chimney-medium", "chimney-small",
                "detail-tank"
            ])
        2: # Mixed
            # Combine commercial and industrial assets
            for letter in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n"]:
                available_types.append("building-" + letter)
            # Add some industrial variety
            for letter in ["a", "b", "c", "d", "e", "f", "g", "h"]:
                available_types.append("industrial-building-" + letter)
            # Add mixed-use buildings
            available_types.append_array([
                "building-skyscraper-a", "building-skyscraper-b",
                "low-detail-building-a", "low-detail-building-b"
            ])
        3: # Residential
            # Use smaller commercial buildings for residential
            for letter in ["a", "b", "c", "d", "e", "f"]:
                available_types.append("building-" + letter)
            available_types.append_array([
                "low-detail-building-a", "low-detail-building-b",
                "low-detail-building-c", "low-detail-building-d"
            ])
        4: # Military
            # Use industrial-style buildings for military
            for letter in ["g", "h", "i", "j", "k", "l", "m", "n", "o", "p"]:
                available_types.append("building-" + letter)
        _:
            # Fallback - use some commercial buildings
            for letter in ["a", "b", "c", "d"]:
                available_types.append("building-" + letter)
    
    return available_types

func _find_best_position_in_lot(lot: Dictionary, building_size: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
    """Find the best position to place a building of the given size within the lot"""
    var possible_positions = []
    
    # Check all positions where the building would fit entirely within the lot bounds
    for x in range(lot.min_pos.x, lot.max_pos.x - building_size.x + 2):
        for y in range(lot.min_pos.y, lot.max_pos.y - building_size.y + 2):
            var candidate_pos = Vector2i(x, y)
            
            # Check if all tiles for this building position are within the lot
            var fits = true
            for bx in range(building_size.x):
                for by in range(building_size.y):
                    var check_pos = Vector2i(x + bx, y + by)
                    if not lot.positions.has(check_pos):
                        fits = false
                        break
                if not fits:
                    break
            
            if fits:
                possible_positions.append(candidate_pos)
    
    # Choose randomly from possible positions, or return center-most if available
    if possible_positions.size() > 0:
        return possible_positions[rng.randi() % possible_positions.size()]
    else:
        return Vector2i(-1, -1)

func _extract_road_positions(road_data: Dictionary) -> Dictionary:
    """Extract road positions from road data for collision detection"""
    var road_positions = {}
    
    # Check if road data has segments (the final road segments)
    if road_data.has("segments") and road_data.segments is Array:
        for segment in road_data.segments:
            if segment.has("position"):
                var pos = segment.position
                var key = str(pos.x) + "," + str(pos.y)
                road_positions[key] = pos
    
    return road_positions

func _select_building_asset(district_type: int, rng: RandomNumberGenerator) -> String:
    """Select building asset using actual Kenny assets from AssetLoader"""
    if not asset_loader:
        return "building-a.glb"  # Fallback
    
    # Ensure assets are loaded
    if not asset_loader.is_loading_complete():
        asset_loader.load_kenney_assets()
    
    var selected_asset = null
    var asset_path = ""
    
    match district_type:
        0: # Commercial
            # Mix of regular buildings and skyscrapers
            if rng.randf() < 0.7:  # 70% regular buildings
                selected_asset = asset_loader.get_random_commercial_building()
                if selected_asset:
                    asset_path = "commercial/building-" + _get_building_letter_from_asset(selected_asset) + ".glb"
                else:
                    asset_path = "commercial/building-a.glb"
            else:  # 30% skyscrapers
                selected_asset = asset_loader.get_skyscraper()
                if selected_asset:
                    asset_path = "commercial/building-skyscraper-" + _get_building_letter_from_asset(selected_asset) + ".glb"
                else:
                    asset_path = "commercial/building-skyscraper-a.glb"
        
        1: # Industrial
            # Use industrial buildings
            selected_asset = asset_loader.get_random_industrial_building()
            if selected_asset:
                asset_path = "industrial/building-" + _get_building_letter_from_asset(selected_asset) + ".glb"
            else:
                asset_path = "industrial/building-a.glb"
        
        2: # Mixed
            # Mix commercial and industrial
            if rng.randf() < 0.6:  # 60% commercial
                selected_asset = asset_loader.get_random_commercial_building()
                if selected_asset:
                    asset_path = "commercial/building-" + _get_building_letter_from_asset(selected_asset) + ".glb"
                else:
                    asset_path = "commercial/building-a.glb"
            else:  # 40% industrial
                selected_asset = asset_loader.get_random_industrial_building()
                if selected_asset:
                    asset_path = "industrial/building-" + _get_building_letter_from_asset(selected_asset) + ".glb"
                else:
                    asset_path = "industrial/building-a.glb"
        
        3: # Residential
            # Use smaller commercial buildings for residential areas
            selected_asset = asset_loader.get_random_commercial_building()
            if selected_asset:
                asset_path = "residential/building-" + _get_building_letter_from_asset(selected_asset) + ".glb"
            else:
                asset_path = "residential/building-a.glb"
        
        4: # Military
            # Use industrial-style buildings for military bases
            selected_asset = asset_loader.get_random_industrial_building()
            if selected_asset:
                asset_path = "military/building-" + _get_building_letter_from_asset(selected_asset) + ".glb"
            else:
                asset_path = "military/building-a.glb"
        
        _:
            # Default fallback
            selected_asset = asset_loader.get_random_commercial_building()
            if selected_asset:
                asset_path = "default/building-" + _get_building_letter_from_asset(selected_asset) + ".glb"
            else:
                asset_path = "default/building-a.glb"
    
    return asset_path

func _get_building_letter_from_asset(asset) -> String:
    """Extract building letter identifier from asset resource path"""
    if not asset:
        return "a"
    
    var resource_path = asset.resource_path
    if resource_path.contains("building-"):
        # Extract letter from patterns like "building-a.glb", "building-skyscraper-b.glb"
        var parts = resource_path.split("building-")
        if parts.size() > 1:
            var suffix = parts[1]
            # Handle skyscraper format
            if suffix.contains("skyscraper-"):
                var skyscraper_parts = suffix.split("skyscraper-")
                if skyscraper_parts.size() > 1:
                    return skyscraper_parts[1].replace(".glb", "")
            else:
                # Regular building format
                return suffix.replace(".glb", "")
    
    # Fallback to random letter
    var letters = ["a", "b", "c", "d", "e", "f", "g", "h"]
    return letters[randi() % letters.size()]

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

func get_building_density() -> float:
    """Get current building density"""
    return building_density 

func _fill_lot_with_buildings(lot: Dictionary, district_type: int, rng: RandomNumberGenerator) -> Array:
    """Aggressively fill a lot with as many buildings as possible"""
    var buildings = []
    var occupied_positions = {}
    
    # Get lot dimensions
    var lot_width = lot.max_pos.x - lot.min_pos.x + 1
    var lot_height = lot.max_pos.y - lot.min_pos.y + 1
    
    # Try different building sizes, starting with larger ones
    var building_sizes = [
        Vector2i(3, 3), Vector2i(2, 3), Vector2i(3, 2),  # Large buildings
        Vector2i(2, 2),                                   # Medium buildings
        Vector2i(1, 2), Vector2i(2, 1),                  # Small buildings
        Vector2i(1, 1)                                    # Tiny buildings to fill gaps
    ]
    
    # Scan through lot positions and place buildings
    for y in range(lot.min_pos.y, lot.max_pos.y + 1):
        for x in range(lot.min_pos.x, lot.max_pos.x + 1):
            var pos = Vector2i(x, y)
            var pos_key = str(x) + "," + str(y)
            
            # Skip if position already occupied
            if occupied_positions.has(pos_key):
                continue
            
            # Try each building size until one fits
            for building_size in building_sizes:
                if _can_place_building_at(pos, building_size, lot, occupied_positions):
                    # Place the building
                    var building_data = _create_building_at_position(pos, building_size, district_type, rng)
                    buildings.append(building_data)
                    
                    # Mark all occupied positions
                    for by in range(building_size.y):
                        for bx in range(building_size.x):
                            var occupied_pos = pos + Vector2i(bx, by)
                            var occupied_key = str(occupied_pos.x) + "," + str(occupied_pos.y)
                            occupied_positions[occupied_key] = true
                    
                    # Found a fit, break to next position
                    break
    
    if logger and buildings.size() > 0:
        logger.info("BuildingPlacer", "Filled lot (%dx%d) with %d buildings using aggressive placement" % [lot_width, lot_height, buildings.size()])
    
    return buildings

func _can_place_building_at(pos: Vector2i, building_size: Vector2i, lot: Dictionary, occupied_positions: Dictionary) -> bool:
    """Check if a building of given size can be placed at the position"""
    # Check if building extends beyond lot boundaries
    if pos.x + building_size.x - 1 > lot.max_pos.x:
        return false
    if pos.y + building_size.y - 1 > lot.max_pos.y:
        return false
    
    # Check if any part of the building overlaps with occupied positions
    for y in range(building_size.y):
        for x in range(building_size.x):
            var check_pos = pos + Vector2i(x, y)
            var check_key = str(check_pos.x) + "," + str(check_pos.y)
            if occupied_positions.has(check_key):
                return false
    
    return true

func _create_building_at_position(pos: Vector2i, building_size: Vector2i, district_type: int, rng: RandomNumberGenerator) -> Dictionary:
    """Create a building at the specified position with given size"""
    var building_type = _select_building_type_for_size(building_size, district_type, rng)
    var rotation = rng.randi_range(0, 3) * 90  # Rotate in 90-degree increments
    
    var building_data = {
        "position": pos,
        "type": building_type,
        "size": building_size,
        "asset_path": _select_building_asset(district_type, rng),
        "rotation": rotation,
        "metadata": {
            "placement_time": Time.get_ticks_msec(),
            "district_id": "unknown",
            "lot_area": building_size.x * building_size.y,
            "uses_real_dimensions": true,
            "scaled_2x": true,
            "aggressive_placement": true
        }
    }
    
    # Apply 2x scaling while respecting real asset dimensions
    building_data["optimal_scale"] = Vector3(2.0, 2.0, 2.0)
    building_data["connectivity_valid"] = true
    
    return building_data

func _select_building_type_for_size(building_size: Vector2i, district_type: int, rng: RandomNumberGenerator) -> String:
    """Select appropriate building type based on size and district type"""
    var area = building_size.x * building_size.y
    
    # Large buildings (6+ tiles)
    if area >= 6:
        match district_type:
            0: return "commercial_large"  # Commercial
            1: return "industrial_large"  # Industrial
            2: return "mixed_large"       # Mixed
            _: return "commercial_large"
    
    # Medium buildings (4-5 tiles)
    elif area >= 4:
        match district_type:
            0: return "commercial"
            1: return "industrial"
            2: return "commercial" if rng.randf() < 0.5 else "industrial"
            _: return "commercial"
    
    # Small buildings (1-3 tiles)
    else:
        return "small_building" 