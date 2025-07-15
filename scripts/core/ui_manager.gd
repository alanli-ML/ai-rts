# UIManager.gd - Handle all UI state transitions and callbacks
extends Node

# Dependencies
var logger
var network_manager
var main_node

# UI references
var menu_container
var mode_selection
var server_button
var client_button
var status_label
var game_ui
var connection_panel
var server_address_input
var connect_button
var disconnect_button

# Lobby UI references
var lobby_ui
var session_info_label
var players_list
var ready_status_label
var ready_button
var start_button
var leave_lobby_button

# Testing UI references
var testing_suite
var close_testing_button

# Signals
signal server_mode_selected()
signal client_mode_selected()
signal connect_requested(address: String)
signal disconnect_requested()
signal ready_state_changed(ready: bool)
signal game_start_requested()
signal leave_lobby_requested()
signal testing_mode_toggled(enabled: bool)

# State
var is_testing_mode: bool = false

func setup(logger_instance, network_manager_instance, main_node_instance) -> void:
    """Setup the UI manager with dependencies"""
    logger = logger_instance
    network_manager = network_manager_instance
    main_node = main_node_instance
    
    # Setup UI references (main_node is already ready)
    _setup_ui_references()
    
    # Setup UI elements
    _setup_ui()
    
    # Connect network manager signals
    _connect_network_signals()
    
    logger.info("UIManager", "UI manager setup complete")

func _setup_ui_references() -> void:
    """Setup UI node references"""
    if not main_node:
        logger.error("UIManager", "main_node is null - cannot setup UI references")
        return
    
    # Main UI references
    menu_container = main_node.get_node("MenuContainer")
    mode_selection = main_node.get_node("MenuContainer/ModeSelection")
    server_button = main_node.get_node("MenuContainer/ModeSelection/ServerButton")
    client_button = main_node.get_node("MenuContainer/ModeSelection/ClientButton")
    status_label = main_node.get_node("MenuContainer/StatusLabel")
    game_ui = main_node.get_node("GameUI")
    connection_panel = main_node.get_node("MenuContainer/ConnectionPanel")
    server_address_input = main_node.get_node("MenuContainer/ConnectionPanel/ServerAddressInput")
    connect_button = main_node.get_node("MenuContainer/ConnectionPanel/ConnectionButtons/ConnectButton")
    disconnect_button = main_node.get_node("MenuContainer/ConnectionPanel/ConnectionButtons/DisconnectButton")
    
    # Lobby UI references
    lobby_ui = main_node.get_node("LobbyUI")
    session_info_label = main_node.get_node("LobbyUI/LobbyPanel/LobbyContainer/SessionInfo")
    players_list = main_node.get_node("LobbyUI/LobbyPanel/LobbyContainer/PlayersList")
    ready_status_label = main_node.get_node("LobbyUI/LobbyPanel/LobbyContainer/ReadyStatus")
    ready_button = main_node.get_node("LobbyUI/LobbyPanel/LobbyContainer/LobbyButtons/ReadyButton")
    start_button = main_node.get_node("LobbyUI/LobbyPanel/LobbyContainer/LobbyButtons/StartButton")
    leave_lobby_button = main_node.get_node("LobbyUI/LobbyPanel/LobbyContainer/LobbyButtons/LeaveLobbyButton")
    
    # Testing UI references
    testing_suite = main_node.get_node("TestingSuite")
    close_testing_button = main_node.get_node("TestingSuite/TestingPanel/TestingContainer/TestingButtons/CloseTestingButton")
    
    logger.info("UIManager", "UI references setup complete")

func _setup_ui() -> void:
    """Setup the UI elements"""
    if DisplayServer.get_name() == "headless":
        logger.info("UIManager", "Headless mode - skipping UI setup")
        return
    
    # Setup button connections
    if server_button:
        server_button.pressed.connect(_on_server_mode_selected)
    if client_button:
        client_button.pressed.connect(_on_client_mode_selected)
    if connect_button:
        connect_button.pressed.connect(_on_connect_pressed)
    if disconnect_button:
        disconnect_button.pressed.connect(_on_disconnect_pressed)
    
    # Setup lobby button connections
    if ready_button:
        ready_button.pressed.connect(_on_ready_pressed)
    if start_button:
        start_button.pressed.connect(_on_start_pressed)
    if leave_lobby_button:
        leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
    
    # Setup testing button connections
    if close_testing_button:
        close_testing_button.pressed.connect(_on_close_testing_pressed)
    
    # Setup initial UI state
    _update_ui_state()
    
    # Setup game UI
    if game_ui:
        game_ui.visible = false
    if testing_suite:
        testing_suite.visible = false
    
    logger.info("UIManager", "UI setup complete")

