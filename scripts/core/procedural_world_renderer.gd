# ProceduralWorldRenderer.gd - Handle procedural world rendering
class_name ProceduralWorldRenderer
extends Node

# Dependencies
var logger
var world_asset_manager
var scene_3d
var camera_3d
var control_points_container

# Signals
signal procedural_world_rendered()

func _ready() -> void:
    # Initialize when added to scene tree
    pass

func setup(logger_instance, world_asset_manager_instance, scene_3d_instance, camera_3d_instance, control_points_container_instance) -> void:
    """Setup the procedural world renderer with dependencies"""
    logger = logger_instance
    world_asset_manager = world_asset_manager_instance
    scene_3d = scene_3d_instance
    camera_3d = camera_3d_instance
    control_points_container = control_points_container_instance
    
    logger.info("ProceduralWorldRenderer", "Procedural world renderer setup complete")

func initialize_procedural_world(dependency_container) -> void:
    """Initialize the game world using procedural generation"""
    logger.info("ProceduralWorldRenderer", "Initializing procedural game world")
    
    var map_generator = dependency_container.get_map_generator()
    logger.info("ProceduralWorldRenderer", "Map generator retrieved: %s" % (map_generator != null))
    
    if not map_generator:
        logger.error("ProceduralWorldRenderer", "MapGenerator not available, cannot render procedural world")
        return
    
    # Generate the procedural map
    var generation_seed = randi()  # Could be configurable or from game settings
    logger.info("ProceduralWorldRenderer", "Generating procedural map with seed: %d" % generation_seed)
    
    # Generate the map data
    var map_data = await map_generator.generate_map(generation_seed)
    logger.info("ProceduralWorldRenderer", "Map generation completed. Data size: %d keys" % map_data.size())
    
    if map_data.is_empty():
        logger.error("ProceduralWorldRenderer", "Map generation failed, cannot render procedural world")
        return
    
    # Debug: Print map data structure
    logger.info("ProceduralWorldRenderer", "Map data keys: %s" % str(map_data.keys()))
    for key in map_data.keys():
        var value = map_data[key]
        if value is Dictionary:
            logger.info("ProceduralWorldRenderer", "  %s: Dictionary with %d keys" % [str(key), value.size()])
        elif value is Array:
            logger.info("ProceduralWorldRenderer", "  %s: Array with %d elements" % [str(key), value.size()])
        else:
            logger.info("ProceduralWorldRenderer", "  %s: %s" % [str(key), str(value)])
    
    # Apply the generated map to the 3D world
    apply_procedural_map(map_data)
    
    # Position RTS camera to view the procedural map with mouse controls
    position_rts_camera_for_procedural_map(map_data)
    
    procedural_world_rendered.emit()
    logger.info("ProceduralWorldRenderer", "Procedural world initialization complete")

func apply_procedural_map(map_data: Dictionary) -> void:
    """Apply the procedural map data to the 3D world"""
    logger.info("ProceduralWorldRenderer", "Applying procedural map to 3D world")
    logger.info("ProceduralWorldRenderer", "scene_3d available: %s" % (scene_3d != null))
    logger.info("ProceduralWorldRenderer", "control_points_container available: %s" % (control_points_container != null))
    
    if not scene_3d:
        logger.error("ProceduralWorldRenderer", "scene_3d not available - cannot apply procedural map")
        return
    
    # Create ground plane sized and positioned to match the procedural map
    create_aligned_ground_plane(map_data)
    
    # Get tile size for consistent use
    var tile_size = map_data.get("tile_size", 3.0)
    
    # Apply control points from map data with actual tile size
    apply_procedural_control_points(map_data.get("control_points", {}), tile_size)
    
    # Apply districts and buildings
    apply_procedural_districts(map_data.get("districts", {}))
    
    # Apply road networks with tile size
    var roads_data = map_data.get("roads", {})
    roads_data["tile_size"] = tile_size
    apply_procedural_roads(roads_data)
    
    # Apply buildings with tile size
    var buildings_data = map_data.get("buildings", {})
    buildings_data["tile_size"] = tile_size
    apply_procedural_buildings(buildings_data)
    
    logger.info("ProceduralWorldRenderer", "Procedural map applied to 3D world")

