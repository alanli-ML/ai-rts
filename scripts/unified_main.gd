# UnifiedMain.gd - Main script for unified architecture
extends Node

# UI references
@onready var menu_container = $MenuContainer
@onready var mode_selection = $MenuContainer/ModeSelection
@onready var server_button = $MenuContainer/ModeSelection/ServerButton
@onready var client_button = $MenuContainer/ModeSelection/ClientButton
@onready var status_label = $MenuContainer/StatusLabel
@onready var game_ui = $GameUI
@onready var connection_panel = $MenuContainer/ConnectionPanel
@onready var server_address_input = $MenuContainer/ConnectionPanel/ServerAddressInput
@onready var connect_button = $MenuContainer/ConnectionPanel/ConnectionButtons/ConnectButton
@onready var disconnect_button = $MenuContainer/ConnectionPanel/ConnectionButtons/DisconnectButton

# Lobby UI references
@onready var lobby_ui = $LobbyUI
@onready var session_info_label = $LobbyUI/LobbyPanel/LobbyContainer/SessionInfo
@onready var players_list = $LobbyUI/LobbyPanel/LobbyContainer/PlayersList
@onready var ready_status_label = $LobbyUI/LobbyPanel/LobbyContainer/ReadyStatus
@onready var ready_button = $LobbyUI/LobbyPanel/LobbyContainer/LobbyButtons/ReadyButton
@onready var start_button = $LobbyUI/LobbyPanel/LobbyContainer/LobbyButtons/StartButton
@onready var leave_lobby_button = $LobbyUI/LobbyPanel/LobbyContainer/LobbyButtons/LeaveLobbyButton

# Game UI references
@onready var game_hud = $GameUI/GameHUD
@onready var speech_bubble_manager = $GameUI/SpeechBubbleManager
@onready var plan_progress_manager = $GameUI/PlanProgressManager
@onready var game_world = $GameUI/GameWorld
@onready var testing_suite = $TestingSuite
@onready var close_testing_button = $TestingSuite/TestingPanel/TestingContainer/TestingButtons/CloseTestingButton

# 3D World references
@onready var scene_3d = $"GameUI/GameWorldContainer/GameWorld/3DView"
@onready var camera_3d = $"GameUI/GameWorldContainer/GameWorld/3DView/Camera3D"
@onready var control_points_container = $"GameUI/GameWorldContainer/GameWorld/3DView/ControlPoints"
@onready var buildings_container = $"GameUI/GameWorldContainer/GameWorld/3DView/Buildings"
@onready var units_container = $"GameUI/GameWorldContainer/GameWorld/3DView/Units"
@onready var team1_units_container = $"GameUI/GameWorldContainer/GameWorld/3DView/Units/Team1Units"
@onready var team2_units_container = $"GameUI/GameWorldContainer/GameWorld/3DView/Units/Team2Units"

# Core components
var dependency_container
var game_mode
var logger

# New system references
var ai_command_processor
var resource_manager
var node_capture_system
var game_hud_system
var speech_bubble_system
var plan_progress_system

# Client state
var is_connected: bool = false
var current_session_id: String = ""
var client_peer: ENetMultiplayerPeer
var server_address: String = "127.0.0.1"
var server_port: int = 7777

# Lobby state
var is_in_lobby: bool = false
var is_ready: bool = false
var lobby_players: Dictionary = {}
var can_start_game: bool = false

# Game state display
var displayed_units: Dictionary = {}
var displayed_buildings: Dictionary = {}
var displayed_control_points: Dictionary = {}
var selected_units: Array = []

# Testing state
var is_testing_mode: bool = false

# Signals
signal connected_to_server()
signal disconnected_from_server()
signal game_state_updated(state_data: Dictionary)

func _ready() -> void:
    print("UnifiedMain starting...")
    
    # Wait for autoloads to be available
    await get_tree().process_frame
    
    # Initialize dependencies using autoload
    dependency_container = get_node("/root/DependencyContainer")
    
    # Get logger
    logger = dependency_container.get_logger()
    logger.info("UnifiedMain", "Starting unified application")
    
    # Setup UI
    _setup_ui()
    
    # Setup input handling
    _setup_input_handling()
    
    # Determine if we're running headless (server mode)
    if OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
        _start_server_mode()
    else:
        _start_client_mode()

func _setup_ui() -> void:
    """Setup the UI elements"""
    if not DisplayServer.get_name() == "headless":
        # Setup button connections
        server_button.pressed.connect(_on_server_mode_selected)
        client_button.pressed.connect(_on_client_mode_selected)
        connect_button.pressed.connect(_on_connect_pressed)
        disconnect_button.pressed.connect(_on_disconnect_pressed)
        
        # Setup lobby button connections
        ready_button.pressed.connect(_on_ready_pressed)
        start_button.pressed.connect(_on_start_pressed)
        leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
        
        # Setup testing button connections
        if close_testing_button:
            close_testing_button.pressed.connect(_on_close_testing_pressed)
        
        # Setup initial UI state
        _update_ui_state()
        
        # Setup game UI
        game_ui.visible = false
        testing_suite.visible = false
        
        logger.info("UnifiedMain", "UI setup complete")

