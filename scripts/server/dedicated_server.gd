# DedicatedServer.gd - Dedicated server with dependency injection
extends Node

# Injected dependencies
var logger
var session_manager: Node

# Network configuration
const DEFAULT_PORT = 7777
const MAX_CLIENTS = 100

# Server state
var multiplayer_peer: ENetMultiplayerPeer
var connected_clients: Dictionary = {}
var is_running: bool = false

# Signals
signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)
signal server_started()
signal server_stopped()

func setup(logger_ref, session_manager_ref):
    """Setup dependencies - called by DependencyContainer"""
    logger = logger_ref
    session_manager = session_manager_ref
    
    logger.info("DedicatedServer", "Setting up dedicated server")
    
    # Initialize server
    _initialize_server()

func _initialize_server():
    """Initialize the server"""
    # Connect multiplayer signals
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connection_failed.connect(_on_connection_failed)
    
    # Start server
    start_server()

func start_server(port: int = DEFAULT_PORT) -> bool:
    """Start the dedicated server"""
    if is_running:
        logger.warning("DedicatedServer", "Server already running")
        return false
    
    multiplayer_peer = ENetMultiplayerPeer.new()
    var error = multiplayer_peer.create_server(port, MAX_CLIENTS)
    
    if error != OK:
        logger.error("DedicatedServer", "Failed to start server: %s" % error)
        return false
    
    multiplayer.multiplayer_peer = multiplayer_peer
    is_running = true
    
    logger.info("DedicatedServer", "Server started on port %d (max clients: %d)" % [port, MAX_CLIENTS])
    server_started.emit()
    
    return true

func stop_server() -> void:
    """Stop the dedicated server"""
    if not is_running:
        logger.warning("DedicatedServer", "Server not running")
        return
    
    # Disconnect all clients
    for peer_id in connected_clients:
        multiplayer_peer.disconnect_peer(peer_id)
    
    # Close server
    multiplayer_peer.close()
    multiplayer.multiplayer_peer = null
    
    connected_clients.clear()
    is_running = false
    
    logger.info("DedicatedServer", "Server stopped")
    server_stopped.emit()

func get_client_count() -> int:
    """Get the number of connected clients"""
    return connected_clients.size()

func get_client_data(peer_id: int) -> Dictionary:
    """Get client data by peer ID"""
    return connected_clients.get(peer_id, {})

func is_client_connected(peer_id: int) -> bool:
    """Check if a client is connected"""
    return peer_id in connected_clients

func kick_client(peer_id: int, reason: String = "") -> void:
    """Kick a client from the server"""
    if peer_id in connected_clients:
        logger.info("DedicatedServer", "Kicking client %d: %s" % [peer_id, reason])
        multiplayer_peer.disconnect_peer(peer_id)

# Signal handlers
func _on_peer_connected(peer_id: int) -> void:
    """Handle new peer connection"""
    logger.info("DedicatedServer", "Peer connected: %d" % peer_id)
    
    # Add client to tracking
    connected_clients[peer_id] = {
        "peer_id": peer_id,
        "connected_at": Time.get_ticks_msec(),
        "authenticated": false,
        "player_id": "",
        "session_id": ""
    }
    
    # Send welcome message to client
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if root_node:
        root_node.rpc_id(peer_id, "_on_server_welcome", {
            "server_version": "1.0.0",
            "max_clients": MAX_CLIENTS,
            "current_clients": connected_clients.size()
        })
    
    # Notify session manager
    if session_manager:
        session_manager.on_client_connected(peer_id)
    
    client_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
    """Handle peer disconnection"""
    logger.info("DedicatedServer", "Peer disconnected: %d" % peer_id)
    
    # Get client data before removing
    var client_data = connected_clients.get(peer_id, {})
    
    # Remove client from tracking
    connected_clients.erase(peer_id)
    
    # Notify session manager
    if session_manager:
        session_manager.on_client_disconnected(peer_id, client_data)
    
    client_disconnected.emit(peer_id)

func _on_connection_failed() -> void:
    """Handle connection failure"""
    logger.error("DedicatedServer", "Connection failed")

# Handler methods (called by UnifiedMain RPC delegation)
func handle_authentication(peer_id: int, player_name: String, _auth_token: String) -> void:
    """Handle client authentication request"""
    logger.info("DedicatedServer", "Authentication request from %d: %s" % [peer_id, player_name])
    
    # Simple authentication (in production, this would be more secure)
    var success = true
    var player_id = "player_%d_%d" % [peer_id, Time.get_ticks_msec()]
    
    if peer_id in connected_clients:
        connected_clients[peer_id]["authenticated"] = success
        connected_clients[peer_id]["player_id"] = player_id
        connected_clients[peer_id]["player_name"] = player_name
    
    # Send authentication response through root multiplayer node
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if root_node:
        root_node.rpc_id(peer_id, "_on_auth_response", {
            "success": success,
            "player_id": player_id,
            "message": "Authentication successful" if success else "Authentication failed"
        })
    
    logger.info("DedicatedServer", "Client %d authenticated as %s" % [peer_id, player_name])

func handle_ping(peer_id: int) -> void:
    """Handle client ping"""
    logger.info("DedicatedServer", "Ping from %d" % peer_id)
    
    # Send pong response through root multiplayer node
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if root_node:
        root_node.rpc_id(peer_id, "_on_pong", Time.get_ticks_msec())

# Public interface
func get_server_stats() -> Dictionary:
    """Get server statistics"""
    return {
        "is_running": is_running,
        "port": DEFAULT_PORT,
        "max_clients": MAX_CLIENTS,
        "connected_clients": connected_clients.size(),
        "uptime": Time.get_ticks_msec() if is_running else 0
    }

func cleanup() -> void:
    """Cleanup resources"""
    if is_running:
        stop_server()
    logger.info("DedicatedServer", "Dedicated server cleaned up")

# Note: RPC methods are now handled by UnifiedMain root node 