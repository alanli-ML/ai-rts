# SessionManager.gd - Session manager with dependency injection
extends Node

# Injected dependencies
var logger
var game_state: Node

# Session management
var sessions: Dictionary = {}  # session_id -> Session
var client_sessions: Dictionary = {}  # peer_id -> session_id
var session_counter: int = 0

# Session configuration
const MAX_PLAYERS_PER_SESSION: int = 4
const SESSION_TIMEOUT: int = 3600  # 1 hour

# Signals
signal session_created(session_id: String)
signal session_destroyed(session_id: String)
signal match_started(session_id: String)
signal player_joined_session(session_id: String, player_id: String)
signal player_left_session(session_id: String, player_id: String)

func setup(logger_ref, game_state_ref):
    """Setup dependencies - called by DependencyContainer"""
    logger = logger_ref
    game_state = game_state_ref
    
    logger.info("SessionManager", "Setting up session manager")
    
    # Initialize session management
    _initialize_session_manager()

func _initialize_session_manager():
    """Initialize session management"""
    # Setup session cleanup timer
    var cleanup_timer = Timer.new()
    cleanup_timer.wait_time = 60.0  # Check every minute
    cleanup_timer.timeout.connect(_cleanup_sessions)
    add_child(cleanup_timer)
    cleanup_timer.start()
    
    logger.info("SessionManager", "Session manager initialized")

# Session management
func create_session(host_player_id: String = "") -> String:
    """Create a new session"""
    session_counter += 1
    var session_id = "session_%d" % session_counter
    
    var session = {
        "id": session_id,
        "host_player_id": host_player_id,
        "players": {},
        "created_at": Time.get_ticks_msec(),
        "last_activity": Time.get_ticks_msec(),
        "state": "waiting",
        "max_players": MAX_PLAYERS_PER_SESSION,
        "map": "default",
        "game_mode": "standard"
    }
    
    sessions[session_id] = session
    session_created.emit(session_id)
    
    logger.info("SessionManager", "Created session %s" % session_id)
    return session_id

func destroy_session(session_id: String) -> void:
    """Destroy a session"""
    if session_id in sessions:
        var session = sessions[session_id]
        
        # Remove all players from session
        for player_id in session.players.keys():
            _remove_player_from_session_internal(player_id, session_id)
        
        # Remove session
        sessions.erase(session_id)
        session_destroyed.emit(session_id)
        
        logger.info("SessionManager", "Destroyed session %s" % session_id)

func join_session(peer_id: int, player_id: String, preferred_session_id: String = "") -> String:
    """Join a player to a session"""
    var session_id = ""
    
    # If preferred session specified, try to join it
    if preferred_session_id != "" and preferred_session_id in sessions:
        var session = sessions[preferred_session_id]
        
        if session.players.size() < session.max_players:
            session_id = preferred_session_id
    
    # Otherwise, find or create a session
    if session_id == "":
        session_id = _find_available_session()
        
        if session_id == "":
            session_id = create_session(player_id)
    
    # Add player to session
    if session_id != "":
        _add_player_to_session(peer_id, player_id, session_id)
    
    return session_id

func leave_session(peer_id: int) -> void:
    """Remove a player from their session"""
    if peer_id in client_sessions:
        var session_id = client_sessions[peer_id]
        var session = sessions.get(session_id)
        
        if session:
            # Find player ID by peer ID
            var player_id = ""
            for pid in session.players.keys():
                if session.players[pid]["peer_id"] == peer_id:
                    player_id = pid
                    break
            
            if player_id != "":
                _remove_player_from_session_internal(player_id, session_id)

func get_session(session_id: String) -> Dictionary:
    """Get session data"""
    return sessions.get(session_id, {})

func get_session_count() -> int:
    """Get the number of active sessions"""
    return sessions.size()

func get_player_session(peer_id: int) -> String:
    """Get the session ID for a player"""
    return client_sessions.get(peer_id, "")

func get_all_peer_ids_in_session(session_id: String) -> Array[int]:
    """Get all peer IDs for players in a specific session."""
    var peer_ids: Array[int] = []
    var session = get_session(session_id)
    if not session.is_empty():
        for player_data in session.players.values():
            peer_ids.append(player_data.peer_id)
    return peer_ids

