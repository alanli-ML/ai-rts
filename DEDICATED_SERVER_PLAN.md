# Godot Dedicated Server Architecture Migration Plan

## 🎯 Architecture Overview

### Current Architecture (P2P)
```
┌─────────────────┐    ┌─────────────────┐
│   Client A      │    │   Client B      │
│   (Host/Server) │◄──►│   (Client)      │
└─────────────────┘    └─────────────────┘
```

### Target Architecture (Godot Dedicated Server)
```
┌─────────────┐    ┌─────────────────┐    ┌─────────────┐
│   Client A  │    │ Godot Headless  │    │   Client B  │
│             │◄──►│  Server (ENet)  │◄──►│             │
└─────────────┘    └─────────────────┘    └─────────────┘
                            │
                   ┌─────────────────┐
                   │   AI Service    │
                   │   (HTTP/REST)   │
                   └─────────────────┘
```

## 🏗️ Phase 1: Server Infrastructure (Weeks 1-2)

### 1.1 Dedicated Game Server Setup

**Technology Stack:**
- **Framework**: Godot 4.4 headless server
- **Communication**: ENetMultiplayerPeer with RPC system
- **Database**: Redis for real-time state (PostgreSQL optional)
- **Synchronization**: MultiplayerSynchronizer for state sync
- **Load Balancer**: Nginx for multiple server instances

**Server Components:**
```
game-server/
├── main.gd                    # Headless Godot server
├── server/
│   ├── dedicated_server.gd   # ENetMultiplayerPeer server
│   ├── session_manager.gd    # Game session management
│   ├── player_manager.gd     # Player connection handling
│   └── game_state_manager.gd # Authoritative game state
├── multiplayer/
│   ├── server_spawner.gd     # MultiplayerSpawner management
│   ├── unit_synchronizer.gd  # MultiplayerSynchronizer
│   └── rpc_manager.gd        # RPC definitions
├── game_logic/
│   ├── unit_controller.gd    # Server-side unit logic
│   ├── combat_system.gd      # Server-side combat
│   └── ai_integration.gd     # AI service integration
└── database/
    ├── game_persistence.gd   # Database operations
    └── redis_client.gd       # Redis real-time state
```

### 1.2 Server Architecture Design

**Server Responsibilities:**
- ✅ **Game State Authority**: Single source of truth with MultiplayerSynchronizer
- ✅ **Player Management**: ENet peer connections and session management
- ✅ **Unit Control**: Authoritative unit control via RPC system
- ✅ **Combat Resolution**: Server-side damage calculation and validation
- ✅ **AI Integration**: Coordinate with AI service via HTTP requests
- ✅ **Session Management**: Multiple concurrent game sessions
- ✅ **Node Spawning**: Automatic unit spawning with MultiplayerSpawner

**Client Responsibilities:**
- ✅ **Input Handling**: Capture and send user input via RPC
- ✅ **Rendering**: Display synchronized game state from server
- ✅ **UI Management**: Local UI state and responsiveness
- ✅ **Node Synchronization**: Receive state updates via MultiplayerSynchronizer
- ✅ **RPC Handling**: Process server commands and responses

## 🔗 Phase 2: Godot Multiplayer Communication (Weeks 3-4)

### 2.1 ENetMultiplayerPeer-Based Communication

**Connection Flow:**
```
Client → ENet Connection → Authentication → Session Join → State Sync
```

**RPC Methods:**
```gdscript
# Server RPCs (called by clients)
@rpc("any_peer", "call_local", "reliable")
func authenticate_client(player_name: String, auth_token: String)

@rpc("any_peer", "call_local", "reliable")
func join_session(preferred_session_id: String)

@rpc("any_peer", "call_local", "reliable")
func leave_session()

@rpc("any_peer", "call_local", "reliable")
func process_ai_command(command: String, selected_units: Array)

# Client RPCs (called by server)
@rpc("authority", "call_local", "reliable")
func _on_auth_response(success: bool, player_id: String)

@rpc("authority", "call_local", "reliable")
func _on_session_joined(session_id: String)

@rpc("authority", "call_local", "reliable")
func _on_ai_commands_executed(commands: Array)

# Unit RPCs
@rpc("any_peer", "call_local", "reliable")
func move_to(target_position: Vector3)

@rpc("any_peer", "call_local", "reliable")
func attack_target(target_unit_id: String)
```

### 2.2 RPC Protocol Design

**Automatic Message Handling:**
```gdscript
# Godot handles peer identification automatically
func _on_peer_connected(id: int) -> void:
    # Server assigns player data to peer ID
    connected_clients[id] = player_data

# RPCs automatically include sender information
@rpc("any_peer", "call_local", "reliable")
func process_command(command: String) -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    var player_data = connected_clients[peer_id]
    # Process command with player context
```

**Game State Update Message:**
```gdscript
class GameStateMessage:
    var message_type = MessageType.GAME_STATE_UPDATE
    var tick_number: int
    var game_time: float
    var units: Array[UnitState]
    var players: Array[PlayerState]
    var match_state: MatchState
```

