# Godot Dedicated Server Quick Start Guide

## 🚀 Phase 1: Godot Multiplayer API Server Setup (Start Here)

### Prerequisites
- Godot 4.4+ installed
- Basic understanding of Godot multiplayer API
- AI service from previous implementation

### Step 1: Create Dedicated Server Project

```bash
# Create dedicated server directory
mkdir game-server
cd game-server

# Initialize Godot project
touch project.godot

# Create basic structure
mkdir -p server multiplayer game_logic shared scenes
```

### Step 2: Configure Server Project

**File: `game-server/project.godot`**
```ini
[application]
config/name="AI-RTS Dedicated Server"
run/main_scene="res://scenes/Main.tscn"
config/features=PackedStringArray("4.4")

[autoload]
DedicatedServer="*res://server/dedicated_server.gd"
SessionManager="*res://server/session_manager.gd"
AIIntegration="*res://game_logic/ai_integration.gd"

[rendering]
renderer/rendering_method="gl_compatibility"
driver/threads/thread_model=2

[debug]
settings/stdout/print_fps=true
settings/stdout/verbose_stdout=true
```

### Step 3: Basic Dedicated Server

**File: `game-server/server/dedicated_server.gd`**
```gdscript
extends Node

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 100

var multiplayer_peer: ENetMultiplayerPeer
var connected_clients: Dictionary = {}

func _ready() -> void:
    print("Starting Godot Dedicated Server...")
    
    # Connect multiplayer signals
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    
    # Start server
    start_server()

func start_server(port: int = DEFAULT_PORT) -> bool:
    multiplayer_peer = ENetMultiplayerPeer.new()
    var error = multiplayer_peer.create_server(port, MAX_CLIENTS)
    
    if error != OK:
        print("Failed to start server: %s" % error)
        return false
    
    multiplayer.multiplayer_peer = multiplayer_peer
    print("Server started on port %d (Server ID: %d)" % [port, multiplayer.get_unique_id()])
    
    return true

func _on_peer_connected(id: int) -> void:
    print("Client connected: %d" % id)
    connected_clients[id] = {
        "peer_id": id,
        "authenticated": false,
        "player_id": "",
        "connected_at": Time.get_ticks_msec()
    }
    
    # Send welcome message
    rpc_id(id, "_on_server_welcome", {"server_version": "1.0.0"})

func _on_peer_disconnected(id: int) -> void:
    print("Client disconnected: %d" % id)
    connected_clients.erase(id)

# Client authentication
@rpc("any_peer", "call_local", "reliable")
func authenticate_client(player_name: String) -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    var player_id = "player_%d_%s" % [peer_id, player_name]
    
    if peer_id in connected_clients:
        connected_clients[peer_id]["authenticated"] = true
        connected_clients[peer_id]["player_id"] = player_id
        
        print("Player authenticated: %s" % player_id)
        rpc_id(peer_id, "_on_auth_success", player_id)
    else:
        rpc_id(peer_id, "_on_auth_failed", "Invalid peer")

@rpc("any_peer", "call_local", "reliable")
func client_ping() -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    rpc_id(peer_id, "_on_server_pong", Time.get_ticks_msec())

# Status endpoint
func get_server_status() -> Dictionary:
    return {
        "running": multiplayer_peer != null,
        "clients": connected_clients.size(),
        "uptime": Time.get_ticks_msec()
    }
```

### Step 4: Basic Session Manager

**File: `game-server/server/session_manager.gd`**
```gdscript
extends Node

var sessions: Dictionary = {}

class GameSession:
    var session_id: String
    var players: Array = []
    var max_players: int = 4
    var state: String = "waiting"
    var game_scene: Node
    var multiplayer_spawner: MultiplayerSpawner
    
    func _init(id: String):
        session_id = id
        
        # Create dedicated game scene
        game_scene = Node.new()
        game_scene.name = "Session_" + session_id
        
        # Setup multiplayer spawner
        multiplayer_spawner = MultiplayerSpawner.new()
        multiplayer_spawner.name = "MultiplayerSpawner"
        multiplayer_spawner.spawn_path = game_scene.get_path()
        game_scene.add_child(multiplayer_spawner)
        
        # Add to server
        DedicatedServer.add_child(game_scene)
        
        print("Created session: %s" % session_id)

@rpc("any_peer", "call_local", "reliable")
func join_session(preferred_session_id: String = "") -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    
    # Find or create session
    var session = _find_available_session()
    if not session:
        var new_session_id = "session_%d" % Time.get_ticks_msec()
        session = GameSession.new(new_session_id)
        sessions[new_session_id] = session
    
    # Add player to session
    session.players.append(peer_id)
    
    print("Player %d joined session %s" % [peer_id, session.session_id])
    rpc_id(peer_id, "_on_session_joined", session.session_id)

func _find_available_session() -> GameSession:
    for session in sessions.values():
        if session.state == "waiting" and session.players.size() < session.max_players:
            return session
    return null
```

### Step 5: Basic Unit with MultiplayerSynchronizer