# Client event handlers
func on_client_connected(peer_id: int) -> void:
    """Handle client connection"""
    logger.info("SessionManager", "Client connected: %d" % peer_id)

func on_client_disconnected(peer_id: int, _client_data: Dictionary) -> void:
    """Handle client disconnection"""
    logger.info("SessionManager", "Client disconnected: %d" % peer_id)
    
    # Remove from session if in one
    if peer_id in client_sessions:
        leave_session(peer_id)

func handle_join_session(peer_id: int, preferred_session_id: String) -> void:
    """Handle session join request"""
    var player_id = "player_%d" % peer_id  # Simplified for now
    var session_id = join_session(peer_id, player_id, preferred_session_id)
    
    # Send response through root multiplayer node
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if root_node:
        if session_id != "":
            var session_data = get_session(session_id)
            var can_start = _can_start_game(session_id)
            session_data["can_start_game"] = can_start
            
            root_node.rpc_id(peer_id, "_on_session_join_response", {
                "success": true,
                "session_id": session_id,
                "session_data": session_data
            })
            
            # Broadcast lobby update to all players in session
            _broadcast_lobby_update(session_id)
        else:
            root_node.rpc_id(peer_id, "_on_session_join_response", {
                "success": false,
                "message": "Failed to join session"
            })

func handle_player_ready(peer_id: int, ready_state: bool) -> void:
    """Handle player ready state changes"""
    var session_id = get_player_session(peer_id)
    
    if session_id == "":
        logger.warning("SessionManager", "Player %d not in any session" % peer_id)
        return
    
    var session = sessions.get(session_id)
    if not session:
        return
    
    # Find and update player ready state
    var player_id_to_update = ""
    for pid in session.players:
        if session.players[pid].peer_id == peer_id:
            player_id_to_update = pid
            break
            
    if not player_id_to_update.is_empty():
        session.players[player_id_to_update]["ready"] = ready_state
        logger.info("SessionManager", "Player %s (Peer %d) ready state: %s" % [player_id_to_update, peer_id, ready_state])
        
        # Broadcast lobby update
        _broadcast_lobby_update(session_id)
        
        # Check if game can start automatically (e.g. if all players are ready)
        call_deferred("_check_start_game", session_id)
    else:
        logger.warning("SessionManager", "Could not find player for peer_id %d in session %s" % [peer_id, session_id])

func handle_force_start_game(peer_id: int) -> void:
    """Handle force start game request from a client (host)."""
    var session_id = get_player_session(peer_id)
    
    logger.info("SessionManager", "Start game request from peer %d" % peer_id)
    
    if session_id == "":
        logger.warning("SessionManager", "Player %d not in any session" % peer_id)
        return
    
    var session = sessions.get(session_id)
    if not session:
        logger.warning("SessionManager", "Session %s not found" % session_id)
        return
    
    # TODO: Check if peer_id is the host
    
    if session.state != "waiting":
        logger.warning("SessionManager", "Session %s is not in waiting state (current: %s)" % [session_id, session.state])
        return

    if _can_start_game(session_id):
        logger.info("SessionManager", "Starting game for session %s with %d players" % [session_id, session.players.size()])
        await _start_game(session_id)
    else:
        logger.warning("SessionManager", "Start game request denied. Not all players are ready.")
        # Optionally, send a message back to the host.

func handle_leave_session(peer_id: int) -> void:
    """Handle leave session request"""
    leave_session(peer_id)
    
    # Send response through root multiplayer node
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if root_node:
        root_node.rpc_id(peer_id, "_on_session_leave_response", {
            "success": true,
            "message": "Left session successfully"
        })

func handle_ai_command(peer_id: int, command: String, selected_units: Array) -> void:
    """Handle AI command from client"""
    var session_id = get_player_session(peer_id)
    
    if session_id != "":
        var session = sessions[session_id]
        
        # Forward to game state if session is active
        if session.state == "active" and game_state:
            var player_id = "player_%d" % peer_id
            game_state.process_ai_command(command, selected_units, player_id)

# Internal methods
func _find_available_session() -> String:
    """Find an available session to join"""
    for session_id in sessions.keys():
        var session = sessions[session_id]
        
        if session.state == "waiting" and session.players.size() < session.max_players:
            return session_id
    
    return ""

