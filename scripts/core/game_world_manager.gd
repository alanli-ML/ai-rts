# GameWorldManager.gd - Handle 3D world initialization and procedural generation
extends Node

# Dependencies
var logger
var dependency_container
var main_node
var asset_loader  # Add asset loader dependency

# 3D World references
var scene_3d
var camera_3d
var control_points_container
var buildings_container
var units_container
var team1_units_container
var team2_units_container

# Game state display
var displayed_units: Dictionary = {}
var displayed_buildings: Dictionary = {}
var displayed_control_points: Dictionary = {}
var selected_units: Array = []

# Signals
signal world_initialized()
signal game_display_updated(state_data: Dictionary)

func setup(logger_instance, dependency_container_instance, main_node_instance) -> void:
    """Setup the game world manager with dependencies"""
    logger = logger_instance
    dependency_container = dependency_container_instance
    main_node = main_node_instance
    
    # Get asset loader from dependency container
    asset_loader = dependency_container.get_asset_loader()
    if not asset_loader:
        logger.warning("GameWorldManager", "Asset loader not available - will use fallback rendering")
    else:
        logger.info("GameWorldManager", "Asset loader connected successfully")
        
        # Ensure Kenney assets are loaded
        if not asset_loader.is_loading_complete():
            logger.info("GameWorldManager", "Loading Kenney assets...")
            asset_loader.load_kenney_assets()
            logger.info("GameWorldManager", "Kenney assets loaded")
    
    # Setup 3D world references (main_node is already ready)
    _setup_3d_references()
    
    logger.info("GameWorldManager", "Game world manager setup complete")

func _setup_3d_references() -> void:
    """Setup 3D world node references"""
    scene_3d = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView")
    camera_3d = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Camera3D")
    control_points_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/ControlPoints")
    buildings_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Buildings")
    units_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Units")
    team1_units_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Units/Team1Units")
    team2_units_container = main_node.get_node("GameUI/GameWorldContainer/GameWorld/3DView/Units/Team2Units")
    
    logger.info("GameWorldManager", "3D world references setup complete")



func _load_building_asset_by_type(building_type: String) -> PackedScene:
    """Load a building asset based on specific type using asset loader"""
    if not asset_loader:
        logger.warning("GameWorldManager", "Asset loader not available for building type: %s" % building_type)
        return null
    
    var scene: PackedScene = null
    
    match building_type:
        "shop", "office", "restaurant", "bank", "commercial":
            scene = asset_loader.get_random_commercial_building()
        "factory", "warehouse", "power_plant", "refinery", "industrial":
            scene = asset_loader.get_random_industrial_building()
        "apartment", "house", "townhouse":
            scene = asset_loader.get_random_commercial_building()  # Use commercial as fallback for residential
        "barracks", "command_center", "depot":
            scene = asset_loader.get_random_industrial_building()  # Use industrial as fallback for military
        _:
            # Default to commercial for unknown types
            scene = asset_loader.get_random_commercial_building()
    
    if scene:
        logger.info("GameWorldManager", "Loaded building asset for type: %s" % building_type)
        return scene
    else:
        logger.warning("GameWorldManager", "Failed to load building asset for type: %s" % building_type)
        return null

func _load_road_asset_by_type(road_type: String, direction: String = "horizontal") -> PackedScene:
    """Load a road asset based on specific type and direction using asset loader"""
    if not asset_loader:
        logger.warning("GameWorldManager", "Asset loader not available for road type: %s" % road_type)
        return null
    
    var scene: PackedScene = null
    
    # Map road types to asset loader categories
    match road_type:
        "road_straight", "main_road", "street":
            scene = asset_loader.get_random_road_asset("straight")
        "road_intersection", "road_crossroad":
            scene = asset_loader.get_random_road_asset("intersections")
        "road_curve", "road_bend":
            scene = asset_loader.get_random_road_asset("curves")
        "road_bridge", "road_end", "road_roundabout":
            scene = asset_loader.get_random_road_asset("specialized")
        _:
            # Default to straight road
            scene = asset_loader.get_random_road_asset("straight")
    
    if scene:
        logger.info("GameWorldManager", "Loaded road asset for type: %s, direction: %s" % [road_type, direction])
        return scene
    else:
        logger.warning("GameWorldManager", "Failed to load road asset for type: %s" % road_type)
        return null

