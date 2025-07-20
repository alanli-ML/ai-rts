# SessionManager.gd - Session manager with dependency injection
extends Node

# Injected dependencies
var logger
var game_state: Node

# Session management
var sessions: Dictionary = {}  # session_id -> Session
var client_sessions: Dictionary = {}  # peer_id -> session_id
var session_counter: int = 0
var cleanup_timer: Timer

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
    
    _log_info("Setting up session manager")
    if game_state:
        _log_info("Game state reference set successfully")
    else:
        _log_warning("Game state reference is null during setup!")
    
    # Initialize session management
    _initialize_session_manager()

func _log_info(message: String) -> void:
    """Safe logging function that handles null logger"""
    if logger:
        logger.info("SessionManager", message)
    else:
        print("SessionManager: %s" % message)

func _log_warning(message: String) -> void:
    """Safe logging function that handles null logger"""
    if logger:
        logger.warning("SessionManager", message)
    else:
        print("SessionManager WARNING: %s" % message)

func _log_error(message: String) -> void:
    """Safe logging function that handles null logger"""
    if logger:
        logger.error("SessionManager", message)
    else:
        print("SessionManager ERROR: %s" % message)

func _find_nodes_by_name(node: Node, target_name: String, results: Array) -> void:
    """Recursively find nodes by name"""
    if node.name == target_name:
        results.append(node)
    
    for child in node.get_children():
        _find_nodes_by_name(child, target_name, results)

func _initialize_session_manager():
    """Initialize session management"""
    # Setup session cleanup timer
    cleanup_timer = Timer.new()
    cleanup_timer.wait_time = 60.0  # Check every minute
    cleanup_timer.timeout.connect(_cleanup_sessions)
    add_child(cleanup_timer)
    cleanup_timer.start()
    
    _log_info("Session manager initialized")

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
    
    _log_info("Created session %s" % session_id)
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
        
        _log_info("Destroyed session %s" % session_id)

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
    _log_info("Client connected: %d" % peer_id)

func on_client_disconnected(peer_id: int, _client_data: Dictionary) -> void:
    """Handle client disconnection"""
    _log_info("Client disconnected: %d" % peer_id)
    
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
        _log_warning("Player %d not in any session" % peer_id)
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
        _log_info("Player %s (Peer %d) ready state: %s" % [player_id_to_update, peer_id, ready_state])
        
        # Broadcast lobby update
        _broadcast_lobby_update(session_id)
        
        # Check if game can start automatically (e.g. if all players are ready)
        call_deferred("_check_start_game", session_id)
    else:
                    _log_warning("Could not find player for peer_id %d in session %s" % [peer_id, session_id])

func handle_force_start_game(peer_id: int) -> void:
    """Handle force start game request from a client (host)."""
    var session_id = get_player_session(peer_id)
    
    _log_info("Start game request from peer %d" % peer_id)
    
    if session_id == "":
        _log_warning("Player %d not in any session" % peer_id)
        return
    
    var session = sessions.get(session_id)
    if not session:
        _log_warning("Session %s not found" % session_id)
        return
    
    # TODO: Check if peer_id is the host
    
    if session.state != "waiting":
        _log_warning("Session %s is not in waiting state (current: %s)" % [session_id, session.state])
        return

    if _can_start_game(session_id):
        _log_info("Starting game for session %s with %d players" % [session_id, session.players.size()])
        await _start_game(session_id)
    else:
        _log_warning("Start game request denied. Not all players are ready.")
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
        
        _log_info("Player %s joined session %s" % [player_id, session_id])
        
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
            
            _log_info("Player %s left session %s" % [player_id, session_id])
            
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
        _log_warning("Cannot start game - session %s not found" % session_id)
        return
    
    # CRITICAL: Prevent duplicate game starts for the same session
    if session.state == "active":
        _log_warning("Game already started for session %s - ignoring duplicate start request" % session_id)
        return
    
    _log_info("Starting game for session %s" % session_id)
    
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
        _log_error("Cannot find UnifiedMain root node for RPC calls")
        return
    
    # Notify all players in session
    for player_id in session.players.keys():
        var player = session.players[player_id]
        var peer_id = player.peer_id
        
        _log_info("Notifying player %s (peer %d) that game started" % [player_id, peer_id])
        
        root_node.rpc_id(peer_id, "_on_game_started", {
            "session_id": session_id,
            "player_team": player.team_id,
            "map": session.map,
            "game_mode": session.game_mode
        })
    
    _log_info("Game started for session %s" % session_id)

func _load_server_map() -> void:
    """Load the map on the server side for unit spawning"""
    _log_info("Loading map on server side for unit spawning")
    
    # Check if map is already loaded
    var map_node = get_tree().get_root().find_child("TestMap", true, false)
    if map_node:
        _log_info("Map already loaded on server")
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
            _log_info("Map loaded successfully on server")
        else:
            _log_error("Could not find UnifiedMain to attach map")
    else:
        _log_error("Could not load map scene")

