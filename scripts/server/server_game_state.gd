# ServerGameState.gd
# Server-authoritative game state manager
extends Node

const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Load shared enums
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

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

# Fog of War
const VisibilityManager = preload("res://scripts/server/visibility_manager.gd")
var visibility_manager: VisibilityManager

# System references (injected via dependency container)
var ai_command_processor: Node
var team_unit_spawner: Node
var plan_executor: Node

func _get_event_bus():
    if has_node("/root/EventBus"):
        return get_node("/root/EventBus")
    return null
var resource_manager: Node
var node_capture_system: Node
var logger: Node
var game_constants
var network_messages

# Cached data for client synchronization
var control_points_data: Dictionary = {}  # Updated control point data for clients
var resource_data: Dictionary = {}  # Updated resource data for clients
var ai_progress_data: Dictionary = {}  # AI plan progress for clients

# Change tracking for efficient client updates
var unit_goal_cache: Dictionary = {}  # unit_id -> {strategic_goal, control_sequence, sequence_index}
var units_with_goal_changes: Array = []  # Units that need goal updates sent to clients

# Signals
signal game_state_changed()
signal unit_spawned(unit_id: String)
signal unit_destroyed(unit_id: String)
signal match_ended(result: int)

# Team AI command coordination
var teams_awaiting_first_command: Dictionary = {}  # team_id -> bool (true if team still needs first command)
var match_started_but_waiting_for_commands: bool = false  # Flag to track if match started but waiting for AI

var tick_counter: int = 0
const NETWORK_TICK_RATE = 2 # ~30 times per second if physics is 60fps
var ui_tick_counter: int = 0
const UI_NETWORK_TICK_RATE = 6 # ~10 times per second if physics is 60fps

# Safe logging functions that handle null logger
func _log_info(component: String, message: String):
    if logger and logger.has_method("info"):
        logger.info(component, message)
    else:
        print("[INFO] %s: %s" % [component, message])

func _log_warning(component: String, message: String):
    if logger and logger.has_method("warning"):
        logger.warning(component, message)
    else:
        print("[WARNING] %s: %s" % [component, message])

func _log_error(component: String, message: String):
    if logger and logger.has_method("error"):
        logger.error(component, message)
    else:
        print("[ERROR] %s: %s" % [component, message])

@rpc("any_peer", "call_local", "reliable")
func request_spawn_unit_rpc(archetype: String, requesting_peer_id: int) -> void:
    """Handle direct unit spawn request from UI - bypasses AI command processor"""
    # Only process on the server/authority
    if not multiplayer.is_server():
        return
        
    _log_info("ServerGameState", "Direct spawn request for %s from peer %d" % [archetype, requesting_peer_id])
    
    # Find the player and their team
    var player_id = "player_%d" % requesting_peer_id
    var player_data = null
    var team_id = 1  # Default fallback
    
    # Find player data in the players dictionary
    for pid in players.keys():
        var pdata = players[pid]
        if pdata.peer_id == requesting_peer_id:
            player_data = pdata
            team_id = pdata.team_id
            player_id = pid
            break
    
    if not player_data:
        _log_warning("ServerGameState", "Could not find player data for peer %d, using defaults" % requesting_peer_id)
    
    # Check if we have enough energy (server-side validation)
    if resource_manager:
        var current_energy = resource_manager.team_resources.get(team_id, {}).get("energy", 0)
        var spawn_cost = 100  # Standard unit cost
        
        if current_energy < spawn_cost:
            _log_warning("ServerGameState", "Team %d has insufficient energy to spawn %s (need %d, have %d)" % [team_id, archetype, spawn_cost, current_energy])
            # TODO: Send failure message back to client
            return
        
        # Deduct energy cost
        resource_manager.team_resources[team_id]["energy"] = current_energy - spawn_cost
        _log_info("ServerGameState", "Deducted %d energy from team %d (remaining: %d)" % [spawn_cost, team_id, current_energy - spawn_cost])
    
    # Get spawn position near team's base
    var spawn_position = _get_team_spawn_position(team_id)
    
    # Spawn the unit
    var unit_id = await spawn_unit(archetype, team_id, spawn_position, player_id)
    
    if unit_id != "":
        _log_info("ServerGameState", "Successfully spawned %s unit %s for team %d at %s" % [archetype, unit_id, team_id, spawn_position])
    else:
        _log_error("ServerGameState", "Failed to spawn %s unit for team %d" % [archetype, team_id])

func _get_team_spawn_position(team_id: int) -> Vector3:
    """Get a safe spawn position for the team"""
    # Try to use home base manager first
    var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
    if home_base_manager:
        return home_base_manager.get_spawn_position_with_offset(team_id)
    
    # Fallback to basic team positions
    match team_id:
        1:
            return Vector3(-20, 1, 0)
        2:
            return Vector3(20, 1, 0)
        _:
            return Vector3(0, 1, 0)

func _ready() -> void:
    # Systems will be initialized via dependency injection
    add_to_group("server_game_state")  # Add to group for easy discovery
    _log_info("ServerGameState", "ServerGameState ready and added to group")

func _physics_process(_delta: float) -> void:
    if match_state != "active":
        return

    if visibility_manager:
        visibility_manager.update_visibility(units, node_capture_system.control_points)
        
        # Debug: Log visibility updates every few seconds
        if Engine.get_frames_drawn() % 180 == 0:  # Every 3 seconds
            var team1_grid = visibility_manager.get_visibility_grid_data(1)
            var team2_grid = visibility_manager.get_visibility_grid_data(2)
            var visible_count_t1 = 0
            var visible_count_t2 = 0
            
            for i in range(team1_grid.size()):
                if team1_grid[i] == 255:
                    visible_count_t1 += 1
            
            for i in range(team2_grid.size()):
                if team2_grid[i] == 255:
                    visible_count_t2 += 1
            
            _log_info("ServerGameState", "Visibility update: Team 1 visible cells: %d/%d, Team 2: %d/%d, Units: %d" % [visible_count_t1, team1_grid.size(), visible_count_t2, team2_grid.size(), units.size()])

    tick_counter += 1
    if tick_counter >= NETWORK_TICK_RATE:
        tick_counter = 0
        _broadcast_game_state()

    ui_tick_counter += 1
    if ui_tick_counter >= UI_NETWORK_TICK_RATE:
        ui_tick_counter = 0
        _broadcast_ui_data()