**Player Input Message:**
```gdscript
class PlayerInputMessage:
    var message_type = MessageType.PLAYER_INPUT
    var input_type: InputType
    var target_position: Vector3
    var selected_units: Array[String]
    var command_data: Dictionary
```

### 2.3 State Synchronization Strategy

**MultiplayerSynchronizer Settings:**
- **Critical Updates**: 30 FPS (unit positions, combat)
- **Standard Updates**: 10 FPS (UI state, resources)
- **Event-Based**: Immediate (unit death, AI responses)

**Automatic Delta Compression:**
- Godot handles delta compression automatically
- Only changed properties are transmitted
- Configurable replication intervals per property

## 🎮 Phase 3: Godot Server-Authoritative Game State (Weeks 5-6)

### 3.1 Game State Manager with MultiplayerSynchronizer

**File: `game-server/core/game_state_manager.gd`**
```gdscript
class_name GameStateManager
extends Node

# Authoritative game state
var current_tick: int = 0
var game_time: float = 0.0
var units: Dictionary = {}  # unit_id -> UnitState
var players: Dictionary = {}  # player_id -> PlayerState
var match_state: MatchState

# State validation
var state_history: Array[GameState] = []
var max_history_size: int = 300  # 10 seconds at 30 FPS

func _ready() -> void:
    # Initialize server-side game loop
    var timer = Timer.new()
    timer.wait_time = 1.0 / 30.0  # 30 FPS
    timer.timeout.connect(_server_tick)
    add_child(timer)
    timer.start()

func _server_tick() -> void:
    current_tick += 1
    game_time += 1.0 / 30.0
    
    # Update all units
    _update_units()
    
    # Process combat
    _process_combat()
    
    # Send state updates to clients
    _send_state_updates()
    
    # Store state history
    _store_state_history()

func _update_units() -> void:
    for unit_id in units:
        var unit = units[unit_id]
        unit.update(1.0 / 30.0)

func _process_combat() -> void:
    # Server-authoritative combat resolution
    for unit_id in units:
        var unit = units[unit_id]
        if unit.is_attacking:
            _resolve_combat(unit)

func _send_state_updates() -> void:
    # Send delta updates to all connected clients
    var delta_update = _create_delta_update()
    NetworkManager.broadcast_message(delta_update)

func validate_player_input(player_id: String, input_data: Dictionary) -> bool:
    # Validate input against server state
    if not players.has(player_id):
        return false
    
    var player = players[player_id]
    
    # Validate unit ownership
    if input_data.has("selected_units"):
        for unit_id in input_data.selected_units:
            if not _player_owns_unit(player_id, unit_id):
                return false
    
    return true

func process_player_input(player_id: String, input_data: Dictionary) -> void:
    if not validate_player_input(player_id, input_data):
        Logger.warning("GameStateManager", "Invalid input from player: " + player_id)
        return
    
    # Process validated input
    match input_data.type:
        "move_command":
            _process_move_command(player_id, input_data)
        "attack_command":
            _process_attack_command(player_id, input_data)
        "ai_command":
            _process_ai_command(player_id, input_data)
```

### 3.2 Unit State Management

**File: `game-server/game_logic/unit_controller.gd`**
```gdscript
class_name ServerUnitController
extends Node

# Server-authoritative unit state
class UnitState:
    var unit_id: String
    var owner_team: int
    var archetype: String
    var position: Vector3
    var rotation: float
    var health: float
    var max_health: float
    var state: String  # "idle", "moving", "attacking", "dead"
    var target_position: Vector3
    var move_speed: float
    var last_update: float
    
    func update(delta: float) -> void:
        match state:
            "moving":
                _update_movement(delta)
            "attacking":
                _update_attack(delta)
    
    func _update_movement(delta: float) -> void:
        var direction = (target_position - position).normalized()
        var distance = position.distance_to(target_position)
        
        if distance > 0.1:  # Not at target
            var move_distance = move_speed * delta
            if move_distance >= distance:
                position = target_position
                state = "idle"
            else:
                position += direction * move_distance
        else:
            state = "idle"

func create_unit(unit_id: String, archetype: String, team: int, spawn_position: Vector3) -> UnitState:
    var unit = UnitState.new()
    unit.unit_id = unit_id
    unit.archetype = archetype
    unit.owner_team = team
    unit.position = spawn_position
    unit.health = _get_archetype_health(archetype)
    unit.max_health = unit.health
    unit.move_speed = _get_archetype_speed(archetype)
    unit.state = "idle"
    
    return unit

func move_unit(unit_id: String, target_position: Vector3) -> bool:
    if not GameStateManager.units.has(unit_id):
        return false
    
    var unit = GameStateManager.units[unit_id]
    unit.target_position = target_position
    unit.state = "moving"
    
    Logger.info("ServerUnitController", "Unit %s moving to %s" % [unit_id, target_position])
    return true

func damage_unit(unit_id: String, damage: float, attacker_id: String) -> bool:
    if not GameStateManager.units.has(unit_id):
        return false
    
    var unit = GameStateManager.units[unit_id]
    unit.health -= damage
    
    if unit.health <= 0:
        unit.health = 0
        unit.state = "dead"
        _handle_unit_death(unit_id, attacker_id)
        return true
    
    # Broadcast damage event
    var damage_event = {
        "type": "damage_dealt",
        "unit_id": unit_id,
        "damage": damage,
        "attacker_id": attacker_id,
        "new_health": unit.health
    }
    NetworkManager.broadcast_message(damage_event)
    
    return false  # Unit still alive

func _handle_unit_death(unit_id: String, attacker_id: String) -> void:
    var death_event = {
        "type": "unit_death",
        "unit_id": unit_id,
        "attacker_id": attacker_id
    }
    NetworkManager.broadcast_message(death_event)
    
    # Remove unit after delay for death animation
    await get_tree().create_timer(2.0).timeout
    GameStateManager.units.erase(unit_id)
```

