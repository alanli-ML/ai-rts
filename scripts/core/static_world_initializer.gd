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
    
    # Initialize unit containers
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
            
            # Set control point properties
            control_point.setup("CP_%d" % (control_point_index - 1), "Grid Point %d" % control_point_index)
            
            # Add to control points container
            control_points_container.add_child(control_point)
            
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
    logger.info("StaticWorldInitializer", "Initializing units in 3D world")
    
    # Create and setup team unit spawner for dynamic unit spawning
    var TeamUnitSpawnerScript = load("res://scripts/units/team_unit_spawner.gd")
    var team_unit_spawner = TeamUnitSpawnerScript.new()
    team_unit_spawner.name = "TeamUnitSpawner"
    
    # Add to units container for easy access
    units_container.add_child(team_unit_spawner)
    
    # Set map reference to the scene root for spawning
    team_unit_spawner.map_node = scene_3d
    
    logger.info("StaticWorldInitializer", "TeamUnitSpawner initialized and ready for dynamic spawning")

func _fill_map_with_buildings() -> void:
    """Fill the entire 200x200 map with buildings, ignoring districts and just avoiding home bases"""
    logger.info("StaticWorldInitializer", "Filling entire 200x200 map with buildings")
    
    # Create a buildings container if it doesn't exist
    var procedural_buildings_container = scene_3d.get_node_or_null("ProceduralBuildings")
    if not procedural_buildings_container:
        procedural_buildings_container = Node3D.new()
        procedural_buildings_container.name = "ProceduralBuildings"
        scene_3d.add_child(procedural_buildings_container)
        logger.info("StaticWorldInitializer", "Created ProceduralBuildings container")
    
    # Clear existing buildings
    for child in procedural_buildings_container.get_children():
        child.queue_free()
    
    var building_count = 0
    var grid_size = 60  # 60x60 tile grid
    var tile_size = 3.33  # Match the 200x200 grid alignment
    var rng = RandomNumberGenerator.new()
    rng.randomize()
    
    # Define areas to avoid (home bases and immediate surroundings)
    var home_base_exclusions = {
        # Team 1 home base at (-40, 0, -40) with buffer
        "team1": Vector2i(18, 18),  # Tile coordinates for (-40, -40)
        "team2": Vector2i(42, 42)   # Tile coordinates for (40, 40)
    }
    
    # Create a road network pattern to avoid placing buildings on roads
    var road_tiles = _generate_road_network(grid_size)
    
    logger.info("StaticWorldInitializer", "Generated road network with %d road tiles" % road_tiles.size())
    
    # Scan the entire 60x60 grid and place buildings
    for x in range(grid_size):
        for y in range(grid_size):
            var tile_pos = Vector2i(x, y)
            
            # Skip home base areas (5x5 exclusion zones around each base)
            var skip_this_tile = false
            for base_pos in home_base_exclusions.values():
                if abs(tile_pos.x - base_pos.x) <= 2 and abs(tile_pos.y - base_pos.y) <= 2:
                    skip_this_tile = true
                    break
            
            if skip_this_tile:
                continue
            
            # Skip road tiles - buildings should never be placed on roads
            if road_tiles.has(tile_pos):
                continue
            
            # Check if this tile is near a road (within 2 tiles for accessibility)
            var near_road = false
            for dx in range(-2, 3):
                for dy in range(-2, 3):
                    if dx == 0 and dy == 0:
                        continue
                    var nearby_tile = Vector2i(tile_pos.x + dx, tile_pos.y + dy)
                    if road_tiles.has(nearby_tile):
                        near_road = true
                        break
                if near_road:
                    break
            
            # Only place buildings near roads for accessibility (realistic city planning)
            if not near_road:
                continue
            
            # Skip some tiles randomly for variety
            if rng.randf() < 0.3:  # Reduced to 30% since we're already filtering heavily
                continue
            
            # Convert tile position to world position using centered coordinate system
            var center_offset = Vector2i(30, 30)  # Half of 60x60 grid
            var centered_tile_pos = tile_pos - center_offset
            var world_position = Vector3(
                centered_tile_pos.x * tile_size,
                0.1,  # Slightly above ground
                centered_tile_pos.y * tile_size
            )
            
            # Only place buildings within reasonable bounds
            if abs(world_position.x) > 95 or abs(world_position.z) > 95:
                continue
            
            # Create fallback mesh building (since we don't have world_asset_manager here)
            var building = MeshInstance3D.new()
            var building_types = ["commercial", "industrial", "office", "shop", "factory", "warehouse"]
            var building_type = building_types[rng.randi() % building_types.size()]
            building.name = "Building_%d_%s" % [building_count, building_type]
            building.position = world_position
            
            # Create building mesh
            var box_mesh = BoxMesh.new()
            var height = rng.randf_range(4.0, 12.0)
            var size_x = rng.randf_range(2.0, 4.0)
            var size_z = rng.randf_range(2.0, 4.0)
            
            box_mesh.size = Vector3(size_x, height, size_z)
            building.mesh = box_mesh
            
            # Create building material based on type
            var material = StandardMaterial3D.new()
            match building_type:
                "commercial":
                    material.albedo_color = Color.LIGHT_BLUE
                "industrial":
                    material.albedo_color = Color.DARK_GRAY
                "office":
                    material.albedo_color = Color.BLUE
                "shop":
                    material.albedo_color = Color.CYAN
                "factory":
                    material.albedo_color = Color.BROWN
                "warehouse":
                    material.albedo_color = Color.GRAY
                _:
                    material.albedo_color = Color.WHITE
            
            material.roughness = rng.randf_range(0.3, 0.8)
            material.metallic = rng.randf_range(0.1, 0.4)
            
            # Add emission for visibility
            material.emission_enabled = true
            material.emission = material.albedo_color * 0.1
            material.emission_energy = 0.5
            
            building.material_override = material
            
            # Random rotation
            building.rotation_degrees.y = rng.randi_range(0, 3) * 90
            
            procedural_buildings_container.add_child(building)
            building_count += 1
            
            # Log progress every 200 buildings
            if building_count % 200 == 0:
                logger.info("StaticWorldInitializer", "Placed %d buildings so far..." % building_count)
            
            # Stop if we've placed enough buildings
            if building_count >= 1500:  # Reasonable limit for full coverage
                break
        
        if building_count >= 1500:
            break
    
    logger.info("StaticWorldInitializer", "Filled map with %d buildings across entire 200x200 area" % building_count)

