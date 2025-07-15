# UnifiedMain.gd - Refactored main script using manager classes
extends Node

# Manager classes
var network_manager
var ui_manager
var game_world_manager
var input_manager

# Core components
var dependency_container
var logger

func _ready() -> void:
    print("UnifiedMain starting...")
    
    # Wait for autoloads to be available
    await get_tree().process_frame
    
    # Initialize dependencies using autoload
    dependency_container = get_node("/root/DependencyContainer")
    logger = dependency_container.get_logger()
    
    logger.info("UnifiedMain", "Starting unified application")
    
    # Create and setup managers
    _create_managers()
    
    # Connect manager signals
    _connect_manager_signals()
    
    # Determine if we're running headless (server mode)
    if OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
        _start_server_mode()
    else:
        _start_client_mode()
    
    logger.info("UnifiedMain", "UnifiedMain initialization complete")

func _create_managers() -> void:
    """Create and setup all manager classes"""
    logger.info("UnifiedMain", "Creating manager classes")
    
    # Create managers (no need to add them as children)
    network_manager = preload("res://scripts/core/network_manager.gd").new()
    ui_manager = preload("res://scripts/core/ui_manager.gd").new()
    game_world_manager = preload("res://scripts/core/game_world_manager.gd").new()
    input_manager = preload("res://scripts/core/input_manager.gd").new()
    
    # Setup managers directly
    network_manager.setup(logger, dependency_container)
    logger.info("UnifiedMain", "NetworkManager setup complete")
    
    ui_manager.setup(logger, network_manager, self)
    logger.info("UnifiedMain", "UIManager setup complete")
    
    game_world_manager.setup(logger, dependency_container, self)
    logger.info("UnifiedMain", "GameWorldManager setup complete")
    
    input_manager.setup(logger, network_manager, ui_manager)
    logger.info("UnifiedMain", "InputManager setup complete")
    
    logger.info("UnifiedMain", "Manager classes created and setup complete")

func _connect_manager_signals() -> void:
    """Connect signals between managers"""
    logger.info("UnifiedMain", "Connecting manager signals")
    
    # UI Manager signals
    ui_manager.server_mode_selected.connect(_on_server_mode_selected)
    ui_manager.connect_requested.connect(_on_connect_requested)
    ui_manager.disconnect_requested.connect(_on_disconnect_requested)
    ui_manager.ready_state_changed.connect(_on_ready_state_changed)
    ui_manager.game_start_requested.connect(_on_game_start_requested)
    ui_manager.leave_lobby_requested.connect(_on_leave_lobby_requested)
    
    # Network Manager signals
    network_manager.game_state_update.connect(_on_game_state_update)
    network_manager.game_started.connect(_on_game_started)
    
    # Game World Manager signals
    game_world_manager.world_initialized.connect(_on_world_initialized)
    
    logger.info("UnifiedMain", "Manager signals connected")

func _start_server_mode() -> void:
    """Start in server mode"""
    logger.info("UnifiedMain", "Starting server mode")
    
    # Create server dependencies
    dependency_container.create_server_dependencies()
    
    # Initialize server systems
    _initialize_server_systems()
    
    # Show game UI immediately for non-headless server testing
    if DisplayServer.get_name() != "headless":
        logger.info("UnifiedMain", "Non-headless server mode - showing game UI for testing")
        ui_manager.show_game_ui()
        await game_world_manager.initialize_game_world()
    
    logger.info("UnifiedMain", "Server mode started")

func _start_client_mode() -> void:
    """Start in client mode"""
    logger.info("UnifiedMain", "Starting client mode")
    
    # Create client dependencies
    dependency_container.create_client_dependencies()
    
    # Initialize client systems
    _initialize_client_systems()
    
    # Show mode selection
    ui_manager.show_mode_selection()
    
    logger.info("UnifiedMain", "Client mode started")

func _initialize_server_systems() -> void:
    """Initialize all server-side systems"""
    logger.info("UnifiedMain", "Initializing server systems")
    
    # Get system references from dependency container
    var ai_command_processor = dependency_container.get_ai_command_processor()
    var resource_manager = dependency_container.get_resource_manager()
    var node_capture_system = dependency_container.get_node_capture_system()
    
    # Set system references in input manager for testing
    input_manager.set_system_references(ai_command_processor, resource_manager, node_capture_system)
    
    # Connect server system signals
    _connect_server_signals()
    
    logger.info("UnifiedMain", "Server systems initialized")

func _initialize_client_systems() -> void:
    """Initialize all client-side systems"""
    logger.info("UnifiedMain", "Initializing client systems")
    
    # Get system references from dependency container
    var game_hud_system = dependency_container.get_game_hud()
    var speech_bubble_system = dependency_container.get_speech_bubble_manager()
    var plan_progress_system = dependency_container.get_plan_progress_manager()
    
    # Initialize UI systems
    if game_hud_system:
        logger.info("UnifiedMain", "Game HUD system initialized")
    
    if speech_bubble_system:
        logger.info("UnifiedMain", "Speech bubble system initialized")
    
    if plan_progress_system:
        logger.info("UnifiedMain", "Plan progress system initialized")
    
    # Connect client system signals
    _connect_client_signals()
    
    logger.info("UnifiedMain", "Client systems initialized")