func _load_character_asset() -> PackedScene:
    """Load a character asset using asset loader"""
    if not asset_loader:
        logger.warning("GameWorldManager", "Asset loader not available for character")
        return null
    
    var scene = asset_loader.get_random_character()
    
    if scene:
        logger.info("GameWorldManager", "Loaded character asset")
        return scene
    else:
        logger.warning("GameWorldManager", "Failed to load character asset")
        return null

func initialize_game_world() -> void:
    """Initialize the 3D game world with control points and other elements"""
    logger.info("GameWorldManager", "Initializing game world")
    logger.info("GameWorldManager", "Server mode check: %s" % dependency_container.is_server_mode())
    
    # Initialize ground plane material for better visibility
    _initialize_ground_plane()
    
    # Check if we should use procedural generation (server mode)
    if dependency_container.is_server_mode():
        logger.info("GameWorldManager", "Server mode detected - using procedural generation")
        await _initialize_procedural_world()
    else:
        logger.info("GameWorldManager", "Client mode detected - using static world")
        # Fallback to static control points for client mode
        _initialize_static_world()
    
    # Initialize unit containers
    if units_container:
        _initialize_units_3d()
    
    world_initialized.emit()
    logger.info("GameWorldManager", "Game world initialized")

func _initialize_procedural_world() -> void:
    """Initialize the game world using procedural generation"""
    logger.info("GameWorldManager", "Initializing procedural game world")
    
    var map_generator = dependency_container.get_map_generator()
    logger.info("GameWorldManager", "Map generator retrieved: %s" % (map_generator != null))
    
    if not map_generator:
        logger.error("GameWorldManager", "MapGenerator not available, falling back to static world")
        _initialize_static_world()
        return
    
    # Generate the procedural map
    var generation_seed = randi()  # Could be configurable or from game settings
    logger.info("GameWorldManager", "Generating procedural map with seed: %d" % generation_seed)
    
    # Generate the map data
    var map_data = await map_generator.generate_map(generation_seed)
    logger.info("GameWorldManager", "Map generation completed. Data size: %d keys" % map_data.size())
    
    if map_data.is_empty():
        logger.error("GameWorldManager", "Map generation failed, falling back to static world")
        _initialize_static_world()
        return
    
    # Debug: Print map data structure
    logger.info("GameWorldManager", "Map data keys: %s" % str(map_data.keys()))
    for key in map_data.keys():
        var value = map_data[key]
        if value is Dictionary:
            logger.info("GameWorldManager", "  %s: Dictionary with %d keys" % [str(key), value.size()])
        elif value is Array:
            logger.info("GameWorldManager", "  %s: Array with %d elements" % [str(key), value.size()])
        else:
            logger.info("GameWorldManager", "  %s: %s" % [str(key), str(value)])
    
    # Apply the generated map to the 3D world
    _apply_procedural_map(map_data)
    
    # Position camera to view the procedural map
    _position_camera_for_procedural_map()
    
    logger.info("GameWorldManager", "Procedural world initialization complete")

func _initialize_static_world() -> void:
    """Initialize the game world with static control points (fallback)"""
    logger.info("GameWorldManager", "Initializing static game world")
    
    # Initialize control points in the 3D world
    if control_points_container:
        _initialize_control_points_3d()
    
    # Initialize building positions
    if buildings_container:
        _initialize_buildings_3d()

func _apply_procedural_map(map_data: Dictionary) -> void:
    """Apply the procedural map data to the 3D world"""
    logger.info("GameWorldManager", "Applying procedural map to 3D world")
    logger.info("GameWorldManager", "scene_3d available: %s" % (scene_3d != null))
    logger.info("GameWorldManager", "control_points_container available: %s" % (control_points_container != null))
    
    if not scene_3d:
        logger.error("GameWorldManager", "scene_3d not available - cannot apply procedural map")
        return
    
    # Apply control points from map data
    _apply_procedural_control_points(map_data.get("control_points", {}))
    
    # Apply districts and buildings
    _apply_procedural_districts(map_data.get("districts", {}))
    
    # Apply road networks
    _apply_procedural_roads(map_data.get("roads", {}))
    
    # Apply buildings
    _apply_procedural_buildings(map_data.get("buildings", {}))
    
    logger.info("GameWorldManager", "Procedural map applied to 3D world")

