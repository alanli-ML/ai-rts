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
@export var zoom_speed: float = 5.0
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
    
    # Rotation input with Q and E keys
    var rotation_input: float = 0.0
    if Input.is_key_pressed(KEY_E):
        rotation_input += 1.0
    if Input.is_key_pressed(KEY_Q):
        rotation_input -= 1.0
    
    if rotation_input != 0.0:
        rotate_y(deg_to_rad(rotation_input * rotation_speed * delta))
    
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
        _update_camera_position()

func _update_camera_position() -> void:
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
    
    # Update camera angle for closer view with steeper angle
    if camera_3d:
        camera_3d.position = Vector3(0, current_zoom * 0.7, current_zoom * 0.3)  # Steeper angle for closer view
        camera_3d.look_at(look_target - position, Vector3.UP)
    
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
    
    # Update camera position based on new zoom
    _update_camera_position()
    
    if has_node("/root/Logger"):
        var logger = get_node("/root/Logger")
        logger.info("RTSCamera", "Positioned for map: %sx%s units, zoom range: %s-%s, default zoom: %.1f" % [world_width, world_height, min_zoom, max_zoom, current_zoom])
    else:
        print("RTSCamera: Positioned for map: %sx%s units, zoom range: %s-%s, default zoom: %.1f" % [world_width, world_height, min_zoom, max_zoom, current_zoom])

func shake(_intensity: float = 1.0, _duration: float = 0.5) -> void:
    """Add camera shake effect"""
    # TODO: Implement camera shake
    pass 