func _initialize_game_content(session: Dictionary) -> void:
    """Initialize game content when a game starts"""
    var session_id = session.id
    _log_info("Initializing game content for session %s" % session_id)
    
    var map_node = get_tree().get_root().find_child("TestMap", true, false)
    if not map_node:
        _log_error("Could not find map node 'TestMap' in the scene tree.")
        return

    # Get the game state to add players and spawn units
    _log_info("Checking game state availability...")
    
    # Try to get game state from dependency container if our reference is null
    if not game_state:
        _log_warning("Game state reference is null, trying to get from dependency container...")
        var dependency_container = get_node_or_null("/root/DependencyContainer")
        if dependency_container:
            game_state = dependency_container.get_game_state()
            if game_state:
                _log_info("Successfully retrieved game state from dependency container")
            else:
                _log_error("Game state not available in dependency container either")
        else:
            _log_error("Could not find dependency container")
    
    if game_state:
        _log_info("Game state is available")
        # Initialize all game systems
        _initialize_game_systems(session)
        
        # Add players to the game state
        for player_id in session.players.keys():
            var player = session.players[player_id]
            var peer_id = player.peer_id
            var team_id = player.team_id
            
            game_state.add_player(player_id, peer_id, player_id, team_id)
            _log_info("Added player %s to game state (team %d)" % [player_id, team_id])
        
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
        _log_info("Game content initialized successfully")
    else:
        _log_warning("No game state available to initialize content")

func _initialize_game_systems(_session: Dictionary) -> void:
    """Initialize all game systems for the session"""
    _log_info("Initializing game systems")
    
    # Get system references from dependency container
    var dependency_container = get_node("/root/DependencyContainer")
    if not dependency_container:
        _log_error("Cannot find DependencyContainer")
        return
    
    var resource_manager = dependency_container.get_resource_manager()
    var node_capture_system = dependency_container.get_node_capture_system()
    var ai_command_processor = dependency_container.get_ai_command_processor()
    
    # Initialize systems
    if resource_manager:
        _log_info("Resource manager available")
    
    if node_capture_system:
        _log_info("Node capture system available")
    
    if ai_command_processor:
        _log_info("AI command processor available")
    
    _log_info("Game systems initialized")

func _initialize_team_systems(session: Dictionary) -> void:
    """Initialize team-based systems"""
    _log_info("Initializing team systems")
    
    # Get unique team IDs from session
    var team_ids = []
    for player_id in session.players.keys():
        var player = session.players[player_id]
        var team_id = player.team_id
        if team_id not in team_ids:
            team_ids.append(team_id)
    
    _log_info("Teams in session: %s" % str(team_ids))
    
    # Initialize resource manager for teams
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        var resource_manager = dependency_container.get_resource_manager()
        if resource_manager:
            # ResourceManager handles team initialization internally in _ready()
            _log_info("Resource manager initialized for teams: %s" % str(team_ids))

func _initialize_control_points(_session: Dictionary, map_node: Node) -> void:
    """Initialize control points for the session"""
    _log_info("Initializing control points")
    
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        var node_capture_system = dependency_container.get_node_capture_system()
        if node_capture_system:
            node_capture_system.initialize_control_points(map_node)
            _log_info("Control points initialized")

func _initialize_resource_management(_session: Dictionary) -> void:
    """Initialize resource management for the session"""
    _log_info("Initializing resource management")
    
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        var resource_manager = dependency_container.get_resource_manager()
        if resource_manager:
            # Start resource generation for all teams
            resource_manager.start_match()
            _log_info("Resource generation started")

func _initialize_ai_systems(_session: Dictionary) -> void:
    """Initialize AI systems for the session"""
    _log_info("Initializing AI systems")
    
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        var ai_command_processor = dependency_container.get_ai_command_processor()
        if ai_command_processor:
            # AI system is ready for command processing
            _log_info("AI command processor initialized")

