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

func initialize_procedural_world(dependency_container, team_id: int = -1) -> void:
    """Initialize the game world using procedural generation, optionally team-aware"""
    logger.info("ProceduralWorldRenderer", "Initializing procedural game world (team_id: %d)" % team_id)
    
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
    
    # Position RTS camera to view the procedural map with team-based positioning if available
    position_rts_camera_for_procedural_map(map_data, team_id)
    
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
    
    # Get map dimensions for logging
    var tile_size = map_data.get("tile_size", 3.33)
    var grid_size = map_data.get("size", Vector2i(60, 60))
    var _world_width = grid_size.x * tile_size  # Calculated for validation
    var _world_height = grid_size.y * tile_size  # Should be ~200x200
    
    # Center procedural map at origin (0,0,0) to align with ground plane and home bases
    var map_center = Vector3(0, 0, 0)
    
    # Remove existing ground plane if it exists
    var existing_ground = scene_3d.get_node_or_null("GroundPlane")
    if existing_ground:
        existing_ground.queue_free()
    
    # Create new ground plane
    var ground_plane = MeshInstance3D.new()
    ground_plane.name = "GroundPlane"
    
    # Create plane mesh sized to exactly match the 200x200 static ground plane
    var plane_mesh = PlaneMesh.new()
    plane_mesh.size = Vector2(200, 200)  # Exact match with static ground plane
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
        
        # Convert tile position to world position using centered coordinate system
        var center_offset = Vector2i(30, 30)  # Half of 60x60 grid
        var centered_tile_pos = tile_position - center_offset
        var world_position = Vector3(
            centered_tile_pos.x * tile_size,
            0,
            centered_tile_pos.y * tile_size
        )
        
        # Create or update control point
        var control_point_index = int(cp_id.split("_")[1]) + 1  # Convert cp_0 to 1, etc.
        var control_point = control_points_container.get_node_or_null("ControlPoint%d" % control_point_index)
        
        if not control_point:
            # Create control point node if it doesn't exist
            var ControlPointScript = load("res://scripts/gameplay/control_point.gd")
            control_point = ControlPointScript.new()
            control_point.name = "ControlPoint%d" % control_point_index
            control_point.position = world_position
            # Set control point properties directly instead of calling non-existent setup() method
            control_point.control_point_id = "CP_%d" % (control_point_index - 1)
            control_point.control_point_name = "Procedural Point %d" % control_point_index
            # Note: Control point collision prevention is handled in the control_point.gd _ready() method
            control_points_container.call_deferred("add_child", control_point)
            logger.info("ProceduralWorldRenderer", "Created control point %d at %s (no unit collision)" % [control_point_index, world_position])
        
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
            
            # Create road segment at tile position using centered coordinate system
            # Center the grid around origin to align with 200x200 ground plane
            var center_offset = Vector2i(30, 30)  # Half of 60x60 grid
            var centered_pos = position - center_offset
            var world_pos = Vector3(
                centered_pos.x * tile_size,
                0,
                centered_pos.y * tile_size
            )
            
            # Use actual asset type and rotation from road network generation
            var asset_type = segment.get("asset_type", "road-straight")
            var rotation = segment.get("rotation", 0.0)
            var road_scene = world_asset_manager.load_road_asset_by_type(asset_type, "")
            
            if road_scene:
                # Use correct Kenny asset based on connectivity
                var road_segment = road_scene.instantiate()
                road_segment.name = "Road_%s_%d" % [asset_type, i]
                road_segment.position = world_pos
                
                # Apply rotation from road network generation
                road_segment.rotation_degrees = Vector3(0, rotation, 0)
                
                # Use optimal scale from road network for proper connectivity
                if segment.has("optimal_scale") and segment.optimal_scale != null:
                    road_segment.scale = segment.optimal_scale
                    logger.info("ProceduralWorldRenderer", "Applied optimal scale %s to road %d" % [segment.optimal_scale, i])
                else:
                    # Fallback: scale to fill tile for connectivity
                    var scale_factor = tile_size / 1.0  # Assume 1.0 unit base asset size
                    road_segment.scale = Vector3(scale_factor, 1.0, scale_factor)
                    logger.info("ProceduralWorldRenderer", "Applied fallback scale %s to road %d" % [Vector3(scale_factor, 1.0, scale_factor), i])
                
                
                roads_container.call_deferred("add_child", road_segment)
                created_segments += 1
                
                logger.info("ProceduralWorldRenderer", "Created %s road at %s with rotation %.1f°" % [asset_type, world_pos, rotation])
            else:
                # Fallback to generic mesh if Kenny asset fails, but still use proper connectivity
                var road_segment = MeshInstance3D.new()
                road_segment.name = "Road_%s_%d_fallback" % [asset_type, i]
                road_segment.position = world_pos
                
                # Apply rotation even for fallback
                road_segment.rotation_degrees = Vector3(0, rotation, 0)
        
                # Create square road mesh (simplified fallback)
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
                
                logger.info("ProceduralWorldRenderer", "Created fallback %s road at %s with rotation %.1f°" % [asset_type, world_pos, rotation])
    
    logger.info("ProceduralWorldRenderer", "Applied %d road segments with proper asset types and rotations to 3D world" % created_segments)

