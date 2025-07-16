# StaticWorldInitializer.gd - Handle static world initialization as fallback
class_name StaticWorldInitializer
extends Node

# Dependencies
var logger
var scene_3d
var control_points_container
var buildings_container
var units_container

# Home base management
var home_base_manager

# Signals
signal static_world_initialized()

func _ready() -> void:
    # Initialize when added to scene tree
    pass

func setup(logger_instance, scene_3d_instance, control_points_container_instance, buildings_container_instance, units_container_instance) -> void:
    """Setup the static world initializer with dependencies"""
    logger = logger_instance
    scene_3d = scene_3d_instance
    control_points_container = control_points_container_instance
    buildings_container = buildings_container_instance
    units_container = units_container_instance
    
    # Create and setup home base manager
    _setup_home_base_manager()
    
    logger.info("StaticWorldInitializer", "Static world initializer setup complete")

func _setup_home_base_manager() -> void:
    """Setup the home base manager"""
    var HomeBaseManagerScript = load("res://scripts/core/home_base_manager.gd")
    home_base_manager = HomeBaseManagerScript.new()
    home_base_manager.name = "HomeBaseManager"
    
    # Find the home bases container in the buildings
    var home_bases_container = buildings_container.get_node_or_null("HomeBases")
    if home_bases_container:
        home_bases_container.add_child(home_base_manager)
        logger.info("StaticWorldInitializer", "HomeBaseManager added to HomeBases container")
    else:
        # Fallback: add to buildings container directly
        buildings_container.add_child(home_base_manager)
        logger.info("StaticWorldInitializer", "HomeBaseManager added to Buildings container (fallback)")

func initialize_static_world() -> void:
    """Initialize the game world with static control points (fallback)"""
    logger.info("StaticWorldInitializer", "Initializing static game world")
    
    # Initialize home bases first
    if home_base_manager:
        logger.info("StaticWorldInitializer", "Initializing home bases")
        # Home base manager initializes itself in _ready() - no need to wait
    
    # Initialize control points in the 3D world
    if control_points_container:
        logger.info("StaticWorldInitializer", "Skipping control point creation for now - focusing on building generation")
    
    # Initialize building positions
    if buildings_container:
        initialize_buildings_3d()
    
    # Initialize unit containers - but only if not in active multiplayer session
    if units_container:
        initialize_units_3d()
    
    # Fill the entire map with buildings directly
    _fill_map_with_buildings()
    
    static_world_initialized.emit()
    logger.info("StaticWorldInitializer", "Static world initialization complete")

func initialize_control_points_3d() -> void:
    """Initialize control points in the 3D world"""
    logger.info("StaticWorldInitializer", "Initializing control points in 3D world")
    
    # Create 25 control points for 5x5 grid to match procedural system expectations
    _create_control_points_grid()
    
    # Add visual representations to all control points
    for i in range(1, 26):  # Control points 1-25
        var control_point = control_points_container.get_node("ControlPoint%d" % i)
        if control_point:
            # Add visual representation (sphere or other mesh) - MUCH more visible
            var mesh_instance = MeshInstance3D.new()
            var sphere_mesh = SphereMesh.new()
            sphere_mesh.radius = 3.0  # Larger radius
            sphere_mesh.height = 6.0  # Taller height
            mesh_instance.mesh = sphere_mesh
            
            # Position the sphere above the ground to avoid z-fighting
            mesh_instance.position = Vector3(0, 3.0, 0)  # 3 units above ground
            
            # Create VERY visible material
            var material = StandardMaterial3D.new()
            material.albedo_color = Color.YELLOW  # Bright yellow instead of gray
            material.emission_enabled = true
            material.emission = Color.YELLOW * 1.2  # Very bright emission
            material.emission_energy = 4.0  # High energy emission
            material.roughness = 0.0  # Shiny surface
            material.metallic = 0.3
            material.flags_unshaded = true  # Always bright
            mesh_instance.material_override = material
            
            control_point.call_deferred("add_child", mesh_instance)
            logger.info("StaticWorldInitializer", "Control point %d visual added at height 3.0" % i)

func _create_control_points_grid() -> void:
    """Create 25 control points in a 5x5 grid to match procedural system expectations"""
    logger.info("StaticWorldInitializer", "Creating 5x5 control point grid (25 points)")
    
    # Grid configuration matching the procedural system
    var grid_size = 5
    var tile_size = 3.33  # Match procedural system tile size
    var map_size = 60    # 60x60 tile grid
    var grid_spacing = map_size / 4  # 4 intervals for 5 points
    var start_offset = grid_spacing / 2  # Start at quarter spacing from edge
    
    var control_point_index = 1
    
    for i in range(grid_size):
        for j in range(grid_size):
            # Calculate tile position using same logic as procedural system
            var tile_pos_x = start_offset + i * grid_spacing
            var tile_pos_y = start_offset + j * grid_spacing
            
            # Convert to world position using centered coordinate system
            var center_offset = Vector2i(30, 30)  # Half of 60x60 grid
            var centered_tile_pos = Vector2i(tile_pos_x, tile_pos_y) - center_offset
            var world_position = Vector3(
                centered_tile_pos.x * tile_size,
                0,
                centered_tile_pos.y * tile_size
            )
            
            # Create control point node
            var ControlPointScript = load("res://scripts/gameplay/control_point.gd")
            var control_point = ControlPointScript.new()
            control_point.name = "ControlPoint%d" % control_point_index
            control_point.position = world_position
            
            # Set control point properties directly instead of calling non-existent setup() method
            control_point.control_point_id = "CP_%d" % (control_point_index - 1)
            control_point.control_point_name = "Grid Point %d" % control_point_index
            
            # Add to control points container using call_deferred to avoid parent busy errors
            control_points_container.call_deferred("add_child", control_point)
            
            logger.info("StaticWorldInitializer", "Created control point %d at %s" % [control_point_index, world_position])
            
            control_point_index += 1
    
    logger.info("StaticWorldInitializer", "Created %d control points in 5x5 grid" % (control_point_index - 1))

