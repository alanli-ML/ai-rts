extends Node

var sessions: Dictionary = {}
var waiting_players: Array = []

class GameSession:
    var session_id: String
    var players: Array = []
    var max_players: int = 4
    var state: String = "waiting"
    var created_at: float
    var game_scene: Node
    var multiplayer_spawner: MultiplayerSpawner
    
    func _init(id: String):
        session_id = id
        created_at = Time.get_ticks_msec()
        
        # Create dedicated game scene
        game_scene = Node.new()
        game_scene.name = "Session_" + session_id
        
        # Setup multiplayer spawner
        multiplayer_spawner = MultiplayerSpawner.new()
        multiplayer_spawner.name = "MultiplayerSpawner"
        multiplayer_spawner.spawn_path = game_scene.get_path()
        multiplayer_spawner.auto_spawn = false
        game_scene.add_child(multiplayer_spawner)
        
        # Add to server scene tree
        DedicatedServer.add_child(game_scene)
        
        print("Created session: %s" % session_id)
    
    func add_player(player_id: String) -> bool:
        if players.size() >= max_players:
            return false
        
        if player_id not in players:
            players.append(player_id)
            print("Player %s joined session %s (%d/%d)" % [player_id, session_id, players.size(), max_players])
            
            # Check if session can start
            if players.size() >= 2 and state == "waiting":
                _start_session()
        
        return true
    
    func remove_player(player_id: String) -> void:
        if player_id in players:
            players.erase(player_id)
            print("Player %s left session %s (%d/%d)" % [player_id, session_id, players.size(), max_players])
            
            # Handle session state
            if state == "active" and players.size() < 2:
                _end_session("insufficient_players")
            elif players.size() == 0:
                _cleanup_session()
    
    func _start_session() -> void:
        state = "active"
        print("Starting session %s with %d players" % [session_id, players.size()])
        
        # Create basic test units for now
        _spawn_test_units()
        
        # Notify all players
        var session_data = {
            "session_id": session_id,
            "players": players.duplicate(),
            "state": state,
            "started_at": Time.get_ticks_msec()
        }
        
        _broadcast_to_session("_on_session_started", session_data)
    
    func _spawn_test_units() -> void:
        print("Spawning units for session %s" % session_id)
        
        # Create unit spawner
        var unit_spawner = UnitSpawner.new()
        unit_spawner.name = "UnitSpawner"
        game_scene.add_child(unit_spawner)
        
        # Spawn units for each team
        var team_units = {}
        for i in range(min(2, players.size())):  # Up to 2 teams
            var team_id = i
            var player_id = players[i] if i < players.size() else "ai_player_%d" % i
            
            var spawned_units = unit_spawner.spawn_units_for_team(team_id, player_id)
            team_units[team_id] = spawned_units
            
            print("Spawned %d units for team %d (player: %s)" % [spawned_units.size(), team_id, player_id])
        
        # Store reference for command execution
        multiplayer_spawner.add_spawnable_scene("res://scenes/ServerUnit.tscn")
        
        # Broadcast unit spawn info to clients
        var spawn_data = {
            "session_id": session_id,
            "team_units": team_units,
            "spawn_positions": {
                0: Vector3(-20, 0, 0),
                1: Vector3(20, 0, 0)
            }
        }
        
        _broadcast_to_session("_on_units_spawned", spawn_data)
    
    func _broadcast_to_session(method: String, data: Dictionary) -> void:
        for player_id in players:
            var peer_id = _get_peer_id_for_player(player_id)
            if peer_id > 0:
                DedicatedServer.rpc_id(peer_id, method, data)
    
    func _get_peer_id_for_player(player_id: String) -> int:
        for peer_id in DedicatedServer.connected_clients:
            var client_data = DedicatedServer.connected_clients[peer_id]
            if client_data.player_id == player_id:
                return peer_id
        return -1
    
    func _end_session(reason: String) -> void:
        state = "ended"
        print("Session %s ended: %s" % [session_id, reason])
        
        _broadcast_to_session("_on_session_ended", {
            "session_id": session_id,
            "reason": reason
        })
        
        _cleanup_session()
    
    func _cleanup_session() -> void:
        # Remove from scene tree
        if game_scene:
            game_scene.queue_free()
        
        # Clean up data
        players.clear()

class PlayerData:
    var player_id: String
    var session_id: String
    var team_id: int
    var joined_at: float
    var status: String = "active"

func _ready() -> void:
    print("SessionManager initialized")

func join_session(player_id: String, preferred_session_id: String = "") -> String:
    var session: GameSession
    
    if preferred_session_id != "" and preferred_session_id in sessions:
        session = sessions[preferred_session_id]
        if session.state != "waiting" or session.players.size() >= session.max_players:
            session = null  # Can't join this session
    
    if not session:
        # Find available session
        session = _find_available_session()
        if not session:
            # Create new session
            var new_session_id = _create_session()
            session = sessions[new_session_id]
    
    if session.add_player(player_id):
        return session.session_id
    else:
        return ""

func remove_player_from_session(player_id: String, session_id: String) -> void:
    if session_id in sessions:
        var session = sessions[session_id]
        session.remove_player(player_id)
        
        # Clean up empty session
        if session.players.size() == 0:
            sessions.erase(session_id)
            print("Cleaned up empty session: %s" % session_id)

func _create_session() -> String:
    var session_id = "session_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000)
    var session = GameSession.new(session_id)
    sessions[session_id] = session
    
    print("Created new session: %s" % session_id)
    return session_id

func _find_available_session() -> GameSession:
    for session in sessions.values():
        if session.state == "waiting" and session.players.size() < session.max_players:
            return session
    return null

func get_session_count() -> int:
    return sessions.size()

func get_session_stats() -> Dictionary:
    var stats = {
        "total_sessions": sessions.size(),
        "active_sessions": 0,
        "waiting_sessions": 0,
        "total_players": 0
    }
    
    for session in sessions.values():
        stats.total_players += session.players.size()
        
        if session.state == "active":
            stats.active_sessions += 1
        elif session.state == "waiting":
            stats.waiting_sessions += 1
    
    return stats

# RPC methods for session management
@rpc("any_peer", "call_local", "reliable")
func request_session_list() -> void:
    var peer_id = multiplayer.get_remote_sender_id()
    
    var session_list = []
    for session_id in sessions:
        var session = sessions[session_id]
        session_list.append({
            "session_id": session_id,
            "player_count": session.players.size(),
            "max_players": session.max_players,
            "state": session.state
        })
    
    DedicatedServer.rpc_id(peer_id, "_on_session_list_response", session_list) 