func _apply_procedural_control_points(control_points_data: Dictionary) -> void:
    """Apply procedural control points to the 3D world"""
    logger.info("GameWorldManager", "Applying procedural control points")
    logger.info("GameWorldManager", "Control points data size: %d" % control_points_data.size())
    
    if not control_points_container:
        logger.error("GameWorldManager", "control_points_container not available")
        return
    
    var tile_size = 3.0  # Should match MapGenerator.TILE_SIZE
    
    for cp_id in control_points_data:
        var cp_data = control_points_data[cp_id]
        var tile_position = cp_data.get("position", Vector2i(0, 0))
        
        # Convert tile position to world position
        var world_position = Vector3(
            tile_position.x * tile_size,
            0,
            tile_position.y * tile_size
        )
        
        # Create or update control point
        var control_point_index = int(cp_id.split("_")[1]) + 1  # Convert cp_0 to 1, etc.
        var control_point = control_points_container.get_node("ControlPoint%d" % control_point_index)
        
        if control_point:
            control_point.position = world_position
            
            # Clear any existing visual representation
            for child in control_point.get_children():
                if child is MeshInstance3D:
                    child.queue_free()
            
            # Add enhanced visual representation
            var mesh_instance = MeshInstance3D.new()
            var sphere_mesh = SphereMesh.new()
            sphere_mesh.radius = 4.0  # Larger radius for better visibility
            sphere_mesh.height = 8.0  # Taller height
            mesh_instance.mesh = sphere_mesh
            mesh_instance.position = Vector3(0, 4.0, 0)  # Elevated above ground
            
            # Create district-type specific material
            var material = StandardMaterial3D.new()
            var district_type = cp_data.get("district_type", 0)
            material.albedo_color = _get_district_color(district_type)
            material.emission_enabled = true
            material.emission = material.albedo_color * 1.5  # Brighter emission
            material.emission_energy = 5.0  # Higher energy
            material.roughness = 0.0
            material.metallic = 0.3
            material.flags_unshaded = true
            mesh_instance.material_override = material
            
            control_point.add_child(mesh_instance)
            
            logger.info("GameWorldManager", "Applied procedural control point %d at %s (type: %d)" % [control_point_index, world_position, district_type])
        else:
            logger.warning("GameWorldManager", "Control point %d not found in scene" % control_point_index)

func _apply_procedural_districts(districts_data: Dictionary) -> void:
    """Apply procedural districts to the 3D world"""
    logger.info("GameWorldManager", "Applying procedural districts")
    
    # Districts will be rendered through individual buildings and roads
    # This is a placeholder for any district-level 3D elements
    
    for district_id in districts_data:
        var district_data = districts_data[district_id]
        logger.info("GameWorldManager", "Processing district %s with %d buildings" % [district_id, district_data.get("buildings", []).size()])

