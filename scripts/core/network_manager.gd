# NetworkManager.gd - Handle all network and multiplayer functionality
extends Node

# Dependencies
var logger
var dependency_container

# Network state
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

# Signals
signal connected_to_server()
signal disconnected_from_server()
signal connection_failed()
signal server_disconnected()
signal authentication_response(success: bool, data: Dictionary)
signal session_join_response(success: bool, data: Dictionary)
signal lobby_update(data: Dictionary)
signal game_started(data: Dictionary)
signal game_state_update(data: Dictionary)

func setup(logger_instance, dependency_container_instance) -> void:
    """Setup the network manager with dependencies"""
    logger = logger_instance
    dependency_container = dependency_container_instance
    logger.info("NetworkManager", "Network manager setup complete")

func set_server_address(address: String) -> void:
    """Set the server address"""
    server_address = address.strip_edges()
    logger.info("NetworkManager", "Server address set to: %s" % server_address)

func connect_to_server() -> void:
    """Connect to the server"""
    if is_connected:
        logger.warning("NetworkManager", "Already connected to server")
        return
    
    if server_address == "":
        logger.error("NetworkManager", "Server address is empty")
        return
    
    logger.info("NetworkManager", "Connecting to server: %s:%d" % [server_address, server_port])
    
    # Create client peer
    client_peer = ENetMultiplayerPeer.new()
    var error = client_peer.create_client(server_address, server_port)
    
    if error != OK:
        logger.error("NetworkManager", "Failed to create client: %s" % error)
        connection_failed.emit()
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

func disconnect_from_server() -> void:
    """Disconnect from the server"""
    if not is_connected:
        logger.warning("NetworkManager", "Not connected to server")
        return
    
    # Close connection
    if client_peer:
        client_peer.close()
    
    multiplayer.multiplayer_peer = null
    
    # Reset state
    is_connected = false
    _reset_lobby_state()
    
    disconnected_from_server.emit()
    logger.info("NetworkManager", "Disconnected from server")

func _reset_lobby_state() -> void:
    """Reset lobby state"""
    is_in_lobby = false
    is_ready = false
    lobby_players.clear()
    can_start_game = false
    current_session_id = ""

# Network signal handlers
func _on_connected_to_server() -> void:
    """Handle successful connection to server"""
    is_connected = true
    logger.info("NetworkManager", "Connected to server")
    
    # Authenticate with server
    rpc_id(1, "authenticate_client", "Player_%d" % multiplayer.get_unique_id(), "")
    
    connected_to_server.emit()

func _on_connection_failed() -> void:
    """Handle connection failure"""
    is_connected = false
    logger.error("NetworkManager", "Connection to server failed")
    connection_failed.emit()

func _on_server_disconnected() -> void:
    """Handle server disconnection"""
    is_connected = false
    _reset_lobby_state()
    logger.info("NetworkManager", "Server disconnected")
    server_disconnected.emit()

# Server-side RPC methods (called by clients)
@rpc("any_peer", "call_local", "reliable")
func authenticate_client(player_name: String, auth_token: String) -> void:
    """Handle client authentication request"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("NetworkManager", "Authentication request from %d: %s" % [peer_id, player_name])
    
    # Delegate to dedicated server if in server mode
    if dependency_container and dependency_container.dedicated_server:
        dependency_container.dedicated_server.handle_authentication(peer_id, player_name, auth_token)
    else:
        logger.warning("NetworkManager", "No dedicated server available for authentication")

@rpc("any_peer", "call_local", "reliable")
func join_session(preferred_session_id: String) -> void:
    """Handle session join request"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("NetworkManager", "Session join request from %d" % peer_id)
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_join_session(peer_id, preferred_session_id)
    else:
        logger.warning("NetworkManager", "No session manager available for session join")

@rpc("any_peer", "call_local", "reliable")
func process_ai_command(command: String, selected_units: Array) -> void:
    """Handle AI command from client"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("NetworkManager", "AI command from %d: %s" % [peer_id, command])
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_ai_command(peer_id, command, selected_units)
    else:
        logger.warning("NetworkManager", "No session manager available for AI command")

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

@rpc("any_peer", "call_local", "reliable")
func set_player_ready(ready_state: bool) -> void:
    """Handle player ready state change"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("NetworkManager", "Player ready state from %d: %s" % [peer_id, ready_state])
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_player_ready(peer_id, ready_state)
    else:
        logger.warning("NetworkManager", "No session manager available for ready state")