func _setup_input_handling() -> void:
    """Setup input handling for testing and game controls"""
    # Input will be handled in _unhandled_input
    pass

func _unhandled_input(event: InputEvent) -> void:
    """Handle input events for testing and game controls"""
    if event is InputEventKey and event.pressed:
        # Testing mode toggle
        if event.keycode == KEY_T:
            _toggle_testing_mode()
            
        # Only handle test inputs if in testing mode
        if is_testing_mode:
            _handle_test_input(event.keycode)

func _toggle_testing_mode() -> void:
    """Toggle testing mode visibility"""
    is_testing_mode = not is_testing_mode
    if testing_suite:
        testing_suite.visible = is_testing_mode
    
    logger.info("UnifiedMain", "Testing mode: %s" % ("ON" if is_testing_mode else "OFF"))

func _handle_test_input(keycode: int) -> void:
    """Handle test input based on keycode"""
    match keycode:
        KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12:
            _test_ai_integration(keycode - KEY_F1 + 1)
        KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
            _test_control_point_capture(keycode - KEY_1 + 1)
        KEY_0:
            _test_control_point_status()
        KEY_MINUS:
            _test_control_point_reset()
        KEY_EQUAL:
            _test_control_point_victory()
        KEY_R:
            _test_resource_management()
        KEY_H:
            _test_resource_help()
        KEY_P:
            _test_plan_progress()
        KEY_S:
            _test_speech_bubbles()

func _test_ai_integration(test_id: int) -> void:
    """Test AI integration system"""
    logger.info("UnifiedMain", "Testing AI integration scenario %d" % test_id)
    if ai_command_processor:
        # Simulate AI command processing
        var test_command = "Test AI command %d" % test_id
        logger.info("UnifiedMain", "Executing AI test: %s" % test_command)

func _test_control_point_capture(control_point_id: int) -> void:
    """Test control point capture"""
    logger.info("UnifiedMain", "Testing control point %d capture" % control_point_id)
    if node_capture_system:
        # Simulate control point capture
        logger.info("UnifiedMain", "Capturing control point %d" % control_point_id)

func _test_control_point_status() -> void:
    """Test control point status display"""
    logger.info("UnifiedMain", "Testing control point status")
    if node_capture_system:
        logger.info("UnifiedMain", "Displaying control point status")

func _test_control_point_reset() -> void:
    """Test control point reset"""
    logger.info("UnifiedMain", "Testing control point reset")
    if node_capture_system:
        logger.info("UnifiedMain", "Resetting control points")

func _test_control_point_victory() -> void:
    """Test control point victory conditions"""
    logger.info("UnifiedMain", "Testing control point victory")
    if node_capture_system:
        logger.info("UnifiedMain", "Checking victory conditions")

func _test_resource_management() -> void:
    """Test resource management system"""
    logger.info("UnifiedMain", "Testing resource management")
    if resource_manager:
        logger.info("UnifiedMain", "Resource management test")

func _test_resource_help() -> void:
    """Test resource help display"""
    logger.info("UnifiedMain", "Testing resource help")
    if resource_manager:
        logger.info("UnifiedMain", "Displaying resource help")

func _test_plan_progress() -> void:
    """Test plan progress indicators"""
    logger.info("UnifiedMain", "Testing plan progress indicators")
    if plan_progress_system:
        logger.info("UnifiedMain", "Testing plan progress display")

func _test_speech_bubbles() -> void:
    """Test speech bubble system"""
    logger.info("UnifiedMain", "Testing speech bubbles")
    if speech_bubble_system:
        logger.info("UnifiedMain", "Testing speech bubble display")

func _on_close_testing_pressed() -> void:
    """Handle close testing button press"""
    _toggle_testing_mode()

func _start_server_mode() -> void:
    """Start in server mode"""
    logger.info("UnifiedMain", "Starting server mode")
    
    # Create server dependencies directly without GameMode autoload
    dependency_container.create_server_dependencies()
    
    # Initialize server systems
    _initialize_server_systems()
    
    # Hide UI for headless server
    if DisplayServer.get_name() == "headless":
        if menu_container:
            menu_container.visible = false
        if game_ui:
            game_ui.visible = false
    
    logger.info("UnifiedMain", "Server mode started")

func _start_client_mode() -> void:
    """Start in client mode"""
    logger.info("UnifiedMain", "Starting client mode")
    
    # Create client dependencies directly without GameMode autoload
    dependency_container.create_client_dependencies()
    
    # Initialize client systems
    _initialize_client_systems()
    
    # Show mode selection
    _show_mode_selection()
    
    logger.info("UnifiedMain", "Client mode started")

func _initialize_server_systems() -> void:
    """Initialize all server-side systems"""
    logger.info("UnifiedMain", "Initializing server systems")
    
    # Get system references from dependency container
    ai_command_processor = dependency_container.get_ai_command_processor()
    resource_manager = dependency_container.get_resource_manager()
    node_capture_system = dependency_container.get_node_capture_system()
    
    # Initialize systems
    if ai_command_processor:
        logger.info("UnifiedMain", "AI command processor initialized")
    
    if resource_manager:
        resource_manager.initialize_teams([1, 2])
        logger.info("UnifiedMain", "Resource manager initialized")
    
    if node_capture_system:
        node_capture_system.initialize_control_points()
        logger.info("UnifiedMain", "Node capture system initialized")
    
    # Connect server system signals
    _connect_server_signals()
    
    logger.info("UnifiedMain", "Server systems initialized")