func _gather_filtered_game_state_for_team(team_id: int) -> Dictionary:
    var state = {
        "units": [],
        "mines": [],
        "control_points": [],
        "visibility_data": {}
    }
    
    var entity_manager = get_node("/root/DependencyContainer").get_entity_manager()

    # Filter units based on visibility
    for unit_id in units:
        var unit = units[unit_id]
        if is_instance_valid(unit):
            var is_visible = (unit.team_id == team_id) or (visibility_manager.is_position_visible(team_id, unit.global_position) and unit.can_be_targeted())
            
            if is_visible:
                var plan_summary = "Idle"
                if "current_reactive_state" in unit:
                    plan_summary = unit.current_reactive_state.capitalize()

                var basis = unit.transform.basis
                var unit_data = {
                    "id": unit.unit_id,
                    "archetype": unit.archetype,
                    "team_id": unit.team_id,
                    "position": { "x": unit.global_position.x, "y": unit.global_position.y, "z": unit.global_position.z },
                    "velocity": { "x": unit.velocity.x, "y": unit.velocity.y, "z": unit.velocity.z },
                    "basis": {
                        "x": {"x": basis.x.x, "y": basis.x.y, "z": basis.x.z},
                        "y": {"x": basis.y.x, "y": basis.y.y, "z": basis.y.z},
                        "z": {"x": basis.z.x, "y": basis.z.y, "z": basis.z.z}
                    },
                    "current_state": unit.current_state,
                    "health": unit.current_health,
                    "current_health": unit.current_health,
                    "max_health": unit.max_health,
                    "is_dead": unit.is_dead,
                    "is_respawning": unit.is_respawning,
                    "respawn_timer": unit.respawn_timer if "respawn_timer" in unit else 0.0,
                    "plan_summary": plan_summary,
                    "waiting_for_first_command": unit.waiting_for_first_command if "waiting_for_first_command" in unit else true,
                    "has_received_first_command": unit.has_received_first_command if "has_received_first_command" in unit else false,
                    "waiting_for_ai": false, # This is now deprecated
                    "active_triggers": [],  # Deprecated
                    "all_triggers": {}     # Deprecated
                }
                
                # Only include goal data for friendly units (never for enemies)
                if unit.team_id == team_id:
                    var unit_needs_goal_update = units_with_goal_changes.has(unit.unit_id)
                    var has_goal_changes = _check_and_cache_unit_goal_changes(unit.unit_id, unit)
                    
                    if unit_needs_goal_update or has_goal_changes:
                        unit_data["strategic_goal"] = unit.strategic_goal if "strategic_goal" in unit else ""
                        unit_data["control_point_attack_sequence"] = unit.control_point_attack_sequence if "control_point_attack_sequence" in unit else []
                        unit_data["current_attack_sequence_index"] = unit.current_attack_sequence_index if "current_attack_sequence_index" in unit else 0
                        _log_info("ServerGameState", "Including goal data for friendly unit %s: %s" % [unit.unit_id, unit_data.get("strategic_goal", "none")])
                        GameConstants.debug_print("ServerGameState - Sending goal update for friendly unit %s: strategic_goal='%s', sequence=%s" % [unit.unit_id, unit_data.get("strategic_goal", ""), unit_data.get("control_point_attack_sequence", [])], "NETWORK")
                    else:
                        GameConstants.debug_print("ServerGameState - NOT including goal data for friendly unit %s (marked: %s, detected change: %s)" % [unit.unit_id, unit_needs_goal_update, has_goal_changes], "NETWORK")
                else:
                    GameConstants.debug_print("ServerGameState - NOT including goal data for enemy unit %s (team %d vs %d)" % [unit.unit_id, unit.team_id, team_id], "NETWORK")
                
                if unit.archetype == "sniper" and unit.current_state == GameEnums.UnitState.CHARGING_SHOT:
                    if "charge_timer" in unit and "charge_time" in unit:
                        unit_data["charge_timer"] = unit.charge_timer
                        unit_data["charge_time"] = unit.charge_time
                state.units.append(unit_data)

    # Filter mines based on visibility
    if entity_manager:
        var all_entities = entity_manager.get_all_entities()
        for mine_id in all_entities.mines:
            var mine = all_entities.mines[mine_id]
            if is_instance_valid(mine):
                var is_visible = (mine.team_id == team_id) or visibility_manager.is_position_visible(team_id, mine.global_position)
                if is_visible:
                    state.mines.append({
                        "id": mine_id,
                        "team_id": mine.team_id,
                        "position": { "x": mine.global_position.x, "y": mine.global_position.y, "z": mine.global_position.z }
                    })
    
    # Control points are always sent
    if node_capture_system and not node_capture_system.control_points.is_empty():
        for cp in node_capture_system.control_points:
            if is_instance_valid(cp):
                state.control_points.append({
                    "id": cp.control_point_id,
                    "team_id": cp.get_controlling_team(),
                    "capture_value": cp.capture_value
                })

    # Add visibility data for the client's renderer
    state["visibility_grid"] = visibility_manager.get_visibility_grid_data(team_id)
    state["visibility_grid_meta"] = visibility_manager.get_grid_metadata()
    
    # Add team AI coordination status to state
    if match_started_but_waiting_for_commands:
        state.ai_coordination = {
            "waiting_for_synchronized_start": true,
            "teams_awaiting_commands": []
        }
        for tracked_team_id in teams_awaiting_first_command:
            if teams_awaiting_first_command[tracked_team_id]:
                state.ai_coordination.teams_awaiting_commands.append(tracked_team_id)
    else:
        state.ai_coordination = {
            "waiting_for_synchronized_start": false,
            "teams_awaiting_commands": []
        }

    return state

