# RTSCamera.gd
class_name RTSCamera
extends Node3D

# Camera movement settings
@export_group("Movement")
@export var pan_speed: float = 30.0
@export var edge_scroll_margin: int = 20
@export var edge_scroll_speed: float = 40.0
@export var use_edge_scroll: bool = true

# Zoom settings
@export_group("Zoom")
@export var zoom_speed: float = 2.0  # Reduced from 5.0 for more precise control
@export var min_zoom: float = 5.0  # Reduced from 10.0 to allow much closer zoom
@export var max_zoom: float = 60.0
@export var zoom_smoothing: float = 10.0

# Bounds settings
@export_group("Bounds")
@export var use_bounds: bool = true
@export var min_x: float = -90.0  # Expanded for more camera movement
@export var max_x: float = 280.0  # Expanded for more camera movement  
@export var min_z: float = -90.0  # Expanded for more camera movement
@export var max_z: float = 280.0  # Expanded for more camera movement

# Mouse drag settings
@export_group("Mouse Drag")
@export var mouse_drag_sensitivity: float = 0.5
@export var invert_drag: bool = false

@export_group("Rotation")
@export var rotation_speed: float = 90.0 # degrees per second

# Internal variables
var camera_3d: Camera3D
var current_zoom: float = 20.0  # Closer default zoom (was 30.0)
var target_zoom: float = 20.0   # Closer default zoom (was 30.0)
var is_dragging: bool = false
var last_mouse_position: Vector2
var velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
    # Find or create Camera3D child
    camera_3d = get_node_or_null("Camera3D")
    if not camera_3d:
        camera_3d = Camera3D.new()
        camera_3d.name = "Camera3D"
        add_child(camera_3d)
    
    # Set initial camera position and rotation
    camera_3d.position = Vector3(0, current_zoom, current_zoom * 0.7)
    camera_3d.look_at(Vector3.ZERO, Vector3.UP)
    
    # Load edge scroll setting from config if available
    if has_node("/root/ConfigManager"):
        var config_manager = get_node("/root/ConfigManager")
        use_edge_scroll = config_manager.user_settings.get("edge_scroll_enabled", true)
    else:
        use_edge_scroll = true  # Default enabled
    
    # Add to groups for easy discovery
    add_to_group("rts_cameras")
    add_to_group("cameras")
    
    if has_node("/root/Logger"):
        var logger = get_node("/root/Logger")
        logger.info("RTSCamera", "RTS Camera initialized")
    else:
        print("RTSCamera: RTS Camera initialized")

