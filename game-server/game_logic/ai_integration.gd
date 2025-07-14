extends Node

# AI service configuration
var ai_service_url: String = "http://localhost:8000"
var http_request: HTTPRequest
var pending_requests: Dictionary = {}

# Request tracking
var request_counter: int = 0
var max_concurrent_requests: int = 10

func _ready() -> void:
    # Create HTTP request node
    http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.request_completed.connect(_on_ai_response)
    
    # Set timeout
    http_request.timeout = 10.0
    
    print("AI Integration initialized")

@rpc("any_peer", "call_local", "reliable")
func process_ai_command(command: String, selected_unit_ids: Array) -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    
    # Validate sender
    if not _validate_ai_command_authority(peer_id):
        return
    
    # Get player and session info
    var player_id = _get_player_id_from_peer(peer_id)
    var session_id = _get_session_id_from_peer(peer_id)
    
    if player_id == "" or session_id == "":
        _send_ai_error_to_player(peer_id, "Invalid player or session")
        return
    
    # Rate limiting
    if pending_requests.size() >= max_concurrent_requests:
        _send_ai_error_to_player(peer_id, "Too many concurrent AI requests")
        return
    
    # Create request
    var request_id = "ai_req_" + str(request_counter)
    request_counter += 1
    
    var request_data = {
        "request_id": request_id,
        "session_id": session_id,
        "player_id": player_id,
        "command": command,
        "selected_units": selected_unit_ids,
        "game_state": _build_game_state(session_id, player_id),
        "timestamp": Time.get_ticks_msec()
    }
    
    # Store request info
    pending_requests[request_id] = {
        "sender_id": peer_id,
        "player_id": player_id,
        "session_id": session_id,
        "selected_unit_ids": selected_unit_ids,
        "timestamp": Time.get_ticks_msec()
    }
    
    # Send to AI service
    _send_ai_request(request_data)
    
    print("AI command from %s: %s" % [player_id, command])

func _send_ai_request(request_data: Dictionary) -> void:
    var headers = ["Content-Type: application/json"]
    var json_data = JSON.stringify(request_data)
    var url = ai_service_url + "/ai/process-command"
    
    var error = http_request.request(url, headers, HTTPClient.METHOD_POST, json_data)
    
    if error != OK:
        print("Failed to send AI request: %s" % error)
        var request_id = request_data.get("request_id", "")
        if request_id in pending_requests:
            var request_info = pending_requests[request_id]
            _send_ai_error_to_player(request_info.sender_id, "Failed to contact AI service")
            pending_requests.erase(request_id)

func _on_ai_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if response_code != 200:
        print("AI service HTTP error: %s" % response_code)
        return
    
    var json = JSON.new()
    var parse_result = json.parse(body.get_string_from_utf8())
    
    if parse_result != OK:
        print("Failed to parse AI response")
        return
    
    var response_data = json.data
    var request_id = response_data.get("request_id", "")
    
    if not request_id in pending_requests:
        print("Unknown AI request ID: %s" % request_id)
        return
    
    var request_info = pending_requests[request_id]
    pending_requests.erase(request_id)
    
    if response_data.get("success", false):
        var commands = response_data.get("commands", [])
        _execute_ai_commands(request_info, commands)
    else:
        var error_msg = response_data.get("error", "AI processing failed")
        _send_ai_error_to_player(request_info.sender_id, error_msg)

func _execute_ai_commands(request_info: Dictionary, commands: Array) -> void:
    var session_id = request_info.session_id
    var player_id = request_info.player_id
    var selected_unit_ids = request_info.selected_unit_ids
    
    print("Executing %d AI commands for player %s" % [commands.size(), player_id])
    
    # Get session and unit spawner
    var session = SessionManager.sessions.get(session_id, null)
    if not session:
        print("Session not found: %s" % session_id)
        return
    
    var unit_spawner = session.game_scene.get_node("UnitSpawner")
    if not unit_spawner:
        print("Unit spawner not found in session: %s" % session_id)
        return
    
    # Execute commands on actual units
    for command in commands:
        _execute_single_ai_command(command, selected_unit_ids, session_id, unit_spawner)
    
    # Broadcast AI command execution to session
    var session_players = _get_session_players(session_id)
    for session_player_id in session_players:
        var peer_id = _get_peer_id_from_player(session_player_id)
        if peer_id > 0:
            DedicatedServer.rpc_id(peer_id, "_on_ai_commands_executed", {
                "player_id": player_id,
                "commands": commands,
                "timestamp": Time.get_ticks_msec()
            })