func get_units_in_radius(p_position: Vector3, p_radius: float, p_team_to_exclude: int = -1, p_team_to_find: int = -1) -> Array[Unit]:
    var units_in_range: Array[Unit] = []
    var radius_sq = p_radius * p_radius
    for unit_id in units:
        var unit = units[unit_id]
        if not is_instance_valid(unit) or unit.is_dead:
            continue
        
        if p_team_to_exclude != -1 and unit.team_id == p_team_to_exclude:
            continue
            
        if p_team_to_find != -1 and unit.team_id != p_team_to_find:
            continue
            
        if unit.global_position.distance_squared_to(p_position) < radius_sq:
            units_in_range.append(unit)
    return units_in_range

func get_units_by_archetype(archetype: String, team_id: int = -1) -> Array:
    """Get all units of a specific archetype, optionally filtered by team"""
    var matching_units = []
    
    for unit_id in units:
        var unit = units[unit_id]
        if not is_instance_valid(unit):
            continue
            
        # Check archetype match
        if unit.archetype != archetype:
            continue
            
        # Check team filter (if specified)
        if team_id != -1 and unit.team_id != team_id:
            continue
            
        # Include both dead and alive units for accurate counting
        # (dead turrets are removed from the dictionary, but this covers edge cases)
        matching_units.append(unit)
    
    return matching_units

func _broadcast_game_state() -> void:
    var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
    if not session_manager or session_manager.get_session_count() == 0:
        return

    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if not root_node:
        return
        
    GameConstants.debug_print("ServerGameState - Broadcasting game state update with %d units marked for goal updates: %s" % [units_with_goal_changes.size(), str(units_with_goal_changes)], "NETWORK")
        
    # Assume one session for now
    var session_id = session_manager.sessions.keys()[0]
    var session = session_manager.get_session(session_id)

    # Loop through teams and send filtered state
    var teams_to_process = {} # team_id -> [peer_ids]
    for player_id in session.players:
        var player_data = session.players[player_id]
        var team_id = player_data.team_id
        var peer_id = player_data.peer_id
        if not teams_to_process.has(team_id):
            teams_to_process[team_id] = []
        teams_to_process[team_id].append(peer_id)

    for team_id in teams_to_process:
        var state = _gather_filtered_game_state_for_team(team_id)
        var peer_ids = teams_to_process[team_id]
        for peer_id in peer_ids:
            root_node.rpc_id(peer_id, "_on_game_state_update", state)
    
    # Clear the goal changes list after broadcasting
    if not units_with_goal_changes.is_empty():
        GameConstants.debug_print("ServerGameState - Clearing goal changes list after broadcast (%d units had changes): %s" % [units_with_goal_changes.size(), str(units_with_goal_changes)], "NETWORK")
    units_with_goal_changes.clear()

func _broadcast_ui_data() -> void:
    var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
    if not session_manager or session_manager.get_session_count() == 0:
        return

    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if not root_node:
        return
        
    # Gather UI data for all units
    var all_units_ui_data = {}
    for unit_id in units:
        var unit = units[unit_id]
        if is_instance_valid(unit):
            all_units_ui_data[unit_id] = {
                "last_action_scores": unit.last_action_scores if "last_action_scores" in unit else {},
                "last_state_variables": unit.last_state_variables if "last_state_variables" in unit else {},
                "current_reactive_state": unit.current_reactive_state if "current_reactive_state" in unit else "defend"
            }
    
    # This sends all UI data to all clients. It could be optimized to send only to clients that can see the units.
    # For now, this is fine as a first step.
    # DISABLED: Function doesn't exist and causes RPC errors
    # root_node.rpc("update_units_ui_data_rpc", all_units_ui_data)

func setup(logger_ref: Node, game_constants_ref, network_messages_ref) -> void:
    """Setup the server game state with dependencies"""
    logger = logger_ref
    game_constants = game_constants_ref
    network_messages = network_messages_ref
    
    # Fog of War setup
    visibility_manager = VisibilityManager.new()
    visibility_manager.name = "VisibilityManager"
    add_child(visibility_manager)
    visibility_manager.setup(Vector2(120, 120), 4.0) # Map size, cell size
    
    # Get system references from dependency container
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container:
        _log_info("ServerGameState", "Dependency container found, getting system references...")
        
        ai_command_processor = dependency_container.get_ai_command_processor()
        resource_manager = dependency_container.get_resource_manager()
        node_capture_system = dependency_container.get_node_capture_system()
        team_unit_spawner = dependency_container.get_team_unit_spawner()
        
        # Debug the team_unit_spawner specifically
        if team_unit_spawner:
            _log_info("ServerGameState", "TeamUnitSpawner successfully obtained: %s" % team_unit_spawner.name)
        else:
            _log_error("ServerGameState", "TeamUnitSpawner is null! Available children in DependencyContainer:")
            for child in dependency_container.get_children():
                _log_info("ServerGameState", "  - %s" % child.name)
            
            # Try to find it manually
            var manual_spawner = dependency_container.get_node_or_null("TeamUnitSpawner")
            if manual_spawner:
                _log_info("ServerGameState", "Found TeamUnitSpawner manually: %s" % manual_spawner.name)
                team_unit_spawner = manual_spawner
            else:
                _log_error("ServerGameState", "TeamUnitSpawner not found even manually")
        
        # Connect system signals
        _connect_system_signals()
        
        _log_info("ServerGameState", "Setup complete with all systems")
    else:
        _log_error("ServerGameState", "Cannot find DependencyContainer")

func _connect_system_signals() -> void:
    """Connect signals from all integrated systems"""
    var dependency_container = get_node("/root/DependencyContainer")
    
    # Connect AI system signals
    if ai_command_processor:
        ai_command_processor.plan_processed.connect(_on_ai_plan_processed)
        ai_command_processor.command_failed.connect(_on_ai_command_failed)
    
    # Connect PlanExecutor signals
    plan_executor = dependency_container.get_node_or_null("PlanExecutor")
    if plan_executor:
        plan_executor.speech_triggered.connect(_on_speech_triggered)
        plan_executor.unit_became_idle.connect(_on_unit_became_idle)

    # Connect resource manager signals
    if resource_manager:
        resource_manager.resource_changed.connect(_on_resource_changed)
    
    # Connect node capture system signals
    if node_capture_system:
        if not node_capture_system.victory_achieved.is_connected(_on_victory_achieved):
            node_capture_system.victory_achieved.connect(_on_victory_achieved)
    
    _log_info("ServerGameState", "System signals connected")