func _initialize_client_systems() -> void:
    """Initialize all client-side systems"""
    logger.info("UnifiedMain", "Initializing client systems")
    
    # Get system references from dependency container
    game_hud_system = dependency_container.get_game_hud()
    speech_bubble_system = dependency_container.get_speech_bubble_manager()
    plan_progress_system = dependency_container.get_plan_progress_manager()
    
    # Initialize UI systems
    if game_hud_system:
        game_hud_system.initialize()
        logger.info("UnifiedMain", "Game HUD system initialized")
    
    if speech_bubble_system:
        speech_bubble_system.initialize(speech_bubble_manager)
        logger.info("UnifiedMain", "Speech bubble system initialized")
    
    if plan_progress_system:
        plan_progress_system.initialize(plan_progress_manager)
        logger.info("UnifiedMain", "Plan progress system initialized")
    
    # Connect client system signals
    _connect_client_signals()
    
    logger.info("UnifiedMain", "Client systems initialized")

func _connect_server_signals() -> void:
    """Connect server system signals"""
    logger.info("UnifiedMain", "Connecting server signals")
    
    # Connect resource manager signals
    if resource_manager:
        resource_manager.resource_changed.connect(_on_resource_changed)
        resource_manager.resource_depleted.connect(_on_resource_depleted)
    
    # Connect control point signals
    if node_capture_system:
        node_capture_system.control_point_captured.connect(_on_control_point_captured)
        node_capture_system.victory_achieved.connect(_on_victory_achieved)
    
    # Connect AI system signals
    if ai_command_processor:
        ai_command_processor.plan_created.connect(_on_plan_created)
        ai_command_processor.plan_completed.connect(_on_plan_completed)
    
    logger.info("UnifiedMain", "Server signals connected")

func _connect_client_signals() -> void:
    """Connect client system signals"""
    logger.info("UnifiedMain", "Connecting client signals")
    
    # Connect to EventBus signals
    # if EventBus:
    #     EventBus.game_state_updated.connect(_on_game_state_updated)
    #     EventBus.resource_updated.connect(_on_resource_updated)
    #     EventBus.control_point_updated.connect(_on_control_point_updated)
    #     EventBus.unit_speech_requested.connect(_on_unit_speech_requested)
    #     EventBus.plan_progress_updated.connect(_on_plan_progress_updated)
    
    logger.info("UnifiedMain", "Client signals connected")

# Signal handlers for server systems
func _on_resource_changed(team_id: int, resource_type: String, amount: int) -> void:
    """Handle resource change events"""
    logger.info("UnifiedMain", "Resource changed: Team %d, %s: %d" % [team_id, resource_type, amount])

func _on_resource_depleted(team_id: int, resource_type: String) -> void:
    """Handle resource depletion events"""
    logger.info("UnifiedMain", "Resource depleted: Team %d, %s" % [team_id, resource_type])

func _on_control_point_captured(control_point_id: int, team_id: int) -> void:
    """Handle control point capture events"""
    logger.info("UnifiedMain", "Control point captured: Point %d by Team %d" % [control_point_id, team_id])

func _on_victory_achieved(team_id: int, victory_type: String) -> void:
    """Handle victory achievement events"""
    logger.info("UnifiedMain", "Victory achieved: Team %d via %s" % [team_id, victory_type])

func _on_plan_created(plan_id: String, unit_id: String) -> void:
    """Handle plan creation events"""
    logger.info("UnifiedMain", "Plan created: %s for unit %s" % [plan_id, unit_id])

func _on_plan_completed(plan_id: String, unit_id: String) -> void:
    """Handle plan completion events"""
    logger.info("UnifiedMain", "Plan completed: %s for unit %s" % [plan_id, unit_id])

# Signal handlers for client systems
func _on_game_state_updated(state_data: Dictionary) -> void:
    """Handle game state updates"""
    logger.info("UnifiedMain", "Game state updated")
    emit_signal("game_state_updated", state_data)

func _on_resource_updated(team_id: int, resources: Dictionary) -> void:
    """Handle resource updates"""
    if game_hud_system:
        game_hud_system.update_resources(team_id, resources)

func _on_control_point_updated(control_point_data: Dictionary) -> void:
    """Handle control point updates"""
    if game_hud_system:
        game_hud_system.update_control_points(control_point_data)

func _on_unit_speech_requested(unit_id: String, message: String, team_id: int) -> void:
    """Handle unit speech requests"""
    if speech_bubble_system:
        speech_bubble_system.show_unit_speech(unit_id, message, team_id)

func _on_plan_progress_updated(unit_id: String, progress_data: Dictionary) -> void:
    """Handle plan progress updates"""
    if plan_progress_system:
        plan_progress_system.update_progress(unit_id, progress_data)

