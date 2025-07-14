extends Node

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 100

var multiplayer_peer: ENetMultiplayerPeer
var connected_clients: Dictionary = {}
var server_running: bool = false

func _ready() -> void:
    print("Starting AI-RTS Dedicated Server...")
    
    # Connect multiplayer signals
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connection_failed.connect(_on_connection_failed)
    
    # Start server
    start_server()

func start_server(port: int = DEFAULT_PORT) -> bool:
    multiplayer_peer = ENetMultiplayerPeer.new()
    var error = multiplayer_peer.create_server(port, MAX_CLIENTS)
    
    if error != OK:
        print("Failed to start server: %s" % error)
        return false
    
    multiplayer.multiplayer_peer = multiplayer_peer
    server_running = true
    
    print("Server started on port %d (Server ID: %d)" % [port, multiplayer.get_unique_id()])
    print("Maximum clients: %d" % MAX_CLIENTS)
    
    return true

func stop_server() -> void:
    if multiplayer_peer:
        multiplayer_peer.close()
        multiplayer_peer = null
    
    server_running = false
    connected_clients.clear()
    
    print("Dedicated server stopped")

func _on_peer_connected(id: int) -> void:
    print("Client connected: %d" % id)
    connected_clients[id] = {
        "peer_id": id,
        "authenticated": false,
        "player_id": "",
        "session_id": "",
        "connected_at": Time.get_ticks_msec(),
        "last_ping": Time.get_ticks_msec()
    }
    
    # Send welcome message
    rpc_id(id, "_on_server_welcome", {
        "server_version": "1.0.0",
        "max_players_per_session": 4,
        "requires_auth": true
    })

func _on_peer_disconnected(id: int) -> void:
    print("Client disconnected: %d" % id)
    
    if id in connected_clients:
        var client_data = connected_clients[id]
        
        # Handle session cleanup
        if client_data.session_id != "":
            SessionManager.remove_player_from_session(client_data.player_id, client_data.session_id)
        
        # Clean up client data
        connected_clients.erase(id)

func _on_connection_failed() -> void:
    print("Server connection failed")

# Client authentication
@rpc("any_peer", "call_local", "reliable")
func authenticate_client(player_name: String, auth_token: String = "") -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    
    # Simple authentication for now - in production, verify auth_token
    var player_id = "player_%d_%s" % [peer_id, player_name.to_lower()]
    
    if peer_id in connected_clients:
        connected_clients[peer_id]["authenticated"] = true
        connected_clients[peer_id]["player_id"] = player_id
        
        print("Player authenticated: %s (peer: %d)" % [player_id, peer_id])
        
        # Send authentication response
        rpc_id(peer_id, "_on_auth_response", {
            "success": true,
            "player_id": player_id,
            "message": "Authentication successful"
        })
    else:
        rpc_id(peer_id, "_on_auth_response", {
            "success": false,
            "message": "Authentication failed - invalid peer"
        })

@rpc("any_peer", "call_local", "reliable")
func join_session(preferred_session_id: String = "") -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    
    if not peer_id in connected_clients:
        return
    
    var client_data = connected_clients[peer_id]
    
    if not client_data.authenticated:
        rpc_id(peer_id, "_on_session_join_response", {
            "success": false,
            "message": "Must authenticate first"
        })
        return
    
    # Let SessionManager handle the join
    var session_id = SessionManager.join_session(client_data.player_id, preferred_session_id)
    
    if session_id != "":
        client_data.session_id = session_id
        
        rpc_id(peer_id, "_on_session_join_response", {
            "success": true,
            "session_id": session_id,
            "message": "Joined session successfully"
        })
    else:
        rpc_id(peer_id, "_on_session_join_response", {
            "success": false,
            "message": "Failed to join session"
        })

@rpc("any_peer", "call_local", "reliable")
func leave_session() -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    
    if peer_id in connected_clients:
        var client_data = connected_clients[peer_id]
        
        if client_data.session_id != "":
            SessionManager.remove_player_from_session(client_data.player_id, client_data.session_id)
            client_data.session_id = ""
            
            rpc_id(peer_id, "_on_session_leave_response", {
                "success": true,
                "message": "Left session successfully"
            })

@rpc("any_peer", "call_local", "reliable")
func client_ping() -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    
    if peer_id in connected_clients:
        connected_clients[peer_id].last_ping = Time.get_ticks_msec()
        rpc_id(peer_id, "_on_server_pong", Time.get_ticks_msec())

# Server monitoring
func _process(_delta: float) -> void:
    if server_running:
        _monitor_connections()

func _monitor_connections() -> void:
    var current_time = Time.get_ticks_msec()
    var timeout_threshold = 30000  # 30 seconds
    
    for peer_id in connected_clients.keys():
        var client_data = connected_clients[peer_id]
        
        if current_time - client_data.last_ping > timeout_threshold:
            print("Client timeout: %d" % peer_id)
            if multiplayer_peer:
                multiplayer_peer.disconnect_peer(peer_id)

# Utility functions
func get_session_count() -> int:
    return SessionManager.get_session_count()

func get_connected_clients_count() -> int:
    return connected_clients.size()

func get_server_stats() -> Dictionary:
    return {
        "running": server_running,
        "connected_clients": connected_clients.size(),
        "active_sessions": get_session_count(),
        "uptime": Time.get_ticks_msec(),
        "port": DEFAULT_PORT
    }

# Print server stats periodically
func _on_stats_timer() -> void:
    var stats = get_server_stats()
    print("Server Stats: %d clients, %d sessions, uptime: %d ms" % [
        stats.connected_clients,
        stats.active_sessions,
        stats.uptime
    ]) 