# AI System Integration
func _on_ai_plan_processed(plans: Array, message: String, originating_peer_id: int = -1) -> void:
    """Handle successful AI plan processing"""
    _log_info("ServerGameState", "AI plan processed successfully: %s" % message)
    
    # Determine which team received these commands
    var team_id = -1
    if not plans.is_empty():
        var first_plan = plans[0]
        var unit_id = first_plan.get("unit_id", "")
        if not unit_id.is_empty() and units.has(unit_id):
            var unit = units[unit_id]
            if is_instance_valid(unit):
                team_id = unit.team_id
    
    # Check team AI readiness for synchronized start
    if team_id != -1:
        _check_team_ai_readiness(team_id)
    
    # CRITICAL: Immediately broadcast game state to sync goal updates to clients
    # Don't wait for the next scheduled broadcast - goals need to be visible immediately
    _log_info("ServerGameState", "Broadcasting immediate state update after AI plan processing")
    _broadcast_game_state()
    
    # ALSO: Ensure host's client display manager updates immediately
    # This ensures goals are visible on the host side without waiting for network loop-back
    var client_display_manager = get_node_or_null("/root/UnifiedMain/ClientDisplayManager")
    if client_display_manager:
        # Find the host's actual team ID instead of hardcoding team 1
        var host_team_id = _get_host_team_id()
        if host_team_id != -1:
            var current_state = _gather_filtered_game_state_for_team(host_team_id)
            client_display_manager.update_state(current_state)
            _log_info("ServerGameState", "Updated host client display manager with new goal data for team %d" % host_team_id)
        else:
            _log_warning("ServerGameState", "Could not determine host team ID, skipping immediate host update")
    
    # Send AI command feedback only to the originating peer (not broadcast to all)
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node and originating_peer_id != -1:
        # Include coordination status in feedback message
        var coordination_status = ""
        if match_started_but_waiting_for_commands:
            var readiness_status = get_team_ai_readiness_status()
            var waiting_teams = []
            for tracked_team_id in readiness_status:
                if readiness_status[tracked_team_id]["waiting_for_first_command"]:
                    waiting_teams.append("Team %d" % tracked_team_id)
            
            if not waiting_teams.is_empty():
                coordination_status = "\n[color=orange]Waiting for %s to receive commands...[/color]" % " and ".join(waiting_teams)
            else:
                coordination_status = "\n[color=green]All teams ready - match starting![/color]"
        
        root_node.rpc_id(originating_peer_id, "_on_ai_command_feedback_rpc", 
            message + coordination_status, "[color=green]✓ Command processed[/color]")
    elif root_node and originating_peer_id == -1:
        # Fallback for backward compatibility - send to all clients if peer_id not specified
        var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
        if session_manager and session_manager.get_session_count() > 0:
            var session_id = session_manager.sessions.keys()[0]
            var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
            for peer_id in peer_ids:
                root_node.rpc_id(peer_id, "_on_ai_command_feedback_rpc", message, "[color=green]✓ Command processed[/color]")

func _on_ai_command_failed(error: String, p_unit_ids: Array, originating_peer_id: int = -1) -> void:
    """Handle failed AI command processing"""
    _log_warning("ServerGameState", "AI command failed for units %s: %s" % [str(p_unit_ids), error])
    
    # Send AI command failure feedback only to the originating peer (not broadcast to all)
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node and originating_peer_id != -1:
        root_node.rpc_id(originating_peer_id, "_on_ai_command_feedback_rpc", "[color=red]Error: %s[/color]" % error, "[color=red]✗ Command failed[/color]")
    elif root_node and originating_peer_id == -1:
        # Fallback for backward compatibility - send to all clients if peer_id not specified
        var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
        if session_manager and session_manager.get_session_count() > 0:
            var session_id = session_manager.sessions.keys()[0]
            var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
            for peer_id in peer_ids:
                root_node.rpc_id(peer_id, "_on_ai_command_feedback_rpc", "[color=red]Error: %s[/color]" % error, "[color=red]✗ Command failed[/color]")

# Resource System Integration
func _on_resource_changed(team_id: int, resource_type: int, current_amount: int) -> void:
    """Handle resource changes"""
    var resource_type_str = "energy" # Assuming only energy for now (enum 0)
    #_log_info("ServerGameState", "Resource changed: Team %d, %s: %d" % [team_id, resource_type_str, current_amount])
    
    # Update cached resource data
    if team_id not in resource_data:
        resource_data[team_id] = {}
    
    resource_data[team_id][resource_type_str] = {
        "current": current_amount,
        "change": 0 # Cannot determine change from this signal alone
    }
    
    # Broadcast to clients
    _broadcast_resource_update(team_id)

func _on_resource_generated(_team_id: int, _resource_type: String, _amount: int) -> void:
    """Handle resource generation"""
    # Update cached data (already handled by _on_resource_changed)
    pass

# Control Point System Integration
func _on_control_point_captured(control_point_id: int, team_id: int, capture_progress: float) -> void:
    """Handle control point capture"""
    _log_info("ServerGameState", "Control point captured: Point %d by Team %d" % [control_point_id, team_id])
    
    # Update cached control point data
    control_points_data[control_point_id] = {
        "team_id": team_id,
        "status": "controlled",
        "capture_progress": capture_progress
    }
    
    # Broadcast to clients
    _broadcast_control_point_update(control_point_id)
    
    # Send notification
    _broadcast_notification(team_id, "success", "Control Point %d captured!" % control_point_id)