## 🔄 Phase 4: Session Management (Weeks 7-8)

### 4.1 Session Manager

**File: `game-server/core/session_manager.gd`**
```gdscript
class_name SessionManager
extends Node

# Session management
var active_sessions: Dictionary = {}  # session_id -> GameSession
var waiting_players: Array[PlayerData] = []

class GameSession:
    var session_id: String
    var max_players: int = 4  # 2v2
    var current_players: Dictionary = {}  # player_id -> PlayerData
    var teams: Dictionary = {}  # team_id -> TeamData
    var state: String = "waiting"  # "waiting", "starting", "active", "ending"
    var created_at: float
    var started_at: float
    var game_state_manager: GameStateManager
    
    func _init(id: String):
        session_id = id
        created_at = Time.get_ticks_msec()
        game_state_manager = GameStateManager.new()
    
    func add_player(player_data: PlayerData) -> bool:
        if current_players.size() >= max_players:
            return false
        
        current_players[player_data.player_id] = player_data
        _assign_to_team(player_data)
        
        # Check if session can start
        if current_players.size() == max_players:
            _check_ready_to_start()
        
        return true
    
    func remove_player(player_id: String) -> void:
        if player_id in current_players:
            var player = current_players[player_id]
            _remove_from_team(player)
            current_players.erase(player_id)
            
            # Handle session state
            if state == "active":
                _handle_player_disconnect(player_id)
            elif current_players.size() == 0:
                _mark_for_cleanup()
    
    func _assign_to_team(player_data: PlayerData) -> void:
        # Assign to team with fewer players
        var team_1_size = teams.get(1, {}).get("players", []).size()
        var team_2_size = teams.get(2, {}).get("players", []).size()
        
        var target_team = 1 if team_1_size <= team_2_size else 2
        
        if not teams.has(target_team):
            teams[target_team] = {"players": [], "units": []}
        
        teams[target_team]["players"].append(player_data.player_id)
        player_data.team_id = target_team
    
    func start_match() -> void:
        state = "active"
        started_at = Time.get_ticks_msec()
        
        # Spawn units for each team
        _spawn_team_units()
        
        # Start game loop
        game_state_manager.start_match()
        
        # Notify all players
        var start_message = {
            "type": "match_started",
            "session_id": session_id,
            "teams": teams
        }
        _broadcast_to_session(start_message)

func create_session() -> String:
    var session_id = "session_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
    var session = GameSession.new(session_id)
    active_sessions[session_id] = session
    
    Logger.info("SessionManager", "Created session: " + session_id)
    return session_id

func join_session(player_data: PlayerData, session_id: String = "") -> String:
    var session: GameSession
    
    if session_id == "":
        # Find available session or create new one
        session = _find_available_session()
        if not session:
            session_id = create_session()
            session = active_sessions[session_id]
    else:
        session = active_sessions.get(session_id, null)
    
    if not session:
        Logger.error("SessionManager", "Session not found: " + session_id)
        return ""
    
    if session.add_player(player_data):
        Logger.info("SessionManager", "Player %s joined session %s" % [player_data.player_id, session_id])
        return session_id
    else:
        Logger.warning("SessionManager", "Failed to add player to session: " + session_id)
        return ""

func leave_session(player_id: String, session_id: String) -> void:
    if session_id in active_sessions:
        var session = active_sessions[session_id]
        session.remove_player(player_id)
        
        # Clean up empty sessions
        if session.current_players.size() == 0:
            active_sessions.erase(session_id)
            Logger.info("SessionManager", "Cleaned up empty session: " + session_id)

func _find_available_session() -> GameSession:
    for session in active_sessions.values():
        if session.state == "waiting" and session.current_players.size() < session.max_players:
            return session
    return null
```

### 4.2 Player Connection Management