func initialize_buildings_3d() -> void:
    """Initialize building positions in the 3D world"""
    logger.info("StaticWorldInitializer", "Initializing buildings in 3D world")
    # Home bases are handled by HomeBaseManager in the setup phase
    # Other buildings will be spawned dynamically during gameplay

func initialize_units_3d() -> void:
    """Initialize unit containers in the 3D world"""
    print("StaticWorldInitializer: Initializing units in 3D world")
    
    # Check if we're in server mode with an active session
    # If so, units should be spawned by SessionManager, not here
    var dependency_container = get_node_or_null("/root/DependencyContainer")
    if dependency_container and dependency_container.is_server_mode():
        var session_manager = dependency_container.get_node_or_null("SessionManager")
        if session_manager and session_manager.get_session_count() > 0:
            print("StaticWorldInitializer: Server mode with active session detected - skipping demo unit spawning")
            print("StaticWorldInitializer: Units will be spawned by SessionManager instead")
            return
    
    # Only spawn demo units if we're not in a proper multiplayer session
    print("StaticWorldInitializer: No active session found - spawning demo units for testing")
    _spawn_demo_units_for_teams()
    
    print("StaticWorldInitializer: Demo units spawned for both teams")

func _fill_map_with_buildings() -> void:
    """This function is a fallback and should not perform complex procedural generation.
    It's simplified to avoid confusion with the main procedural renderer."""
    logger.info("StaticWorldInitializer", "Skipping complex building placement in static fallback.")
    # The static world should be simple. The complex procedural generation
    # is handled by the MapGenerator and ProceduralWorldRenderer. If that fails,
    # we don't want another complex system running here. This function can be
    # used to place a few key static buildings if needed.

func _generate_road_network(grid_size: int) -> Dictionary:
    """This function is no longer needed as _fill_map_with_buildings is simplified."""
    return {}

func _spawn_demo_units_for_teams() -> void:
    """Spawn demo units for both teams at their home base positions"""
    var unit_archetypes = ["scout", "tank", "sniper", "medic", "engineer"]
    var team_spawn_positions = {
        1: Vector3(-40, 0, -52),  # Team 1 spawn position
        2: Vector3(40, 0, 28)     # Team 2 spawn position
    }
    
    for team_id in [1, 2]:
        var base_position = team_spawn_positions.get(team_id, Vector3.ZERO)
        print("StaticWorldInitializer: Spawning %d units for team %d at %s" % [unit_archetypes.size(), team_id, base_position])
        
        # Get team container
        var team_container = null
        if team_id == 1:
            team_container = units_container.get_node("Team1Units")
        else:
            team_container = units_container.get_node("Team2Units")
        
        if not team_container:
            print("StaticWorldInitializer ERROR: Could not find team container for team %d" % team_id)
            continue
        
        # Spawn 5 units in formation
        for i in range(unit_archetypes.size()):
            var archetype = unit_archetypes[i]
            var unit_position = _get_formation_position(base_position, i, unit_archetypes.size())
            var unit = _create_demo_unit(archetype, team_id, unit_position)
            
            if unit:
                team_container.call_deferred("add_child", unit)
                print("StaticWorldInitializer: Spawned %s unit for team %d at %s" % [archetype, team_id, unit_position])

func _get_formation_position(base_position: Vector3, index: int, total_units: int) -> Vector3:
    """Generate formation positions around base position"""
    var spacing = 8.0
    var rows = 2
    var cols = 3
    
    var row = index / cols
    var col = index % cols
    var x_offset = (col - 1) * spacing
    var z_offset = (row - 0.5) * spacing
    
    return base_position + Vector3(x_offset, 0, z_offset)

func _create_demo_unit(archetype: String, team_id: int, position: Vector3) -> Node:
    """Create a demo unit with the specified archetype"""
    var unit_scene = preload("res://scenes/units/AnimatedUnit.tscn")
    var unit = unit_scene.instantiate()
    
    if unit:
        unit.archetype = archetype
        unit.team_id = team_id
        unit.position = position
        unit.name = "AnimatedUnit_%s_Team%d" % [archetype, team_id]
    
    return unit

func cleanup() -> void:
    """Cleanup static world initializer resources"""
    if home_base_manager and home_base_manager.has_method("cleanup"):
        home_base_manager.cleanup()
    logger.info("StaticWorldInitializer", "Static world initializer cleanup complete") 