func _on_control_point_contested(control_point_id: int, attacking_team: int, defending_team: int, progress: float) -> void:
    """Handle control point contested state"""
    _log_info("ServerGameState", "Control point contested: Point %d - Team %d vs Team %d (%.1f%%)" % [control_point_id, attacking_team, defending_team, progress * 100])
    
    # Update cached control point data
    control_points_data[control_point_id] = {
        "team_id": defending_team,
        "status": "contested",
        "capture_progress": progress,
        "attacking_team": attacking_team
    }
    
    # Broadcast to clients
    _broadcast_control_point_update(control_point_id)

func _on_victory_achieved(team_id: int) -> void:
    """Handle victory conditions"""
    _log_info("ServerGameState", "Victory achieved: Team %d via node control" % team_id)
    
    # Set match state
    match_state = "ended"
    
    # Collect match statistics
    var match_data = _collect_match_statistics(team_id)
    
    # Broadcast victory to all clients
    _broadcast_match_ended(team_id, match_data)
    
    emit_signal("match_ended", team_id)

func _collect_match_statistics(winning_team: int) -> Dictionary:
    """Collect match statistics for victory screen"""
    var stats = {}
    
    # Match duration
    stats["duration"] = game_time
    
    # Team control counts from node capture system
    if node_capture_system:
        stats["team_control_counts"] = node_capture_system.get_team_control_counts()
    else:
        stats["team_control_counts"] = {1: 0, 2: 0, 0: 9}
    
    # Victory type
    stats["victory_type"] = "node_control"
    
    # Winning team
    stats["winning_team"] = winning_team
    
    return stats

func _broadcast_match_ended(winning_team: int, match_data: Dictionary) -> void:
    """Broadcast match ended to all clients"""
    _log_info("ServerGameState", "Broadcasting match end: Team %d wins" % winning_team)
    
    # Get all clients to send victory screen to
    var session_manager = get_node("/root/DependencyContainer").get_node_or_null("SessionManager")
    if not session_manager or session_manager.get_session_count() == 0:
        _log_warning("ServerGameState", "No session manager or sessions available for match end broadcast")
        return

    var session_id = session_manager.sessions.keys()[0]
    var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
    
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if not root_node:
        _log_error("ServerGameState", "Cannot find UnifiedMain for victory screen RPC")
        return
    
    # Send victory screen RPC to all clients
    for peer_id in peer_ids:
        root_node.rpc_id(peer_id, "_on_match_ended_rpc", winning_team, match_data)
        _log_info("ServerGameState", "Sent victory screen to peer %d" % peer_id)

func _on_unit_became_idle(_unit_id: String):
    # This is a hook for potential future autonomous behavior, currently disabled.
    pass

# Broadcasting methods
func _broadcast_ai_progress_update(unit_id: String) -> void:
    """Broadcast AI progress update to all clients"""
    if unit_id in ai_progress_data:
        var progress_data = ai_progress_data[unit_id]
        
        # Send to all clients via EventBus
        var event_bus = _get_event_bus()
        if event_bus:
            event_bus.emit_signal("plan_progress_updated", unit_id, progress_data)

func _broadcast_resource_update(team_id: int) -> void:
    """Broadcast resource update to all clients"""
    if team_id in resource_data:
        var resources = resource_data[team_id]
        
        # Send to all clients via EventBus
        var event_bus = _get_event_bus()
        if event_bus:
            event_bus.emit_signal("resource_updated", team_id, resources)

func _broadcast_control_point_update(control_point_id: int) -> void:
    """Broadcast control point update to all clients"""
    if control_point_id in control_points_data:
        var control_point_data = control_points_data[control_point_id]
        
        # Send to all clients via EventBus
        var event_bus = _get_event_bus()
        if event_bus:
            event_bus.emit_signal("control_point_updated", control_point_id, control_point_data)

func _broadcast_notification(team_id: int, type: String, message: String) -> void:
    """Broadcast notification to team clients"""
    var notification_data = {
        "type": type,
        "message": message,
        "timestamp": Time.get_ticks_msec()
    }
    
    # Send to all clients via EventBus
    var event_bus = _get_event_bus()
    if event_bus:
        event_bus.emit_signal("notification_received", team_id, notification_data)



func _on_speech_triggered(unit_id: String, speech_text: String) -> void:
    var unit = units.get(unit_id)
    if not is_instance_valid(unit): return

    var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
    if not session_manager or session_manager.get_session_count() == 0: return

    # Find the session this unit is in to get the correct peers
    # For now, we assume a single session
    var session_id = session_manager.sessions.keys()[0]
    var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
    
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if root_node:
        for peer_id in peer_ids:
            # Tell the client to display the speech bubble
            root_node.rpc_id(peer_id, "display_speech_bubble_rpc", unit_id, speech_text)

func _trigger_unit_speech(unit_id: String, message: String) -> void:
    """Trigger unit speech bubble"""
    var unit = units.get(unit_id)
    if unit:
        var team_id = unit.team_id
        
        # Send to all clients via EventBus
        var event_bus = _get_event_bus()
        if event_bus:
            event_bus.emit_signal("unit_speech_requested", unit_id, message, team_id)

func add_player(player_id: String, peer_id: int, player_name: String, team_id: int) -> void:
    if player_id in players:
        _log_warning("ServerGameState", "Player %s already exists." % player_id)
        return
    
    players[player_id] = {
        "peer_id": peer_id,
        "name": player_name,
        "team_id": team_id,
        "units": [],
        "buildings": []
    }
    
    _log_info("ServerGameState", "Added player %s (Peer: %d, Team: %d)" % [player_name, peer_id, team_id])