**File: `game-server/game_logic/server_unit.gd`**
```gdscript
extends CharacterBody3D
class_name ServerUnit

@export var unit_id: String
@export var team_id: int
@export var max_health: float = 100.0
@export var move_speed: float = 5.0

var current_health: float
var target_position: Vector3
var current_state: String = "idle"

# Multiplayer synchronizer
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready() -> void:
    current_health = max_health
    target_position = global_position
    
    # Configure synchronizer (server authority)
    sync.set_multiplayer_authority(1)
    
    # Add synchronized properties
    sync.add_property("global_position")
    sync.add_property("current_health")
    sync.add_property("current_state")
    sync.add_property("team_id")
    
    print("Server unit ready: %s" % unit_id)

func _physics_process(delta: float) -> void:
    if not multiplayer.is_server():
        return
    
    # Update movement
    if current_state == "moving":
        var direction = (target_position - global_position).normalized()
        var distance = global_position.distance_to(target_position)
        
        if distance > 0.5:
            velocity = direction * move_speed
            move_and_slide()
        else:
            global_position = target_position
            current_state = "idle"
            velocity = Vector3.ZERO

# Unit commands
@rpc("any_peer", "call_local", "reliable")
func move_to(new_target: Vector3) -> void:
    if not multiplayer.is_server():
        return
    
    target_position = new_target
    current_state = "moving"
    
    print("Unit %s moving to %s" % [unit_id, new_target])
    rpc("_on_unit_moved", unit_id, new_target)

@rpc("any_peer", "call_local", "reliable")
func stop_unit() -> void:
    if not multiplayer.is_server():
        return
    
    current_state = "idle"
    target_position = global_position
    
    print("Unit %s stopped" % unit_id)
    rpc("_on_unit_stopped", unit_id)

# Client notifications
@rpc("authority", "call_local", "reliable")
func _on_unit_moved(moved_unit_id: String, new_target: Vector3) -> void:
    # Client-side movement feedback
    pass

@rpc("authority", "call_local", "reliable")
func _on_unit_stopped(stopped_unit_id: String) -> void:
    # Client-side stop feedback
    pass

func get_unit_data() -> Dictionary:
    return {
        "unit_id": unit_id,
        "team_id": team_id,
        "position": [global_position.x, global_position.y, global_position.z],
        "health": current_health,
        "state": current_state
    }
```

### Step 6: Client Connection

**File: `scripts/network/godot_server_client.gd`**
```gdscript
extends Node
class_name GodotServerClient

@export var server_address: String = "127.0.0.1"
@export var server_port: int = 7777
@export var player_name: String = "TestPlayer"

var multiplayer_peer: ENetMultiplayerPeer
var connected: bool = false
var authenticated: bool = false
var player_id: String = ""

# Signals
signal connected_to_server()
signal authentication_result(success: bool, player_id: String)
signal session_joined(session_id: String)

func _ready() -> void:
    # Connect multiplayer signals
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

func connect_to_server() -> bool:
    multiplayer_peer = ENetMultiplayerPeer.new()
    var error = multiplayer_peer.create_client(server_address, server_port)
    
    if error != OK:
        print("Failed to create client: %s" % error)
        return false
    
    multiplayer.multiplayer_peer = multiplayer_peer
    print("Connecting to server...")
    return true

func _on_connected_to_server() -> void:
    print("Connected to server")
    connected = true
    connected_to_server.emit()
    
    # Auto-authenticate
    authenticate()

func _on_connection_failed() -> void:
    print("Connection failed")
    connected = false

func _on_server_disconnected() -> void:
    print("Server disconnected")
    connected = false
    authenticated = false

func authenticate() -> void:
    if not connected:
        return
    
    rpc_id(1, "authenticate_client", player_name)
    print("Authenticating as %s..." % player_name)

func join_session() -> void:
    if not authenticated:
        return
    
    rpc_id(1, "join_session", "")
    print("Joining session...")

func move_unit(unit_id: String, target_position: Vector3) -> void:
    if not authenticated:
        return
    
    # Find unit and send move command
    var unit = _find_unit(unit_id)
    if unit:
        unit.rpc_id(1, "move_to", target_position)

func _find_unit(unit_id: String) -> ServerUnit:
    var units = get_tree().get_nodes_in_group("units")
    for unit in units:
        if unit.unit_id == unit_id:
            return unit
    return null

# Server RPC receivers
@rpc("authority", "call_local", "reliable")
func _on_server_welcome(data: Dictionary) -> void:
    print("Server welcome: %s" % data)

@rpc("authority", "call_local", "reliable")
func _on_auth_success(received_player_id: String) -> void:
    print("Authentication successful: %s" % received_player_id)
    authenticated = true
    player_id = received_player_id
    authentication_result.emit(true, player_id)
    
    # Auto-join session
    join_session()

@rpc("authority", "call_local", "reliable")
func _on_auth_failed(reason: String) -> void:
    print("Authentication failed: %s" % reason)
    authentication_result.emit(false, "")

@rpc("authority", "call_local", "reliable")
func _on_session_joined(session_id: String) -> void:
    print("Joined session: %s" % session_id)
    session_joined.emit(session_id)

@rpc("authority", "call_local", "reliable")
func _on_server_pong(server_time: int) -> void:
    var ping = Time.get_ticks_msec() - server_time
    print("Ping: %d ms" % ping)
```

