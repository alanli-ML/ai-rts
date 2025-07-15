# AssetDimensionManager.gd - Read and manage asset dimensions for procedural generation
class_name AssetDimensionManager
extends Node

# Dependencies
var logger
var asset_loader

# Asset dimension cache
var asset_dimensions: Dictionary = {}
var road_dimensions: Dictionary = {}
var building_dimensions: Dictionary = {}
var character_dimensions: Dictionary = {}

# Calculated tile size based on asset dimensions
var optimal_tile_size: float = 3.0
var road_tile_size: float = 3.0
var building_base_size: float = 3.0

# Signals
signal dimensions_analyzed()
signal tile_size_calculated(new_tile_size: float)

func _ready() -> void:
    pass

func setup(logger_instance, asset_loader_instance) -> void:
    """Setup the asset dimension manager with dependencies"""
    logger = logger_instance
    asset_loader = asset_loader_instance
    
    if logger:
        logger.info("AssetDimensionManager", "Asset dimension manager initialized")

func analyze_asset_dimensions() -> void:
    """Analyze dimensions of all loaded assets"""
    if not asset_loader:
        logger.warning("AssetDimensionManager", "Asset loader not available")
        return
    
    logger.info("AssetDimensionManager", "Analyzing asset dimensions...")
    
    # Analyze road asset dimensions
    await _analyze_road_dimensions()
    
    # Analyze building asset dimensions
    await _analyze_building_dimensions()
    
    # Analyze character asset dimensions
    await _analyze_character_dimensions()
    
    # Calculate optimal tile size based on asset dimensions
    _calculate_optimal_tile_size()
    
    dimensions_analyzed.emit()
    logger.info("AssetDimensionManager", "Asset dimension analysis complete")

func _analyze_road_dimensions() -> void:
    """Analyze road asset dimensions"""
    var road_categories = ["straight", "intersections", "curves", "specialized"]
    
    for category in road_categories:
        var sample_asset = asset_loader.get_random_road_asset(category)
        if sample_asset:
            var dimensions = await _get_asset_dimensions(sample_asset)
            road_dimensions[category] = dimensions
            
            if logger:
                logger.info("AssetDimensionManager", "Road %s dimensions: %s" % [category, dimensions])

func _analyze_building_dimensions() -> void:
    """Analyze building asset dimensions"""
    var building_types = ["commercial", "industrial", "office", "factory", "shop", "warehouse"]
    
    for building_type in building_types:
        var sample_asset = asset_loader.get_random_commercial_building() if building_type in ["commercial", "office", "shop"] else asset_loader.get_random_industrial_building()
        if sample_asset:
            var dimensions = await _get_asset_dimensions(sample_asset)
            building_dimensions[building_type] = dimensions
            
            if logger:
                logger.info("AssetDimensionManager", "Building %s dimensions: %s" % [building_type, dimensions])

func _analyze_character_dimensions() -> void:
    """Analyze character asset dimensions"""
    var sample_character = asset_loader.get_random_character()
    if sample_character:
        var dimensions = await _get_asset_dimensions(sample_character)
        character_dimensions["character"] = dimensions
        
        if logger:
            logger.info("AssetDimensionManager", "Character dimensions: %s" % dimensions)

func _get_asset_dimensions(asset: PackedScene) -> Dictionary:
    """Get actual dimensions of an asset by instantiating and measuring"""
    if not asset:
        return {"size": Vector3.ZERO, "error": "null_asset"}
    
    var instance = asset.instantiate()
    if not instance:
        return {"size": Vector3.ZERO, "error": "instantiation_failed"}
    
    # Add to the scene tree properly for accurate transforms
    var temp_parent = Node3D.new()
    temp_parent.name = "TempAssetMeasurement"
    add_child(temp_parent)
    temp_parent.add_child(instance)
    
    # Wait for the node to be properly initialized in the scene tree
    await get_tree().process_frame
    
    # Calculate AABB
    var aabb = _calculate_node_aabb(instance)
    
    # Cleanup
    temp_parent.queue_free()
    
    return {
        "size": aabb.size,
        "center": aabb.get_center(),
        "min": aabb.position,
        "max": aabb.end,
        "volume": aabb.get_volume()
    }