**File: `game-server/core/player_manager.gd`**
```gdscript
class_name PlayerManager
extends Node

# Player connection state
var connected_players: Dictionary = {}  # player_id -> PlayerConnection
var authentication_tokens: Dictionary = {}  # token -> player_id

class PlayerConnection:
    var player_id: String
    var websocket: WebSocketPeer
    var session_id: String
    var last_ping: float
    var is_authenticated: bool = false
    var connection_time: float
    
    func _init(id: String, ws: WebSocketPeer):
        player_id = id
        websocket = ws
        connection_time = Time.get_ticks_msec()
        last_ping = connection_time

func authenticate_player(token: String) -> String:
    # Validate authentication token
    if token in authentication_tokens:
        return authentication_tokens[token]
    
    # For development, generate temporary player ID
    var player_id = "player_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
    authentication_tokens[token] = player_id
    
    Logger.info("PlayerManager", "Authenticated player: " + player_id)
    return player_id

func connect_player(player_id: String, websocket: WebSocketPeer) -> bool:
    if player_id in connected_players:
        Logger.warning("PlayerManager", "Player already connected: " + player_id)
        return false
    
    var connection = PlayerConnection.new(player_id, websocket)
    connected_players[player_id] = connection
    
    Logger.info("PlayerManager", "Player connected: " + player_id)
    return true

func disconnect_player(player_id: String) -> void:
    if player_id in connected_players:
        var connection = connected_players[player_id]
        
        # Leave current session
        if connection.session_id != "":
            SessionManager.leave_session(player_id, connection.session_id)
        
        # Clean up connection
        connected_players.erase(player_id)
        Logger.info("PlayerManager", "Player disconnected: " + player_id)

func send_message(player_id: String, message: Dictionary) -> bool:
    if not player_id in connected_players:
        return false
    
    var connection = connected_players[player_id]
    var json_message = JSON.stringify(message)
    
    if connection.websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        connection.websocket.send_text(json_message)
        return true
    else:
        Logger.warning("PlayerManager", "WebSocket not ready for player: " + player_id)
        return false

func broadcast_message(message: Dictionary, exclude_player: String = "") -> void:
    for player_id in connected_players:
        if player_id != exclude_player:
            send_message(player_id, message)

func _ready() -> void:
    # Start connection monitoring
    var timer = Timer.new()
    timer.wait_time = 5.0  # Check every 5 seconds
    timer.timeout.connect(_monitor_connections)
    add_child(timer)
    timer.start()

func _monitor_connections() -> void:
    var current_time = Time.get_ticks_msec()
    var timeout_threshold = 30000  # 30 seconds
    
    for player_id in connected_players.keys():
        var connection = connected_players[player_id]
        
        if current_time - connection.last_ping > timeout_threshold:
            Logger.warning("PlayerManager", "Player timed out: " + player_id)
            disconnect_player(player_id)
```

## 🤖 Phase 5: AI Service Integration (Weeks 9-10)

### 5.1 Server-Side AI Integration

