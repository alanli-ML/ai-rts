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
@export var min_zoom: float = 10.0
@export var max_zoom: float = 60.0
@export var zoom_smoothing: float = 10.0

# Bounds settings
@export_group("Bounds")
@export var use_bounds: bool = true
@export var min_x: float = -50.0
@export var max_x: float = 150.0
@export var min_z: float = -50.0
@export var max_z: float = 150.0

# Mouse drag settings
@export_group("Mouse Drag")
@export var mouse_drag_sensitivity: float = 0.5
@export var invert_drag: bool = false

# Internal variables
var camera_3d: Camera3D
var current_zoom: float = 30.0
var target_zoom: float = 30.0
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
    
    # Load edge scroll setting from config
    use_edge_scroll = ConfigManager.user_settings.get("edge_scroll_enabled", true)
    
    # Add to groups for easy discovery
    add_to_group("rts_cameras")
    add_to_group("cameras")
    
    Logger.info("RTSCamera", "RTS Camera initialized")

func _input(event: InputEvent) -> void:
    # Mouse wheel zoom
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
        
        # Middle mouse button drag
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            is_dragging = event.pressed
            if is_dragging:
                last_mouse_position = event.position
    
    # Mouse motion for dragging
    elif event is InputEventMouseMotion and is_dragging:
        var delta = event.position - last_mouse_position
        last_mouse_position = event.position
        
        # Convert mouse delta to world movement
        var movement = Vector3(delta.x, 0, delta.y) * mouse_drag_sensitivity
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

func _process(delta: float) -> void:
    # Keyboard input
    var input_vector = Vector3.ZERO
    
    if Input.is_action_pressed("camera_left"):
        input_vector.x -= 1
    if Input.is_action_pressed("camera_right"):
        input_vector.x += 1
    if Input.is_action_pressed("camera_forward"):
        input_vector.z -= 1
    if Input.is_action_pressed("camera_backward"):
        input_vector.z += 1
    
    # Edge scrolling
    if use_edge_scroll and get_viewport().gui_get_focus_owner() == null:
        var mouse_pos = get_viewport().get_mouse_position()
        var viewport_size = get_viewport().get_visible_rect().size
        
        if mouse_pos.x < edge_scroll_margin:
            input_vector.x -= 1
        elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
            input_vector.x += 1
        
        if mouse_pos.y < edge_scroll_margin:
            input_vector.z -= 1
        elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
            input_vector.z += 1
    
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
        # Update camera position based on zoom level
        var angle = deg_to_rad(-60)  # Camera angle
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

func shake(_intensity: float = 1.0, _duration: float = 0.5) -> void:
    """Add camera shake effect"""
    # TODO: Implement camera shake
    pass 