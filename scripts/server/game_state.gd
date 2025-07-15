# ServerGameState.gd - Server-side game state with dependency injection
extends Node

# Load GameEnums
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Injected dependencies
var logger
var game_constants
var network_messages

# Game state
var current_tick: int = 0
var game_time: float = 0.0
var match_state: String = "waiting"

# Game entities
var units: Dictionary = {}  # unit_id -> Unit
var buildings: Dictionary = {}  # building_id -> Building
var players: Dictionary = {}  # player_id -> PlayerData
var teams: Dictionary = {}  # team_id -> TeamData

# Resources
var team_resources: Dictionary = {}  # team_id -> ResourceData

# Networking
var is_running: bool = false

# Signals
signal game_state_changed()
signal unit_spawned(unit_id: String)
signal unit_destroyed(unit_id: String)
signal match_ended(result: int)

func setup(logger_ref, constants_ref, messages_ref):
    """Setup dependencies - called by DependencyContainer"""
    logger = logger_ref
    game_constants = constants_ref
    network_messages = messages_ref
    
    logger.info("ServerGameState", "Setting up server game state")
    
    # Initialize game state
    _initialize_game_state()

func _initialize_game_state():
    """Initialize the game state"""
    # Initialize team resources
    for team_id in range(1, 3):  # Teams 1 and 2
        team_resources[team_id] = game_constants.STARTING_RESOURCES.duplicate()
    
    # Start game loop
    var timer = Timer.new()
    timer.wait_time = 1.0 / game_constants.TICK_RATE
    timer.timeout.connect(_server_tick)
    add_child(timer)
    timer.start()
    
    is_running = true
    logger.info("ServerGameState", "Game state initialized")

func _server_tick() -> void:
    """Main server tick - runs at TICK_RATE"""
    current_tick += 1
    game_time += 1.0 / game_constants.TICK_RATE
    
    # Update game entities
    _update_units()
    _update_buildings()
    
    # Check victory conditions
    _check_victory_conditions()
    
    # Broadcast game state to clients (every few ticks to reduce bandwidth)
    if current_tick % (game_constants.TICK_RATE / game_constants.NETWORK_TICK_RATE) == 0:
        _broadcast_game_state()

func _update_units() -> void:
    """Update all units"""
    for unit_id in units:
        var unit = units[unit_id]
        if unit.has_method("server_update"):
            unit.server_update(1.0 / game_constants.TICK_RATE)

func _update_buildings() -> void:
    """Update all buildings"""
    for building_id in buildings:
        var building = buildings[building_id]
        if building.has_method("server_update"):
            building.server_update(1.0 / game_constants.TICK_RATE)

func _check_victory_conditions() -> void:
    """Check if any team has won"""
    if match_state != "active":
        return
    
    # Don't check victory conditions for single-player games
    if players.size() <= 1:
        return
    
    # Check if any team has no units left
    var team_unit_counts = {}
    
    for unit_id in units:
        var unit = units[unit_id]
        var team_id = unit.team_id
        
        if not team_unit_counts.has(team_id):
            team_unit_counts[team_id] = 0
        team_unit_counts[team_id] += 1
    
    # Check for elimination victory (only for multiplayer)
    var alive_teams = []
    for team_id in team_unit_counts:
        if team_unit_counts[team_id] > 0:
            alive_teams.append(team_id)
    
    # Only trigger victory conditions if there are multiple teams
    if alive_teams.size() == 1 and team_unit_counts.size() > 1:
        _end_match(alive_teams[0])
    elif alive_teams.size() == 0:
        _end_match(0)  # Draw

func _end_match(winner_team: int) -> void:
    """End the match with a winner"""
    match_state = "ended"
    match_ended.emit(winner_team)
    
    # Notify all clients
    var result_message = network_messages.create_match_result_message(winner_team, game_time)
    _broadcast_to_all_clients(result_message)
    
    logger.info("ServerGameState", "Match ended - winner: team %d" % winner_team)

func _broadcast_game_state() -> void:
    """Broadcast current game state to all clients"""
    var state_message = network_messages.create_game_state_message()
    
    # Add units
    for unit_id in units:
        var unit = units[unit_id]
        state_message.units.append({
            "id": unit_id,
            "unit_type": unit.unit_type,
            "team_id": unit.team_id,
            "position": [unit.global_position.x, unit.global_position.y, unit.global_position.z],
            "rotation": unit.rotation.y,
            "health": unit.current_health,
            "max_health": unit.max_health,
            "state": GameEnums.get_unit_state_string(unit.current_state)
        })
    
    # Add buildings
    for building_id in buildings:
        var building = buildings[building_id]
        state_message.buildings.append({
            "id": building_id,
            "building_type": building.building_type,
            "team_id": building.team_id,
            "position": [building.global_position.x, building.global_position.y, building.global_position.z],
            "health": building.current_health,
            "max_health": building.max_health
        })
    
    # Add resources
    state_message.resources = team_resources.duplicate()
    state_message.match_state = match_state
    state_message.game_time = game_time
    
    _broadcast_to_all_clients(state_message)

