extends Node
class_name GodotServerClient

@export var server_address: String = "127.0.0.1"
@export var server_port: int = 7777
@export var player_name: String = "TestPlayer"

var multiplayer_peer: ENetMultiplayerPeer
var connected: bool = false
var authenticated: bool = false
var in_session: bool = false
var player_id: String = ""
var session_id: String = ""

# Connection state
enum ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    AUTHENTICATED,
    IN_SESSION
}

var connection_state: ConnectionState = ConnectionState.DISCONNECTED

# Reconnection
var reconnect_attempts: int = 0
var max_reconnect_attempts: int = 3

# Signals
signal connected_to_server()
signal disconnected_from_server()
signal authentication_result(success: bool, player_id: String)
signal session_joined(session_id: String)
signal session_left()
signal ai_command_executed(data: Dictionary)
signal ai_command_error(error: String)

func _ready() -> void:
    # Connect multiplayer signals
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)
    
    print("GodotServerClient initialized")

func connect_to_server() -> bool:
    if connection_state != ConnectionState.DISCONNECTED:
        print("Already connected or connecting")
        return false
    
    multiplayer_peer = ENetMultiplayerPeer.new()
    var error = multiplayer_peer.create_client(server_address, server_port)
    
    if error != OK:
        print("Failed to create client: %s" % error)
        return false
    
    multiplayer.multiplayer_peer = multiplayer_peer
    connection_state = ConnectionState.CONNECTING
    
    print("Connecting to server at %s:%d..." % [server_address, server_port])
    return true

func disconnect_from_server() -> void:
    if connection_state == ConnectionState.DISCONNECTED:
        return
    
    # Send leave session if in session
    if connection_state == ConnectionState.IN_SESSION:
        leave_session()
    
    # Disconnect
    if multiplayer_peer:
        multiplayer_peer.close()
        multiplayer_peer = null
    
    connection_state = ConnectionState.DISCONNECTED
    connected = false
    authenticated = false
    in_session = false
    player_id = ""
    session_id = ""
    
    disconnected_from_server.emit()
    print("Disconnected from server")

func _on_connected_to_server() -> void:
    print("Connected to server")
    connection_state = ConnectionState.CONNECTED
    connected = true
    reconnect_attempts = 0
    
    connected_to_server.emit()
    
    # Auto-authenticate
    authenticate()

func _on_connection_failed() -> void:
    print("Connection to server failed")
    connection_state = ConnectionState.DISCONNECTED
    connected = false
    
    # Attempt reconnection
    _attempt_reconnection()

func _on_server_disconnected() -> void:
    print("Server disconnected")
    connection_state = ConnectionState.DISCONNECTED
    connected = false
    authenticated = false
    in_session = false
    player_id = ""
    session_id = ""
    
    disconnected_from_server.emit()
    
    # Attempt reconnection
    _attempt_reconnection()

func _attempt_reconnection() -> void:
    if reconnect_attempts < max_reconnect_attempts:
        reconnect_attempts += 1
        print("Reconnection attempt %d/%d in 2 seconds..." % [reconnect_attempts, max_reconnect_attempts])
        
        await get_tree().create_timer(2.0).timeout
        connect_to_server()
    else:
        print("Max reconnection attempts reached")

func authenticate() -> void:
    if connection_state != ConnectionState.CONNECTED:
        print("Not connected to server")
        return
    
    rpc_id(1, "authenticate_client", player_name, "default_token")
    print("Authenticating as %s..." % player_name)

func join_session(preferred_session_id: String = "") -> void:
    if connection_state != ConnectionState.AUTHENTICATED:
        print("Not authenticated")
        return
    
    rpc_id(1, "join_session", preferred_session_id)
    print("Joining session...")

func leave_session() -> void:
    if connection_state != ConnectionState.IN_SESSION:
        print("Not in session")
        return
    
    rpc_id(1, "leave_session")
    print("Leaving session...")

func send_ai_command(command: String, selected_unit_ids: Array = []) -> void:
    if connection_state != ConnectionState.IN_SESSION:
        print("Not in session - cannot send AI command")
        return
    
    rpc_id(1, "process_ai_command", command, selected_unit_ids)
    print("Sent AI command: %s" % command)

func ping_server() -> void:
    if connection_state in [ConnectionState.CONNECTED, ConnectionState.AUTHENTICATED, ConnectionState.IN_SESSION]:
        rpc_id(1, "client_ping")

# Server RPC receivers
@rpc("authority", "call_local", "reliable")
func _on_server_welcome(data: Dictionary) -> void:
    print("Server welcome: %s" % data.get("server_version", "unknown"))