**File: `game-server/game_logic/ai_integration.gd`**
```gdscript
class_name AIIntegration
extends Node

# AI service communication
var ai_service_url: String = "http://localhost:8000"
var http_client: HTTPRequest
var pending_ai_requests: Dictionary = {}  # request_id -> AIRequest

class AIRequest:
    var request_id: String
    var session_id: String
    var player_id: String
    var command: String
    var game_state: Dictionary
    var timestamp: float
    var callback: Callable
    
    func _init(id: String, session: String, player: String, cmd: String, state: Dictionary, cb: Callable):
        request_id = id
        session_id = session
        player_id = player
        command = cmd
        game_state = state
        timestamp = Time.get_ticks_msec()
        callback = cb

func _ready() -> void:
    http_client = HTTPRequest.new()
    add_child(http_client)
    http_client.request_completed.connect(_on_ai_response)

func process_ai_command(session_id: String, player_id: String, command: String, callback: Callable) -> String:
    var request_id = _generate_request_id()
    
    # Get current game state for the session
    var game_state = _build_game_state(session_id, player_id)
    
    # Create AI request
    var ai_request = AIRequest.new(request_id, session_id, player_id, command, game_state, callback)
    pending_ai_requests[request_id] = ai_request
    
    # Send to AI service
    var request_data = {
        "request_id": request_id,
        "session_id": session_id,
        "player_id": player_id,
        "command": command,
        "game_state": game_state,
        "timestamp": Time.get_ticks_msec()
    }
    
    var headers = ["Content-Type: application/json"]
    var json_data = JSON.stringify(request_data)
    var url = ai_service_url + "/ai/process-command"
    
    Logger.info("AIIntegration", "Sending AI command: " + command)
    http_client.request(url, headers, HTTPClient.METHOD_POST, json_data)
    
    return request_id

func _on_ai_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if response_code != 200:
        Logger.error("AIIntegration", "AI service error: " + str(response_code))
        return
    
    var json = JSON.new()
    var parse_result = json.parse(body.get_string_from_utf8())
    
    if parse_result != OK:
        Logger.error("AIIntegration", "Failed to parse AI response")
        return
    
    var response_data = json.data
    var request_id = response_data.get("request_id", "")
    
    if request_id in pending_ai_requests:
        var ai_request = pending_ai_requests[request_id]
        pending_ai_requests.erase(request_id)
        
        # Process AI response
        if response_data.get("success", false):
            var commands = response_data.get("commands", [])
            _execute_ai_commands(ai_request.session_id, ai_request.player_id, commands)
            
            # Call callback
            ai_request.callback.call(true, commands)
        else:
            var error = response_data.get("error", "Unknown error")
            Logger.error("AIIntegration", "AI command failed: " + error)
            ai_request.callback.call(false, [])

func _execute_ai_commands(session_id: String, player_id: String, commands: Array) -> void:
    var session = SessionManager.active_sessions.get(session_id, null)
    if not session:
        return
    
    Logger.info("AIIntegration", "Executing %d AI commands for player %s" % [commands.size(), player_id])
    
    for command in commands:
        match command.get("type", ""):
            "MOVE":
                _execute_move_command(session, player_id, command)
            "ATTACK":
                _execute_attack_command(session, player_id, command)
            "FORMATION":
                _execute_formation_command(session, player_id, command)
            "STOP":
                _execute_stop_command(session, player_id, command)
    
    # Broadcast AI command execution to all players in session
    var ai_event = {
        "type": "ai_command_executed",
        "player_id": player_id,
        "commands": commands
    }
    _broadcast_to_session(session_id, ai_event)

func _execute_move_command(session: SessionManager.GameSession, player_id: String, command: Dictionary) -> void:
    var unit_ids = command.get("unit_ids", [])
    var target_position = command.get("target_position", [0, 0, 0])
    var target_vec = Vector3(target_position[0], target_position[1], target_position[2])
    
    # Validate unit ownership
    for unit_id in unit_ids:
        if _player_owns_unit(session, player_id, unit_id):
            ServerUnitController.move_unit(unit_id, target_vec)

func _build_game_state(session_id: String, player_id: String) -> Dictionary:
    var session = SessionManager.active_sessions.get(session_id, null)
    if not session:
        return {}
    
    var game_state = {
        "match_time": (Time.get_ticks_msec() - session.started_at) / 1000.0,
        "team_id": _get_player_team(session, player_id),
        "selected_units": [],  # Will be populated by current selection
        "visible_enemies": [],  # Will be populated by vision system
        "map_info": {},
        "units": []
    }
    
    # Add visible units
    for unit_id in session.game_state_manager.units:
        var unit = session.game_state_manager.units[unit_id]
        game_state.units.append({
            "id": unit_id,
            "archetype": unit.archetype,
            "position": [unit.position.x, unit.position.y, unit.position.z],
            "health": unit.health,
            "max_health": unit.max_health,
            "team": unit.owner_team,
            "state": unit.state
        })
    
    return game_state

func _generate_request_id() -> String:
    return "ai_req_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
```

## 🔄 Phase 6: Client Migration (Weeks 11-12)

### 6.1 Client Network Manager Refactoring