func create_aligned_ground_plane(map_data: Dictionary) -> void:
    """Create a ground plane that is properly aligned with the procedural map"""
    logger.info("ProceduralWorldRenderer", "Creating aligned ground plane for procedural map")
    
    # Get map dimensions
    var tile_size = map_data.get("tile_size", 3.0)
    var grid_size = map_data.get("size", Vector2i(20, 20))
    var world_width = grid_size.x * tile_size
    var world_height = grid_size.y * tile_size
    
    # Calculate map center (procedural map starts at 0,0 and goes to world_width, world_height)
    var map_center = Vector3(world_width * 0.5, 0, world_height * 0.5)
    
    # Remove existing ground plane if it exists
    var existing_ground = scene_3d.get_node_or_null("GroundPlane")
    if existing_ground:
        existing_ground.queue_free()
    
    # Create new ground plane
    var ground_plane = MeshInstance3D.new()
    ground_plane.name = "GroundPlane"
    
    # Create plane mesh sized to match map with some margin
    var plane_mesh = PlaneMesh.new()
    plane_mesh.size = Vector2(world_width * 1.2, world_height * 1.2)  # 20% margin
    ground_plane.mesh = plane_mesh
    
    # Position the ground plane at the map center
    ground_plane.position = Vector3(map_center.x, -0.1, map_center.z)  # Slightly below ground level
    
    # Create ground material
    var ground_material = StandardMaterial3D.new()
    ground_material.albedo_color = Color(0.2, 0.6, 0.2)  # Green
    ground_material.roughness = 0.8
    ground_material.metallic = 0.0
    ground_plane.material_override = ground_material
    
    # Add to scene
    scene_3d.call_deferred("add_child", ground_plane)
    
    logger.info("ProceduralWorldRenderer", "Ground plane created: %sx%s units centered at %s" % [
        plane_mesh.size.x, plane_mesh.size.y, map_center
    ])

func apply_procedural_control_points(control_points_data: Dictionary, tile_size: float) -> void:
    """Apply procedural control points to the 3D world"""
    logger.info("ProceduralWorldRenderer", "Applying procedural control points with tile size: %.2f" % tile_size)
    logger.info("ProceduralWorldRenderer", "Control points data size: %d" % control_points_data.size())
    
    if not control_points_container:
        logger.error("ProceduralWorldRenderer", "control_points_container not available")
        return
    
    for cp_id in control_points_data:
        var cp_data = control_points_data[cp_id]
        var tile_position = cp_data.get("position", Vector2i(0, 0))
        
        # Convert tile position to world position using actual tile size
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
            material.albedo_color = get_district_color(district_type)
            material.emission_enabled = true
            material.emission = material.albedo_color * 1.5  # Brighter emission
            material.emission_energy = 5.0  # Higher energy
            material.roughness = 0.0
            material.metallic = 0.3
            material.flags_unshaded = true
            mesh_instance.material_override = material
            
            control_point.add_child(mesh_instance)
            
            logger.info("ProceduralWorldRenderer", "Applied procedural control point %d at %s (type: %d)" % [control_point_index, world_position, district_type])
        else:
            logger.warning("ProceduralWorldRenderer", "Control point %d not found in scene" % control_point_index)

func apply_procedural_districts(districts_data: Dictionary) -> void:
    """Apply procedural districts to the 3D world"""
    logger.info("ProceduralWorldRenderer", "Applying procedural districts")
    
    # Districts will be rendered through individual buildings and roads
    # This is a placeholder for any district-level 3D elements
    
    for district_id in districts_data:
        var district_data = districts_data[district_id]
        logger.info("ProceduralWorldRenderer", "Processing district %s with %d buildings" % [district_id, district_data.get("buildings", []).size()])