### Step 7: Create Test Scene

**File: `game-server/scenes/Main.tscn`**
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://server/dedicated_server.gd" id="1"]

[node name="Main" type="Node"]
script = ExtResource("1")

[node name="Timer" type="Timer" parent="."]
wait_time = 1.0
autostart = true

[connection signal="timeout" from="Timer" to="." method="_on_timer_timeout"]
```

### Step 8: Run Server and Test

**Terminal 1 - Start Server:**
```bash
cd game-server
godot --headless --main-pack . --server
```

**Terminal 2 - Test Client:**
```bash
cd your-main-project
# Add GodotServerClient to a test scene
# Connect to server and test basic functionality
```

### Step 9: Expected Output

**Server Output:**
```
Starting Godot Dedicated Server...
Server started on port 7777 (Server ID: 1)
Client connected: 1001
Player authenticated: player_1001_TestPlayer
Player 1001 joined session session_1234567890
```

**Client Output:**
```
Connecting to server...
Connected to server
Server welcome: {"server_version":"1.0.0"}
Authenticating as TestPlayer...
Authentication successful: player_1001_TestPlayer
Joining session...
Joined session: session_1234567890
```

### Step 10: Add AI Integration

**File: `game-server/game_logic/ai_integration.gd`**
```gdscript
extends Node

var ai_service_url: String = "http://localhost:8000"
var http_request: HTTPRequest

func _ready() -> void:
    http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.request_completed.connect(_on_ai_response)

@rpc("any_peer", "call_local", "reliable")
func process_ai_command(command: String, selected_unit_ids: Array) -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    
    # Build AI request
    var request_data = {
        "command": command,
        "selected_units": selected_unit_ids,
        "player_id": "player_%d" % peer_id,
        "timestamp": Time.get_ticks_msec()
    }
    
    # Send to AI service
    var headers = ["Content-Type: application/json"]
    var json_data = JSON.stringify(request_data)
    
    http_request.request(ai_service_url + "/ai/process-command", headers, HTTPClient.METHOD_POST, json_data)
    
    print("AI command from %d: %s" % [peer_id, command])

func _on_ai_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if response_code != 200:
        print("AI service error: %d" % response_code)
        return
    
    var json = JSON.new()
    var parse_result = json.parse(body.get_string_from_utf8())
    
    if parse_result == OK:
        var response = json.data
        var commands = response.get("commands", [])
        
        print("Executing %d AI commands" % commands.size())
        
        # Execute commands on server
        for command in commands:
            _execute_ai_command(command)

func _execute_ai_command(command: Dictionary) -> void:
    var command_type = command.get("type", "")
    var unit_ids = command.get("unit_ids", [])
    
    match command_type:
        "MOVE":
            var target_pos = command.get("target_position", [0, 0, 0])
            var target_vector = Vector3(target_pos[0], target_pos[1], target_pos[2])
            
            for unit_id in unit_ids:
                var unit = _find_unit(unit_id)
                if unit:
                    unit.move_to(target_vector)
        
        "STOP":
            for unit_id in unit_ids:
                var unit = _find_unit(unit_id)
                if unit:
                    unit.stop_unit()

func _find_unit(unit_id: String) -> ServerUnit:
    var units = get_tree().get_nodes_in_group("units")
    for unit in units:
        if unit.unit_id == unit_id:
            return unit
    return null
```

### Step 11: Test AI Commands

**Client Test:**
```gdscript
# In your client test scene
func test_ai_command():
    var client = get_node("GodotServerClient")
    client.rpc_id(1, "process_ai_command", "move all units forward", ["unit_1", "unit_2"])
```

### Next Steps

1. **Add Unit Spawning**: Create MultiplayerSpawner for automatic unit creation
2. **Implement Combat**: Add server-authoritative combat system
3. **Enhanced AI**: Full AI service integration with game state
4. **Client Prediction**: Add smooth client-side prediction
5. **Production Deploy**: Docker containers and scaling

### Troubleshooting

**Common Issues:**
- **Connection refused**: Check server is running on correct port
- **Authentication failed**: Verify client sends correct player name
- **Units not moving**: Ensure MultiplayerSynchronizer is configured
- **AI not working**: Check AI service is running on port 8000

**Debug Commands:**
```bash
# Check server is listening
netstat -an | grep 7777

# Test AI service
curl -X POST http://localhost:8000/ai/process-command -H "Content-Type: application/json" -d '{"command":"test"}'
```

This quick start provides a solid foundation using Godot's multiplayer API for dedicated server architecture with AI integration. The approach is more maintainable and leverages Godot's optimized networking systems. 