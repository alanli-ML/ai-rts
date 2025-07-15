# WorldAssetManager.gd - Handle asset loading for the 3D world
class_name WorldAssetManager
extends Node

# Dependencies
var logger
var asset_loader

# Signals
signal assets_ready()

func _ready() -> void:
    # Initialize when added to scene tree
    pass

func setup(logger_instance, asset_loader_instance) -> void:
    """Setup the world asset manager with dependencies"""
    logger = logger_instance
    asset_loader = asset_loader_instance
    
    if not asset_loader:
        logger.warning("WorldAssetManager", "Asset loader not available - will use fallback rendering")
    else:
        logger.info("WorldAssetManager", "Asset loader connected successfully")
        
        # Ensure Kenney assets are loaded
        if not asset_loader.is_loading_complete():
            logger.info("WorldAssetManager", "Loading Kenney assets...")
            asset_loader.load_kenney_assets()
            logger.info("WorldAssetManager", "Kenney assets loaded")
    
    assets_ready.emit()
    logger.info("WorldAssetManager", "World asset manager setup complete")

func load_building_asset_by_type(building_type: String) -> PackedScene:
    """Load a building asset based on specific type using all available Kenny assets"""
    if not asset_loader:
        logger.warning("WorldAssetManager", "Asset loader not available for building type: %s" % building_type)
        return null
    
    # Ensure assets are loaded
    if not asset_loader.is_loading_complete():
        asset_loader.load_kenney_assets()
    
    var scene: PackedScene = null
    
    # Handle specific Kenny building types
    if building_type.begins_with("building-"):
        # Commercial building variants (building-a through building-n)
        var letter = building_type.replace("building-", "")
        if letter in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n"]:
            scene = asset_loader.get_random_commercial_building()
        else:
            # For industrial buildings or other types
            scene = asset_loader.get_random_industrial_building()
    
    elif building_type.begins_with("building-skyscraper-"):
        # Skyscraper variants
        scene = asset_loader.get_skyscraper()
    
    elif building_type.begins_with("low-detail-building"):
        # Low detail buildings
        scene = asset_loader.get_random_commercial_building()
    
    elif building_type.begins_with("industrial-building-"):
        # Industrial building variants
        scene = asset_loader.get_random_industrial_building()
    
    elif building_type.begins_with("chimney-") or building_type == "detail-tank":
        # Industrial details
        scene = asset_loader.get_random_industrial_building()
    
    else:
        # Handle legacy and generic building types
        match building_type:
            "shop", "office", "restaurant", "bank", "commercial", "commercial_large", "small_building":
                scene = asset_loader.get_random_commercial_building()
            "factory", "warehouse", "power_plant", "refinery", "industrial", "industrial_large":
                scene = asset_loader.get_random_industrial_building()
            "apartment", "house", "townhouse", "residential":
                scene = asset_loader.get_random_commercial_building()  # Use commercial as residential
            "barracks", "command_center", "depot", "military":
                scene = asset_loader.get_random_industrial_building()  # Use industrial for military
            "mixed_large":
                # For mixed large buildings, randomly choose between commercial and industrial
                if randf() < 0.5:
                    scene = asset_loader.get_random_commercial_building()
                else:
                    scene = asset_loader.get_random_industrial_building()
            _:
                # Default to commercial for unknown types
                scene = asset_loader.get_random_commercial_building()
    
    if scene:
        logger.info("WorldAssetManager", "Loaded Kenny building asset for type: %s" % building_type)
        return scene
    else:
        logger.warning("WorldAssetManager", "Failed to load Kenny building asset for type: %s, trying fallback" % building_type)
        # Try fallback to any available building
        scene = asset_loader.get_random_commercial_building()
        if not scene:
            scene = asset_loader.get_random_industrial_building()
        
        if scene:
            logger.info("WorldAssetManager", "Loaded fallback Kenny building asset for type: %s" % building_type)
        else:
            logger.error("WorldAssetManager", "No Kenny building assets available for type: %s" % building_type)
        
        return scene