func _execute_single_ai_command(command: Dictionary, selected_unit_ids: Array, session_id: String, unit_spawner: UnitSpawner) -> void:
    var command_type = command.get("type", "")
    var unit_ids = command.get("unit_ids", selected_unit_ids)
    
    # Execute command on actual units
    match command_type:
        "MOVE":
            var target_pos_array = command.get("target_position", [0, 0, 0])
            var target_pos = Vector3(target_pos_array[0], target_pos_array[1], target_pos_array[2])
            print("AI MOVE command: units %s to position %s" % [unit_ids, target_pos])
            
            var move_command = {
                "type": "MOVE",
                "target_position": target_pos
            }
            unit_spawner.execute_command_on_units(unit_ids, move_command)
            
        "ATTACK":
            var target_id = command.get("target_unit_id", "")
            print("AI ATTACK command: units %s attack %s" % [unit_ids, target_id])
            
            var attack_command = {
                "type": "ATTACK",
                "target_unit_id": target_id
            }
            unit_spawner.execute_command_on_units(unit_ids, attack_command)
            
        "STOP":
            print("AI STOP command: units %s" % [unit_ids])
            
            var stop_command = {
                "type": "STOP"
            }
            unit_spawner.execute_command_on_units(unit_ids, stop_command)
            
        "FORMATION":
            var formation = command.get("formation", "line")
            var center_pos_array = command.get("center_position", [0, 0, 0])
            var center_pos = Vector3(center_pos_array[0], center_pos_array[1], center_pos_array[2])
            print("AI FORMATION command: units %s formation %s at %s" % [unit_ids, formation, center_pos])
            
            unit_spawner.arrange_units_in_formation(unit_ids, formation, center_pos)
            
        _:
            print("Unknown AI command type: %s" % command_type)

func _build_game_state(session_id: String, player_id: String) -> Dictionary:
    # Build basic game state for AI processing
    var session = SessionManager.sessions.get(session_id, null)
    if not session:
        return {}
    
    var game_state = {
        "session_id": session_id,
        "player_id": player_id,
        "match_time": (Time.get_ticks_msec() - session.created_at) / 1000.0,
        "players": session.players.duplicate(),
        "units": [],
        "enemies": [],
        "map_info": {}
    }
    
    # Get actual unit data from the spawner
    var unit_spawner = session.game_scene.get_node("UnitSpawner")
    if unit_spawner:
        var all_units = unit_spawner.get_all_units()
        
        # Get player's team ID
        var player_team_id = -1
        for i in range(session.players.size()):
            if session.players[i] == player_id:
                player_team_id = i
                break
        
        # Separate units into player's units and enemies
        for unit in all_units:
            var unit_data = {
                "id": unit.unit_id,
                "type": unit.unit_type,
                "position": [unit.global_position.x, unit.global_position.y, unit.global_position.z],
                "health": unit.current_health,
                "max_health": unit.max_health,
                "state": ServerUnit.UnitState.keys()[unit.current_state].to_lower()
            }
            
            if unit.team_id == player_team_id:
                game_state.units.append(unit_data)
            else:
                game_state.enemies.append(unit_data)
    
    return game_state

func _validate_ai_command_authority(sender_id: int) -> bool:
    # Check if sender is authenticated and in a session
    if not sender_id in DedicatedServer.connected_clients:
        return false
    
    var client_data = DedicatedServer.connected_clients[sender_id]
    return client_data.authenticated and client_data.session_id != ""

func _get_player_id_from_peer(peer_id: int) -> String:
    if peer_id in DedicatedServer.connected_clients:
        return DedicatedServer.connected_clients[peer_id].player_id
    return ""

func _get_session_id_from_peer(peer_id: int) -> String:
    if peer_id in DedicatedServer.connected_clients:
        return DedicatedServer.connected_clients[peer_id].session_id
    return ""

func _get_peer_id_from_player(player_id: String) -> int:
    for peer_id in DedicatedServer.connected_clients:
        var client_data = DedicatedServer.connected_clients[peer_id]
        if client_data.player_id == player_id:
            return peer_id
    return -1

func _get_session_players(session_id: String) -> Array:
    var session = SessionManager.sessions.get(session_id, null)
    if session:
        return session.players.duplicate()
    return []

func _send_ai_error_to_player(peer_id: int, error_message: String) -> void:
    DedicatedServer.rpc_id(peer_id, "_on_ai_command_error", {
        "error": error_message,
        "timestamp": Time.get_ticks_msec()
    })

# Health check for AI service
func check_ai_service_health() -> void:
    var headers = ["Content-Type: application/json"]
    var url = ai_service_url + "/ai/status"
    
    var temp_http = HTTPRequest.new()
    add_child(temp_http)
    temp_http.request_completed.connect(_on_health_check_response)
    temp_http.timeout = 5.0
    
    var error = temp_http.request(url, headers, HTTPClient.METHOD_GET)
    if error != OK:
        print("Failed to check AI service health: %s" % error)
        temp_http.queue_free()

func _on_health_check_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    var sender = get_children().back()  # Get the temp HTTP request node
    
    if response_code == 200:
        print("AI service is healthy")
    else:
        print("AI service health check failed: %s" % response_code)
    
    sender.queue_free()

# Test AI service on startup
func _on_startup_timer() -> void:
    check_ai_service_health()

# Set up periodic health checks
func _ready_health_monitoring() -> void:
    var timer = Timer.new()
    timer.wait_time = 60.0  # Check every minute
    timer.timeout.connect(check_ai_service_health)
    timer.autostart = true
    add_child(timer)
    
    # Initial health check after 2 seconds
    var startup_timer = Timer.new()
    startup_timer.wait_time = 2.0
    startup_timer.timeout.connect(_on_startup_timer)
    startup_timer.one_shot = true
    startup_timer.autostart = true
    add_child(startup_timer) 