func _connect_network_signals() -> void:
    """Connect network manager signals"""
    if network_manager:
        network_manager.connected_to_server.connect(_on_connected_to_server)
        network_manager.disconnected_from_server.connect(_on_disconnected_from_server)
        network_manager.connection_failed.connect(_on_connection_failed)
        network_manager.authentication_response.connect(_on_authentication_response)
        network_manager.session_join_response.connect(_on_session_join_response)
        network_manager.lobby_update.connect(_on_lobby_update)
        network_manager.game_started.connect(_on_game_started)

# UI State Management
func show_mode_selection() -> void:
    """Show the mode selection UI"""
    if not menu_container:
        return
    
    menu_container.visible = true
    mode_selection.visible = true
    connection_panel.visible = false
    lobby_ui.visible = false
    game_ui.visible = false
    testing_suite.visible = false
    
    update_status("Select game mode")

func show_connection_panel() -> void:
    """Show the connection panel"""
    if not menu_container:
        return
    
    mode_selection.visible = false
    connection_panel.visible = true
    lobby_ui.visible = false
    game_ui.visible = false
    testing_suite.visible = false
    
    if server_address_input:
        server_address_input.text = network_manager.server_address
    
    update_status("Enter server address")

func show_lobby_ui() -> void:
    """Show the lobby UI"""
    if not menu_container or not lobby_ui:
        return
    
    menu_container.visible = false
    lobby_ui.visible = true
    game_ui.visible = false
    testing_suite.visible = false
    
    update_lobby_display()
    update_status("In lobby - waiting for players")

func show_game_ui() -> void:
    """Show the game UI"""
    logger.info("UIManager", "show_game_ui() called - checking UI elements")
    
    if not menu_container or not lobby_ui or not game_ui:
        logger.error("UIManager", "Missing UI elements - cannot show game UI")
        return
    
    logger.info("UIManager", "All UI elements found - hiding menu and lobby, showing game")
    menu_container.visible = false
    lobby_ui.visible = false
    game_ui.visible = true
    
    logger.info("UIManager", "Game UI shown successfully")

func toggle_testing_mode() -> void:
    """Toggle testing mode visibility"""
    is_testing_mode = not is_testing_mode
    if testing_suite:
        testing_suite.visible = is_testing_mode
    
    logger.info("UIManager", "Testing mode: %s" % ("ON" if is_testing_mode else "OFF"))
    testing_mode_toggled.emit(is_testing_mode)

func update_status(message: String) -> void:
    """Update the status label"""
    if status_label:
        status_label.text = message
    
    logger.info("UIManager", "Status: %s" % message)

func update_lobby_display() -> void:
    """Update the lobby display with current session info"""
    var lobby_state = network_manager.get_lobby_state()
    
    if not lobby_state.is_in_lobby:
        return
    
    # Update session info
    if session_info_label:
        session_info_label.text = "Session: %s" % lobby_state.current_session_id
    
    # Clear existing player list
    if players_list:
        for child in players_list.get_children():
            child.queue_free()
    
    # Add current players
    for player_id in lobby_state.lobby_players:
        var player_data = lobby_state.lobby_players[player_id]
        var player_label = Label.new()
        var ready_status = " (Ready)" if player_data.get("ready", false) else " (Not Ready)"
        var team_info = " - Team %d" % player_data.get("team_id", 0)
        player_label.text = "%s%s%s" % [player_id, team_info, ready_status]
        player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        players_list.add_child(player_label)
    
    # Update ready status
    if ready_status_label:
        if lobby_state.can_start_game:
            ready_status_label.text = "All players ready! You can start the game."
        elif lobby_state.lobby_players.size() == 1:
            ready_status_label.text = "Single player mode - you can start anytime!"
        else:
            ready_status_label.text = "Waiting for players to ready up..."
    
    # Update button states
    if ready_button:
        ready_button.text = "Not Ready" if lobby_state.is_ready else "Ready"
        ready_button.disabled = false
    
    if start_button:
        start_button.disabled = not lobby_state.can_start_game