func apply_procedural_buildings(buildings_data: Dictionary) -> void:
    """Apply procedural buildings to the 3D world based on the provided building data."""
    logger.info("ProceduralWorldRenderer", "Applying procedural buildings from building placer")
    
    var tile_size = buildings_data.get("tile_size", 3.33)
    
    var procedural_buildings_container = scene_3d.get_node("ProceduralBuildings")
    if not procedural_buildings_container:
        procedural_buildings_container = Node3D.new()
        procedural_buildings_container.name = "ProceduralBuildings"
        scene_3d.call_deferred("add_child", procedural_buildings_container)
        logger.info("ProceduralWorldRenderer", "Created procedural buildings container")
    
    for child in procedural_buildings_container.get_children():
        child.queue_free()
    
    var building_count = 0
    # Assuming a 60x60 grid from map_generator.gd
    var center_offset = Vector2i(30, 30)
    
    for district_id in buildings_data:
        if district_id == "tile_size": continue # Skip metadata key
        
        var district_buildings = buildings_data[district_id]
        if not district_buildings is Array:
            logger.warning("ProceduralWorldRenderer", "District buildings data for '%s' is not an array." % district_id)
            continue

        for building_info in district_buildings:
            var building_type = building_info.get("type")
            var building_pos_tile = building_info.get("position")
            var building_rotation = building_info.get("rotation", 0.0)
            var building_scale = building_info.get("optimal_scale", Vector3.ONE)

            var building_scene = world_asset_manager.load_building_asset_by_type(building_type)
            
            if building_scene:
                var building = building_scene.instantiate()
                building.name = "Building_%d_%s" % [building_count, building_type]
                
                var centered_tile_pos = building_pos_tile - center_offset
                var world_position = Vector3(
                    centered_tile_pos.x * tile_size,
                    0.1,
                    centered_tile_pos.y * tile_size
                )
                
                building.position = world_position
                building.scale = building_scale
                building.rotation_degrees.y = building_rotation
                
                procedural_buildings_container.add_child(building)
                building_count += 1
            else:
                logger.warning("ProceduralWorldRenderer", "Failed to load building asset for type: %s" % building_type)
    
    logger.info("ProceduralWorldRenderer", "Placed %d buildings from building placer data." % building_count)

func _extract_road_positions_from_scene() -> Dictionary:
    """Extract road positions from the scene's ProceduralRoads container to avoid placing buildings on roads"""
    var road_positions = {}
    
    # Try to get road data from the scene's ProceduralRoads container
    var roads_container = scene_3d.get_node_or_null("ProceduralRoads")
    if roads_container:
        for road_child in roads_container.get_children():
            if road_child.has_method("get_position") or road_child.position != Vector3.ZERO:
                var world_pos = road_child.position
                var tile_size = 3.33
                var center_offset = Vector2i(30, 30)
                
                # Convert world position back to tile coordinates
                var tile_x = int(round(world_pos.x / tile_size)) + center_offset.x
                var tile_y = int(round(world_pos.z / tile_size)) + center_offset.y
                
                var tile_key = str(tile_x) + "," + str(tile_y)
                road_positions[tile_key] = Vector2i(tile_x, tile_y)
    
    logger.info("ProceduralWorldRenderer", "Extracted %d road positions for building avoidance" % road_positions.size())
    return road_positions

func position_rts_camera_for_procedural_map(map_data: Dictionary, team_id: int = -1) -> void:
    """Position the RTS camera to view the procedural map using dynamic map data, optionally team-aware"""
    logger.info("ProceduralWorldRenderer", "Positioning RTS camera for procedural map (team_id: %d)" % team_id)
    
    # Find the RTS camera in the scene
    var rts_cameras = scene_3d.get_children().filter(func(node): return node is RTSCamera)
    
    if rts_cameras.size() > 0:
        var rts_camera = rts_cameras[0] as RTSCamera
        
        # Use the RTSCamera's built-in positioning method for map data with team support
        rts_camera.position_for_map_data(map_data, team_id)
        
        if team_id > 0:
            logger.info("ProceduralWorldRenderer", "RTS camera positioned for team %d with tactical focus on home base" % team_id)
        else:
            logger.info("ProceduralWorldRenderer", "RTS camera positioned with map-centered view")
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
    """Initialize the ground plane with a visible material aligned with the grid system"""
    var ground_mesh = scene_3d.get_node_or_null("Ground/GroundMesh")
    if ground_mesh:
        # Update existing ground plane material to match procedural system
        var ground_material = StandardMaterial3D.new()
        ground_material.albedo_color = Color(0.2, 0.6, 0.2)  # Green grass color
        ground_material.roughness = 0.8
        ground_material.metallic = 0.0
        ground_mesh.material_override = ground_material
        logger.info("ProceduralWorldRenderer", "Ground plane material applied to existing ground")
    else:
        # Create a new ground plane sized for the full grid system (200x200 to cover home bases)
        var ground_container = scene_3d.get_node_or_null("Ground")
        if not ground_container:
            ground_container = Node3D.new()
            ground_container.name = "Ground"
            scene_3d.call_deferred("add_child", ground_container)
        
        var ground_mesh_instance = MeshInstance3D.new()
        ground_mesh_instance.name = "GroundMesh"
        var plane_mesh = PlaneMesh.new()
        plane_mesh.size = Vector2(200, 200)  # Large enough to cover home bases at ±40
        ground_mesh_instance.mesh = plane_mesh
        ground_mesh_instance.position = Vector3(0, -0.5, 0)  # Slightly below world origin
        
        # Create ground material
        var ground_material = StandardMaterial3D.new()
        ground_material.albedo_color = Color(0.2, 0.6, 0.2)  # Green grass color
        ground_material.roughness = 0.8
        ground_material.metallic = 0.0
        ground_mesh_instance.material_override = ground_material
        
        ground_container.call_deferred("add_child", ground_mesh_instance)
        logger.info("ProceduralWorldRenderer", "Ground plane created: 200x200 units to cover home base grid")

func cleanup() -> void:
    """Cleanup procedural world renderer resources"""
    logger.info("ProceduralWorldRenderer", "Procedural world renderer cleanup complete") 