func _add_player_to_session(peer_id: int, player_id: String, session_id: String) -> void:
    """Add a player to a session"""
    if session_id in sessions:
        var session = sessions[session_id]
        
        # Add player to session
        session.players[player_id] = {
            "peer_id": peer_id,
            "player_id": player_id,
            "team_id": _assign_team(session),
            "ready": false,
            "joined_at": Time.get_ticks_msec()
        }
        
        session.last_activity = Time.get_ticks_msec()
        
        # Track client session
        client_sessions[peer_id] = session_id
        
        # Notify observers
        player_joined_session.emit(session_id, player_id)
        
        logger.info("SessionManager", "Player %s joined session %s" % [player_id, session_id])
        
        # Broadcast lobby update to all players in session
        _broadcast_lobby_update(session_id)
        
        # Check if game can start
        call_deferred("_check_start_game", session_id)

func _remove_player_from_session_internal(player_id: String, session_id: String) -> void:
    """Remove a player from a session"""
    if session_id in sessions:
        var session = sessions[session_id]
        
        if player_id in session.players:
            # Remove player from session
            var player_data = session.players[player_id]
            var peer_id = player_data["peer_id"]
            
            session.players.erase(player_id)
            session.last_activity = Time.get_ticks_msec()
            
            # Remove client session tracking
            client_sessions.erase(peer_id)
            
            # Notify observers
            player_left_session.emit(session_id, player_id)
            
            logger.info("SessionManager", "Player %s left session %s" % [player_id, session_id])
            
            # Broadcast lobby update to remaining players
            if session.players.size() > 0:
                _broadcast_lobby_update(session_id)
            
            # Destroy session if empty
            if session.players.size() == 0:
                destroy_session(session_id)

func _assign_team(session: Dictionary) -> int:
    """Assign a team to a new player"""
    var team_counts = {}
    
    for player_id in session.players.keys():
        var player = session.players[player_id]
        var team_id = player.team_id
        
        if not team_counts.has(team_id):
            team_counts[team_id] = 0
        team_counts[team_id] += 1
    
    # Find team with fewest players
    var min_count = 999
    var best_team = 1
    
    for team_id in range(1, 3):  # Teams 1 and 2
        var count = team_counts.get(team_id, 0)
        if count < min_count:
            min_count = count
            best_team = team_id
    
    return best_team

func _check_start_game(session_id: String) -> void:
    """Check if game should start"""
    var session = sessions.get(session_id)
    
    if not session or session.state != "waiting":
        return
    
    # Check if all players are ready
    var all_ready = true
    var player_count = session.players.size()
    
    # Allow single-player games
    if player_count < 1:
        all_ready = false
    
    for player_id in session.players.keys():
        var player = session.players[player_id]
        if not player.ready:
            all_ready = false
            break
    
    if all_ready:
        await _start_game(session_id)

func _start_game(session_id: String) -> void:
    """Start the game for a session"""
    var session = sessions.get(session_id)
    
    if not session:
        logger.warning("SessionManager", "Cannot start game - session %s not found" % session_id)
        return
    
    logger.info("SessionManager", "Starting game for session %s" % session_id)
    
    session.state = "active"
    session.last_activity = Time.get_ticks_msec()
    
    if multiplayer.is_server():
        match_started.emit(session_id)
        
        # Load the map on the server side for unit spawning
        _load_server_map()
        
    # Initialize game content
    await _initialize_game_content(session)
    
    # Get root node for RPC calls
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    
    if not root_node:
        logger.error("SessionManager", "Cannot find UnifiedMain root node for RPC calls")
        return
    
    # Notify all players in session
    for player_id in session.players.keys():
        var player = session.players[player_id]
        var peer_id = player.peer_id
        
        logger.info("SessionManager", "Notifying player %s (peer %d) that game started" % [player_id, peer_id])
        
        root_node.rpc_id(peer_id, "_on_game_started", {
            "session_id": session_id,
            "player_team": player.team_id,
            "map": session.map,
            "game_mode": session.game_mode
        })
    
    logger.info("SessionManager", "Game started for session %s" % session_id)