func _calculate_node_aabb(node: Node3D) -> AABB:
    """Calculate the AABB of a node and all its children"""
    var mesh_instances = []
    _collect_mesh_instances_recursive(node, mesh_instances)
    
    if mesh_instances.size() == 0:
        return AABB()
    
    var combined_aabb = AABB()
    var first_aabb = true
    
    for mesh_instance in mesh_instances:
        if mesh_instance.mesh:
            var mesh_aabb = mesh_instance.mesh.get_aabb()
            # Transform AABB to world space
            var world_aabb = mesh_instance.transform * mesh_aabb
            
            if first_aabb:
                combined_aabb = world_aabb
                first_aabb = false
            else:
                combined_aabb = combined_aabb.merge(world_aabb)
    
    return combined_aabb

func _collect_mesh_instances_recursive(node: Node3D, mesh_instances: Array) -> void:
    """Recursively collect all MeshInstance3D nodes"""
    if node is MeshInstance3D:
        var mesh_instance = node as MeshInstance3D
        if mesh_instance.mesh:
            mesh_instances.append(mesh_instance)
    
    # Recurse through children
    for child in node.get_children():
        if child is Node3D:
            _collect_mesh_instances_recursive(child, mesh_instances)

func _calculate_optimal_tile_size() -> void:
    """Calculate optimal tile size based on asset dimensions"""
    var road_sizes = []
    var building_sizes = []
    
    # Collect road sizes
    for category in road_dimensions.keys():
        var dimensions = road_dimensions[category]
        if dimensions.has("size"):
            var size = dimensions.size
            road_sizes.append(max(size.x, size.z))  # Use largest horizontal dimension
    
    # Collect building sizes
    for building_type in building_dimensions.keys():
        var dimensions = building_dimensions[building_type]
        if dimensions.has("size"):
            var size = dimensions.size
            building_sizes.append(max(size.x, size.z))  # Use largest horizontal dimension
    
    # Calculate optimal tile size
    if road_sizes.size() > 0:
        road_tile_size = _calculate_average(road_sizes)
    
    if building_sizes.size() > 0:
        building_base_size = _calculate_average(building_sizes)
    
    # Set optimal tile size with connectivity considerations
    # Kenny road assets are small (~0.5-1.0 units) but need larger tiles for proper connectivity
    var calculated_tile_size = road_tile_size if road_tile_size > 0 else 3.0
    
    # Apply minimum tile size for road connectivity (Kenny roads need at least 2.0 units spacing)
    var minimum_road_tile_size = 2.5  # Ensure proper road connectivity
    optimal_tile_size = max(calculated_tile_size, minimum_road_tile_size)
    
    # Round to reasonable precision
    optimal_tile_size = round(optimal_tile_size * 4.0) / 4.0  # Round to nearest 0.25
    
    if logger:
        logger.info("AssetDimensionManager", "Calculated optimal tile size: %.2f (road: %.2f, building: %.2f, minimum enforced: %.2f)" % [optimal_tile_size, road_tile_size, building_base_size, minimum_road_tile_size])
    
    tile_size_calculated.emit(optimal_tile_size)

func _calculate_average(values: Array) -> float:
    """Calculate average of array values"""
    if values.size() == 0:
        return 0.0
    
    var sum = 0.0
    for value in values:
        sum += value
    
    return sum / values.size()

func get_optimal_tile_size() -> float:
    """Get the calculated optimal tile size"""
    return optimal_tile_size

func get_road_tile_size() -> float:
    """Get the optimal road tile size"""
    return road_tile_size

func get_building_base_size() -> float:
    """Get the base building size"""
    return building_base_size

func get_asset_dimensions(asset_type: String, asset_subtype: String = "") -> Dictionary:
    """Get dimensions for a specific asset type"""
    match asset_type:
        "road":
            return road_dimensions.get(asset_subtype, {})
        "building":
            return building_dimensions.get(asset_subtype, {})
        "character":
            return character_dimensions.get("character", {})
        _:
            return {}

func calculate_building_tile_span(building_type: String) -> Vector2i:
    """Calculate how many tiles a building should span"""
    var building_dims = get_asset_dimensions("building", building_type)
    
    if building_dims.has("size"):
        var size = building_dims.size
        var tiles_x = int(ceil(size.x / optimal_tile_size))
        var tiles_z = int(ceil(size.z / optimal_tile_size))
        
        return Vector2i(max(tiles_x, 1), max(tiles_z, 1))
    
    return Vector2i(1, 1)  # Default to 1x1 tile

