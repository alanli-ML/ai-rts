# ServerGameState.gd
# Server-authoritative game state manager
extends Node

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

# Signals
signal game_state_changed()
signal unit_spawned(unit_id: String)
signal unit_destroyed(unit_id: String)
signal match_ended(result: int)

var tick_counter: int = 0
const NETWORK_TICK_RATE = 2 # ~30 times per second if physics is 60fps

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
func _ready() -> void:
    # Systems will be initialized via dependency injection
    pass

func _physics_process(_delta: float) -> void:
    if match_state != "active":
        return

    tick_counter += 1
    if tick_counter >= NETWORK_TICK_RATE:
        tick_counter = 0
        _broadcast_game_state()

func _gather_game_state() -> Dictionary:
    var state = {
        "units": [],
        "mines": [],
        "control_points": []
    }
    
    var placeable_entity_manager = get_node("/root/DependencyContainer").get_placeable_entity_manager()
    if placeable_entity_manager:
        state.mines = placeable_entity_manager.get_all_mines_data()
        
    for unit_id in units:
        var unit = units[unit_id]
        if is_instance_valid(unit):
            var plan_summary = "Idle"
            var full_plan_data = []

            # The new behavior matrix system doesn't use sequential plans anymore
            # Plan summary comes from the unit's current reactive state
            if "current_reactive_state" in unit:
                plan_summary = unit.current_reactive_state.capitalize()

            var unit_data = {
                "id": unit.unit_id,
                "archetype": unit.archetype,
                "team_id": unit.team_id,
                "position": { "x": unit.global_position.x, "y": unit.global_position.y, "z": unit.global_position.z },
                "velocity": { "x": unit.velocity.x, "y": unit.velocity.y, "z": unit.velocity.z },
                "basis": {
                    "x": [unit.transform.basis.x.x, unit.transform.basis.x.y, unit.transform.basis.x.z],
                    "y": [unit.transform.basis.y.x, unit.transform.basis.y.y, unit.transform.basis.y.z],
                    "z": [unit.transform.basis.z.x, unit.transform.basis.z.y, unit.transform.basis.z.z]
                },
                "current_state": unit.current_state,
                "health": unit.current_health,
                "current_health": unit.current_health,
                "max_health": unit.max_health,
                "is_dead": unit.is_dead,
                "is_respawning": unit.is_respawning,
                "respawn_timer": unit.respawn_timer if "respawn_timer" in unit else 0.0,
                "is_stealthed": unit.is_stealthed if "is_stealthed" in unit else false,
                "shield_active": false,
                "shield_pct": 0.0,
                "plan_summary": plan_summary,
                "full_plan": full_plan_data,
                "strategic_goal": unit.strategic_goal,
                "control_point_attack_sequence": unit.control_point_attack_sequence if "control_point_attack_sequence" in unit else [],
                "current_attack_sequence_index": unit.current_attack_sequence_index if "current_attack_sequence_index" in unit else 0,
                "waiting_for_first_command": unit.waiting_for_first_command if "waiting_for_first_command" in unit else true,
                "has_received_first_command": unit.has_received_first_command if "has_received_first_command" in unit else false,
                "waiting_for_ai": false, # This is now deprecated
                "active_triggers": [],  # Deprecated - use behavior matrix data instead
                "all_triggers": {},     # Deprecated - use behavior matrix data instead
                # New behavior data for UI
                "behavior_matrix": unit.behavior_matrix if "behavior_matrix" in unit else {},
                "last_action_scores": unit.last_action_scores if "last_action_scores" in unit else {},
                "last_state_variables": unit.last_state_variables if "last_state_variables" in unit else {},
                "current_reactive_state": unit.current_reactive_state if "current_reactive_state" in unit else "defend"
            }
            
            # Add charge shot data for sniper units
            if unit.archetype == "sniper" and unit.current_state == GameEnums.UnitState.CHARGING_SHOT:
                if "charge_timer" in unit and "charge_time" in unit:
                    unit_data["charge_timer"] = unit.charge_timer
                    unit_data["charge_time"] = unit.charge_time
            if unit.has_method("get") and "shield_active" in unit:
                unit_data["shield_active"] = unit.shield_active
                if unit.max_shield_health > 0:
                    unit_data["shield_pct"] = (unit.shield_health / unit.max_shield_health) * 100.0
            state.units.append(unit_data)

    if node_capture_system and not node_capture_system.control_points.is_empty():
        for cp in node_capture_system.control_points:
            if is_instance_valid(cp):
                state.control_points.append({
                    "id": cp.control_point_id,
                    "team_id": cp.get_controlling_team(),
                    "capture_value": cp.capture_value
                })
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