func _unhandled_input(event: InputEvent) -> void:
    # Use _unhandled_input to avoid interfering with selection system
    # Only handle mouse events that don't conflict with left-click selection
    
    if event is InputEventMouseButton:
        # Mouse wheel zoom (these don't conflict with selection)
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
            get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
            get_viewport().set_input_as_handled()
        
        # Middle mouse button drag (doesn't conflict with left-click selection)
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            is_dragging = event.pressed
            if is_dragging:
                last_mouse_position = event.position
            get_viewport().set_input_as_handled()
    
    # Mouse motion for camera dragging (only when middle mouse is held)
    elif event is InputEventMouseMotion and is_dragging:
        var delta = event.position - last_mouse_position
        last_mouse_position = event.position
        
        # Convert mouse delta to world movement (invert Y-axis to feel natural)
        var movement = Vector3(delta.x, 0, -delta.y) * mouse_drag_sensitivity
        if invert_drag:
            movement *= -1
        
        # Apply movement relative to camera rotation
        var cam_transform = camera_3d.global_transform.basis
        var forward = -cam_transform.z
        forward.y = 0
        forward = forward.normalized()
        var right = cam_transform.x
        right.y = 0
        right = right.normalized()
        
        velocity = right * movement.x + forward * movement.z
        get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
    # Keyboard input
    var input_vector = Vector3.ZERO
    
    if Input.is_action_pressed("camera_left"):
        input_vector.x -= 1
    if Input.is_action_pressed("camera_right"):
        input_vector.x += 1
    if Input.is_action_pressed("camera_forward"):  # W key should move forward
        input_vector.z += 1
    if Input.is_action_pressed("camera_backward"):  # S key should move backward
        input_vector.z -= 1
    
    # Rotation input with Q and E keys - orbit around focus point
    var rotation_input: float = 0.0
    if Input.is_key_pressed(KEY_Q):
        rotation_input += 1.0
    if Input.is_key_pressed(KEY_E):
        rotation_input -= 1.0
    
    if rotation_input != 0.0:
        _orbit_around_ground_focus(rotation_input * rotation_speed * delta)
    
    # Edge scrolling
    if use_edge_scroll and get_viewport().gui_get_focus_owner() == null:
        var mouse_pos = get_viewport().get_mouse_position()
        var viewport_size = get_viewport().get_visible_rect().size
        
        if mouse_pos.x < edge_scroll_margin:
            input_vector.x -= 1
        elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
            input_vector.x += 1
        
        # Invert Y-axis for natural edge scrolling (mouse at top = move forward)
        if mouse_pos.y < edge_scroll_margin:
            input_vector.z += 1  # Move forward when mouse at top
        elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
            input_vector.z -= 1  # Move backward when mouse at bottom
    
    # Apply movement
    if input_vector.length() > 0:
        input_vector = input_vector.normalized()
        
        # Convert to world space based on camera orientation
        var cam_transform = camera_3d.global_transform.basis
        var forward = -cam_transform.z
        forward.y = 0
        forward = forward.normalized()
        var right = cam_transform.x
        right.y = 0
        right = right.normalized()
        
        var movement_speed = edge_scroll_speed if use_edge_scroll else pan_speed
        velocity = (right * input_vector.x + forward * input_vector.z) * movement_speed
    
    # Apply velocity
    if velocity.length() > 0:
        position += velocity * delta
        
        # Apply bounds
        if use_bounds:
            position.x = clamp(position.x, min_x, max_x)
            position.z = clamp(position.z, min_z, max_z)
        
        # Decay velocity when using mouse drag
        if is_dragging:
            velocity *= 0.95
        else:
            velocity = Vector3.ZERO
    
    # Smooth zoom
    if abs(current_zoom - target_zoom) > 0.1:
        current_zoom = lerp(current_zoom, target_zoom, zoom_smoothing * delta)
        _update_camera_position()  # Don't force center look during zoom changes

func _update_camera_position() -> void:
    if camera_3d:
        # Simple approach: maintain current look direction and adjust distance
        var current_look_direction = -camera_3d.global_transform.basis.z
        
        # Find where we're currently looking on the ground
        var camera_world_pos = camera_3d.global_position
        var ground_focus_point = _get_ground_intersection(camera_world_pos, current_look_direction)
        
        # Fallback if no ground intersection
        if ground_focus_point == Vector3.INF:
            # Use current camera XZ position projected to ground as focus
            ground_focus_point = Vector3(camera_world_pos.x, 0, camera_world_pos.z)
        
        # Calculate where camera node should be to achieve desired zoom distance
        var horizontal_distance = current_zoom * 0.8
        var height = current_zoom * 0.6
        
        # Get direction from focus point to current camera position (horizontal only)
        var current_direction = global_position - ground_focus_point
        current_direction.y = 0
        current_direction = current_direction.normalized()
        
        # If no clear direction (camera directly above focus), use a default
        if current_direction.length() < 0.1:
            current_direction = Vector3(0, 0, 1)  # Default backward direction
        
        # Position camera node at zoom distance from focus point
        global_position = ground_focus_point + current_direction * horizontal_distance
        global_position.y = height
        
        # Update camera local position for tactical angle
        var angle = deg_to_rad(-55)
        camera_3d.position = Vector3(
            0,
            current_zoom * sin(-angle),
            current_zoom * cos(-angle)
        )
        
        # Maintain look at focus point
        camera_3d.look_at(ground_focus_point, Vector3.UP)

func _update_camera_position_with_center_look() -> void:
    """Update camera position and force it to look at center - used for initial positioning only"""
    if camera_3d:
        # Update camera position based on zoom level with improved angle calculation
        var angle = deg_to_rad(-55)  # Slightly steeper angle for better close-up views
        camera_3d.position = Vector3(
            0,
            current_zoom * sin(-angle),
            current_zoom * cos(-angle)
        )
        camera_3d.look_at(Vector3.ZERO, Vector3.UP)