func calculate_optimal_asset_scale(asset_type: String, asset_subtype: String, target_tiles: Vector2i) -> Vector3:
    """Calculate optimal scale for an asset to fit in target tiles"""
    var asset_dims = get_asset_dimensions(asset_type, asset_subtype)
    
    if not asset_dims.has("size"):
        return Vector3.ONE  # Default scale
    
    var asset_size = asset_dims.size
    var target_size = Vector3(
        target_tiles.x * optimal_tile_size,
        asset_size.y,  # Keep original height
        target_tiles.y * optimal_tile_size
    )
    
    var scale = Vector3(
        target_size.x / asset_size.x if asset_size.x > 0 else 1.0,
        1.0,  # Keep original height scaling
        target_size.z / asset_size.z if asset_size.z > 0 else 1.0
    )
    
    return scale

func validate_asset_connectivity(position: Vector3, asset_type: String, asset_subtype: String) -> bool:
    """Validate that an asset at a position will connect properly with neighbors"""
    var asset_dims = get_asset_dimensions(asset_type, asset_subtype)
    
    if not asset_dims.has("size"):
        return true  # Can't validate, assume okay
    
    var asset_size = asset_dims.size
    var tile_pos = Vector2i(int(position.x / optimal_tile_size), int(position.z / optimal_tile_size))
    
    # Check if asset fits within tile boundaries
    var asset_bounds = Rect2(
        position.x - asset_size.x * 0.5,
        position.z - asset_size.z * 0.5,
        asset_size.x,
        asset_size.z
    )
    
    var tile_bounds = Rect2(
        tile_pos.x * optimal_tile_size,
        tile_pos.y * optimal_tile_size,
        optimal_tile_size,
        optimal_tile_size
    )
    
    return tile_bounds.encloses(asset_bounds)

func get_road_connection_points(road_type: String, position: Vector3, rotation: float) -> Array:
    """Get connection points for a road asset"""
    var road_dims = get_asset_dimensions("road", road_type)
    
    if not road_dims.has("size"):
        return []
    
    var size = road_dims.size
    var connection_points = []
    
    # Calculate connection points based on road type and rotation
    match road_type:
        "straight":
            # Two connection points at ends
            connection_points.append(position + Vector3(size.x * 0.5, 0, 0))
            connection_points.append(position + Vector3(-size.x * 0.5, 0, 0))
        "intersections":
            # Four connection points
            connection_points.append(position + Vector3(size.x * 0.5, 0, 0))
            connection_points.append(position + Vector3(-size.x * 0.5, 0, 0))
            connection_points.append(position + Vector3(0, 0, size.z * 0.5))
            connection_points.append(position + Vector3(0, 0, -size.z * 0.5))
        "curves":
            # Two connection points at curve ends
            connection_points.append(position + Vector3(size.x * 0.5, 0, 0))
            connection_points.append(position + Vector3(0, 0, size.z * 0.5))
    
    # Apply rotation to connection points
    for i in range(connection_points.size()):
        connection_points[i] = _rotate_point_around(connection_points[i], position, rotation)
    
    return connection_points

func _rotate_point_around(point: Vector3, center: Vector3, angle_degrees: float) -> Vector3:
    """Rotate a point around a center"""
    var angle_radians = deg_to_rad(angle_degrees)
    var cos_angle = cos(angle_radians)
    var sin_angle = sin(angle_radians)
    
    var relative = point - center
    var rotated = Vector3(
        relative.x * cos_angle - relative.z * sin_angle,
        relative.y,
        relative.x * sin_angle + relative.z * cos_angle
    )
    
    return center + rotated

func get_dimension_statistics() -> Dictionary:
    """Get statistics about analyzed dimensions"""
    return {
        "optimal_tile_size": optimal_tile_size,
        "road_tile_size": road_tile_size,
        "building_base_size": building_base_size,
        "road_types_analyzed": road_dimensions.keys(),
        "building_types_analyzed": building_dimensions.keys(),
        "character_analyzed": character_dimensions.has("character")
    } 