func apply_procedural_roads(roads_data: Dictionary) -> void:
    """Apply procedural roads to the 3D world using square road tiles"""
    logger.info("ProceduralWorldRenderer", "Applying procedural roads using square Kenny assets")
    logger.info("ProceduralWorldRenderer", "Roads data keys: %s" % str(roads_data.keys()))
    
    # Get dynamic tile size from map data
    var tile_size = 3.0  # Default fallback
    if "tile_size" in roads_data:
        tile_size = roads_data.get("tile_size", 3.0)
    
    # Create a roads container if it doesn't exist
    var roads_container = scene_3d.get_node("ProceduralRoads")
    if not roads_container:
        roads_container = Node3D.new()
        roads_container.name = "ProceduralRoads"
        scene_3d.call_deferred("add_child", roads_container)
        logger.info("ProceduralWorldRenderer", "Created procedural roads container")
    
    # Clear existing roads
    for child in roads_container.get_children():
        child.queue_free()
    
    var created_segments = 0
    
    # Process road segments using square tiles
    if roads_data.has("segments"):
        for i in range(roads_data.segments.size()):
            var segment = roads_data.segments[i]
            var position = segment.get("position", Vector2i(0, 0))
            
            # Create road segment at tile position
            var world_pos = Vector3(
                position.x * tile_size,
                0,  # At ground level
                position.y * tile_size
            )
            
            # Use square road asset for everything
            var asset_type = segment.get("asset_type", "road_square")
            var road_scene = world_asset_manager.load_road_asset_by_type(asset_type, "")
            
            if road_scene:
                # Use square Kenny asset
                var road_segment = road_scene.instantiate()
                road_segment.name = "RoadSquare_%d" % i
                road_segment.position = world_pos
                
                # Use optimal scale from road network for proper connectivity
                if segment.has("optimal_scale") and segment.optimal_scale != null:
                    road_segment.scale = segment.optimal_scale
                    logger.info("ProceduralWorldRenderer", "Applied optimal scale %s to road %d" % [segment.optimal_scale, i])
                else:
                    # Fallback: scale to fill tile for connectivity
                    var scale_factor = tile_size / 1.0  # Assume 1.0 unit base asset size
                    road_segment.scale = Vector3(scale_factor, 1.0, scale_factor)
                    logger.info("ProceduralWorldRenderer", "Applied fallback scale %s to road %d" % [Vector3(scale_factor, 1.0, scale_factor), i])
                
                # No rotation needed for square tiles
                road_segment.rotation_degrees = Vector3.ZERO
                
                roads_container.call_deferred("add_child", road_segment)
                created_segments += 1
                
                logger.info("ProceduralWorldRenderer", "Created square road tile %d at %s" % [i, world_pos])
            else:
                # Fallback to generic square mesh if Kenny asset fails
                var road_segment = MeshInstance3D.new()
                road_segment.name = "RoadSquare_%d_fallback" % i
                road_segment.position = world_pos
        
                # Create square road mesh
                var box_mesh = BoxMesh.new()
                box_mesh.size = Vector3(tile_size, 0.1, tile_size)  # Flat square
                road_segment.mesh = box_mesh
                
                # Create road material
                var material = StandardMaterial3D.new()
                material.albedo_color = Color.DARK_GRAY
                material.roughness = 0.3
                material.metallic = 0.0
                road_segment.material_override = material
                
                roads_container.call_deferred("add_child", road_segment)
                created_segments += 1
                
                logger.info("ProceduralWorldRenderer", "Created fallback square road tile %d at %s" % [i, world_pos])
    
    logger.info("ProceduralWorldRenderer", "Applied %d square road tiles to 3D world" % created_segments)