func spawn_unit(archetype: String, team_id: int, position: Vector3, owner_id: String) -> String:
    _log_info("ServerGameState", "spawn_unit called: archetype=%s, team_id=%d, position=%s, owner_id=%s" % [archetype, team_id, position, owner_id])
    
    if not team_unit_spawner:
        _log_error("ServerGameState", "TeamUnitSpawner not available.")
        
        # Try to get it again from dependency container as a fallback
        var dependency_container = get_node("/root/DependencyContainer")
        if dependency_container:
            _log_info("ServerGameState", "Attempting to retrieve TeamUnitSpawner again from dependency container...")
            team_unit_spawner = dependency_container.get_team_unit_spawner()
            
            if team_unit_spawner:
                _log_info("ServerGameState", "Successfully retrieved TeamUnitSpawner on retry: %s" % team_unit_spawner.name)
            else:
                _log_error("ServerGameState", "TeamUnitSpawner still null after retry attempt")
                return ""
        else:
            _log_error("ServerGameState", "Cannot find DependencyContainer for fallback retrieval")
            return ""
    
    _log_info("ServerGameState", "About to spawn unit with TeamUnitSpawner: %s" % team_unit_spawner.name)
    
    GameConstants.debug_print("ServerGameState - Calling team_unit_spawner.spawn_unit for %s" % archetype, "NETWORK")
    var unit = await team_unit_spawner.spawn_unit(team_id, position, archetype)
    GameConstants.debug_print("ServerGameState - team_unit_spawner.spawn_unit returned: %s" % unit, "NETWORK")
    
    if unit and is_instance_valid(unit):
        var unit_id = ""
        if "unit_id" in unit:
            unit_id = unit.unit_id
        elif unit.has_method("get"):
            unit_id = unit.get("unit_id", "")
        else:
            # Fallback ID generation using archetype and team
            unit_id = _generate_fallback_unit_id(archetype, team_id)
            
        GameConstants.debug_print("ServerGameState - Unit ID determined as: '%s'" % unit_id, "NETWORK")
            
        if not unit_id.is_empty():
            units[unit_id] = unit
            
            if owner_id in players:
                players[owner_id].units.append(unit_id)
            
            if unit.has_signal("unit_died"):
                unit.unit_died.connect(_on_unit_died)
            
            if unit.has_signal("unit_respawned"):
                unit.unit_respawned.connect(_on_unit_respawned)
            
            unit_spawned.emit(unit_id)
            _log_info("ServerGameState", "Added unit %s (%s) to game state for team %d" % [unit_id, archetype, team_id])
            GameConstants.debug_print("ServerGameState - Successfully spawned and registered unit %s" % unit_id, "NETWORK")
            return unit_id

    _log_error("ServerGameState", "Failed to spawn unit or unit initialization failed for archetype %s." % archetype)
    GameConstants.debug_print("ServerGameState - FAILED to spawn unit for archetype %s" % archetype, "NETWORK")
    return ""

func _on_unit_died(unit_id: String):
    if units.has(unit_id):
        var unit = units[unit_id]
        # Turrets are destroyed permanently and do not respawn.
        if is_instance_valid(unit) and unit.archetype == "turret":
            _log_info("ServerGameState", "Turret %s destroyed permanently." % unit_id)
            units.erase(unit_id) # Remove from state, it won't respawn
        else:
            _log_info("ServerGameState", "Unit %s died and will remain in scene for respawning." % unit_id)
            # The unit's 'is_dead' flag is now true and will be broadcast in the next state update.
            # No need to remove it from the 'units' dictionary for respawning units.
        
        unit_destroyed.emit(unit_id)

func _on_unit_respawned(unit_id: String):
    if units.has(unit_id):
        _log_info("ServerGameState", "Unit %s has respawned and is back in action." % unit_id)
        # The unit's 'is_dead' flag is now false and will be broadcast in the next state update.
        # Unit remains in the 'units' dictionary and is fully functional again.

# Removed team relative transformation functions as they are no longer needed

func _convert_team_ids_to_readable(data: Dictionary, requesting_team: int) -> Dictionary:
    """Convert numerical team IDs to 'ours'/'enemy' for better LLM understanding"""
    var converted_data = data.duplicate()
    
    # Convert team_id field
    if converted_data.has("team_id"):
        var team_id = converted_data["team_id"]
        if team_id == requesting_team:
            converted_data["team_id"] = "ours"
        elif team_id == 0:
            converted_data["team_id"] = "neutral"
        else:
            converted_data["team_id"] = "enemy"
    
    # Convert controlling_team field
    if converted_data.has("controlling_team"):
        var team_id = converted_data["controlling_team"]
        if team_id == requesting_team:
            converted_data["controlling_team"] = "ours"
        elif team_id == 0:
            converted_data["controlling_team"] = "neutral"
        else:
            converted_data["controlling_team"] = "enemy"
    
    return converted_data