func _show_mode_selection() -> void:
    """Show the mode selection UI"""
    if menu_container:
        menu_container.visible = true
        mode_selection.visible = true
        connection_panel.visible = false
        lobby_ui.visible = false
        game_ui.visible = false
        testing_suite.visible = false
    
    _update_status("Select game mode")

func _show_connection_panel() -> void:
    """Show the connection panel"""
    if menu_container:
        mode_selection.visible = false
        connection_panel.visible = true
        lobby_ui.visible = false
        game_ui.visible = false
        testing_suite.visible = false
        server_address_input.text = server_address
    
    _update_status("Enter server address")

func _show_lobby_ui() -> void:
    """Show the lobby UI"""
    if menu_container and lobby_ui:
        menu_container.visible = false
        lobby_ui.visible = true
        game_ui.visible = false
        testing_suite.visible = false
        is_in_lobby = true
    
    _update_lobby_display()
    _update_status("In lobby - waiting for players")

func _show_game_ui() -> void:
    """Show the game UI and initialize game world"""
    logger.info("UnifiedMain", "_show_game_ui() called - checking UI elements")
    logger.info("UnifiedMain", "menu_container: %s, lobby_ui: %s, game_ui: %s" % [menu_container != null, lobby_ui != null, game_ui != null])
    
    if menu_container and lobby_ui and game_ui:
        logger.info("UnifiedMain", "All UI elements found - hiding menu and lobby, showing game")
        menu_container.visible = false
        lobby_ui.visible = false
        game_ui.visible = true
        is_in_lobby = false
        
        # Initialize game world
        _initialize_game_world()
        
        # Initialize UI systems with proper references
        _initialize_game_ui_systems()
        
        logger.info("UnifiedMain", "Game UI initialized and visible")
    else:
        logger.error("UnifiedMain", "Missing UI elements - cannot show game UI")

func _initialize_game_world() -> void:
    """Initialize the 3D game world with control points and other elements"""
    logger.info("UnifiedMain", "Initializing game world")
    
    # Initialize ground plane material for better visibility
    _initialize_ground_plane()
    
    # Initialize control points in the 3D world
    if control_points_container:
        _initialize_control_points_3d()
    
    # Initialize building positions
    if buildings_container:
        _initialize_buildings_3d()
    
    # Initialize unit containers
    if units_container:
        _initialize_units_3d()
    
    logger.info("UnifiedMain", "Game world initialized")

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
        logger.info("UnifiedMain", "Ground plane material applied")
    else:
        logger.warning("UnifiedMain", "Ground mesh not found")

func _initialize_control_points_3d() -> void:
    """Initialize control points in the 3D world"""
    logger.info("UnifiedMain", "Initializing control points in 3D world")
    
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
            
            control_point.add_child.call_deferred(mesh_instance)
            logger.info("UnifiedMain", "Control point %d visual added at height 3.0" % i)

func _initialize_buildings_3d() -> void:
    """Initialize building positions in the 3D world"""
    logger.info("UnifiedMain", "Initializing buildings in 3D world")
    # Buildings will be spawned dynamically during gameplay

func _initialize_units_3d() -> void:
    """Initialize unit containers in the 3D world"""
    logger.info("UnifiedMain", "Initializing units in 3D world")
    # Units will be spawned dynamically during gameplay

func _initialize_game_ui_systems() -> void:
    """Initialize game UI systems with proper references"""
    logger.info("UnifiedMain", "Initializing game UI systems")
    
    # UI systems are already initialized and configured
    # The game_hud_system IS the game_hud, so no need to set references
    if game_hud_system:
        logger.info("UnifiedMain", "Game HUD system ready")
    
    if speech_bubble_system:
        logger.info("UnifiedMain", "Speech bubble system ready")
    
    if plan_progress_system:
        logger.info("UnifiedMain", "Plan progress system ready")
    
    logger.info("UnifiedMain", "Game UI systems initialized")

func _update_lobby_display() -> void:
    """Update the lobby display with current session info"""
    if not is_in_lobby:
        return
    
    # Update session info
    if session_info_label:
        session_info_label.text = "Session: %s" % current_session_id
    
    # Clear existing player list
    if players_list:
        for child in players_list.get_children():
            child.queue_free()
    
    # Add current players
    for player_id in lobby_players:
        var player_data = lobby_players[player_id]
        var player_label = Label.new()
        var ready_status = " (Ready)" if player_data.get("ready", false) else " (Not Ready)"
        var team_info = " - Team %d" % player_data.get("team_id", 0)
        player_label.text = "%s%s%s" % [player_id, team_info, ready_status]
        player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        players_list.add_child(player_label)
    
    # Update ready status
    if ready_status_label:
        if can_start_game:
            ready_status_label.text = "All players ready! You can start the game."
        elif lobby_players.size() == 1:
            ready_status_label.text = "Single player mode - you can start anytime!"
        else:
            ready_status_label.text = "Waiting for players to ready up..."
    
    # Update button states
    if ready_button:
        ready_button.text = "Not Ready" if is_ready else "Ready"
        ready_button.disabled = false
    
    if start_button:
        start_button.disabled = not can_start_game

