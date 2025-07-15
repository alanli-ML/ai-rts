# LODManager.gd - Level of Detail management for procedural generation
class_name LODManager
extends Node

# Dependencies
var logger

# LOD configuration
enum LODLevel {
    HIGH,    # Full detail - close districts
    MEDIUM,  # Reduced detail - mid-distance
    LOW      # Minimal detail - far districts
}

var lod_distances: Dictionary = {
    LODLevel.HIGH: 20.0,
    LODLevel.MEDIUM: 50.0,
    LODLevel.LOW: 100.0
}

var optimized_assets: Dictionary = {}

func _ready() -> void:
    pass

func setup(logger_ref) -> void:
    """Setup the LOD manager with dependencies"""
    logger = logger_ref
    
    if logger:
        logger.info("LODManager", "LOD management system initialized")

func optimize_map_data(map_data: Dictionary) -> void:
    """Apply LOD optimization to generated map data"""
    
    if logger:
        logger.info("LODManager", "Applying LOD optimization to map data")
    
    # Optimize districts
    _optimize_districts(map_data.get("districts", {}))
    
    # Optimize buildings
    _optimize_buildings(map_data.get("buildings", {}))
    
    # Optimize roads
    _optimize_roads(map_data.get("roads", {}))
    
    # Update metadata
    if "metadata" in map_data:
        map_data.metadata["lod_optimization"] = true
        map_data.metadata["lod_levels"] = LODLevel.values()
    
    if logger:
        logger.info("LODManager", "LOD optimization complete")

func _optimize_districts(districts: Dictionary) -> void:
    """Optimize districts for different LOD levels"""
    for district_id in districts.keys():
        var district_data = districts[district_id]
        
        # Create LOD variants for each district
        district_data["lod_variants"] = {
            LODLevel.HIGH: _create_high_lod_district(district_data),
            LODLevel.MEDIUM: _create_medium_lod_district(district_data),
            LODLevel.LOW: _create_low_lod_district(district_data)
        }

func _optimize_buildings(buildings: Dictionary) -> void:
    """Optimize buildings for different LOD levels"""
    for district_id in buildings.keys():
        var district_buildings = buildings[district_id]
        
        for building in district_buildings:
            building["lod_variants"] = {
                LODLevel.HIGH: _create_high_lod_building(building),
                LODLevel.MEDIUM: _create_medium_lod_building(building),
                LODLevel.LOW: _create_low_lod_building(building)
            }

func _optimize_roads(roads: Dictionary) -> void:
    """Optimize roads for different LOD levels"""
    var road_segments = roads.get("segments", [])
    
    for segment in road_segments:
        segment["lod_variants"] = {
            LODLevel.HIGH: _create_high_lod_road(segment),
            LODLevel.MEDIUM: _create_medium_lod_road(segment),
            LODLevel.LOW: _create_low_lod_road(segment)
        }

func _create_high_lod_district(district_data: Dictionary) -> Dictionary:
    """Create high detail version of district"""
    return {
        "detail_level": LODLevel.HIGH,
        "buildings": district_data.get("buildings", []),
        "roads": district_data.get("roads", []),
        "decorations": true,
        "lighting": true,
        "shadows": true
    }

func _create_medium_lod_district(district_data: Dictionary) -> Dictionary:
    """Create medium detail version of district"""
    var buildings = district_data.get("buildings", [])
    var filtered_buildings = []
    
    # Keep only larger buildings for medium LOD
    for building in buildings:
        var size = building.get("size", Vector2i(1, 1))
        if size.x >= 2 and size.y >= 2:
            filtered_buildings.append(building)
    
    return {
        "detail_level": LODLevel.MEDIUM,
        "buildings": filtered_buildings,
        "roads": district_data.get("roads", []),
        "decorations": false,
        "lighting": true,
        "shadows": false
    }

func _create_low_lod_district(district_data: Dictionary) -> Dictionary:
    """Create low detail version of district"""
    var buildings = district_data.get("buildings", [])
    var filtered_buildings = []
    
    # Keep only the largest buildings for low LOD
    for building in buildings:
        var size = building.get("size", Vector2i(1, 1))
        if size.x >= 3 and size.y >= 3:
            filtered_buildings.append(building)
    
    return {
        "detail_level": LODLevel.LOW,
        "buildings": filtered_buildings,
        "roads": [],  # No roads at low LOD
        "decorations": false,
        "lighting": false,
        "shadows": false
    }