func _update_ui_state() -> void:
    """Update UI state based on connection"""
    if not connect_button or not disconnect_button:
        return
    
    var is_connected = network_manager.get_connection_state()
    
    connect_button.disabled = is_connected
    disconnect_button.disabled = not is_connected
    
    if server_address_input:
        server_address_input.editable = not is_connected

# Button handlers
func _on_server_mode_selected() -> void:
    """Handle server mode selection"""
    logger.info("UIManager", "Server mode selected")
    server_mode_selected.emit()

func _on_client_mode_selected() -> void:
    """Handle client mode selection"""
    logger.info("UIManager", "Client mode selected")
    show_connection_panel()
    client_mode_selected.emit()

func _on_connect_pressed() -> void:
    """Handle connect button press"""
    var address = ""
    if server_address_input:
        address = server_address_input.text.strip_edges()
    
    if address == "":
        update_status("Please enter server address")
        return
    
    logger.info("UIManager", "Connect requested: %s" % address)
    connect_requested.emit(address)

func _on_disconnect_pressed() -> void:
    """Handle disconnect button press"""
    logger.info("UIManager", "Disconnect requested")
    disconnect_requested.emit()

func _on_ready_pressed() -> void:
    """Handle ready button press"""
    var lobby_state = network_manager.get_lobby_state()
    var new_ready_state = not lobby_state.is_ready
    
    logger.info("UIManager", "Ready state changed: %s" % new_ready_state)
    ready_state_changed.emit(new_ready_state)

func _on_start_pressed() -> void:
    """Handle start game button press"""
    var lobby_state = network_manager.get_lobby_state()
    
    if lobby_state.can_start_game:
        logger.info("UIManager", "Game start requested")
        game_start_requested.emit()
    else:
        logger.warning("UIManager", "Cannot start game - not ready")

func _on_leave_lobby_pressed() -> void:
    """Handle leave lobby button press"""
    logger.info("UIManager", "Leave lobby requested")
    leave_lobby_requested.emit()

func _on_close_testing_pressed() -> void:
    """Handle close testing button press"""
    toggle_testing_mode()

# Network signal handlers
func _on_connected_to_server() -> void:
    """Handle successful connection to server"""
    _update_ui_state()
    update_status("Connected to server")

func _on_disconnected_from_server() -> void:
    """Handle disconnection from server"""
    _update_ui_state()
    show_connection_panel()
    update_status("Disconnected from server")

func _on_connection_failed() -> void:
    """Handle connection failure"""
    _update_ui_state()
    update_status("Connection failed")

func _on_authentication_response(success: bool, data: Dictionary) -> void:
    """Handle authentication response"""
    if success:
        var player_id = data.get("player_id", "")
        update_status("Authenticated as %s" % player_id)
    else:
        update_status("Authentication failed")

func _on_session_join_response(success: bool, data: Dictionary) -> void:
    """Handle session join response"""
    if success:
        var session_id = data.get("session_id", "")
        update_status("Joined session: %s" % session_id)
        show_lobby_ui()
    else:
        update_status("Failed to join session")

func _on_lobby_update(data: Dictionary) -> void:
    """Handle lobby update"""
    update_lobby_display()

func _on_game_started(data: Dictionary) -> void:
    """Handle game started notification"""
    var player_team = data.get("player_team", 0)
    update_status("Game started! You are team %d" % player_team)
    show_game_ui()

# Input handling
func handle_input(event: InputEvent) -> bool:
    """Handle input events, return true if handled"""
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_T:
            toggle_testing_mode()
            return true
    
    return false

# Getters
func get_testing_mode() -> bool:
    return is_testing_mode

func cleanup() -> void:
    """Cleanup UI resources"""
    logger.info("UIManager", "UI manager cleanup complete") 