func _update_status(message: String) -> void:
    """Update the status label"""
    if status_label:
        status_label.text = message
    
    logger.info("UnifiedMain", "Status: %s" % message)

func _update_ui_state() -> void:
    """Update UI state based on connection"""
    if not connect_button or not disconnect_button:
        return
    
    connect_button.disabled = is_connected
    disconnect_button.disabled = not is_connected
    
    if server_address_input:
        server_address_input.editable = not is_connected

# Button handlers
func _on_server_mode_selected() -> void:
    """Handle server mode selection"""
    logger.info("UnifiedMain", "Server mode selected")
    
    # Switch to server mode
    if game_mode:
        game_mode.stop()
    
    _start_server_mode()

func _on_client_mode_selected() -> void:
    """Handle client mode selection"""
    logger.info("UnifiedMain", "Client mode selected")
    
    # Show connection panel
    _show_connection_panel()

func _on_connect_pressed() -> void:
    """Handle connect button press"""
    if server_address_input:
        server_address = server_address_input.text.strip_edges()
    
    if server_address == "":
        _update_status("Please enter server address")
        return
    
    logger.info("UnifiedMain", "Connecting to server: %s:%d" % [server_address, server_port])
    _connect_to_server()

func _on_disconnect_pressed() -> void:
    """Handle disconnect button press"""
    logger.info("UnifiedMain", "Disconnecting from server")
    _disconnect_from_server()

# Lobby button handlers
func _on_ready_pressed() -> void:
    """Handle ready button press"""
    is_ready = !is_ready
    logger.info("UnifiedMain", "Player ready state: %s" % is_ready)
    
    # Send ready state to server
    rpc_id(1, "set_player_ready", is_ready)
    
    # Update UI immediately
    _update_lobby_display()

func _on_start_pressed() -> void:
    """Handle start game button press"""
    logger.info("UnifiedMain", "Start button pressed. can_start_game: %s, is_connected: %s" % [can_start_game, is_connected])
    
    if can_start_game:
        logger.info("UnifiedMain", "Starting game from lobby")
        rpc_id(1, "force_start_game")
    else:
        logger.warning("UnifiedMain", "Cannot start game - not ready")
        logger.info("UnifiedMain", "Debug: lobby_players: %s, can_start_game: %s, is_in_lobby: %s" % [lobby_players, can_start_game, is_in_lobby])

func _on_leave_lobby_pressed() -> void:
    """Handle leave lobby button press"""
    logger.info("UnifiedMain", "Leaving lobby")
    rpc_id(1, "leave_session")
    
    # Reset lobby state
    _reset_lobby_state()
    
    # Show connection panel
    _show_connection_panel()

func _reset_lobby_state() -> void:
    """Reset lobby state"""
    is_in_lobby = false
    is_ready = false
    lobby_players.clear()
    can_start_game = false
    current_session_id = ""

# Network connection
func _connect_to_server() -> void:
    """Connect to the server"""
    if is_connected:
        logger.warning("UnifiedMain", "Already connected to server")
        return
    
    _update_status("Connecting to server...")
    
    # Create client peer
    client_peer = ENetMultiplayerPeer.new()
    var error = client_peer.create_client(server_address, server_port)
    
    if error != OK:
        logger.error("UnifiedMain", "Failed to create client: %s" % error)
        _update_status("Failed to connect to server")
        return
    
    # Setup multiplayer
    multiplayer.multiplayer_peer = client_peer
    
    # Connect signals (only if not already connected)
    if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
        multiplayer.connected_to_server.connect(_on_connected_to_server)
    if not multiplayer.connection_failed.is_connected(_on_connection_failed):
        multiplayer.connection_failed.connect(_on_connection_failed)
    if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
        multiplayer.server_disconnected.connect(_on_server_disconnected)

func _disconnect_from_server() -> void:
    """Disconnect from the server"""
    if not is_connected:
        logger.warning("UnifiedMain", "Not connected to server")
        return
    
    # Close connection
    if client_peer:
        client_peer.close()
    
    multiplayer.multiplayer_peer = null
    
    # Reset state
    is_connected = false
    _reset_lobby_state()
    _clear_game_display()
    
    # Update UI
    _update_ui_state()
    _show_connection_panel()
    _update_status("Disconnected from server")
    
    disconnected_from_server.emit()
    logger.info("UnifiedMain", "Disconnected from server")

# Network signal handlers
func _on_connected_to_server() -> void:
    """Handle successful connection to server"""
    is_connected = true
    _update_ui_state()
    _update_status("Connected to server")
    
    # Authenticate with server
    rpc_id(1, "authenticate_client", "Player_%d" % multiplayer.get_unique_id(), "")
    
    connected_to_server.emit()
    logger.info("UnifiedMain", "Connected to server")

func _on_connection_failed() -> void:
    """Handle connection failure"""
    is_connected = false
    _update_ui_state()
    _update_status("Connection failed")
    
    logger.error("UnifiedMain", "Connection to server failed")