func get_group_context_for_ai(p_units: Array) -> Dictionary:
    if p_units.is_empty():
        return {}

    var requesting_team = p_units[0].team_id if not p_units.is_empty() else 1

    _log_info("ServerGameState", "get_group_context_for_ai called with %d units for team %d" % [p_units.size(), requesting_team])
    
    # Debug: Log all input units
    for unit in p_units:
        if is_instance_valid(unit):
            _log_info("ServerGameState", "  Input unit: %s (%s)" % [unit.unit_id, unit.archetype])

    # 1. Global State (get once)
    var controlled_nodes = {
        "ours": [],
        "enemy": [],
        "neutral": []
    }
    
    if node_capture_system and not node_capture_system.control_points.is_empty():
        for cp in node_capture_system.control_points:
            if not is_instance_valid(cp):
                continue
                
            var controlling_team = cp.get_controlling_team()
            var node_name = cp.control_point_name if not cp.control_point_name.is_empty() else cp.control_point_id
            
            if controlling_team == requesting_team:
                controlled_nodes["ours"].append(node_name)
            elif controlling_team == 0:
                controlled_nodes["neutral"].append(node_name)
            else:
                controlled_nodes["enemy"].append(node_name)
    
    var global_state = {
        "game_time_sec": round(game_time * 100.0) / 100.0,
        "team_resources": team_resources.get(requesting_team, {}),
        "controlled_nodes": controlled_nodes
    }

    # 2. Allied Units' States (using direct world positions)
    var group_allies = []
    var turrets_filtered = 0
    for unit in p_units:
        if is_instance_valid(unit):
            # Skip turrets - they operate autonomously and shouldn't be included in AI strategic planning
            if unit.archetype == "turret":
                turrets_filtered += 1
                _log_info("ServerGameState", "  Filtered out turret: %s" % unit.unit_id)
                continue
            var unit_info = unit.get_unit_info()
            # Convert team_id to "ours"/"enemy"
            unit_info = _convert_team_ids_to_readable(unit_info, requesting_team)
            group_allies.append(unit_info)
            _log_info("ServerGameState", "  Added mobile unit to context: %s (%s)" % [unit.unit_id, unit.archetype])
    
    _log_info("ServerGameState", "Final AI context: %d mobile units, %d turrets filtered out" % [group_allies.size(), turrets_filtered])

    # 3. Consolidated Sensor Data
    var group_enemies = {} # Use dict to avoid duplicates by ID
    var group_allies_sensed = {} # For other allies not in the group
    
    for unit in p_units:
        if not is_instance_valid(unit): continue
        
        for other_unit_id in units:
            var other_unit = units[other_unit_id]
            if not is_instance_valid(other_unit) or other_unit == unit: continue
            
            var dist = unit.global_position.distance_to(other_unit.global_position)
            if dist < unit.vision_range:
                var other_info = other_unit.get_unit_info()
                other_info["dist"] = round(dist * 100.0) / 100.0
                # Convert team_id to "ours"/"enemy"
                other_info = _convert_team_ids_to_readable(other_info, requesting_team)
                
                if other_unit.team_id != unit.team_id:
                    if not other_info.get("is_stealthed", false):
                        if not group_enemies.has(other_unit_id):
                            group_enemies[other_unit_id] = other_info
                else:
                    var is_in_group = false
                    for group_unit in p_units:
                        if group_unit.unit_id == other_unit_id:
                            is_in_group = true
                            break
                    if not is_in_group and not group_allies_sensed.has(other_unit_id):
                        group_allies_sensed[other_unit_id] = other_info

    var sorted_enemies = group_enemies.values()
    if not sorted_enemies.is_empty():
        sorted_enemies.sort_custom(func(a, b): return a.dist < b.dist)
        
    var sorted_allies = group_allies_sensed.values()
    if not sorted_allies.is_empty():
        sorted_allies.sort_custom(func(a, b): return a.dist < b.dist)

    # 4. Control Points (using direct world positions)
    var group_control_points = []
    if node_capture_system and not node_capture_system.control_points.is_empty():
        for cp in node_capture_system.control_points:
            if is_instance_valid(cp):
                var cp_info = {
                    "id": cp.control_point_id,
                    #"position": [cp.global_position.x, cp.global_position.y, cp.global_position.z],
                    "controlling_team": cp.get_controlling_team(),
                    "capture_value": round(cp.capture_value * 100.0) / 100.0
                }
                # Convert controlling_team to "ours"/"enemy"
                cp_info = _convert_team_ids_to_readable(cp_info, requesting_team)
                group_control_points.append(cp_info)

    # Assemble the final context
    var group_context = {
        "global_state": global_state,
        "allied_units": group_allies,
        #"sensor_data": {
        #    "visible_enemies": sorted_enemies,
        #    "visible_allies": sorted_allies, # Other allies visible to the group
        #    "visible_control_points": group_control_points
        #}
    }
    
    return group_context

func _get_plan_info_for_unit(unit_id: String) -> Dictionary:
    """Helper method to extract current plan information for a unit for the AI context."""
    var unit = units.get(unit_id)
    if not unit:
        return {}

    # In the new behavior matrix system, return the current reactive state and goal
    var plan_context = {
        "current_reactive_state": unit.current_reactive_state if "current_reactive_state" in unit else "defend",
        "strategic_goal": unit.strategic_goal if "strategic_goal" in unit else "",
        "control_point_attack_sequence": unit.control_point_attack_sequence if "control_point_attack_sequence" in unit else []
    }

    return plan_context

func set_match_state(new_state: String) -> void:
    """Set the match state"""
    match_state = new_state
    if new_state == "active":
        # When match becomes active, initialize team AI coordination
        _initialize_team_ai_coordination()
    _log_info("ServerGameState", "Match state changed to: %s" % new_state)

func _initialize_team_ai_coordination() -> void:
    """Initialize team-level AI command coordination for synchronized start"""
    teams_awaiting_first_command.clear()
    
    # Identify which teams have players and mobile units (excluding turrets)
    var active_teams = {}
    for unit_id in units:
        var unit = units[unit_id]
        if is_instance_valid(unit) and unit.archetype != "turret":
            active_teams[unit.team_id] = true
    
    # Mark all teams as awaiting first command
    for team_id in active_teams:
        teams_awaiting_first_command[team_id] = true
    
    match_started_but_waiting_for_commands = true
    
    _log_info("ServerGameState", "Initialized AI coordination for teams: %s" % str(active_teams.keys()))
    _log_info("ServerGameState", "All mobile units will wait until both teams receive their first AI commands (turrets excluded)")
    GameConstants.debug_print("ServerGameState", "Synchronized start initialized - teams_awaiting_first_command: %s" % str(teams_awaiting_first_command))
    GameConstants.debug_print("ServerGameState", "match_started_but_waiting_for_commands = true")

func _check_team_ai_readiness(team_id: int) -> void:
    """Check if a team has received their first AI commands and handle synchronized release"""
    if not teams_awaiting_first_command.has(team_id):
        GameConstants.debug_print("ServerGameState", "Team %d not tracked for synchronized start" % team_id)
        return  # Team not tracked or already processed
    
    # Mark this team as having received their first command
    teams_awaiting_first_command[team_id] = false
    _log_info("ServerGameState", "Team %d has received their first AI commands" % team_id)
    GameConstants.debug_print("ServerGameState", "Team %d marked ready - teams_awaiting_first_command now: %s" % [team_id, str(teams_awaiting_first_command)])
    
    # Check if all teams have received their first commands
    var all_teams_ready = true
    for tracked_team_id in teams_awaiting_first_command:
        if teams_awaiting_first_command[tracked_team_id]:
            all_teams_ready = false
            break
    
    GameConstants.debug_print("ServerGameState", "All teams ready check: %s" % str(all_teams_ready))
    
    if all_teams_ready and match_started_but_waiting_for_commands:
        _log_info("ServerGameState", "ALL TEAMS READY - Releasing units to begin coordinated match!")
        GameConstants.debug_print("ServerGameState", "Calling _release_all_units_for_synchronized_start()")
        _release_all_units_for_synchronized_start()