func _create_high_lod_building(building: Dictionary) -> Dictionary:
    """Create high detail version of building"""
    return {
        "detail_level": LODLevel.HIGH,
        "asset_path": building.get("asset_path", ""),
        "full_geometry": true,
        "textures": true,
        "animations": true,
        "collision": true
    }

func _create_medium_lod_building(building: Dictionary) -> Dictionary:
    """Create medium detail version of building"""
    return {
        "detail_level": LODLevel.MEDIUM,
        "asset_path": building.get("asset_path", ""),
        "full_geometry": true,
        "textures": true,
        "animations": false,
        "collision": true
    }

func _create_low_lod_building(building: Dictionary) -> Dictionary:
    """Create low detail version of building"""
    return {
        "detail_level": LODLevel.LOW,
        "asset_path": _get_simplified_asset_path(building.get("asset_path", "")),
        "full_geometry": false,
        "textures": false,
        "animations": false,
        "collision": false
    }

func _create_high_lod_road(segment: Dictionary) -> Dictionary:
    """Create high detail version of road"""
    return {
        "detail_level": LODLevel.HIGH,
        "asset_path": segment.get("asset_type", "road_straight"),
        "full_geometry": true,
        "textures": true,
        "markings": true,
        "collision": true
    }

func _create_medium_lod_road(segment: Dictionary) -> Dictionary:
    """Create medium detail version of road"""
    return {
        "detail_level": LODLevel.MEDIUM,
        "asset_path": segment.get("asset_type", "road_straight"),
        "full_geometry": true,
        "textures": true,
        "markings": false,
        "collision": true
    }

func _create_low_lod_road(segment: Dictionary) -> Dictionary:
    """Create low detail version of road"""
    return {
        "detail_level": LODLevel.LOW,
        "asset_path": "road_simple",
        "full_geometry": false,
        "textures": false,
        "markings": false,
        "collision": false
    }

func _get_simplified_asset_path(original_path: String) -> String:
    """Get simplified asset path for low LOD"""
    # Convert detailed assets to simplified versions
    if original_path.contains("building-"):
        return "building-simple.glb"
    elif original_path.contains("factory-"):
        return "factory-simple.glb"
    else:
        return "generic-simple.glb"

func update_district_lod(district_id: String, camera_distance: float) -> LODLevel:
    """Dynamically adjust detail level based on distance"""
    var lod_level: LODLevel
    
    if camera_distance <= lod_distances[LODLevel.HIGH]:
        lod_level = LODLevel.HIGH
    elif camera_distance <= lod_distances[LODLevel.MEDIUM]:
        lod_level = LODLevel.MEDIUM
    else:
        lod_level = LODLevel.LOW
    
    if logger:
        logger.debug("LODManager", "District %s LOD level: %s (distance: %.1f)" % [district_id, LODLevel.keys()[lod_level], camera_distance])
    
    return lod_level

func create_lod_variants(building_asset: PackedScene) -> Dictionary:
    """Generate different detail levels for buildings"""
    var variants = {}
    
    if building_asset:
        # For now, just reference the same asset for all LOD levels
        # In a full implementation, this would generate actual reduced-detail versions
        variants[LODLevel.HIGH] = building_asset
        variants[LODLevel.MEDIUM] = building_asset
        variants[LODLevel.LOW] = building_asset
    
    return variants

func set_lod_distances(high: float, medium: float, low: float) -> void:
    """Set custom LOD distances"""
    lod_distances[LODLevel.HIGH] = high
    lod_distances[LODLevel.MEDIUM] = medium
    lod_distances[LODLevel.LOW] = low
    
    if logger:
        logger.info("LODManager", "LOD distances updated: High=%.1f, Medium=%.1f, Low=%.1f" % [high, medium, low])

func get_lod_distances() -> Dictionary:
    """Get current LOD distances"""
    return lod_distances

func get_optimized_asset_count() -> int:
    """Get number of optimized assets"""
    return optimized_assets.size()

func clear_optimized_assets() -> void:
    """Clear optimized asset cache"""
    optimized_assets.clear()
    
    if logger:
        logger.info("LODManager", "Optimized asset cache cleared") 