func _apply_procedural_roads(roads_data: Dictionary) -> void:
    """Apply procedural roads to the 3D world"""
    logger.info("GameWorldManager", "Applying procedural roads using Kenny assets")
    logger.info("GameWorldManager", "Roads data keys: %s" % str(roads_data.keys()))
    
    var road_segments = roads_data.get("segments", [])
    logger.info("GameWorldManager", "Road segments count: %d" % road_segments.size())
    
    var tile_size = 3.0  # Should match MapGenerator.TILE_SIZE
    
    # Create a roads container if it doesn't exist
    var roads_container = scene_3d.get_node("Roads")
    if not roads_container:
        roads_container = Node3D.new()
        roads_container.name = "Roads"
        scene_3d.call_deferred("add_child", roads_container)
        logger.info("GameWorldManager", "Created roads container")
    
    # Clear existing roads
    for child in roads_container.get_children():
        child.queue_free()
    
    # Create road segments
    var created_segments = 0
    for i in range(min(road_segments.size(), 50)):  # Limit to 50 for performance
        var segment = road_segments[i]
        var start_pos = segment.get("start", Vector2i(0, 0))
        var end_pos = segment.get("end", Vector2i(0, 0))
        
        # Create road segment at midpoint
        var midpoint = Vector3(
            (start_pos.x + end_pos.x) * tile_size * 0.5,
            0,  # At ground level
            (start_pos.y + end_pos.y) * tile_size * 0.5
        )
        
        # Get road type and direction from segment data
        var road_type = segment.get("asset_type", "road_straight")
        var direction = segment.get("direction", "horizontal")
        
        # Load appropriate road asset based on type and direction
        var road_scene = _load_road_asset_by_type(road_type, direction)
        
        if road_scene:
            # Use intelligent Kenny asset
            var road_segment = road_scene.instantiate()
            road_segment.name = "RoadSegment_%d_%s" % [i, road_type]
            road_segment.position = midpoint
            
            # Scale road segments appropriately
            var scale_factor = randf_range(0.9, 1.1)
            road_segment.scale = Vector3(scale_factor, 1.0, scale_factor)
            
            # Use intelligent rotation based on direction
            if direction == "horizontal":
                road_segment.rotation_degrees.y = 0
            elif direction == "vertical":
                road_segment.rotation_degrees.y = 90
            else:
                # For intersections and curves, use minimal rotation
                road_segment.rotation_degrees.y = randf_range(0, 90) * round(randf_range(0, 4))
            
            roads_container.call_deferred("add_child", road_segment)
            created_segments += 1
            
            logger.info("GameWorldManager", "Created intelligent road segment %d: %s (%s) at %s" % [i, road_type, direction, midpoint])
        else:
            # Fallback to generic mesh if Kenny asset fails
            var road_segment = MeshInstance3D.new()
            road_segment.name = "RoadSegment_%d_fallback" % i
            road_segment.position = midpoint
            
            # Create road mesh
            var cylinder_mesh = CylinderMesh.new()
            cylinder_mesh.top_radius = 1.0
            cylinder_mesh.bottom_radius = 1.0
            cylinder_mesh.height = 0.3
            road_segment.mesh = cylinder_mesh
            
            # Create road material
            var material = StandardMaterial3D.new()
            material.albedo_color = Color.DARK_GRAY
            material.roughness = 0.2
            material.metallic = 0.1
            road_segment.material_override = material
            
            roads_container.call_deferred("add_child", road_segment)
            created_segments += 1
            
            logger.info("GameWorldManager", "Created fallback road segment %d at %s" % [i, midpoint])
    
    logger.info("GameWorldManager", "Applied %d road segments to 3D world" % created_segments)

func _apply_procedural_buildings(buildings_data: Dictionary) -> void:
    """Apply procedural buildings to the 3D world"""
    logger.info("GameWorldManager", "Applying procedural buildings using Kenny assets")
    logger.info("GameWorldManager", "Buildings data keys: %s" % str(buildings_data.keys()))
    
    var tile_size = 3.0  # Should match MapGenerator.TILE_SIZE
    
    # Create a buildings container if it doesn't exist
    var procedural_buildings_container = scene_3d.get_node("ProceduralBuildings")
    if not procedural_buildings_container:
        procedural_buildings_container = Node3D.new()
        procedural_buildings_container.name = "ProceduralBuildings"
        scene_3d.call_deferred("add_child", procedural_buildings_container)
        logger.info("GameWorldManager", "Created procedural buildings container")
    
    # Clear existing buildings
    for child in procedural_buildings_container.get_children():
        child.queue_free()
    
    var building_count = 0
    
    # Create buildings from each district
    for district_id in buildings_data:
        var district_buildings = buildings_data[district_id]
        logger.info("GameWorldManager", "Processing district %s with %d buildings" % [district_id, district_buildings.size()])
        
        for building_data in district_buildings:
            if building_count >= 40:  # Limit to 40 buildings for performance
                break
            
            var tile_position = building_data.get("position", Vector2i(0, 0))
            var building_type = building_data.get("type", "commercial")
            var building_size = building_data.get("size", Vector2i(2, 2))
            
            # Convert to world position
            var world_position = Vector3(
                tile_position.x * tile_size,
                0,
                tile_position.y * tile_size
            )
            
            # Get specific building type and calculated rotation
            var specific_building_type = building_data.get("type", building_type)
            var calculated_rotation = building_data.get("rotation", 0)
            var building_size = building_data.get("size", Vector2i(2, 2))
            
            # Load appropriate building asset based on specific type
            var building_scene = _load_building_asset_by_type(specific_building_type)
            
            if building_scene:
                # Use intelligent Kenny asset
                var building = building_scene.instantiate()
                building.name = "Building_%d_%s" % [building_count, specific_building_type]
                building.position = world_position
                
                # Scale buildings based on calculated size
                var scale_factor = (building_size.x + building_size.y) / 4.0  # Use size data for scaling
                scale_factor = clamp(scale_factor, 0.8, 1.5)  # Reasonable scale range
                building.scale = Vector3(scale_factor, scale_factor, scale_factor)
                
                # Use intelligent rotation from procedural generation
                building.rotation_degrees.y = calculated_rotation
                
                procedural_buildings_container.call_deferred("add_child", building)
                building_count += 1
                
                logger.info("GameWorldManager", "Created intelligent building %d: %s (size: %s, rotation: %d°) at %s" % [building_count, specific_building_type, building_size, calculated_rotation, world_position])
            else:
                # Fallback to generic mesh if Kenny asset fails
                var building = MeshInstance3D.new()
                building.name = "Building_%d_%s_fallback" % [building_count, building_type]
                building.position = world_position
                
                # Create building mesh
                var box_mesh = BoxMesh.new()
                var height = randf_range(4.0, 12.0)  # Random height between 4-12 units
                box_mesh.size = Vector3(
                    building_size.x * tile_size * 0.8,  # Slightly smaller than tile
                    height,
                    building_size.y * tile_size * 0.8
                )
                building.mesh = box_mesh
                
                # Create building material based on type
                var material = StandardMaterial3D.new()
                match building_type:
                    "commercial":
                        material.albedo_color = Color.LIGHT_BLUE
                    "industrial":
                        material.albedo_color = Color.DARK_GRAY
                    "shop":
                        material.albedo_color = Color.CYAN
                    "office":
                        material.albedo_color = Color.BLUE
                    "factory":
                        material.albedo_color = Color.BROWN
                    "warehouse":
                        material.albedo_color = Color.GRAY
                    _:
                        material.albedo_color = Color.WHITE
                
                # Add some variation and visibility
                material.roughness = randf_range(0.3, 0.8)
                material.metallic = randf_range(0.1, 0.4)
                
                # Add subtle emission for better visibility
                material.emission_enabled = true
                material.emission = material.albedo_color * 0.1
                material.emission_energy = 0.5
                
                building.material_override = material
                
                procedural_buildings_container.call_deferred("add_child", building)
                building_count += 1
                
                logger.info("GameWorldManager", "Created fallback building %d: %s at %s" % [building_count, building_type, world_position])
        
        if building_count >= 40:
            break
    
    logger.info("GameWorldManager", "Applied %d procedural buildings to 3D world" % building_count)