func _on_server_disconnected() -> void:
    """Handle server disconnection"""
    is_connected = false
    _reset_lobby_state()
    _clear_game_display()
    
    _update_ui_state()
    _show_connection_panel()
    _update_status("Server disconnected")
    
    disconnected_from_server.emit()
    logger.info("UnifiedMain", "Server disconnected")

# Game display
func _clear_game_display() -> void:
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
    
    # Reset lobby state
    _reset_lobby_state()
    
    logger.info("UnifiedMain", "Game display cleared")

func _update_game_display(state_data: Dictionary) -> void:
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
    
    # Update UI
    _update_game_ui(state_data)

func _update_unit_display(unit_id: String, unit_data: Dictionary) -> void:
    """Update a unit's display"""
    var unit_display = displayed_units.get(unit_id)
    
    if not unit_display:
        # Create new unit display
        unit_display = _create_unit_display(unit_data)
        displayed_units[unit_id] = unit_display
        
        # Add to the 3D scene in GameUI first
        var game_world = game_ui.get_node("GameWorld/3DView") if game_ui else null
        if game_world:
            game_world.add_child(unit_display)
            
            # Set position after adding to scene tree
            var position_array = unit_data.get("position", [0, 0, 0])
            var new_position = Vector3(position_array[0], position_array[1], position_array[2])
            unit_display.global_position = new_position
            
            logger.info("UnifiedMain", "Added unit %s to 3D scene at position %s" % [unit_id, unit_display.global_position])
            
            # Debug: Check scene hierarchy
            logger.info("UnifiedMain", "Unit parent: %s" % unit_display.get_parent().name)
            logger.info("UnifiedMain", "3D scene children count: %d" % game_world.get_child_count())
            
            # Debug: List all children in 3D scene
            for i in range(game_world.get_child_count()):
                var child = game_world.get_child(i)
                logger.info("UnifiedMain", "3D scene child %d: %s at %s" % [i, child.name, child.global_position])
                
        else:
            logger.error("UnifiedMain", "Could not find 3D scene to add unit %s" % unit_id)
            logger.error("UnifiedMain", "game_ui: %s" % (game_ui != null))
            if game_ui:
                logger.error("UnifiedMain", "GameWorld exists: %s" % (game_ui.has_node("GameWorld")))
                if game_ui.has_node("GameWorld"):
                    logger.error("UnifiedMain", "3DView exists: %s" % (game_ui.get_node("GameWorld").has_node("3DView")))
    else:
        # Update existing unit position
        var position_array = unit_data.get("position", [0, 0, 0])
        var new_position = Vector3(position_array[0], position_array[1], position_array[2])
        unit_display.global_position = new_position
        
        # Debug: Log position update
        logger.info("UnifiedMain", "Updated unit %s position to %s (from data: %s)" % [unit_id, unit_display.global_position, position_array])
    
    # Update other properties
    var health = unit_data.get("health", 100)
    var max_health = unit_data.get("max_health", 100)
    var team_id = unit_data.get("team_id", 1)
    
    # Update any UI elements or visual indicators as needed
    # TODO: Add health bars, selection indicators, etc.

func _update_building_display(building_id: String, building_data: Dictionary) -> void:
    """Update a building's display"""
    var building_display = displayed_buildings.get(building_id)
    
    if not building_display:
        # Create new building display
        building_display = _create_building_display(building_data)
        displayed_buildings[building_id] = building_display
        
        # Add to the 3D scene in GameUI
        var game_world = game_ui.get_node("GameWorld/3DView") if game_ui else null
        if game_world:
            game_world.add_child(building_display)
            logger.info("UnifiedMain", "Added building %s to 3D scene" % building_id)
        else:
            logger.warning("UnifiedMain", "Could not find 3D scene to add building %s" % building_id)
    
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
    var unit_display = CharacterBody3D.new()  # Use CharacterBody3D for better visibility
    unit_display.name = "Unit_" + unit_data.get("id", "unknown")
    
    # Add visual representation - make units MUCH larger and more visible
    var mesh_instance = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    box_mesh.size = Vector3(5, 8, 5)  # Much larger size - was 2x3x2
    mesh_instance.mesh = box_mesh
    unit_display.add_child(mesh_instance)
    
    # Add collision shape
    var collision_shape = CollisionShape3D.new()
    var box_shape = BoxShape3D.new()
    box_shape.size = Vector3(5, 8, 5)
    collision_shape.shape = box_shape
    unit_display.add_child(collision_shape)
    
    # Add team colors for better visibility
    var team_id = unit_data.get("team_id", 1)
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
    
    logger.info("UnifiedMain", "Created unit display for team %d with color %s, size %s" % [team_id, material.albedo_color, box_mesh.size])
    
    return unit_display

func _create_building_display(building_data: Dictionary) -> Node3D:
    """Create a building display node"""
    var building_display = Node3D.new()
    building_display.name = "Building_" + building_data.get("id", "unknown")
    
    # Add visual representation (simplified)
    var mesh_instance = MeshInstance3D.new()
    mesh_instance.mesh = BoxMesh.new()
    mesh_instance.mesh.size = Vector3(2, 2, 2)
    building_display.add_child(mesh_instance)
    
    # Add team coloring
    var team_id = building_data.get("team_id", 0)
    var material = StandardMaterial3D.new()
    material.albedo_color = Color.DARK_RED if team_id == 1 else Color.DARK_BLUE
    mesh_instance.material_override = material
    
    return building_display