func set_position_2d(pos: Vector2) -> void:
    """Set camera position using 2D coordinates"""
    position = Vector3(pos.x, position.y, pos.y)
    if use_bounds:
        position.x = clamp(position.x, min_x, max_x)
        position.z = clamp(position.z, min_z, max_z)

func get_position_2d() -> Vector2:
    """Get camera position as 2D coordinates"""
    return Vector2(position.x, position.z)

func focus_on_position(target_pos: Vector3, instant: bool = false) -> void:
    """Move camera to focus on a specific position"""
    if instant:
        position = Vector3(target_pos.x, position.y, target_pos.z)
        if use_bounds:
            position.x = clamp(position.x, min_x, max_x)
            position.z = clamp(position.z, min_z, max_z)
    else:
        # TODO: Implement smooth camera movement
        position = Vector3(target_pos.x, position.y, target_pos.z)

func position_for_team_base(team_id: int, instant: bool = true) -> void:
    """Position and rotate the camera to focus on the team's home base for optimal tactical view"""
    # Get home base manager to find team base positions
    var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
    if not home_base_manager:
        print("RTSCamera: No home base manager found for team-based positioning")
        return
    
    var team_base_pos = home_base_manager.get_home_base_position(team_id)
    if team_base_pos == Vector3.ZERO:
        print("RTSCamera: No home base position found for team %d" % team_id)
        return
    
    # Set closer zoom level for team-based positioning
    var team_zoom_level = 15.0  # Closer than default 30.0, but not too close
    current_zoom = team_zoom_level
    target_zoom = team_zoom_level
    
    # Calculate optimal camera position for close tactical overview
    # Position camera at a closer angle that shows the home base and immediate area
    var camera_offset = Vector3()
    var look_target = Vector3()
    
    # Team-specific positioning for close tactical view
    match team_id:
        1:
            # Team 1 (Northwest base): Position camera southwest of base, looking northeast
            camera_offset = Vector3(-12, 20, -12)  # Closer and lower than before
            look_target = team_base_pos + Vector3(8, 0, 8)  # Look toward nearby battlefield
        2:
            # Team 2 (Southeast base): Position camera northeast of base, looking southwest
            camera_offset = Vector3(12, 20, 12)   # Closer and lower than before
            look_target = team_base_pos + Vector3(-8, 0, -8)  # Look toward nearby battlefield
        _:
            # Fallback: Position camera south of base, looking north
            camera_offset = Vector3(0, 20, 15)
            look_target = team_base_pos + Vector3(0, 0, -10)
    
    var camera_position = team_base_pos + camera_offset
    
    # Apply camera bounds
    if use_bounds:
        camera_position.x = clamp(camera_position.x, min_x, max_x)
        camera_position.z = clamp(camera_position.z, min_z, max_z)
    
    # Position the camera
    if instant:
        position = camera_position
    else:
        # Smooth camera movement (implement tween here if needed)
        position = camera_position
    
    # Set up team-specific camera angle and direction initially
    if camera_3d:
        camera_3d.position = Vector3(0, current_zoom * 0.7, current_zoom * 0.3)  # Steeper angle for closer view
        camera_3d.look_at(look_target - position, Vector3.UP)  # Set initial team-specific look direction
    
    # Log the positioning
    if has_node("/root/Logger"):
        var logger = get_node("/root/Logger")
        logger.info("RTSCamera", "Positioned camera for team %d at %s (zoom: %.1f), looking toward %s" % [team_id, camera_position, current_zoom, look_target])
    else:
        print("RTSCamera: Positioned camera for team %d at %s (zoom: %.1f), looking toward %s" % [team_id, camera_position, current_zoom, look_target])