func _load_server_map() -> void:
    """Load the map on the server side for unit spawning"""
    logger.info("SessionManager", "Loading map on server side for unit spawning")
    
    # Check if map is already loaded
    var map_node = get_tree().get_root().find_child("TestMap", true, false)
    if map_node:
        logger.info("SessionManager", "Map already loaded on server")
        return
    
    # Load the test map scene
    const TEST_MAP_SCENE = "res://scenes/maps/test_map.tscn"
    var map_scene = load(TEST_MAP_SCENE)
    if map_scene:
        var map_instance = map_scene.instantiate()
        map_instance.name = "TestMap"
        
        # Add map to the UnifiedMain node
        var unified_main = get_tree().get_root().get_node("UnifiedMain")
        if unified_main:
            unified_main.add_child(map_instance)
            logger.info("SessionManager", "Map loaded successfully on server")
        else:
            logger.error("SessionManager", "Could not find UnifiedMain to attach map")
    else:
        logger.error("SessionManager", "Could not load map scene")

func _initialize_game_content(session: Dictionary) -> void:
    """Initialize game content when a game starts"""
    var session_id = session.id
    logger.info("SessionManager", "Initializing game content for session %s" % session_id)
    
    var map_node = get_tree().get_root().find_child("TestMap", true, false)
    if not map_node:
        logger.error("SessionManager", "Could not find map node 'TestMap' in the scene tree.")
        return

    # Get the game state to add players and spawn units
    if game_state:
        # Initialize all game systems
        _initialize_game_systems(session)
        
        # Add players to the game state
        for player_id in session.players.keys():
            var player = session.players[player_id]
            var peer_id = player.peer_id
            var team_id = player.team_id
            
            game_state.add_player(player_id, peer_id, player_id, team_id)
            logger.info("SessionManager", "Added player %s to game state (team %d)" % [player_id, team_id])
        
        # Initialize teams for all systems
        _initialize_team_systems(session)
        
        # Initialize control points
        _initialize_control_points(session, map_node)
        
        # Initialize resource management
        _initialize_resource_management(session)
        
        # Initialize AI systems
        _initialize_ai_systems(session)
        
        # Spawn initial units for each team
        await _spawn_initial_units(session, map_node)
        
        # Set game state to active
        game_state.set_match_state("active")
        logger.info("SessionManager", "Game content initialized successfully")
    else:
        logger.warning("SessionManager", "No game state available to initialize content")

func _initialize_game_systems(_session: Dictionary) -> void:
    """Initialize all game systems for the session"""
    logger.info("SessionManager", "Initializing game systems")
    
    # Get system references from dependency container
    var dependency_container = get_node("/root/DependencyContainer")
    if not dependency_container:
        logger.error("SessionManager", "Cannot find DependencyContainer")
        return
    
    var resource_manager = dependency_container.get_resource_manager()
    var node_capture_system = dependency_container.get_node_capture_system()
    var ai_command_processor = dependency_container.get_ai_command_processor()
    
    # Initialize systems
    if resource_manager:
        logger.info("SessionManager", "Resource manager available")
    
    if node_capture_system:
        logger.info("SessionManager", "Node capture system available")
    
    if ai_command_processor:
        logger.info("SessionManager", "AI command processor available")
    
    logger.info("SessionManager", "Game systems initialized")

func _initialize_team_systems(session: Dictionary) -> void:
    """Initialize team-based systems"""
    logger.info("SessionManager", "Initializing team systems")
    
    # Get unique team IDs from session
    var team_ids = []
    for player_id in session.players.keys():
        var player = session.players[player_id]
        var team_id = player.team_id
        if team_id not in team_ids:
            team_ids.append(team_id)
    
    logger.info("SessionManager", "Teams in session: %s" % str(team_ids))
    
    # Initialize resource manager for teams
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        var resource_manager = dependency_container.get_resource_manager()
        if resource_manager:
            # ResourceManager handles team initialization internally in _ready()
            logger.info("SessionManager", "Resource manager initialized for teams: %s" % str(team_ids))

func _initialize_control_points(_session: Dictionary, map_node: Node) -> void:
    """Initialize control points for the session"""
    logger.info("SessionManager", "Initializing control points")
    
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        var node_capture_system = dependency_container.get_node_capture_system()
        if node_capture_system:
            node_capture_system.initialize_control_points(map_node)
            logger.info("SessionManager", "Control points initialized")

func _initialize_resource_management(_session: Dictionary) -> void:
    """Initialize resource management for the session"""
    logger.info("SessionManager", "Initializing resource management")
    
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        var resource_manager = dependency_container.get_resource_manager()
        if resource_manager:
            # Start resource generation for all teams
            resource_manager.start_match()
            logger.info("SessionManager", "Resource generation started")