func _position_camera_for_procedural_map() -> void:
    """Position the camera to view the procedural map"""
    logger.info("GameWorldManager", "Positioning camera for procedural map")
    logger.info("GameWorldManager", "camera_3d available: %s" % (camera_3d != null))
    
    if camera_3d:
        # Position camera to view the center of the 20x20 tile map
        # Each tile is 3 units, so the map spans from 0 to 60 in both X and Z
        var map_center = Vector3(30, 0, 30)  # Center of the 60x60 world
        
        # Position camera at an isometric-like angle
        var camera_position = Vector3(45, 40, 45)  # Elevated and angled
        camera_3d.position = camera_position
        camera_3d.look_at(map_center, Vector3.UP)
        
        # Ensure the camera has a good field of view
        camera_3d.fov = 60.0
        
        logger.info("GameWorldManager", "Camera positioned at %s looking at %s" % [camera_3d.position, map_center])
        logger.info("GameWorldManager", "Camera FOV set to: %f" % camera_3d.fov)
    else:
        logger.warning("GameWorldManager", "Camera not found, cannot position for procedural map")

func _get_district_color(district_type: int) -> Color:
    """Get color for district type"""
    match district_type:
        0:  # Commercial
            return Color.CYAN
        1:  # Industrial
            return Color.ORANGE
        2:  # Mixed
            return Color.YELLOW
        3:  # Residential
            return Color.GREEN
        4:  # Military
            return Color.RED
        _:
            return Color.WHITE