func load_road_asset_by_type(road_type: String, direction: String = "horizontal") -> PackedScene:
    """Load a road asset based on specific type and direction using asset loader"""
    if not asset_loader:
        logger.warning("WorldAssetManager", "Asset loader not available for road type: %s" % road_type)
        return _create_procedural_road_scene(road_type, direction)
    
    var scene: PackedScene = null
    
    # Map road types to asset loader categories
    match road_type:
        "road_square":
            # Use square road tiles for everything
            scene = asset_loader.get_square_road_asset()
        "road_straight", "main_road", "street":
            scene = asset_loader.get_random_road_asset("straight")
        "road_intersection", "road_crossroad":
            scene = asset_loader.get_random_road_asset("intersections")
        "road_curve", "road_bend":
            scene = asset_loader.get_random_road_asset("curves")
        "road_bridge", "road_end", "road_roundabout":
            scene = asset_loader.get_random_road_asset("specialized")
        _:
            # Default to square road for consistency
            scene = asset_loader.get_square_road_asset()
    
    if scene:
        logger.info("WorldAssetManager", "Loaded road asset for type: %s, direction: %s" % [road_type, direction])
        return scene
    else:
        logger.warning("WorldAssetManager", "Failed to load road asset for type: %s - creating procedural road" % road_type)
        return _create_procedural_road_scene(road_type, direction)

func load_character_asset() -> PackedScene:
    """Load a character asset using asset loader"""
    if not asset_loader:
        logger.warning("WorldAssetManager", "Asset loader not available for character")
        return null
    
    var scene = asset_loader.get_random_character()
    
    if scene:
        logger.info("WorldAssetManager", "Loaded character asset")
        return scene
    else:
        logger.warning("WorldAssetManager", "Failed to load character asset")
        return null

func is_asset_loader_available() -> bool:
    """Check if asset loader is available"""
    return asset_loader != null

func _create_procedural_road_scene(road_type: String, direction: String) -> PackedScene:
    """Create a procedural road scene when Kenny assets fail to load"""
    var scene = PackedScene.new()
    var road_node = MeshInstance3D.new()
    road_node.name = "ProceduralRoad"
    
    # Create appropriate road mesh based on type
    var road_mesh: Mesh = null
    match road_type:
        "road_straight", "main_road", "street":
            road_mesh = _create_straight_road_mesh(direction)
        "road_intersection", "road_crossroad":
            road_mesh = _create_intersection_road_mesh()
        "road_curve", "road_bend":
            road_mesh = _create_curved_road_mesh()
        _:
            road_mesh = _create_straight_road_mesh(direction)
    
    road_node.mesh = road_mesh
    
    # Create road material
    var road_material = StandardMaterial3D.new()
    road_material.albedo_color = Color(0.3, 0.3, 0.3)  # Dark gray asphalt
    road_material.roughness = 0.8
    road_material.metallic = 0.1
    road_material.specular = 0.2
    road_node.material_override = road_material
    
    # Add collision shape
    var collision_body = StaticBody3D.new()
    collision_body.name = "RoadCollision"
    var collision_shape = CollisionShape3D.new()
    
    # Create collision shape based on road mesh
    if road_mesh:
        collision_shape.shape = road_mesh.create_trimesh_shape()
    
    collision_body.add_child(collision_shape)
    road_node.add_child(collision_body)
    
    # Pack the scene
    scene.pack(road_node)
    
    logger.info("WorldAssetManager", "Created procedural road scene for type: %s, direction: %s" % [road_type, direction])
    return scene

func _create_straight_road_mesh(direction: String) -> BoxMesh:
    """Create a straight road mesh"""
    var box_mesh = BoxMesh.new()
    
    if direction == "horizontal":
        box_mesh.size = Vector3(4.0, 0.1, 1.0)  # Wide and flat
    else:  # vertical
        box_mesh.size = Vector3(1.0, 0.1, 4.0)  # Rotated 90 degrees
    
    return box_mesh

func _create_intersection_road_mesh() -> BoxMesh:
    """Create an intersection road mesh"""
    var box_mesh = BoxMesh.new()
    box_mesh.size = Vector3(4.0, 0.1, 4.0)  # Square intersection
    return box_mesh

func _create_curved_road_mesh() -> BoxMesh:
    """Create a curved road mesh (simplified as angled rectangle)"""
    var box_mesh = BoxMesh.new()
    box_mesh.size = Vector3(3.0, 0.1, 3.0)  # Square for curves
    return box_mesh

func cleanup() -> void:
    """Cleanup asset manager resources"""
    logger.info("WorldAssetManager", "World asset manager cleanup complete") 