func _spawn_initial_units(session: Dictionary, map_node: Node) -> void:
    """Spawn initial units for each team"""
    _log_info("Spawning initial units for session %s" % session.id)
    
    # Try to find spawn points in various locations due to map structure changes
    var team1_spawn = null
    var team2_spawn = null
    
    # First try direct path (legacy test_map structure)
    team1_spawn = map_node.get_node_or_null("SpawnPoints/Team1Spawn")
    team2_spawn = map_node.get_node_or_null("SpawnPoints/Team2Spawn")
    
    # If not found, search in loaded map structures (city_map structure)
    if not team1_spawn or not team2_spawn:
        _log_info("Spawn points not found in direct path, searching in loaded map structures...")
        var map_structures = map_node.get_node_or_null("MapStructures")
        if map_structures:
            _log_info("Found MapStructures node, searching children...")
            for child in map_structures.get_children():
                _log_info("Checking child: %s" % child.name)
                var spawn_points = child.get_node_or_null("SpawnPoints")
                if spawn_points and is_instance_valid(spawn_points):
                    _log_info("Found SpawnPoints in %s" % child.name)
                    if not team1_spawn:
                        team1_spawn = spawn_points.get_node_or_null("Team1Spawn")
                        if team1_spawn:
                            _log_info("Found Team1Spawn at: %s" % team1_spawn.get_path())
                    if not team2_spawn:
                        team2_spawn = spawn_points.get_node_or_null("Team2Spawn")
                        if team2_spawn:
                            _log_info("Found Team2Spawn at: %s" % team2_spawn.get_path())
                    if team1_spawn and team2_spawn:
                        break
        else:
            _log_info("MapStructures node not found")
            
        # Also try searching directly for any SpawnPoints node in the scene tree
        if not team1_spawn or not team2_spawn:
            _log_info("Still missing spawn points, searching entire scene tree...")
            var spawn_points_nodes = get_tree().get_nodes_in_group("spawn_points")
            if spawn_points_nodes.is_empty():
                # Search by name if no group found
                var all_spawn_points = []
                _find_nodes_by_name(map_node, "SpawnPoints", all_spawn_points)
                for sp in all_spawn_points:
                    if not team1_spawn:
                        team1_spawn = sp.get_node_or_null("Team1Spawn")
                    if not team2_spawn:
                        team2_spawn = sp.get_node_or_null("Team2Spawn")
                    if team1_spawn and team2_spawn:
                        break
    
    # Create team_spawns dictionary
    var team_spawns = {}
    
    # Fallback to home base manager if spawn points still not found
    if not team1_spawn or not team2_spawn:
        var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
        if home_base_manager:
            _log_info("Using home base manager for spawn positions")
            team_spawns = {
                1: home_base_manager.get_spawn_position_with_offset(1),
                2: home_base_manager.get_spawn_position_with_offset(2)
            }
        else:
            _log_error("No spawn points or home base manager found!")
            return
    else:
        team_spawns = {
            1: team1_spawn.global_position,
            2: team2_spawn.global_position
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
        _log_info("Spawning initial units for team %d with %d players" % [team_id, team_players.size()])
        
        # Spawn 2x each unit type for this team using safe spawn positions
        var archetypes = ["scout", "tank", "sniper", "medic", "engineer"]
        var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
        
        var unit_index = 0  # Track overall unit position for formation
        for archetype in archetypes:
            # Spawn 2 of each archetype
            for j in range(2):
                # Arrange units in formation around the base center
                var unit_position: Vector3
                if home_base_manager:
                    var base_center = home_base_manager.get_team_spawn_position(team_id)
                    # Create formation offset in a grid pattern around base center
                    # Total units per team is now 10 (2 of each of 5 archetypes)
                    var formation_offset = _get_formation_offset(unit_index, 10)
                    unit_position = base_center + formation_offset
                else:
                    # Fallback with manual bounds checking
                    var raw_position = base_position + Vector3(unit_index * 4, 1, 0)
                    unit_position = Vector3(
                        clamp(raw_position.x, -40.0, 40.0),
                        raw_position.y,
                        clamp(raw_position.z, -40.0, 40.0)
                    )
                
                var unit_id = await game_state.spawn_unit(archetype, team_id, unit_position, representative_player)
                _log_info("Spawned %s unit %s for team %d at %s (unit %d/10)" % [archetype, unit_id, team_id, unit_position, unit_index + 1])
                unit_index += 1
    
    _log_info("Initial units spawned")

func _get_formation_offset(unit_index: int, total_units: int) -> Vector3:
    """Calculate formation offset for unit placement around base center"""
    # Arrange units in a circular formation around the base
    var spacing = 3.0  # Distance between units
    var radius = 4.0   # Base radius for formation
    
    if total_units == 1:
        return Vector3.ZERO  # Single unit at center
    
    # Calculate angle for this unit in the formation circle
    var angle_per_unit = (2 * PI) / total_units
    var angle = unit_index * angle_per_unit
    
    # Calculate position on circle with some radius variation for larger groups
    var effective_radius = radius + (total_units - 2) * 0.5
    var x_offset = cos(angle) * effective_radius
    var z_offset = sin(angle) * effective_radius
    
    return Vector3(x_offset, 0.0, z_offset)

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
    """Check if a session can start"""
    var session = sessions.get(session_id)
    if not session:
        return false
    
    # Check if all players are ready
    for player_id in session.players.keys():
        var player = session.players[player_id]
        if not player.ready:
            return false
    
    return session.players.size() > 0

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
        _log_info("Cleaned up expired session %s" % session_id)

func cleanup() -> void:
    """Cleanup resources"""
    # Destroy all sessions
    for session_id in sessions.keys():
        destroy_session(session_id)
    
    sessions.clear()
    client_sessions.clear()
    
    _log_info("Session manager cleaned up")

# Note: RPC methods are now handled by UnifiedMain root node 

func _ready() -> void:
    pass 