@rpc("authority", "call_local", "reliable")
func _on_auth_response(data: Dictionary) -> void:
    var success = data.get("success", false)
    var message = data.get("message", "")
    
    if success:
        connection_state = ConnectionState.AUTHENTICATED
        authenticated = true
        player_id = data.get("player_id", "")
        print("Authentication successful: %s" % player_id)
        
        # Auto-join session
        join_session()
    else:
        print("Authentication failed: %s" % message)
    
    authentication_result.emit(success, player_id)

@rpc("authority", "call_local", "reliable")
func _on_session_join_response(data: Dictionary) -> void:
    var success = data.get("success", false)
    var message = data.get("message", "")
    
    if success:
        connection_state = ConnectionState.IN_SESSION
        in_session = true
        session_id = data.get("session_id", "")
        print("Joined session: %s" % session_id)
        session_joined.emit(session_id)
    else:
        print("Failed to join session: %s" % message)

@rpc("authority", "call_local", "reliable")
func _on_session_leave_response(data: Dictionary) -> void:
    var success = data.get("success", false)
    
    if success:
        connection_state = ConnectionState.AUTHENTICATED
        in_session = false
        session_id = ""
        print("Left session successfully")
        session_left.emit()

@rpc("authority", "call_local", "reliable")
func _on_session_started(data: Dictionary) -> void:
    print("Session started: %s" % data.get("session_id", ""))
    print("Players: %s" % data.get("players", []))

@rpc("authority", "call_local", "reliable")
func _on_session_ended(data: Dictionary) -> void:
    print("Session ended: %s" % data.get("reason", ""))
    in_session = false
    session_id = ""

@rpc("authority", "call_local", "reliable")
func _on_server_pong(server_time: int) -> void:
    var client_time = Time.get_ticks_msec()
    var ping = client_time - server_time
    print("Ping: %d ms" % ping)

@rpc("authority", "call_local", "reliable")
func _on_ai_commands_executed(data: Dictionary) -> void:
    print("AI commands executed by %s: %s" % [data.get("player_id", ""), data.get("commands", [])])
    ai_command_executed.emit(data)

@rpc("authority", "call_local", "reliable")
func _on_ai_command_error(data: Dictionary) -> void:
    var error = data.get("error", "Unknown error")
    print("AI command error: %s" % error)
    ai_command_error.emit(error)

@rpc("authority", "call_local", "reliable")
func _on_units_spawned(data: Dictionary) -> void:
    print("Units spawned for session: %s" % data.get("session_id", ""))
    var team_units = data.get("team_units", {})
    for team_id in team_units:
        print("Team %s units: %s" % [team_id, team_units[team_id]])

@rpc("authority", "call_local", "reliable")
func _on_session_list_response(session_list: Array) -> void:
    print("Available sessions:")
    for session_data in session_list:
        print("  %s: %d/%d players (%s)" % [
            session_data.get("session_id", ""),
            session_data.get("player_count", 0),
            session_data.get("max_players", 0),
            session_data.get("state", "")
        ])

# Utility functions
func is_connected_to_server() -> bool:
    return connection_state != ConnectionState.DISCONNECTED

func is_authenticated() -> bool:
    return connection_state in [ConnectionState.AUTHENTICATED, ConnectionState.IN_SESSION]

func is_in_session() -> bool:
    return connection_state == ConnectionState.IN_SESSION

func get_connection_info() -> Dictionary:
    return {
        "state": ConnectionState.keys()[connection_state],
        "player_id": player_id,
        "session_id": session_id,
        "server_address": server_address,
        "server_port": server_port
    }

# Auto-connect functionality for testing
func auto_connect_and_test() -> void:
    print("Starting auto-connect test...")
    
    # Connect to server
    if connect_to_server():
        # Wait for connection and session join
        await session_joined
        
        # Test AI commands
        await get_tree().create_timer(1.0).timeout
        send_ai_command("move all units forward")
        
        await get_tree().create_timer(2.0).timeout
        send_ai_command("attack enemy base")
        
        await get_tree().create_timer(2.0).timeout
        send_ai_command("form defensive line")
        
        print("Auto-test completed!")
    else:
        print("Auto-connect failed!")

# Test commands
func test_ai_commands() -> void:
    if not is_in_session():
        print("Must be in session to test AI commands")
        return
    
    var test_commands = [
        "move selected units forward",
        "attack the nearest enemy",
        "form a defensive line",
        "retreat to base",
        "stop all units"
    ]
    
    for command in test_commands:
        var unit_ids = ["unit_scout_0_0", "unit_soldier_0_2", "unit_tank_0_4"]
        send_ai_command(command, unit_ids)
        await get_tree().create_timer(1.0).timeout 