func apply_procedural_buildings(buildings_data: Dictionary) -> void:
    """Apply procedural buildings to the 3D world"""
    logger.info("ProceduralWorldRenderer", "Applying procedural buildings using Kenny assets")
    logger.info("ProceduralWorldRenderer", "Buildings data keys: %s" % str(buildings_data.keys()))
    
    # Get dynamic tile size from map data
    var tile_size = 3.0  # Default fallback
    if "tile_size" in buildings_data:
        tile_size = buildings_data.get("tile_size", 3.0)
    
    # Create a buildings container if it doesn't exist
    var procedural_buildings_container = scene_3d.get_node("ProceduralBuildings")
    if not procedural_buildings_container:
        procedural_buildings_container = Node3D.new()
        procedural_buildings_container.name = "ProceduralBuildings"
        scene_3d.call_deferred("add_child", procedural_buildings_container)
        logger.info("ProceduralWorldRenderer", "Created procedural buildings container")
    
    # Clear existing buildings
    for child in procedural_buildings_container.get_children():
        child.queue_free()
    
    var building_count = 0
    
    # Create buildings from each district
    for district_id in buildings_data:
        # Skip non-district keys like "tile_size"
        if district_id == "tile_size" or not buildings_data[district_id] is Array:
            continue
            
        var district_buildings = buildings_data[district_id]
        logger.info("ProceduralWorldRenderer", "Processing district %s with %d buildings" % [district_id, district_buildings.size()])
        
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
            var building_size_data = building_data.get("size", Vector2i(2, 2))
            
            # Load appropriate building asset based on specific type
            var building_scene = world_asset_manager.load_building_asset_by_type(specific_building_type)
            
            if building_scene:
                # Use intelligent Kenny asset
                var building = building_scene.instantiate()
                building.name = "Building_%d_%s" % [building_count, specific_building_type]
                building.position = world_position
                
                # Use optimal scale from building placement system (2x scaling)
                if building_data.has("optimal_scale") and building_data.optimal_scale != null:
                    building.scale = building_data.optimal_scale
                    logger.info("ProceduralWorldRenderer", "Applied 2x scaling %s to building %s" % [building_data.optimal_scale, specific_building_type])
                else:
                    # Fallback: Apply 2x scaling for better road proportions
                    building.scale = Vector3(2.0, 2.0, 2.0)
                    logger.info("ProceduralWorldRenderer", "Applied fallback 2x scaling to building %s" % specific_building_type)
                
                # Use intelligent rotation from procedural generation
                building.rotation_degrees.y = calculated_rotation
                
                procedural_buildings_container.call_deferred("add_child", building)
                building_count += 1
                
                var connectivity_status = building_data.get("connectivity_valid", true)
                var scaling_status = building_data.get("metadata", {}).get("scaled_2x", false)
                logger.info("ProceduralWorldRenderer", "Created scaled building %d: %s (size: %s, rotation: %d°, 2x scale: %s) at %s" % [building_count, specific_building_type, building_size_data, calculated_rotation, scaling_status, world_position])
            else:
                # Fallback to generic mesh if Kenny asset fails
                var building = MeshInstance3D.new()
                building.name = "Building_%d_%s_fallback" % [building_count, building_type]
                building.position = world_position
                
                # Create building mesh with 2x scaling considerations
                var box_mesh = BoxMesh.new()
                var height = randf_range(4.0, 12.0)  # Random height between 4-12 units
                
                # Apply 2x scaling to mesh size for consistency with Kenny assets
                var base_size_x = building_size.x * tile_size * 0.8
                var base_size_z = building_size.y * tile_size * 0.8
                
                box_mesh.size = Vector3(
                    base_size_x * 2.0,  # 2x width
                    height * 2.0,       # 2x height
                    base_size_z * 2.0   # 2x depth
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
                
                logger.info("ProceduralWorldRenderer", "Created fallback building %d: %s at %s" % [building_count, building_type, world_position])
        
        if building_count >= 40:
            break
    
    logger.info("ProceduralWorldRenderer", "Applied %d procedural buildings to 3D world" % building_count)

func position_rts_camera_for_procedural_map(map_data: Dictionary) -> void:
    """Position the RTS camera to view the procedural map using dynamic map data"""
    logger.info("ProceduralWorldRenderer", "Positioning RTS camera for procedural map")
    
    # Find the RTS camera in the scene
    var rts_cameras = scene_3d.get_children().filter(func(node): return node is RTSCamera)
    
    if rts_cameras.size() > 0:
        var rts_camera = rts_cameras[0] as RTSCamera
        
        # Use the RTSCamera's built-in positioning method for map data
        rts_camera.position_for_map_data(map_data)
        
        logger.info("ProceduralWorldRenderer", "RTS camera positioned with mouse controls enabled")
    else:
        logger.warning("ProceduralWorldRenderer", "No RTS camera found for positioning")
        # Fallback to old method if RTS camera not found
        position_camera_for_procedural_map(map_data)

func position_camera_for_procedural_map(map_data: Dictionary) -> void:
    """Position the camera to view the procedural map using actual map dimensions"""
    logger.info("ProceduralWorldRenderer", "Positioning camera for procedural map")
    logger.info("ProceduralWorldRenderer", "camera_3d available: %s" % (camera_3d != null))
    
    if camera_3d:
        # Get actual tile size from map data
        var tile_size = map_data.get("tile_size", 3.0)  # Default fallback
        var grid_size = map_data.get("size", Vector2i(20, 20))  # Default 20x20 grid
        
        # Calculate actual world dimensions
        var world_width = grid_size.x * tile_size
        var world_height = grid_size.y * tile_size
        
        # Calculate map center based on actual dimensions
        var map_center = Vector3(world_width * 0.5, 0, world_height * 0.5)
        
        # Position camera at an isometric-like angle, scaled to map size
        var camera_distance = max(world_width, world_height) * 0.8  # Scale distance to map size
        var camera_position = Vector3(
            map_center.x + camera_distance * 0.7, 
            camera_distance * 0.6,  # Height proportional to distance
            map_center.z + camera_distance * 0.7
        )
        
        camera_3d.position = camera_position
        camera_3d.look_at(map_center, Vector3.UP)
        
        # Adjust field of view based on map size
        var optimal_fov = clamp(45.0 + (camera_distance / 10.0), 50.0, 75.0)
        camera_3d.fov = optimal_fov
        
        logger.info("ProceduralWorldRenderer", "Camera positioned at %s looking at %s" % [camera_3d.position, map_center])
        logger.info("ProceduralWorldRenderer", "Map size: %sx%s units (tile_size: %s), Camera FOV: %s" % [world_width, world_height, tile_size, camera_3d.fov])
    else:
        logger.warning("ProceduralWorldRenderer", "Camera not found, cannot position for procedural map")

func get_district_color(district_type: int) -> Color:
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

func initialize_ground_plane() -> void:
    """Initialize the ground plane with a visible material"""
    var ground_mesh = scene_3d.get_node("Ground/GroundMesh")
    if ground_mesh:
        # Create a visible ground material
        var ground_material = StandardMaterial3D.new()
        ground_material.albedo_color = Color(0.2, 0.6, 0.2)  # Green grass color
        ground_material.roughness = 0.8
        ground_material.metallic = 0.0
        ground_mesh.material_override = ground_material
        logger.info("ProceduralWorldRenderer", "Ground plane material applied")
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
        logger.info("ProceduralWorldRenderer", "Ground plane created and material applied")

func cleanup() -> void:
    """Cleanup procedural world renderer resources"""
    logger.info("ProceduralWorldRenderer", "Procedural world renderer cleanup complete") 