func position_for_map_data(map_data: Dictionary, team_id: int = -1) -> void:
    """Position and configure camera based on procedural map data, optionally team-aware"""
    # If team ID is provided, use team-based positioning
    if team_id > 0:
        position_for_team_base(team_id, true)
        return
    
    # Original map-centered positioning (fallback)
    # Get map dimensions
    var tile_size = map_data.get("tile_size", 3.0)
    var grid_size = map_data.get("size", Vector2i(20, 20))
    var world_width = grid_size.x * tile_size
    var world_height = grid_size.y * tile_size
    var map_center = Vector3(world_width * 0.5, 0, world_height * 0.5)
    
    # Update camera bounds to match map size with some padding
    var padding = max(world_width, world_height) * 0.3
    min_x = -padding
    max_x = world_width + padding
    min_z = -padding
    max_z = world_height + padding
    
    # Position camera to view the map center
    position = Vector3(map_center.x, position.y, map_center.z)
    
    # Adjust zoom range based on map size with closer default for better gameplay
    var map_scale = max(world_width, world_height) / 60.0  # Normalized to default 60x60 map
    min_zoom = 5.0 * map_scale  # Allow closer zoom-in
    max_zoom = 80.0 * map_scale
    current_zoom = 20.0 * map_scale  # Closer default zoom than before (was 30.0)
    target_zoom = current_zoom
    
    # Update camera position and force center look for initial map positioning
    _update_camera_position_with_center_look()
    
    if has_node("/root/Logger"):
        var logger = get_node("/root/Logger")
        logger.info("RTSCamera", "Positioned for map: %sx%s units, zoom range: %s-%s, default zoom: %.1f" % [world_width, world_height, min_zoom, max_zoom, current_zoom])
    else:
        print("RTSCamera: Positioned for map: %sx%s units, zoom range: %s-%s, default zoom: %.1f" % [world_width, world_height, min_zoom, max_zoom, current_zoom])

func shake(_intensity: float = 1.0, _duration: float = 0.5) -> void:
    """Add camera shake effect"""
    # TODO: Implement camera shake
    pass 

func _orbit_around_ground_focus(rotation_degrees: float) -> void:
    """Orbit the camera around the point where it's looking at the ground (Y=0 plane)"""
    if not camera_3d:
        return
    
    # Get camera's world position and direction
    var camera_world_pos = camera_3d.global_position
    var camera_forward = -camera_3d.global_transform.basis.z
    
    # Calculate intersection with ground plane (Y=0)
    var ground_focus_point = _get_ground_intersection(camera_world_pos, camera_forward)
    if ground_focus_point == Vector3.INF:
        # No intersection found (camera pointing up), use a point in front of camera on ground
        var ground_point = camera_world_pos + camera_forward * 20.0  # 20 units forward
        ground_point.y = 0  # Project to ground
        ground_focus_point = ground_point
    
    # Calculate current offset from focus point to camera node position (not camera_3d position)
    var current_offset = global_position - ground_focus_point
    
    # Rotate the offset around Y-axis (vertical axis) using proper rotation matrix
    var rotation_radians = deg_to_rad(rotation_degrees)
    var cos_angle = cos(rotation_radians)
    var sin_angle = sin(rotation_radians)
    
    var rotated_offset = Vector3(
        current_offset.x * cos_angle - current_offset.z * sin_angle,
        current_offset.y,  # Keep Y the same
        current_offset.x * sin_angle + current_offset.z * cos_angle
    )
    
    # Calculate the new camera node position
    var new_position = ground_focus_point + rotated_offset
    
    # Apply bounds if enabled
    if use_bounds:
        new_position.x = clamp(new_position.x, min_x, max_x)
        new_position.z = clamp(new_position.z, min_z, max_z)
    
    # Apply the new position to the camera node
    global_position = new_position
    
    # Now rotate the camera's look direction to maintain focus on the ground point
    if camera_3d:
        # Calculate direction from new camera position to focus point
        var look_direction = (ground_focus_point - camera_3d.global_position).normalized()
        
        # Set camera rotation to look at the focus point
        camera_3d.look_at(camera_3d.global_position + look_direction, Vector3.UP)

func _get_ground_intersection(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
    """Calculate where a ray intersects with the ground plane (Y=0)"""
    # Ray-plane intersection formula: t = (plane_y - ray_origin.y) / ray_direction.y
    # Where plane_y = 0 for ground plane
    
    if abs(ray_direction.y) < 0.001:
        # Ray is nearly parallel to ground plane, no intersection
        return Vector3.INF
    
    var t = (0.0 - ray_origin.y) / ray_direction.y
    
    if t < 0:
        # Intersection is behind the camera
        return Vector3.INF
    
    # Calculate intersection point
    var intersection = ray_origin + ray_direction * t
    return intersection 