func _update_game_ui(state_data: Dictionary) -> void:
    """Update the game UI"""
    # Update resource display
    var resources = state_data.get("resources", {})
    
    # Update match state
    var match_state = state_data.get("match_state", "unknown")
    
    # Update game time
    var game_time = state_data.get("game_time", 0.0)
    
    # Update resource display in top panel
    var resource_label = game_ui.get_node("GameOverlay/TopPanel/ResourcesLabel") if game_ui else null
    if resource_label:
        var resource_text = "Resources: "
        for team_id in resources:
            var team_resources = resources[team_id]
            resource_text += "Team %d: Energy: %d, Minerals: %d  " % [team_id, team_resources.get("energy", 0), team_resources.get("minerals", 0)]
        resource_label.text = resource_text
    
    # Update game time display
    var time_label = game_ui.get_node("GameOverlay/TopPanel/GameTimeLabel") if game_ui else null
    if time_label:
        var minutes = int(game_time) / 60
        var seconds = int(game_time) % 60
        time_label.text = "Time: %02d:%02d" % [minutes, seconds]
    
    # Ensure game UI is visible
    if not game_ui.visible:
        logger.info("UnifiedMain", "Game UI not visible, showing it now")
        _show_game_ui()
    
    logger.info("UnifiedMain", "Updated game UI - units: %d, buildings: %d, match_state: %s" % [displayed_units.size(), displayed_buildings.size(), match_state])

# Server-side RPC methods (called by clients)
@rpc("any_peer", "call_local", "reliable")
func authenticate_client(player_name: String, auth_token: String) -> void:
    """Handle client authentication request"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Authentication request from %d: %s" % [peer_id, player_name])
    
    # Delegate to dedicated server if in server mode
    if dependency_container and dependency_container.dedicated_server:
        dependency_container.dedicated_server.handle_authentication(peer_id, player_name, auth_token)
    else:
        logger.warning("UnifiedMain", "No dedicated server available for authentication")

@rpc("any_peer", "call_local", "reliable")
func join_session(preferred_session_id: String) -> void:
    """Handle session join request"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Session join request from %d" % peer_id)
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_join_session(peer_id, preferred_session_id)
    else:
        logger.warning("UnifiedMain", "No session manager available for session join")

@rpc("any_peer", "call_local", "reliable")
func process_ai_command(command: String, selected_units: Array) -> void:
    """Handle AI command from client"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "AI command from %d: %s" % [peer_id, command])
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_ai_command(peer_id, command, selected_units)
    else:
        logger.warning("UnifiedMain", "No session manager available for AI command")

@rpc("any_peer", "call_local", "reliable")
func client_ping() -> void:
    """Handle client ping"""
    var peer_id = multiplayer.get_remote_sender_id()
    
    # Delegate to dedicated server if in server mode
    if dependency_container and dependency_container.dedicated_server:
        dependency_container.dedicated_server.handle_ping(peer_id)
    else:
        # Fallback: send pong directly
        rpc_id(peer_id, "_on_pong", Time.get_ticks_msec())

# Client-side RPC methods (called by server)
@rpc("authority", "call_local", "reliable")
func _on_server_welcome(data: Dictionary) -> void:
    """Handle server welcome message"""
    logger.info("UnifiedMain", "Server welcome received: %s" % data)

@rpc("authority", "call_local", "reliable")
func _on_pong(timestamp: int) -> void:
    """Handle ping response"""
    var current_time = Time.get_ticks_msec()
    var ping_time = current_time - timestamp
    logger.info("UnifiedMain", "Ping: %d ms" % ping_time)

@rpc("authority", "call_local", "reliable")
func _on_auth_response(data: Dictionary) -> void:
    """Handle authentication response"""
    var success = data.get("success", false)
    var player_id = data.get("player_id", "")
    
    if success:
        logger.info("UnifiedMain", "Authentication successful: %s" % player_id)
        _update_status("Authenticated as %s" % player_id)
        
        # Request to join a session
        rpc_id(1, "join_session", "")
    else:
        logger.error("UnifiedMain", "Authentication failed")
        _update_status("Authentication failed")

@rpc("authority", "call_local", "reliable")
func _on_session_join_response(data: Dictionary) -> void:
    """Handle session join response"""
    var success = data.get("success", false)
    var session_id = data.get("session_id", "")
    var session_data = data.get("session_data", {})
    
    if success:
        current_session_id = session_id
        lobby_players = session_data.get("players", {})
        can_start_game = session_data.get("can_start_game", false)
        logger.info("UnifiedMain", "Joined session: %s" % session_id)
        _update_status("Joined session: %s" % session_id)
        _show_lobby_ui() # Show lobby UI on successful join
    else:
        logger.error("UnifiedMain", "Failed to join session")
        _update_status("Failed to join session")

@rpc("authority", "call_local", "reliable")
func _on_game_started(data: Dictionary) -> void:
    """Handle game started notification"""
    var session_id = data.get("session_id", "")
    var player_team = data.get("player_team", 0)
    
    logger.info("UnifiedMain", "Game started in session %s (team %d)" % [session_id, player_team])
    logger.info("UnifiedMain", "Current UI states - menu: %s, lobby: %s, game: %s" % [menu_container.visible if menu_container else "null", lobby_ui.visible if lobby_ui else "null", game_ui.visible if game_ui else "null"])
    
    _update_status("Game started! You are team %d" % player_team)
    
    # Show game UI
    logger.info("UnifiedMain", "Calling _show_game_ui()")
    _show_game_ui()
    
    logger.info("UnifiedMain", "After _show_game_ui() - menu: %s, lobby: %s, game: %s" % [menu_container.visible if menu_container else "null", lobby_ui.visible if lobby_ui else "null", game_ui.visible if game_ui else "null"])

@rpc("authority", "call_local", "reliable")
func _on_game_state_update(data: Dictionary) -> void:
    """Handle game state updates from server"""
    var units_data = data.get("units", [])
    var buildings_data = data.get("buildings", [])
    var resources_data = data.get("resources", {})
    var match_state = data.get("match_state", "active")
    var game_time = data.get("game_time", 0.0)
    
    logger.info("UnifiedMain", "Game state update received: %d units, %d buildings, match_state: %s" % [units_data.size(), buildings_data.size(), match_state])
    
    # Update units
    for unit_data in units_data:
        var unit_id = unit_data.get("id", "")
        if unit_id != "":
            logger.info("UnifiedMain", "Updating unit %s at position %s" % [unit_id, unit_data.get("position", [])])
            _update_unit_display(unit_id, unit_data)
    
    # Update buildings
    for building_data in buildings_data:
        var building_id = building_data.get("id", "")
        if building_id != "":
            _update_building_display(building_id, building_data)
    
    # Update resources display
    if resources_data.size() > 0:
        _update_resources_display(resources_data)
    
    # Update game time
    _update_game_time_display(game_time)
    
    # Handle match state
    if match_state == "ended":
        logger.info("UnifiedMain", "Game ended")
        # TODO: Show game over screen

# New RPC methods for lobby functionality
@rpc("any_peer", "call_local", "reliable")
func set_player_ready(ready_state: bool) -> void:
    """Handle player ready state change"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Player ready state from %d: %s" % [peer_id, ready_state])
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_player_ready(peer_id, ready_state)
    else:
        logger.warning("UnifiedMain", "No session manager available for ready state")