func _initialize_ground_plane() -> void:
    """Initialize the ground plane with a visible material"""
    var ground_mesh = scene_3d.get_node("Ground/GroundMesh")
    if ground_mesh:
        # Create a visible ground material
        var ground_material = StandardMaterial3D.new()
        ground_material.albedo_color = Color(0.2, 0.6, 0.2)  # Green grass color
        ground_material.roughness = 0.8
        ground_material.metallic = 0.0
        ground_mesh.material_override = ground_material
        logger.info("GameWorldManager", "Ground plane material applied")
    else:
        # Create a new ground plane if it doesn't exist
        var ground_container = scene_3d.get_node("Ground")
        if not ground_container:
            ground_container = Node3D.new()
            ground_container.name = "Ground"
            scene_3d.call_deferred("add_child", ground_container)
        
        var ground_mesh_instance = MeshInstance3D.new()
        ground_mesh_instance.name = "GroundMesh"
        var plane_mesh = PlaneMesh.new()
        plane_mesh.size = Vector2(120, 120)  # Large ground plane
        ground_mesh_instance.mesh = plane_mesh
        ground_mesh_instance.position = Vector3(0, -0.5, 0)  # Slightly below world origin
        
        # Create ground material
        var ground_material = StandardMaterial3D.new()
        ground_material.albedo_color = Color(0.2, 0.6, 0.2)  # Green grass color
        ground_material.roughness = 0.8
        ground_material.metallic = 0.0
        ground_mesh_instance.material_override = ground_material
        
        ground_container.call_deferred("add_child", ground_mesh_instance)
        logger.info("GameWorldManager", "Ground plane created and material applied")

func _initialize_control_points_3d() -> void:
    """Initialize control points in the 3D world"""
    logger.info("GameWorldManager", "Initializing control points in 3D world")
    
    # Control points are already positioned in the scene
    # Add visual representations if needed
    for i in range(1, 10):  # Control points 1-9
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
            logger.info("GameWorldManager", "Control point %d visual added at height 3.0" % i)

func _initialize_buildings_3d() -> void:
    """Initialize building positions in the 3D world"""
    logger.info("GameWorldManager", "Initializing buildings in 3D world")
    # Buildings will be spawned dynamically during gameplay

func _initialize_units_3d() -> void:
    """Initialize unit containers in the 3D world"""
    logger.info("GameWorldManager", "Initializing units in 3D world")
    # Units will be spawned dynamically during gameplay

# Game display management
func update_game_display(state_data: Dictionary) -> void:
    """Update the game display with new state"""
    # Update units
    var units_data = state_data.get("units", [])
    for unit_data in units_data:
        var unit_id = unit_data.get("id", "")
        if unit_id != "":
            _update_unit_display(unit_id, unit_data)
    
    # Update buildings
    var buildings_data = state_data.get("buildings", [])
    for building_data in buildings_data:
        var building_id = building_data.get("id", "")
        if building_id != "":
            _update_building_display(building_id, building_data)
    
    # Update resources display
    var resources_data = state_data.get("resources", {})
    if resources_data.size() > 0:
        _update_resources_display(resources_data)
    
    # Update game time
    var game_time = state_data.get("game_time", 0.0)
    _update_game_time_display(game_time)
    
    game_display_updated.emit(state_data)

func _update_unit_display(unit_id: String, unit_data: Dictionary) -> void:
    """Update a unit's display"""
    var unit_display = displayed_units.get(unit_id)
    
    if not unit_display:
        # Create new unit display
        unit_display = _create_unit_display(unit_data)
        displayed_units[unit_id] = unit_display
        
        # Add to the 3D scene
        if scene_3d:
            scene_3d.add_child(unit_display)
            
            # Set position after adding to scene tree
            var position_array = unit_data.get("position", [0, 0, 0])
            var new_position = Vector3(position_array[0], position_array[1], position_array[2])
            unit_display.global_position = new_position
            
            logger.info("GameWorldManager", "Added unit %s to 3D scene at position %s" % [unit_id, unit_display.global_position])
        else:
            logger.error("GameWorldManager", "Could not find 3D scene to add unit %s" % unit_id)
    else:
        # Update existing unit position
        var position_array = unit_data.get("position", [0, 0, 0])
        var new_position = Vector3(position_array[0], position_array[1], position_array[2])
        unit_display.global_position = new_position
        
        logger.info("GameWorldManager", "Updated unit %s position to %s" % [unit_id, unit_display.global_position])

func _update_building_display(building_id: String, building_data: Dictionary) -> void:
    """Update a building's display"""
    var building_display = displayed_buildings.get(building_id)
    
    if not building_display:
        # Create new building display
        building_display = _create_building_display(building_data)
        displayed_buildings[building_id] = building_display
        
        # Add to the 3D scene
        if scene_3d:
            scene_3d.add_child(building_display)
            logger.info("GameWorldManager", "Added building %s to 3D scene" % building_id)
        else:
            logger.warning("GameWorldManager", "Could not find 3D scene to add building %s" % building_id)
    
    # Update position
    var position_array = building_data.get("position", [0, 0, 0])
    var position = Vector3(position_array[0], position_array[1], position_array[2])
    building_display.global_position = position
    
    # Update health
    var health = building_data.get("health", 100)
    var max_health = building_data.get("max_health", 100)
    
    if building_display.has_method("update_health"):
        building_display.update_health(health, max_health)