func _broadcast_to_all_clients(message) -> void:
    """Broadcast a message to all connected clients"""
    # Get root node for RPC calls
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    
    if not root_node:
        logger.warning("ServerGameState", "Cannot find UnifiedMain root node for RPC calls")
        return
    
    # Send to all connected clients with error handling
    var disconnected_players = []
    
    for player_id in players:
        var player = players[player_id]
        if player.has("peer_id"):
            var peer_id = player.peer_id
            
            # Check if peer is still connected
            if multiplayer.has_multiplayer_peer() and multiplayer.get_multiplayer_peer().is_server():
                var connected_peers = multiplayer.get_peers()
                if peer_id in connected_peers:
                    # Safe to send RPC
                    root_node.rpc_id(peer_id, "_on_game_state_update", message.to_dict())
                else:
                    # Peer is disconnected, mark for removal
                    disconnected_players.append(player_id)
                    logger.info("ServerGameState", "Player %s (peer %d) is disconnected, removing from game" % [player_id, peer_id])
            else:
                # Single player or no multiplayer peer, send directly
                root_node.rpc_id(peer_id, "_on_game_state_update", message.to_dict())
    
    # Remove disconnected players
    for player_id in disconnected_players:
        remove_player(player_id)

# Unit management
func spawn_unit(unit_type: String, team_id: int, position: Vector3, player_id: String = "") -> String:
    """Spawn a new unit"""
    var unit_id = "unit_%s_%d_%d" % [unit_type, team_id, current_tick]
    
    # Load unit scene
    var unit_scene = preload("res://scenes/units/Unit.tscn")
    var unit = unit_scene.instantiate()
    
    # Configure unit
    unit.unit_id = unit_id
    unit.unit_type = unit_type
    unit.team_id = team_id
    unit.owner_player_id = player_id
    unit.global_position = position
    
    # Apply unit stats from config
    var unit_config = game_constants.get_unit_config(unit_type)
    if unit_config:
        unit.max_health = unit_config.get("health", 100)
        unit.current_health = unit.max_health
        unit.movement_speed = unit_config.get("speed", 5.0)
        unit.attack_damage = unit_config.get("damage", 25)
        unit.attack_range = unit_config.get("range", 3.0)
        unit.vision_range = unit_config.get("vision", 8.0)
    
    # Add to scene and tracking
    add_child(unit)
    units[unit_id] = unit
    
    # Connect signals
    unit.unit_destroyed.connect(_on_unit_destroyed)
    unit.unit_health_changed.connect(_on_unit_health_changed)
    
    unit_spawned.emit(unit_id)
    logger.info("ServerGameState", "Spawned unit %s at %s" % [unit_id, position])
    
    return unit_id

func destroy_unit(unit_id: String) -> void:
    """Destroy a unit"""
    if unit_id in units:
        var unit = units[unit_id]
        units.erase(unit_id)
        unit.queue_free()
        unit_destroyed.emit(unit_id)
        logger.info("ServerGameState", "Destroyed unit %s" % unit_id)

func get_unit(unit_id: String) -> Node:
    """Get a unit by ID"""
    return units.get(unit_id, null)

func get_units_by_team(team_id: int) -> Array:
    """Get all units for a specific team"""
    var team_units = []
    for unit_id in units:
        var unit = units[unit_id]
        if unit.team_id == team_id:
            team_units.append(unit)
    return team_units

# Player management
func add_player(player_id: String, peer_id: int, player_name: String, team_id: int) -> void:
    """Add a player to the game"""
    players[player_id] = {
        "peer_id": peer_id,
        "player_name": player_name,
        "team_id": team_id,
        "is_ready": false
    }
    
    # Initialize team resources if needed
    if not team_resources.has(team_id):
        team_resources[team_id] = game_constants.STARTING_RESOURCES.duplicate()
    
    logger.info("ServerGameState", "Added player %s (team %d)" % [player_name, team_id])

func remove_player(player_id: String) -> void:
    """Remove a player from the game"""
    if player_id in players:
        players.erase(player_id)
        logger.info("ServerGameState", "Removed player %s" % player_id)

# AI command processing
func process_ai_command(command: String, selected_units: Array, player_id: String) -> void:
    """Process an AI command"""
    logger.info("ServerGameState", "Processing AI command: %s" % command)
    
    # Get AI command processor from dependency container
    var dependency_container = get_node("/root/DependencyContainer")
    if not dependency_container:
        logger.error("ServerGameState", "Cannot find DependencyContainer for AI command processing")
        return
    
    var ai_command_processor = dependency_container.get_ai_command_processor()
    if not ai_command_processor:
        logger.error("ServerGameState", "AI command processor not available")
        return
    
    # Convert selected_units to actual unit objects if they're IDs
    var unit_objects = []
    for unit_data in selected_units:
        if unit_data is String:
            # Unit ID provided, get the actual unit
            var unit = get_unit(unit_data)
            if unit:
                unit_objects.append(unit)
        else:
            # Assume it's already a unit object
            unit_objects.append(unit_data)
    
    # Build game state context for AI
    var game_state_context = {
        "match_state": match_state,
        "game_time": game_time,
        "team_resources": team_resources,
        "player_id": player_id,
        "units_count": units.size(),
        "buildings_count": buildings.size()
    }
    
    # Send to AI command processor
    ai_command_processor.process_command(command, unit_objects, game_state_context)
    logger.info("ServerGameState", "AI command forwarded to processor")

# Signal handlers
func _on_unit_destroyed(unit_id: String) -> void:
    """Handle unit destruction"""
    destroy_unit(unit_id)

func _on_unit_health_changed(unit_id: String, health: int) -> void:
    """Handle unit health changes"""
    # Update unit health tracking
    pass

# Public interface
func get_game_time() -> float:
    return game_time

func get_current_tick() -> int:
    return current_tick

func get_match_state() -> String:
    return match_state

func set_match_state(state: String) -> void:
    match_state = state
    game_state_changed.emit()

func cleanup() -> void:
    """Cleanup resources"""
    is_running = false
    logger.info("ServerGameState", "Game state cleaned up")

# Note: RPC methods are now handled by UnifiedMain root node 