**File: `scripts/network/server_network_client.gd`**
```gdscript
class_name ServerNetworkClient
extends Node

# Server connection
var websocket: WebSocketPeer
var server_url: String = "ws://localhost:8080"
var auth_token: String = ""
var player_id: String = ""
var session_id: String = ""

# Connection state
enum ConnectionState {
    DISCONNECTED,
    CONNECTING,
    AUTHENTICATING,
    CONNECTED,
    IN_SESSION
}

var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var last_ping: float = 0.0
var reconnect_attempts: int = 0
var max_reconnect_attempts: int = 5

# Message queuing
var message_queue: Array[Dictionary] = []
var sequence_number: int = 0

# Signals
signal connected_to_server()
signal disconnected_from_server()
signal session_joined(session_id: String)
signal session_left()
signal game_state_received(game_state: Dictionary)
signal ai_command_response(response: Dictionary)

func _ready() -> void:
    # Start connection loop
    var timer = Timer.new()
    timer.wait_time = 0.1  # 10 FPS for network updates
    timer.timeout.connect(_process_network)
    add_child(timer)
    timer.start()

func connect_to_server(url: String = "", token: String = "") -> void:
    if connection_state != ConnectionState.DISCONNECTED:
        Logger.warning("ServerNetworkClient", "Already connected or connecting")
        return
    
    if url != "":
        server_url = url
    if token != "":
        auth_token = token
    
    websocket = WebSocketPeer.new()
    var error = websocket.connect_to_url(server_url)
    
    if error != OK:
        Logger.error("ServerNetworkClient", "Failed to connect to server: " + str(error))
        return
    
    connection_state = ConnectionState.CONNECTING
    Logger.info("ServerNetworkClient", "Connecting to server: " + server_url)

func disconnect_from_server() -> void:
    if connection_state == ConnectionState.DISCONNECTED:
        return
    
    if websocket:
        websocket.close()
        websocket = null
    
    connection_state = ConnectionState.DISCONNECTED
    disconnected_from_server.emit()
    Logger.info("ServerNetworkClient", "Disconnected from server")

func send_message(message: Dictionary) -> void:
    if connection_state != ConnectionState.CONNECTED and connection_state != ConnectionState.IN_SESSION:
        # Queue message for later sending
        message_queue.append(message)
        return
    
    message["sequence_number"] = sequence_number
    message["player_id"] = player_id
    message["timestamp"] = Time.get_ticks_msec()
    
    sequence_number += 1
    
    var json_message = JSON.stringify(message)
    websocket.send_text(json_message)

func join_session(target_session_id: String = "") -> void:
    var message = {
        "type": "join_session",
        "session_id": target_session_id
    }
    send_message(message)

func leave_session() -> void:
    var message = {
        "type": "leave_session",
        "session_id": session_id
    }
    send_message(message)

func send_player_input(input_data: Dictionary) -> void:
    var message = {
        "type": "player_input",
        "session_id": session_id,
        "input_data": input_data
    }
    send_message(message)

func send_ai_command(command: String, selected_units: Array) -> void:
    var message = {
        "type": "ai_command",
        "session_id": session_id,
        "command": command,
        "selected_units": selected_units
    }
    send_message(message)

func _process_network() -> void:
    if not websocket:
        return
    
    websocket.poll()
    
    match websocket.get_ready_state():
        WebSocketPeer.STATE_OPEN:
            if connection_state == ConnectionState.CONNECTING:
                _handle_connection_established()
            
            _process_incoming_messages()
        
        WebSocketPeer.STATE_CLOSED:
            if connection_state != ConnectionState.DISCONNECTED:
                _handle_connection_lost()

func _handle_connection_established() -> void:
    connection_state = ConnectionState.AUTHENTICATING
    Logger.info("ServerNetworkClient", "Connection established, authenticating...")
    
    # Send authentication
    var auth_message = {
        "type": "authenticate",
        "token": auth_token
    }
    websocket.send_text(JSON.stringify(auth_message))

func _process_incoming_messages() -> void:
    while websocket.get_available_packet_count() > 0:
        var packet = websocket.get_packet()
        var message_text = packet.get_string_from_utf8()
        
        var json = JSON.new()
        var parse_result = json.parse(message_text)
        
        if parse_result != OK:
            Logger.error("ServerNetworkClient", "Failed to parse message: " + message_text)
            continue
        
        var message = json.data
        _handle_message(message)

func _handle_message(message: Dictionary) -> void:
    var msg_type = message.get("type", "")
    
    match msg_type:
        "auth_response":
            _handle_auth_response(message)
        "session_joined":
            _handle_session_joined(message)
        "session_left":
            _handle_session_left(message)
        "game_state_update":
            _handle_game_state_update(message)
        "ai_command_response":
            _handle_ai_command_response(message)
        "error":
            _handle_error_message(message)

func _handle_auth_response(message: Dictionary) -> void:
    if message.get("success", false):
        player_id = message.get("player_id", "")
        connection_state = ConnectionState.CONNECTED
        connected_to_server.emit()
        
        # Send queued messages
        _process_message_queue()
        
        Logger.info("ServerNetworkClient", "Authentication successful: " + player_id)
    else:
        Logger.error("ServerNetworkClient", "Authentication failed: " + message.get("error", "Unknown error"))
        disconnect_from_server()

func _handle_session_joined(message: Dictionary) -> void:
    session_id = message.get("session_id", "")
    connection_state = ConnectionState.IN_SESSION
    session_joined.emit(session_id)
    Logger.info("ServerNetworkClient", "Joined session: " + session_id)

func _handle_game_state_update(message: Dictionary) -> void:
    var game_state = message.get("game_state", {})
    game_state_received.emit(game_state)

func _handle_ai_command_response(message: Dictionary) -> void:
    ai_command_response.emit(message)

func _process_message_queue() -> void:
    for message in message_queue:
        send_message(message)
    message_queue.clear()

func _handle_connection_lost() -> void:
    Logger.warning("ServerNetworkClient", "Connection lost, attempting to reconnect...")
    
    connection_state = ConnectionState.DISCONNECTED
    websocket = null
    
    # Attempt reconnection
    if reconnect_attempts < max_reconnect_attempts:
        reconnect_attempts += 1
        await get_tree().create_timer(2.0).timeout
        connect_to_server()
    else:
        Logger.error("ServerNetworkClient", "Max reconnection attempts reached")
        disconnected_from_server.emit()
```

### 6.2 Client Game State Manager