func _create_unit_display(unit_data: Dictionary) -> Node3D:
    """Create a unit display node"""
    var unit_id = unit_data.get("id", "unknown")
    var team_id = unit_data.get("team_id", 1)
    
    # Try to load Kenny character asset
    var character_scene = _load_character_asset()
    
    if character_scene:
        # Use Kenny character asset
        var unit_display = character_scene.instantiate()
        unit_display.name = "Unit_" + unit_id
        
        # Scale characters appropriately for RTS view
        var scale_factor = randf_range(1.5, 2.0)
        unit_display.scale = Vector3(scale_factor, scale_factor, scale_factor)
        
        # Add some random rotation for variety
        unit_display.rotation_degrees.y = randf_range(0, 360)
        
        # Add team color overlay by finding the MeshInstance3D and modifying materials
        _apply_team_color_to_character(unit_display, team_id)
        
        # Add collision for selection
        var collision_shape = CollisionShape3D.new()
        var box_shape = BoxShape3D.new()
        box_shape.size = Vector3(3, 6, 3)  # Approximate character size
        collision_shape.shape = box_shape
        unit_display.add_child(collision_shape)
        
        logger.info("GameWorldManager", "Created Kenny character unit for team %d: %s" % [team_id, unit_id])
        
        return unit_display
    else:
        # Fallback to generic mesh if Kenny asset fails
        var unit_display = CharacterBody3D.new()
        unit_display.name = "Unit_" + unit_id + "_fallback"
        
        # Add visual representation - make units MUCH larger and more visible
        var mesh_instance = MeshInstance3D.new()
        var box_mesh = BoxMesh.new()
        box_mesh.size = Vector3(5, 8, 5)  # Much larger size
        mesh_instance.mesh = box_mesh
        unit_display.add_child(mesh_instance)
        
        # Add collision shape
        var collision_shape = CollisionShape3D.new()
        var box_shape = BoxShape3D.new()
        box_shape.size = Vector3(5, 8, 5)
        collision_shape.shape = box_shape
        unit_display.add_child(collision_shape)
        
        # Add team colors for better visibility
        var material = StandardMaterial3D.new()
        
        # Team color coding - make them VERY bright
        if team_id == 1:
            material.albedo_color = Color.CYAN  # Bright cyan instead of blue
        elif team_id == 2:
            material.albedo_color = Color.MAGENTA  # Bright magenta instead of red
        else:
            material.albedo_color = Color.YELLOW  # Bright yellow
        
        # Make material VERY visible
        material.emission_enabled = true
        material.emission = material.albedo_color * 0.8  # Very bright emission
        material.emission_energy = 3.0  # High energy
        material.roughness = 0.3
        material.metallic = 0.1
        material.flags_unshaded = true  # Make it always bright
        
        mesh_instance.material_override = material
        
        logger.info("GameWorldManager", "Created fallback unit display for team %d with color %s" % [team_id, material.albedo_color])
        
        return unit_display

func _apply_team_color_to_character(character_node: Node3D, team_id: int) -> void:
    """Apply team color tinting to a Kenny character"""
    var team_color: Color
    
    # Define team colors
    if team_id == 1:
        team_color = Color.CYAN
    elif team_id == 2:
        team_color = Color.MAGENTA
    else:
        team_color = Color.YELLOW
    
    # Find all MeshInstance3D nodes and apply team color modulation
    _apply_team_color_recursive(character_node, team_color)

func _apply_team_color_recursive(node: Node, team_color: Color) -> void:
    """Recursively apply team color to all MeshInstance3D nodes"""
    if node is MeshInstance3D:
        var mesh_instance = node as MeshInstance3D
        
        # Create a new material or modify existing one
        var material = mesh_instance.material_override
        if not material:
            material = StandardMaterial3D.new()
            # Copy from the original material if it exists
            if mesh_instance.get_surface_override_material(0):
                var original = mesh_instance.get_surface_override_material(0)
                material.albedo_color = original.albedo_color
                material.roughness = original.roughness
                material.metallic = original.metallic
        
        # Apply team color modulation
        material.albedo_color = material.albedo_color * team_color
        material.emission_enabled = true
        material.emission = team_color * 0.3
        material.emission_energy = 1.0
        
        mesh_instance.material_override = material
    
    # Recursively apply to children
    for child in node.get_children():
        _apply_team_color_recursive(child, team_color)