func _generate_road_network(grid_size: int) -> Dictionary:
    """Generate a realistic road network pattern for building placement avoidance"""
    var road_tiles = {}
    
    # Create main arterial roads (major cross routes)
    var center = grid_size / 2
    
    # Main North-South arterial road through center
    for y in range(grid_size):
        road_tiles[Vector2i(center, y)] = true
        road_tiles[Vector2i(center - 1, y)] = true  # Make it 2 lanes wide
    
    # Main East-West arterial road through center  
    for x in range(grid_size):
        road_tiles[Vector2i(x, center)] = true
        road_tiles[Vector2i(x, center - 1)] = true  # Make it 2 lanes wide
    
    # Secondary grid roads every 8 tiles (creating city blocks)
    var road_spacing = 8
    for i in range(0, grid_size, road_spacing):
        # Vertical secondary roads
        if i != center and i != center - 1:  # Don't duplicate main roads
            for y in range(grid_size):
                road_tiles[Vector2i(i, y)] = true
        
        # Horizontal secondary roads
        if i != center and i != center - 1:  # Don't duplicate main roads
            for x in range(grid_size):
                road_tiles[Vector2i(x, i)] = true
    
    # Add perimeter roads around the edge for access
    for i in range(grid_size):
        # Top and bottom edges
        road_tiles[Vector2i(i, 0)] = true
        road_tiles[Vector2i(i, grid_size - 1)] = true
        
        # Left and right edges  
        road_tiles[Vector2i(0, i)] = true
        road_tiles[Vector2i(grid_size - 1, i)] = true
    
    # Add diagonal connector roads for more realistic traffic flow
    var quarter = grid_size / 4
    var three_quarter = (grid_size * 3) / 4
    
    # Diagonal from northwest to center
    for i in range(quarter):
        var x = quarter - i
        var y = quarter - i
        if x >= 0 and y >= 0:
            road_tiles[Vector2i(x, y)] = true
    
    # Diagonal from northeast to center
    for i in range(quarter):
        var x = three_quarter + i
        var y = quarter - i
        if x < grid_size and y >= 0:
            road_tiles[Vector2i(x, y)] = true
    
    logger.info("StaticWorldInitializer", "Generated road network: %d arterial + %d secondary + %d perimeter + %d connector roads" % [
        4 * grid_size,  # 2 main roads * 2 lanes each * grid_size
        ((grid_size / road_spacing) - 1) * 2 * grid_size,  # Secondary roads
        4 * grid_size,  # Perimeter roads
        quarter * 2  # Diagonal connectors
    ])
    
    return road_tiles

func cleanup() -> void:
    """Cleanup static world initializer resources"""
    if home_base_manager and home_base_manager.has_method("cleanup"):
        home_base_manager.cleanup()
    logger.info("StaticWorldInitializer", "Static world initializer cleanup complete") 