func _connect_server_signals() -> void:
    """Connect server system signals"""
    logger.info("UnifiedMain", "Connecting server signals")
    
    # Get system references
    var resource_manager = dependency_container.get_resource_manager()
    var node_capture_system = dependency_container.get_node_capture_system()
    
    # Connect resource manager signals
    if resource_manager:
        resource_manager.resource_changed.connect(_on_resource_changed)
        resource_manager.resource_insufficient.connect(_on_resource_insufficient)
    
    # Connect control point signals
    if node_capture_system:
        node_capture_system.control_point_captured.connect(_on_control_point_captured)
        node_capture_system.victory_condition_met.connect(_on_victory_condition_met)
    
    logger.info("UnifiedMain", "Server signals connected")

func _connect_client_signals() -> void:
    """Connect client system signals"""
    logger.info("UnifiedMain", "Connecting client signals")
    logger.info("UnifiedMain", "Client signals connected")

# Manager signal handlers
func _on_server_mode_selected() -> void:
    """Handle server mode selection"""
    logger.info("UnifiedMain", "Server mode selected")
    _start_server_mode()

func _on_connect_requested(address: String) -> void:
    """Handle connection request"""
    logger.info("UnifiedMain", "Connection requested: %s" % address)
    network_manager.set_server_address(address)
    network_manager.connect_to_server()

func _on_disconnect_requested() -> void:
    """Handle disconnect request"""
    logger.info("UnifiedMain", "Disconnect requested")
    network_manager.disconnect_from_server()

func _on_ready_state_changed(ready_state: bool) -> void:
    """Handle ready state change"""
    logger.info("UnifiedMain", "Ready state changed: %s" % ready_state)
    network_manager.set_ready(ready_state)

func _on_game_start_requested() -> void:
    """Handle game start request"""
    logger.info("UnifiedMain", "Game start requested")
    network_manager.start_game()

func _on_leave_lobby_requested() -> void:
    """Handle leave lobby request"""
    logger.info("UnifiedMain", "Leave lobby requested")
    network_manager.leave_lobby()

func _on_game_state_update(data: Dictionary) -> void:
    """Handle game state updates"""
    logger.info("UnifiedMain", "Game state update received")
    game_world_manager.update_game_display(data)

func _on_game_started(data: Dictionary) -> void:
    """Handle game started notification"""
    logger.info("UnifiedMain", "Game started - initializing world")
    ui_manager.show_game_ui()
    await game_world_manager.initialize_game_world()

func _on_world_initialized() -> void:
    """Handle world initialization completion"""
    logger.info("UnifiedMain", "World initialization complete")

# System signal handlers
func _on_resource_changed(team_id: int, resource_type, amount: int) -> void:
    """Handle resource change events"""
    logger.info("UnifiedMain", "Resource changed: Team %d, %s: %d" % [team_id, resource_type, amount])

func _on_resource_insufficient(team_id: int, resource_type, required: int, available: int) -> void:
    """Handle resource insufficiency events"""
    logger.info("UnifiedMain", "Resource insufficient: Team %d, %s (required: %d, available: %d)" % [team_id, resource_type, required, available])

func _on_control_point_captured(control_point_id: int, team_id: int) -> void:
    """Handle control point capture events"""
    logger.info("UnifiedMain", "Control point captured: Point %d by Team %d" % [control_point_id, team_id])

func _on_victory_condition_met(team_id: int, victory_type: String) -> void:
    """Handle victory achievement events"""
    logger.info("UnifiedMain", "Victory achieved: Team %d via %s" % [team_id, victory_type])

# Input handling
func _unhandled_input(event: InputEvent) -> void:
    """Handle unhandled input events"""
    if input_manager and input_manager.handle_unhandled_input(event):
        return

func _input(event: InputEvent) -> void:
    """Forward input events to appropriate managers and ensure SubViewport receives input"""
    
    # Forward input to input manager first
    if input_manager and input_manager.handle_regular_input(event):
        return  # Input was handled
    
    # Ensure mouse and camera input reaches the SubViewport for RTS camera controls
    var game_world_viewport = get_node_or_null("GameUI/GameWorldContainer/GameWorld")
    if game_world_viewport and game_world_viewport is SubViewport:
        # Forward camera-related input to the SubViewport
        if event is InputEventMouseButton or event is InputEventMouseMotion:
            # Check if the mouse is over the game world area
            var game_world_container = get_node_or_null("GameUI/GameWorldContainer")
            if game_world_container and _is_mouse_over_game_world(event, game_world_container):
                game_world_viewport.push_input(event)
        elif event is InputEventKey:
            # Forward camera movement keys
            if _is_camera_input(event):
                game_world_viewport.push_input(event)

func _is_mouse_over_game_world(event: InputEvent, container: Control) -> bool:
    """Check if mouse event is over the game world container"""
    if event is InputEventMouse:
        var mouse_event = event as InputEventMouse
        var container_rect = container.get_global_rect()
        return container_rect.has_point(mouse_event.global_position)
    return false

func _is_camera_input(event: InputEventKey) -> bool:
    """Check if the key event is for camera controls"""
    if not event.pressed:
        return false
        
    # Check for camera movement keys
    return (event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D] or
            Input.is_action_pressed("camera_forward") or
            Input.is_action_pressed("camera_left") or
            Input.is_action_pressed("camera_backward") or
            Input.is_action_pressed("camera_right"))

func cleanup() -> void:
    """Cleanup resources"""
    logger.info("UnifiedMain", "Starting cleanup")
    
    # Cleanup managers
    if network_manager:
        network_manager.cleanup()
    if ui_manager:
        ui_manager.cleanup()
    if game_world_manager:
        game_world_manager.cleanup()
    if input_manager:
        input_manager.cleanup()
    
    # Cleanup dependency container
    if dependency_container:
        dependency_container.cleanup()
    
    logger.info("UnifiedMain", "Cleanup complete")

func _exit_tree() -> void:
    """Handle scene tree exit"""
    cleanup() 