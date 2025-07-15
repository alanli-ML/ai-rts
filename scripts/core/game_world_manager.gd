# GameWorldManager.gd - Coordinate 3D world initialization and management
extends Node

# Dependencies
var logger
var dependency_container
var main_node

# Component managers
var world_asset_manager
var procedural_world_renderer
var game_display_manager
var static_world_initializer

# 3D World references
var scene_3d
var camera_3d
var control_points_container
var buildings_container
var units_container
var team1_units_container
var team2_units_container

# Signals
signal world_initialized()
signal game_display_updated(state_data: Dictionary)

func setup(logger_instance, dependency_container_instance, main_node_instance) -> void:
    """Setup the game world manager with dependencies"""
    logger = logger_instance
    dependency_container = dependency_container_instance
    main_node = main_node_instance
    
    # Setup 3D world references (main_node is already ready)
    _setup_3d_references()
    
    # Initialize component managers
    await _initialize_components()
    
    logger.info("GameWorldManager", "Game world manager setup complete")

func _setup_3d_references() -> void:
    """Setup 3D world node references"""
    scene_3d = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView")
    
    # Get the old camera position before replacing it
    var old_camera = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Camera3D")
    var old_camera_transform = old_camera.transform
    
    # Remove the basic Camera3D and replace it with RTSCamera
    old_camera.queue_free()
    
    # Create and setup RTSCamera with mouse controls
    var rts_camera = RTSCamera.new()
    rts_camera.name = "RTSCamera"
    
    # Position the RTS camera at the old camera's location initially
    rts_camera.position = old_camera_transform.origin
    
    # Add to scene using call_deferred to avoid parent node busy errors
    scene_3d.call_deferred("add_child", rts_camera)
    
    # Store RTS camera reference for later camera access
    camera_3d = null  # Will be set once RTS camera is properly added
    rts_camera.add_to_group("rts_cameras")
    
    # Ensure the SubViewport can receive input for camera controls
    var sub_viewport = main_node.get_node("GameUI/GameWorldContainer/GameWorld")
    sub_viewport.gui_disable_input = false
    
    control_points_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/ControlPoints")
    buildings_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Buildings")
    units_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Units")
    team1_units_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Units/Team1Units")
    team2_units_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Units/Team2Units")
    
    logger.info("GameWorldManager", "3D references setup complete with RTSCamera mouse controls")

func get_camera_3d() -> Camera3D:
    """Get the Camera3D reference, finding it from RTS camera if needed"""
    if camera_3d:
        return camera_3d
    
    # Try to find the RTS camera and get its Camera3D child
    var rts_cameras = scene_3d.get_children().filter(func(node): return node is RTSCamera)
    if rts_cameras.size() > 0:
        var rts_camera = rts_cameras[0] as RTSCamera
        camera_3d = rts_camera.camera_3d
        return camera_3d
    
    return null

func _initialize_components() -> void:
    """Initialize all component managers"""
    logger.info("GameWorldManager", "Initializing component managers")
    
    # Load component scripts
    var WorldAssetManagerScript = load("res://scripts/core/world_asset_manager.gd")
    var ProceduralWorldRendererScript = load("res://scripts/core/procedural_world_renderer.gd")
    var GameDisplayManagerScript = load("res://scripts/core/game_display_manager.gd")
    var StaticWorldInitializerScript = load("res://scripts/core/static_world_initializer.gd")
    
    # Create and setup World Asset Manager
    world_asset_manager = WorldAssetManagerScript.new()
    world_asset_manager.name = "WorldAssetManager"
    add_child(world_asset_manager)
    
    var asset_loader = dependency_container.get_asset_loader()
    world_asset_manager.setup(logger, asset_loader)
    
    # Create and setup Procedural World Renderer
    procedural_world_renderer = ProceduralWorldRendererScript.new()
    procedural_world_renderer.name = "ProceduralWorldRenderer"
    add_child(procedural_world_renderer)
    
    procedural_world_renderer.setup(logger, world_asset_manager, scene_3d, camera_3d, control_points_container)
    
    # Create and setup Game Display Manager
    game_display_manager = GameDisplayManagerScript.new()
    game_display_manager.name = "GameDisplayManager"
    add_child(game_display_manager)
    
    game_display_manager.setup(logger, world_asset_manager, scene_3d, main_node)
    
    # Create and setup Static World Initializer
    static_world_initializer = StaticWorldInitializerScript.new()
    static_world_initializer.name = "StaticWorldInitializer"
    add_child(static_world_initializer)
    
    static_world_initializer.setup(logger, scene_3d, control_points_container, buildings_container, units_container)
    
    # Connect signals
    game_display_manager.game_display_updated.connect(_on_game_display_updated)
    procedural_world_renderer.procedural_world_rendered.connect(_on_procedural_world_rendered)
    static_world_initializer.static_world_initialized.connect(_on_static_world_initialized)
    
    logger.info("GameWorldManager", "Component managers initialized")

func initialize_game_world() -> void:
    """Initialize the 3D game world with control points and other elements"""
    logger.info("GameWorldManager", "Initializing game world")
    logger.info("GameWorldManager", "Server mode check: %s" % dependency_container.is_server_mode())
    
    # Initialize ground plane material for better visibility
    procedural_world_renderer.initialize_ground_plane()
    
    # Check if procedural generation is available (map generator exists)
    var map_generator = dependency_container.get_map_generator()
    if map_generator:
        logger.info("GameWorldManager", "Map generator available - attempting procedural generation")
        await procedural_world_renderer.initialize_procedural_world(dependency_container)
        
        # Check if procedural generation actually succeeded by looking for procedural elements
        var procedural_success = scene_3d.get_node_or_null("ProceduralBuildings") != null and scene_3d.get_node("ProceduralBuildings").get_child_count() > 0
        
        if not procedural_success:
            logger.info("GameWorldManager", "Procedural generation incomplete - falling back to static world")
            static_world_initializer.initialize_static_world()
    else:
        logger.info("GameWorldManager", "No map generator - using static world")
        # Fallback to static control points when no map generator
        static_world_initializer.initialize_static_world()
    
    world_initialized.emit()
    logger.info("GameWorldManager", "Game world initialized")

# Game display management delegation
func update_game_display(state_data: Dictionary) -> void:
    """Update the game display with new state"""
    game_display_manager.update_game_display(state_data)

func clear_game_display() -> void:
    """Clear the game display"""
    game_display_manager.clear_game_display()

# Signal handlers
func _on_game_display_updated(state_data: Dictionary) -> void:
    """Handle game display updated signal"""
    game_display_updated.emit(state_data)

func _on_procedural_world_rendered() -> void:
    """Handle procedural world rendered signal"""
    logger.info("GameWorldManager", "Procedural world rendering completed")

func _on_static_world_initialized() -> void:
    """Handle static world initialized signal"""
    logger.info("GameWorldManager", "Static world initialization completed")

func cleanup() -> void:
    """Cleanup game world resources"""
    if game_display_manager:
        game_display_manager.cleanup()
    if procedural_world_renderer:
        procedural_world_renderer.cleanup()
    if static_world_initializer:
        static_world_initializer.cleanup()
    if world_asset_manager:
        world_asset_manager.cleanup()
    
    logger.info("GameWorldManager", "Game world manager cleanup complete") 