func _release_all_units_for_synchronized_start() -> void:
    """Release all mobile units from waiting state for synchronized match start"""
    GameConstants.debug_print("ServerGameState", "_release_all_units_for_synchronized_start() called")
    match_started_but_waiting_for_commands = false
    var units_released = 0
    
    # Release all mobile units that are waiting for first command (exclude turrets)
    for unit_id in units:
        var unit = units[unit_id]
        if is_instance_valid(unit) and unit.archetype != "turret":
            if "waiting_for_first_command" in unit and unit.waiting_for_first_command:
                # Force enable AI behavior for synchronized start
                unit.waiting_for_first_command = false
                unit.has_received_first_command = true
                units_released += 1
                GameConstants.debug_print("ServerGameState", "Released unit %s (%s) from waiting state" % [unit.unit_id, unit.archetype])
    
    _log_info("ServerGameState", "Released %d mobile units for synchronized match start (turrets remain autonomous)" % units_released)
    GameConstants.debug_print("ServerGameState", "Total units released: %d, match_started_but_waiting_for_commands = false" % units_released)
    
    # Broadcast immediate state update to show the coordination
    _broadcast_game_state()
    
    # Notify all players about the synchronized start
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        # Get all peer IDs from session manager
        var session_manager = get_node("/root/DependencyContainer").get_node_or_null("SessionManager")
        if session_manager and session_manager.get_session_count() > 0:
            var session_id = session_manager.sessions.keys()[0]
            var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
            for peer_id in peer_ids:
                root_node.rpc_id(peer_id, "_on_ai_command_feedback_rpc", 
                    "Synchronized start activated - both teams are ready!", 
                    "[color=yellow]⚡ Match begins now![/color]")

func get_team_ai_readiness_status() -> Dictionary:
    """Get current AI readiness status for all teams"""
    var status = {}
    for team_id in teams_awaiting_first_command:
        var is_waiting = teams_awaiting_first_command[team_id]
        status[team_id] = {
            "waiting_for_first_command": is_waiting,
            "status": "Ready" if not is_waiting else "Awaiting AI commands"
        }
    return status

func _generate_fallback_unit_id(archetype: String, team_id: int) -> String:
    """Generate a fallback unit ID when unit doesn't have one"""
    # Use a simple counter approach for fallback
    var counter_key = "%s_t%d" % [archetype, team_id]
    var counter = units.size() + 1  # Simple fallback counter
    return "%s_%02d_fallback" % [counter_key, counter]

func mark_unit_goal_changed(unit_id: String) -> void:
    """Mark a unit as having goal/sequence changes that need to be sent to clients"""
    if not units_with_goal_changes.has(unit_id):
        units_with_goal_changes.append(unit_id)
        _log_info("ServerGameState", "Marked unit %s for goal update broadcast" % unit_id)

func _check_and_cache_unit_goal_changes(unit_id: String, unit: Node) -> bool:
    """Check if unit's goals have changed since last cache and update cache. Returns true if changed."""
    var current_goal = unit.strategic_goal if "strategic_goal" in unit else ""
    var current_sequence = unit.control_point_attack_sequence if "control_point_attack_sequence" in unit else []
    var current_index = unit.current_attack_sequence_index if "current_attack_sequence_index" in unit else 0
    
    # Check if this is the first time we're caching this unit's data
    var is_first_time = not unit_goal_cache.has(unit_id)
    
    var cached_data = unit_goal_cache.get(unit_id, {})
    var cached_goal = cached_data.get("strategic_goal", "")
    var cached_sequence = cached_data.get("control_sequence", [])
    var cached_index = cached_data.get("sequence_index", 0)
    
    # Check if anything changed
    var has_changes = (current_goal != cached_goal or 
                      not _arrays_equal(current_sequence, cached_sequence) or 
                      current_index != cached_index)
    
    # Always treat first-time caching as a change (for initial goal setting)
    if is_first_time and not current_goal.is_empty():
        has_changes = true
        GameConstants.debug_print("ServerGameState", "First-time goal caching for unit %s: goal='%s', sequence=%s" % [unit_id, current_goal, current_sequence])
    
    if has_changes:
        GameConstants.debug_print("ServerGameState", "Goal change detected for unit %s: goal '%s' -> '%s', sequence %s -> %s" % [unit_id, cached_goal, current_goal, cached_sequence, current_sequence])
        # Update cache
        unit_goal_cache[unit_id] = {
            "strategic_goal": current_goal,
            "control_sequence": current_sequence.duplicate(),
            "sequence_index": current_index
        }
        return true
    
    return false

func _arrays_equal(arr1: Array, arr2: Array) -> bool:
    """Compare two arrays for equality"""
    if arr1.size() != arr2.size():
        return false
    for i in range(arr1.size()):
        if arr1[i] != arr2[i]:
            return false
    return true

func _get_host_team_id() -> int:
    """Determine the team ID of the host player"""
    var session_manager = get_node("/root/DependencyContainer").get_node_or_null("SessionManager")
    if not session_manager or session_manager.get_session_count() == 0:
        _log_warning("ServerGameState", "No session manager or sessions available to determine host team ID")
        return -1

    var session_id = session_manager.sessions.keys()[0]
    var session = session_manager.get_session(session_id)
    var host_peer_id = multiplayer.get_unique_id()

    # Find the host player by their peer ID
    for player_id in session.players:
        var player_data = session.players[player_id]
        if player_data.peer_id == host_peer_id:
            _log_info("ServerGameState", "Found host player %s (peer %d) on team %d" % [player_id, host_peer_id, player_data.team_id])
            return player_data.team_id

    _log_warning("ServerGameState", "Could not find host player (peer_id %d) in session" % host_peer_id)
    return -1