@rpc("any_peer", "call_local", "reliable")
func force_start_game() -> void:
    """Handle force start game request"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Force start game from %d" % peer_id)
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_force_start_game(peer_id)
    else:
        logger.warning("UnifiedMain", "No session manager available for force start")

@rpc("any_peer", "call_local", "reliable")
func leave_session() -> void:
    """Handle leave session request"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("UnifiedMain", "Leave session from %d" % peer_id)
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_leave_session(peer_id)
    else:
        logger.warning("UnifiedMain", "No session manager available for leave session")

# Client-side RPC methods for lobby updates
@rpc("authority", "call_local", "reliable")
func _on_lobby_update(data: Dictionary) -> void:
    """Handle lobby update from server"""
    lobby_players = data.get("players", {})
    can_start_game = data.get("can_start_game", false)
    
    logger.info("UnifiedMain", "Lobby updated: %d players, can_start: %s" % [lobby_players.size(), can_start_game])
    
    # Update lobby display if in lobby
    if is_in_lobby:
        _update_lobby_display()

# Input handling
func _input(event: InputEvent) -> void:
    """Handle input events"""
    if not is_connected or current_session_id == "":
        return
    
    # Handle AI commands (placeholder)
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_T:
            # Test AI command
            var test_command = "Move selected units to the center"
            rpc_id(1, "process_ai_command", test_command, selected_units)
            logger.info("UnifiedMain", "Sent AI command: %s" % test_command)

func cleanup() -> void:
    """Cleanup resources"""
    _disconnect_from_server()
    _clear_game_display()
    
    if dependency_container:
        dependency_container.cleanup()
    
    logger.info("UnifiedMain", "Cleanup complete") 

func _update_resources_display(resources_data: Dictionary) -> void:
    """Update the resources display"""
    var resources_text = "Resources: "
    for team_id in resources_data:
        var team_resources = resources_data[team_id]
        resources_text += "Team %d - Energy: %d, Minerals: %d  " % [team_id, team_resources.get("energy", 0), team_resources.get("minerals", 0)]
    
    if game_ui:
        var resources_label = game_ui.get_node("GameOverlay/TopPanel/ResourcesLabel")
        if resources_label:
            resources_label.text = resources_text

func _update_game_time_display(game_time: float) -> void:
    """Update the game time display"""
    var minutes = int(game_time / 60)
    var seconds = int(game_time) % 60
    var time_text = "%02d:%02d" % [minutes, seconds]
    
    if game_ui:
        var time_label = game_ui.get_node("GameOverlay/TopPanel/GameTimeLabel")
        if time_label:
            time_label.text = "Time: " + time_text 