func _initialize_ai_systems(_session: Dictionary) -> void:
    """Initialize AI systems for the session"""
    logger.info("SessionManager", "Initializing AI systems")
    
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        var ai_command_processor = dependency_container.get_ai_command_processor()
        if ai_command_processor:
            # AI system is ready for command processing
            logger.info("SessionManager", "AI command processor initialized")

func _spawn_initial_units(session: Dictionary, map_node: Node) -> void:
    """Spawn initial units for each team"""
    logger.info("SessionManager", "Spawning initial units")
    
    var team_spawns = {
        1: map_node.get_node("SpawnPoints/Team1Spawn").global_position,
        2: map_node.get_node("SpawnPoints/Team2Spawn").global_position
    }

    # Spawn initial units for each team (not per player to avoid duplicates)
    var teams_with_players = {}
    
    # First, identify which teams have players
    for player_id in session.players.keys():
        var player = session.players[player_id]
        var team_id = player.team_id
        if not teams_with_players.has(team_id):
            teams_with_players[team_id] = []
        teams_with_players[team_id].append(player_id)
    
    # Then spawn units once per team, regardless of how many players are on that team
    for team_id in teams_with_players.keys():
        var team_players = teams_with_players[team_id]
        var representative_player = team_players[0]  # Use first player as representative for ownership
        
        var base_position = team_spawns.get(team_id, Vector3.ZERO)
        logger.info("SessionManager", "Spawning initial units for team %d with %d players" % [team_id, team_players.size()])
        
        # Spawn a mixed squad for this team
        var archetypes = ["scout", "tank", "sniper", "medic", "engineer"]
        for i in range(archetypes.size()):
            var archetype = archetypes[i]
            # Spacing increased from 3 to 6 to prevent collision shapes (radius 2.5) from overlapping at spawn.
            var unit_position = base_position + Vector3(i * 6, 1, 0) # Spawn at Y=1 to be above ground
            var unit_id = await game_state.spawn_unit(archetype, team_id, unit_position, representative_player)
            logger.info("SessionManager", "Spawned %s unit %s for team %d at %s" % [archetype, unit_id, team_id, unit_position])
    
    logger.info("SessionManager", "Initial units spawned")

func _broadcast_lobby_update(session_id: String) -> void:
    """Broadcast lobby update to all players in session"""
    var session = sessions.get(session_id)
    if not session:
        return
    
    # Determine if game can start
    var can_start = _can_start_game(session_id)
    
    # Create lobby data
    var lobby_data = {
        "players": session.players,
        "can_start_game": can_start,
        "session_id": session_id
    }
    
    # Get root node for RPC calls
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    
    # Send to all players in session
    for player_id in session.players.keys():
        var player = session.players[player_id]
        var player_peer_id = player.peer_id
        
        if root_node:
            root_node.rpc_id(player_peer_id, "_on_lobby_update", lobby_data)

func _can_start_game(session_id: String) -> bool:
    """Check if game can start (all players ready or single player)"""
    var session = sessions.get(session_id)
    if not session or session.state != "waiting":
        return false
    
    var player_count = session.players.size()
    
    # Allow single-player games
    if player_count == 1:
        return true
    
    # Check if all players are ready
    for player_id in session.players.keys():
        var player = session.players[player_id]
        if not player.ready:
            return false
    
    return true

func _cleanup_sessions() -> void:
    """Cleanup expired sessions"""
    var current_time = Time.get_ticks_msec()
    var sessions_to_remove = []
    
    for session_id in sessions.keys():
        var session = sessions[session_id]
        
        # Check if session has expired
        if current_time - session.last_activity > SESSION_TIMEOUT * 1000:
            sessions_to_remove.append(session_id)
    
    # Remove expired sessions
    for session_id in sessions_to_remove:
        destroy_session(session_id)
        logger.info("SessionManager", "Cleaned up expired session %s" % session_id)

func cleanup() -> void:
    """Cleanup resources"""
    # Destroy all sessions
    for session_id in sessions.keys():
        destroy_session(session_id)
    
    sessions.clear()
    client_sessions.clear()
    
    logger.info("SessionManager", "Session manager cleaned up")

# Note: RPC methods are now handled by UnifiedMain root node 