**File: `scripts/client/client_game_state.gd`**
```gdscript
class_name ClientGameState
extends Node

# Client-side game state (prediction and interpolation)
var predicted_units: Dictionary = {}
var authoritative_units: Dictionary = {}
var interpolation_buffer: Array = []
var max_buffer_size: int = 10

# Prediction settings
var prediction_enabled: bool = true
var interpolation_delay: float = 0.1  # 100ms delay for smooth interpolation

# Signals
signal unit_state_updated(unit_id: String, unit_state: Dictionary)
signal game_state_synced()

func _ready() -> void:
    # Connect to server network client
    ServerNetworkClient.game_state_received.connect(_on_game_state_received)
    
    # Start interpolation loop
    var timer = Timer.new()
    timer.wait_time = 1.0 / 60.0  # 60 FPS interpolation
    timer.timeout.connect(_interpolate_units)
    add_child(timer)
    timer.start()

func _on_game_state_received(server_state: Dictionary) -> void:
    # Store authoritative state
    var timestamp = Time.get_ticks_msec()
    var state_snapshot = {
        "timestamp": timestamp,
        "units": server_state.get("units", {}),
        "game_time": server_state.get("game_time", 0.0)
    }
    
    # Add to interpolation buffer
    interpolation_buffer.append(state_snapshot)
    if interpolation_buffer.size() > max_buffer_size:
        interpolation_buffer.pop_front()
    
    # Update authoritative state
    authoritative_units = server_state.get("units", {})
    
    # Reconcile predictions with server state
    _reconcile_predictions(server_state)
    
    game_state_synced.emit()

func predict_unit_movement(unit_id: String, target_position: Vector3) -> void:
    if not prediction_enabled:
        return
    
    if unit_id in predicted_units:
        var predicted_unit = predicted_units[unit_id]
        predicted_unit.target_position = target_position
        predicted_unit.state = "moving"
        predicted_unit.prediction_timestamp = Time.get_ticks_msec()

func _interpolate_units() -> void:
    if interpolation_buffer.size() < 2:
        return
    
    var current_time = Time.get_ticks_msec()
    var target_time = current_time - (interpolation_delay * 1000)
    
    # Find interpolation frames
    var from_frame = null
    var to_frame = null
    
    for i in range(interpolation_buffer.size() - 1):
        if interpolation_buffer[i].timestamp <= target_time and interpolation_buffer[i + 1].timestamp > target_time:
            from_frame = interpolation_buffer[i]
            to_frame = interpolation_buffer[i + 1]
            break
    
    if not from_frame or not to_frame:
        return
    
    # Interpolate between frames
    var lerp_factor = (target_time - from_frame.timestamp) / (to_frame.timestamp - from_frame.timestamp)
    lerp_factor = clamp(lerp_factor, 0.0, 1.0)
    
    # Update interpolated positions
    for unit_id in from_frame.units:
        if unit_id in to_frame.units:
            var from_unit = from_frame.units[unit_id]
            var to_unit = to_frame.units[unit_id]
            
            var interpolated_position = Vector3(
                from_unit.position[0],
                from_unit.position[1],
                from_unit.position[2]
            ).lerp(Vector3(
                to_unit.position[0],
                to_unit.position[1],
                to_unit.position[2]
            ), lerp_factor)
            
            # Update visual representation
            var interpolated_state = {
                "position": [interpolated_position.x, interpolated_position.y, interpolated_position.z],
                "health": to_unit.health,
                "state": to_unit.state
            }
            
            unit_state_updated.emit(unit_id, interpolated_state)

func _reconcile_predictions(server_state: Dictionary) -> void:
    # Check if predictions were correct
    var server_units = server_state.get("units", {})
    
    for unit_id in predicted_units:
        if unit_id in server_units:
            var predicted = predicted_units[unit_id]
            var authoritative = server_units[unit_id]
            
            # Check position difference
            var predicted_pos = Vector3(predicted.position[0], predicted.position[1], predicted.position[2])
            var auth_pos = Vector3(authoritative.position[0], authoritative.position[1], authoritative.position[2])
            var distance = predicted_pos.distance_to(auth_pos)
            
            # If prediction was significantly wrong, snap to server position
            if distance > 2.0:  # 2 meter tolerance
                Logger.warning("ClientGameState", "Prediction correction for unit: " + unit_id)
                predicted_units[unit_id].position = authoritative.position
                predicted_units[unit_id].correction_applied = true

func get_unit_state(unit_id: String) -> Dictionary:
    # Return predicted state if available, otherwise authoritative
    if unit_id in predicted_units:
        return predicted_units[unit_id]
    elif unit_id in authoritative_units:
        return authoritative_units[unit_id]
    else:
        return {}

func get_all_units() -> Dictionary:
    # Merge predicted and authoritative states
    var merged_units = {}
    
    # Start with authoritative
    for unit_id in authoritative_units:
        merged_units[unit_id] = authoritative_units[unit_id]
    
    # Overlay predictions
    for unit_id in predicted_units:
        if unit_id in merged_units:
            # Use predicted position if more recent
            var predicted = predicted_units[unit_id]
            var auth = merged_units[unit_id]
            
            if predicted.get("prediction_timestamp", 0) > auth.get("timestamp", 0):
                merged_units[unit_id] = predicted
    
    return merged_units
```

## 🚀 Phase 7: Deployment & Testing (Weeks 13-14)

### 7.1 Docker Containerization

**File: `game-server/Dockerfile`**
```dockerfile
FROM godotengine/godot:4.4-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    redis-tools \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy game server
COPY . /app
WORKDIR /app

# Export headless server
RUN godot --headless --export-release "Linux/X11" server.x86_64

# Run server
CMD ["./server.x86_64"]
```