func _broadcast_game_state() -> void:
    var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
    if not session_manager or session_manager.get_session_count() == 0:
        return

    var state = _gather_game_state()
    
    # Assume one session for now
    var session_id = session_manager.sessions.keys()[0]
    var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
    
    var root_node = get_tree().get_root().get_node("UnifiedMain")
    if root_node:
        for peer_id in peer_ids:
            root_node.rpc_id(peer_id, "_on_game_state_update", state)

func setup(logger_ref: Node, game_constants_ref, network_messages_ref) -> void:
    """Setup the server game state with dependencies"""
    logger = logger_ref
    game_constants = game_constants_ref
    network_messages = network_messages_ref
    
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
    
    # CRITICAL: Immediately broadcast game state to sync goal updates to clients
    # Don't wait for the next scheduled broadcast - goals need to be visible immediately
    _log_info("ServerGameState", "Broadcasting immediate state update after AI plan processing")
    _broadcast_game_state()
    
    # ALSO: Ensure host's client display manager updates immediately
    # This ensures goals are visible on the host side without waiting for network loop-back
    var client_display_manager = get_node_or_null("/root/UnifiedMain/ClientDisplayManager")
    if client_display_manager:
        var current_state = _gather_game_state()
        client_display_manager.update_state(current_state)
        _log_info("ServerGameState", "Updated host client display manager with new goal data")
    
    # Send AI command feedback only to the originating peer (not broadcast to all)
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node and originating_peer_id != -1:
        root_node.rpc_id(originating_peer_id, "_on_ai_command_feedback_rpc", message, "[color=green]✓ Command completed[/color]")
    elif root_node and originating_peer_id == -1:
        # Fallback for backward compatibility - send to all clients if peer_id not specified
        var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
        if session_manager and session_manager.get_session_count() > 0:
            var session_id = session_manager.sessions.keys()[0]
            var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
            for peer_id in peer_ids:
                root_node.rpc_id(peer_id, "_on_ai_command_feedback_rpc", message, "[color=green]✓ Command completed[/color]")

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

func _on_victory_achieved(team_id: int, victory_type: String) -> void:
    """Handle victory conditions"""
    _log_info("ServerGameState", "Victory achieved: Team %d via %s" % [team_id, victory_type])
    
    # Set match state
    match_state = "ended"
    
    # Broadcast victory to all clients
    _broadcast_match_ended(team_id, victory_type)
    
    emit_signal("match_ended", team_id)

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

func _broadcast_match_ended(winning_team: int, victory_type: String) -> void:
    """Broadcast match ended to all clients"""
    var match_data = {
        "winning_team": winning_team,
        "victory_type": victory_type,
        "timestamp": Time.get_ticks_msec()
    }
    
    # Send to all clients via EventBus
    var event_bus = _get_event_bus()
    if event_bus:
        event_bus.emit_signal("match_ended", match_data)

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
    
    var unit = await team_unit_spawner.spawn_unit(team_id, position, archetype)
    if unit and is_instance_valid(unit):
        var unit_id = ""
        if "unit_id" in unit:
            unit_id = unit.unit_id
        elif unit.has_method("get"):
            unit_id = unit.get("unit_id", "")
        else:
            # Fallback ID generation using archetype and team
            unit_id = _generate_fallback_unit_id(archetype, team_id)
            
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
            return unit_id
    
    _log_error("ServerGameState", "Failed to spawn unit or unit initialization failed for archetype %s." % archetype)
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
    for unit in p_units:
        if is_instance_valid(unit):
            var unit_info = unit.get_unit_info()
            # Convert team_id to "ours"/"enemy"
            unit_info = _convert_team_ids_to_readable(unit_info, requesting_team)
            group_allies.append(unit_info)

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

func set_match_state(new_state: String):
    match_state = new_state
    _log_info("ServerGameState", "Match state changed to: %s" % new_state)

func _generate_fallback_unit_id(archetype: String, team_id: int) -> String:
    """Generate a fallback unit ID when unit doesn't have one"""
    # Use a simple counter approach for fallback
    var counter_key = "%s_t%d" % [archetype, team_id]
    var counter = units.size() + 1  # Simple fallback counter
    return "%s_%02d_fallback" % [counter_key, counter]

# Existing methods continue...