func _create_building_display(building_data: Dictionary) -> Node3D:
    """Create a building display node"""
    var building_id = building_data.get("id", "unknown")
    var building_type = building_data.get("type", "commercial")
    var team_id = building_data.get("team_id", 0)
    
    # Try to load Kenny building asset
    var building_scene = _load_building_asset_by_type(building_type)
    
    if building_scene:
        # Use Kenny building asset
        var building_display = building_scene.instantiate()
        building_display.name = "Building_" + building_id
        
        # Scale buildings appropriately
        var scale_factor = randf_range(0.8, 1.2)
        building_display.scale = Vector3(scale_factor, scale_factor, scale_factor)
        
        # Add some random rotation for variety
        building_display.rotation_degrees.y = randf_range(0, 360)
        
        # Apply team coloring if the building is owned by a team
        if team_id > 0:
            _apply_team_color_to_building(building_display, team_id)
        
        logger.info("GameWorldManager", "Created Kenny building display: %s (team %d)" % [building_id, team_id])
        
        return building_display
    else:
        # Fallback to generic mesh if Kenny asset fails
        var building_display = Node3D.new()
        building_display.name = "Building_" + building_id + "_fallback"
        
        # Add visual representation (simplified)
        var mesh_instance = MeshInstance3D.new()
        mesh_instance.mesh = BoxMesh.new()
        mesh_instance.mesh.size = Vector3(2, 2, 2)
        building_display.add_child(mesh_instance)
        
        # Add team coloring
        var material = StandardMaterial3D.new()
        material.albedo_color = Color.DARK_RED if team_id == 1 else Color.DARK_BLUE
        mesh_instance.material_override = material
        
        logger.info("GameWorldManager", "Created fallback building display: %s (team %d)" % [building_id, team_id])
        
        return building_display

func _apply_team_color_to_building(building_node: Node3D, team_id: int) -> void:
    """Apply team color tinting to a Kenny building"""
    var team_color: Color
    
    # Define team colors
    if team_id == 1:
        team_color = Color.CYAN * 0.7  # Slightly darker for buildings
    elif team_id == 2:
        team_color = Color.MAGENTA * 0.7
    else:
        team_color = Color.YELLOW * 0.7
    
    # Find all MeshInstance3D nodes and apply team color modulation
    _apply_team_color_recursive(building_node, team_color)

func clear_game_display() -> void:
    """Clear the game display"""
    # Clear displayed units
    for unit_id in displayed_units:
        var unit_display = displayed_units[unit_id]
        if unit_display:
            unit_display.queue_free()
    displayed_units.clear()
    
    # Clear displayed buildings
    for building_id in displayed_buildings:
        var building_display = displayed_buildings[building_id]
        if building_display:
            building_display.queue_free()
    displayed_buildings.clear()
    
    # Clear selection
    selected_units.clear()
    
    logger.info("GameWorldManager", "Game display cleared")

func cleanup() -> void:
    """Cleanup game world resources"""
    clear_game_display()
    logger.info("GameWorldManager", "Game world manager cleanup complete")

func _update_resources_display(resources_data: Dictionary) -> void:
    """Update the resources display"""
    var resources_text = "Resources: "
    for team_id in resources_data:
        var team_resources = resources_data[team_id]
        resources_text += "Team %d - Energy: %d, Minerals: %d  " % [team_id, team_resources.get("energy", 0), team_resources.get("minerals", 0)]
    
    if main_node and main_node.has_node("GameUI"):
        var resources_label = main_node.get_node("GameUI/GameOverlay/TopPanel/ResourcesLabel")
        if resources_label:
            resources_label.text = resources_text

func _update_game_time_display(game_time: float) -> void:
    """Update the game time display"""
    var minutes = int(game_time / 60)
    var seconds = int(game_time) % 60
    var time_text = "%02d:%02d" % [minutes, seconds]
    
    if main_node and main_node.has_node("GameUI"):
        var time_label = main_node.get_node("GameUI/GameOverlay/TopPanel/GameTimeLabel")
        if time_label:
            time_label.text = "Time: " + time_text 