@rpc("any_peer", "call_local", "reliable")
func force_start_game() -> void:
    """Handle force start game request"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("NetworkManager", "Force start game from %d" % peer_id)
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_force_start_game(peer_id)
    else:
        logger.warning("NetworkManager", "No session manager available for force start")

@rpc("any_peer", "call_local", "reliable")
func leave_session() -> void:
    """Handle leave session request"""
    var peer_id = multiplayer.get_remote_sender_id()
    logger.info("NetworkManager", "Leave session from %d" % peer_id)
    
    # Delegate to session manager if in server mode
    if dependency_container and dependency_container.session_manager:
        dependency_container.session_manager.handle_leave_session(peer_id)
    else:
        logger.warning("NetworkManager", "No session manager available for leave session")

# Client-side RPC methods (called by server)
@rpc("authority", "call_local", "reliable")
func _on_server_welcome(data: Dictionary) -> void:
    """Handle server welcome message"""
    logger.info("NetworkManager", "Server welcome received: %s" % data)

@rpc("authority", "call_local", "reliable")
func _on_pong(timestamp: int) -> void:
    """Handle ping response"""
    var current_time = Time.get_ticks_msec()
    var ping_time = current_time - timestamp
    logger.info("NetworkManager", "Ping: %d ms" % ping_time)

@rpc("authority", "call_local", "reliable")
func _on_auth_response(data: Dictionary) -> void:
    """Handle authentication response"""
    var success = data.get("success", false)
    var player_id = data.get("player_id", "")
    
    if success:
        logger.info("NetworkManager", "Authentication successful: %s" % player_id)
        # Request to join a session
        rpc_id(1, "join_session", "")
    else:
        logger.error("NetworkManager", "Authentication failed")
    
    authentication_response.emit(success, data)

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
        is_in_lobby = true
        logger.info("NetworkManager", "Joined session: %s" % session_id)
    else:
        logger.error("NetworkManager", "Failed to join session")
    
    session_join_response.emit(success, data)

@rpc("authority", "call_local", "reliable")
func _on_game_started(data: Dictionary) -> void:
    """Handle game started notification"""
    var session_id = data.get("session_id", "")
    var player_team = data.get("player_team", 0)
    
    logger.info("NetworkManager", "Game started in session %s (team %d)" % [session_id, player_team])
    is_in_lobby = false
    
    game_started.emit(data)

@rpc("authority", "call_local", "reliable")
func _on_game_state_update(data: Dictionary) -> void:
    """Handle game state updates from server"""
    var units_data = data.get("units", [])
    var buildings_data = data.get("buildings", [])
    var match_state = data.get("match_state", "active")
    
    logger.info("NetworkManager", "Game state update received: %d units, %d buildings, match_state: %s" % [units_data.size(), buildings_data.size(), match_state])
    
    game_state_update.emit(data)

@rpc("authority", "call_local", "reliable")
func _on_lobby_update(data: Dictionary) -> void:
    """Handle lobby update from server"""
    lobby_players = data.get("players", {})
    can_start_game = data.get("can_start_game", false)
    
    logger.info("NetworkManager", "Lobby updated: %d players, can_start: %s" % [lobby_players.size(), can_start_game])
    
    lobby_update.emit(data)

# Lobby management methods
func set_ready(ready_state: bool) -> void:
    """Set player ready state"""
    if not is_connected:
        logger.warning("NetworkManager", "Not connected to server")
        return
    
    is_ready = ready_state
    logger.info("NetworkManager", "Setting ready state: %s" % ready_state)
    rpc_id(1, "set_player_ready", ready_state)

func start_game() -> void:
    """Request to start the game"""
    if not is_connected or not can_start_game:
        logger.warning("NetworkManager", "Cannot start game - not ready")
        return
    
    logger.info("NetworkManager", "Requesting to start game")
    rpc_id(1, "force_start_game")

func leave_lobby() -> void:
    """Leave the current lobby"""
    if not is_connected:
        logger.warning("NetworkManager", "Not connected to server")
        return
    
    logger.info("NetworkManager", "Leaving lobby")
    rpc_id(1, "leave_session")
    _reset_lobby_state()

func send_ai_command(command: String, selected_units: Array) -> void:
    """Send AI command to server"""
    if not is_connected:
        logger.warning("NetworkManager", "Not connected to server")
        return
    
    logger.info("NetworkManager", "Sending AI command: %s" % command)
    rpc_id(1, "process_ai_command", command, selected_units)

# Getters for UI state
func get_connection_state() -> bool:
    return is_connected

func get_lobby_state() -> Dictionary:
    return {
        "is_in_lobby": is_in_lobby,
        "is_ready": is_ready,
        "lobby_players": lobby_players,
        "can_start_game": can_start_game,
        "current_session_id": current_session_id
    }

func cleanup() -> void:
    """Cleanup network resources"""
    disconnect_from_server()
    logger.info("NetworkManager", "Network manager cleanup complete") 