**File: `docker-compose.yml`**
```yaml
version: '3.8'

services:
  game-server:
    build: ./game-server
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgresql://user:password@db:5432/gamedb
      - REDIS_URL=redis://redis:6379
      - AI_SERVICE_URL=http://ai-service:8000
    depends_on:
      - db
      - redis
      - ai-service

  ai-service:
    build: ./ai-service
    ports:
      - "8000:8000"
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis

  db:
    image: postgres:15
    environment:
      - POSTGRES_DB=gamedb
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - game-server

volumes:
  postgres_data:
  redis_data:
```

### 7.2 Performance Monitoring

**File: `game-server/monitoring/performance_monitor.gd`**
```gdscript
class_name PerformanceMonitor
extends Node

# Performance metrics
var metrics: Dictionary = {
    "active_sessions": 0,
    "connected_players": 0,
    "messages_per_second": 0,
    "average_latency": 0.0,
    "memory_usage": 0.0,
    "cpu_usage": 0.0,
    "ai_requests_per_minute": 0
}

# Performance tracking
var message_count: int = 0
var last_message_reset: float = 0.0
var latency_samples: Array[float] = []
var max_latency_samples: int = 100

func _ready() -> void:
    # Start metrics collection
    var timer = Timer.new()
    timer.wait_time = 1.0  # Update every second
    timer.timeout.connect(_collect_metrics)
    add_child(timer)
    timer.start()

func _collect_metrics() -> void:
    # Update active sessions
    metrics.active_sessions = SessionManager.active_sessions.size()
    
    # Update connected players
    metrics.connected_players = PlayerManager.connected_players.size()
    
    # Update messages per second
    var current_time = Time.get_ticks_msec()
    if current_time - last_message_reset >= 1000:
        metrics.messages_per_second = message_count
        message_count = 0
        last_message_reset = current_time
    
    # Update average latency
    if latency_samples.size() > 0:
        var total_latency = 0.0
        for latency in latency_samples:
            total_latency += latency
        metrics.average_latency = total_latency / latency_samples.size()
    
    # Update memory usage
    metrics.memory_usage = Performance.get_monitor(Performance.MEMORY_DYNAMIC) / 1024.0 / 1024.0  # MB
    
    # Log metrics
    Logger.info("PerformanceMonitor", "Metrics: %s" % str(metrics))

func record_message() -> void:
    message_count += 1

func record_latency(latency: float) -> void:
    latency_samples.append(latency)
    if latency_samples.size() > max_latency_samples:
        latency_samples.pop_front()

func get_metrics() -> Dictionary:
    return metrics.duplicate()
```

## 📊 Migration Benefits

### **Scalability Benefits:**
- ✅ **Multiple Concurrent Sessions**: Support 100+ simultaneous matches
- ✅ **Horizontal Scaling**: Add more server instances as needed
- ✅ **Load Distribution**: Distribute players across multiple servers
- ✅ **Resource Optimization**: Dedicated resources for game logic

### **Reliability Benefits:**
- ✅ **No Single Point of Failure**: Dedicated server eliminates host dependency
- ✅ **Reconnection Support**: Players can reconnect to ongoing matches
- ✅ **State Persistence**: Game state survives client disconnections
- ✅ **Crash Recovery**: Server can recover from individual client issues

### **Performance Benefits:**
- ✅ **Server Authority**: Eliminates cheating and synchronization issues
- ✅ **Optimized Networking**: Dedicated bandwidth for game traffic
- ✅ **Predictive Client**: Smooth gameplay with client-side prediction
- ✅ **Efficient Updates**: Delta compression and targeted updates

### **Security Benefits:**
- ✅ **Centralized Validation**: All game actions validated on server
- ✅ **Anti-Cheat**: Server-side validation prevents manipulation
- ✅ **Secure Communication**: Encrypted WebSocket connections
- ✅ **Authentication**: Centralized player authentication

## 🔄 Migration Timeline

**Total Duration:** 12 weeks (reduced with Godot API)
**Team Size:** 2-3 developers
**Estimated Effort:** 240-360 developer hours

### **Phase Timeline:**
1. **Weeks 1-2**: Godot Dedicated Server Setup
2. **Weeks 3-4**: Multiplayer Communication with ENet
3. **Weeks 5-6**: Server-Authoritative Game State
4. **Weeks 7-8**: Session Management with MultiplayerSpawner
5. **Weeks 9-10**: AI Service Integration
6. **Weeks 11-12**: Client Migration and Deployment

### **Risk Mitigation:**
- **Parallel Development**: AI service and game server can be developed simultaneously
- **Incremental Testing**: Test each phase before moving to next
- **Rollback Plan**: Keep P2P system until dedicated server is fully tested
- **Performance Testing**: Load test server before production deployment

This plan provides a complete migration path from P2P to Godot-based dedicated server architecture while maintaining the innovative cooperative gameplay mechanics and leveraging Godot's native multiplayer capabilities for reduced complexity and better performance. 