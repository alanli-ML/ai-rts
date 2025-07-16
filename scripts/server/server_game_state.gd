# ServerGameState.gd
# Server-authoritative game state manager
extends Node

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

var ai_think_timer: Timer
var tick_counter: int = 0
const NETWORK_TICK_RATE = 2 # ~30 times per second if physics is 60fps

func _ready() -> void:
    # Systems will be initialized via dependency injection
    ai_think_timer = Timer.new()
    ai_think_timer.name = "AIThinkTimer"
    ai_think_timer.wait_time = 2.0 # Each unit's AI thinks every 2 seconds
    ai_think_timer.timeout.connect(_on_ai_think_timer_timeout)
    add_child(ai_think_timer)

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
        "mines": []
    }
    
    var placeable_entity_manager = get_node("/root/DependencyContainer").get_placeable_entity_manager()
    if placeable_entity_manager:
        state.mines = placeable_entity_manager.get_all_mines_data()
        
    for unit_id in units:
        var unit = units[unit_id]
        if is_instance_valid(unit):
            var unit_data = {
                "id": unit.unit_id,
                "archetype": unit.archetype,
                "team_id": unit.team_id,
                "position": { "x": unit.global_position.x, "y": unit.global_position.y, "z": unit.global_position.z },
                "velocity": { "x": unit.velocity.x, "y": unit.velocity.y, "z": unit.velocity.z },
                "health": unit.current_health,
                "is_stealthed": unit.is_stealthed if "is_stealthed" in unit else false,
                "shield_active": false,
                "shield_pct": 0.0
            }
            if unit.has_method("get") and "shield_active" in unit:
                unit_data["shield_active"] = unit.shield_active
                if unit.max_shield_health > 0:
                    unit_data["shield_pct"] = (unit.shield_health / unit.max_shield_health) * 100.0
            state.units.append(unit_data)
    return state

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
        ai_command_processor = dependency_container.get_ai_command_processor()
        resource_manager = dependency_container.get_resource_manager()
        node_capture_system = dependency_container.get_node_capture_system()
        team_unit_spawner = dependency_container.get_team_unit_spawner()
        
        # Connect system signals
        _connect_system_signals()
        
        logger.info("ServerGameState", "Setup complete with all systems")
    else:
        logger.error("ServerGameState", "Cannot find DependencyContainer")

func _connect_system_signals() -> void:
    """Connect signals from all integrated systems"""
    var dependency_container = get_node("/root/DependencyContainer")
    
    # Connect AI system signals
    if ai_command_processor:
        ai_command_processor.plan_processed.connect(_on_ai_plan_processed)
        ai_command_processor.command_failed.connect(_on_ai_command_failed)
    
    # Connect PlanExecutor signals
    var plan_executor = dependency_container.get_node_or_null("PlanExecutor")
    if plan_executor:
        plan_executor.speech_triggered.connect(_on_speech_triggered)

    # Connect resource manager signals
    if resource_manager:
        resource_manager.resource_changed.connect(_on_resource_changed)
    
    # Connect node capture system signals
    if node_capture_system:
        if not node_capture_system.victory_achieved.is_connected(_on_victory_achieved):
            node_capture_system.victory_achieved.connect(_on_victory_achieved)
    
    logger.info("ServerGameState", "System signals connected")

# AI System Integration
func _on_ai_plan_processed(plans: Array, _message: String) -> void:
    """Handle AI plan creation"""
    for plan_data in plans:
        var unit_id = plan_data.get("unit_id")
        if unit_id.is_empty():
            continue
            
        logger.info("ServerGameState", "AI plan processed for unit %s" % unit_id)
        
        # Update AI progress data for clients
        ai_progress_data[unit_id] = {
            "plan_id": plan_data.get("plan_id", unit_id), # No plan_id anymore, use unit_id
            "status": "active",
            "progress": 0.0,
            "current_step": 0,
            "total_steps": plan_data.get("steps", []).size()
        }
        # Broadcast to clients
        _broadcast_ai_progress_update(unit_id)

func _on_ai_command_failed(error_message: String) -> void:
    logger.error("ServerGameState", "AI Command failed: %s" % error_message)
    # TODO: Broadcast failure to the relevant client
    
# Resource System Integration
func _on_resource_changed(team_id: int, resource_type: int, current_amount: int) -> void:
    """Handle resource changes"""
    var resource_type_str = "energy" # Assuming only energy for now (enum 0)
    logger.info("ServerGameState", "Resource changed: Team %d, %s: %d" % [team_id, resource_type_str, current_amount])
    
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
    logger.info("ServerGameState", "Control point captured: Point %d by Team %d" % [control_point_id, team_id])
    
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
    logger.info("ServerGameState", "Control point contested: Point %d - Team %d vs Team %d (%.1f%%)" % [control_point_id, attacking_team, defending_team, progress * 100])
    
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
    logger.info("ServerGameState", "Victory achieved: Team %d via %s" % [team_id, victory_type])
    
    # Set match state
    match_state = "ended"
    
    # Broadcast victory to all clients
    _broadcast_match_ended(team_id, victory_type)
    
    emit_signal("match_ended", team_id)

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
        logger.warning("ServerGameState", "Player %s already exists." % player_id)
        return
    
    players[player_id] = {
        "peer_id": peer_id,
        "name": player_name,
        "team_id": team_id,
        "units": [],
        "buildings": []
    }
    
    logger.info("ServerGameState", "Added player %s (Peer: %d, Team: %d)" % [player_name, peer_id, team_id])

func spawn_unit(archetype: String, team_id: int, position: Vector3, owner_id: String) -> String:
    if not team_unit_spawner:
        logger.error("ServerGameState", "TeamUnitSpawner not available.")
        return ""
    
    var unit = await team_unit_spawner.spawn_unit(team_id, position, archetype)
    if unit and is_instance_valid(unit) and not unit.unit_id.is_empty():
        units[unit.unit_id] = unit
        if owner_id in players:
            players[owner_id].units.append(unit.unit_id)
        
        if unit.has_signal("unit_died"):
            unit.unit_died.connect(_on_unit_died)
        
        unit_spawned.emit(unit.unit_id)
        logger.info("ServerGameState", "Added unit %s (%s) to game state for team %d" % [unit.unit_id, archetype, team_id])
        return unit.unit_id
    
    logger.error("ServerGameState", "Failed to spawn unit or unit initialization failed for archetype %s." % archetype)
    return ""

func _on_unit_died(unit_id: String):
    if units.has(unit_id):
        units.erase(unit_id)
        logger.info("ServerGameState", "Unit %s died and was removed from game state." % unit_id)
        
        # Broadcast removal to clients
        var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
        if not session_manager or session_manager.get_session_count() == 0: return

        var session_id = session_manager.sessions.keys()[0]
        var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
        
        var root_node = get_tree().get_root().get_node("UnifiedMain")
        if root_node:
            for peer_id in peer_ids:
                root_node.rpc_id(peer_id, "remove_unit_rpc", unit_id)
        
        unit_destroyed.emit(unit_id)

func get_context_for_ai(unit: Unit) -> Dictionary:
    if not is_instance_valid(unit):
        return {}

    # 1. Global State
    var global_state = {
        "game_time_sec": game_time,
        "team_resources": team_resources.get(unit.team_id, {}),
        "controlled_nodes": node_capture_system.team_control_counts if node_capture_system else {}
    }

    # 2. Unit's Own State
    var unit_state = unit.get_unit_info()

    # 3. Sensor Data (Visible Entities)
    var sensor_data = {
        "visible_enemies": [],
        "visible_allies": [],
        "visible_buildings": [],
        "visible_mines": [],
        "visible_control_points": [],
        "nearby_cover": [] # Placeholder for cover system
    }

    for other_unit_id in units:
        var other_unit = units[other_unit_id]
        if not is_instance_valid(other_unit) or other_unit == unit:
            continue

        # Simple distance-based "vision" check
        var dist = unit.global_position.distance_to(other_unit.global_position)
        if dist < 40.0: # Vision range
            # Check if target is stealthed
            if other_unit.team_id != unit.team_id and other_unit.get("is_stealthed", false):
                continue # Skip stealthed enemies

            var other_info = other_unit.get_unit_info()
            other_info["dist"] = dist
            if other_unit.team_id != unit.team_id:
                sensor_data.visible_enemies.append(other_info)
            else:
                sensor_data.visible_allies.append(other_info)
    
    # Sort by distance
    sensor_data.visible_enemies.sort_custom(func(a, b): return a.dist < b.dist)
    sensor_data.visible_allies.sort_custom(func(a, b): return a.dist < b.dist)

    var placeable_entity_manager = get_node("/root/DependencyContainer").get_placeable_entity_manager()
    if placeable_entity_manager:
        var all_mines = placeable_entity_manager.get_all_mines_data()
        for mine_data in all_mines:
            var mine_pos = Vector3(mine_data.position.x, mine_data.position.y, mine_data.position.z)
            var dist = unit.global_position.distance_to(mine_pos)
            if dist < 40.0: # Vision range
                var mine_info = mine_data.duplicate()
                mine_info["dist"] = dist
                sensor_data.visible_mines.append(mine_info)

    # Add control point data
    if node_capture_system and not node_capture_system.control_points.is_empty():
        for cp in node_capture_system.control_points:
            if is_instance_valid(cp):
                var dist = unit.global_position.distance_to(cp.global_position)
                var cp_data = {
                    "id": cp.control_point_id,
                    "name": cp.control_point_name,
                    "position": [cp.global_position.x, cp.global_position.y, cp.global_position.z],
                    "controlling_team": cp.get_controlling_team(),
                    "capture_value": cp.capture_value, # -1 (team 2) to 1 (team 1)
                    "dist": dist
                }
                sensor_data.visible_control_points.append(cp_data)
        
        # Sort by distance
        sensor_data.visible_control_points.sort_custom(func(a, b): return a.dist < b.dist)

    # 4. Team Context (simplified)
    var team_context = {
        "teammates_status": sensor_data.visible_allies, # For now, teammates are just visible allies
        "recent_player_commands": [] # Placeholder
    }

    # Assemble the final context object
    var full_context = {
        "global_state": global_state,
        "unit_state": unit_state,
        "sensor_data": sensor_data,
        "team_context": team_context
    }

    return full_context

func _on_ai_think_timer_timeout():
    if match_state != "active":
        return

    # Get idle units and request plans
    var plan_executor = get_node_or_null("/root/DependencyContainer/PlanExecutor")
    if not plan_executor:
        logger.error("ServerGameState", "PlanExecutor not found for AI thinking.")
        return

    for unit_id in units:
        # A unit is considered "idle" for autonomous action if it has no active plan.
        if not plan_executor.active_plans.has(unit_id) or plan_executor.active_plans.get(unit_id, []).is_empty():
            var unit = units[unit_id]
            if is_instance_valid(unit) and not unit.is_dead:
                logger.info("ServerGameState", "Requesting autonomous plan for idle unit %s" % unit_id)
                # Use a generic command for autonomous action.
                # The AICommandProcessor will see this and generate a suitable prompt.
                var unit_id_array: Array[String] = [unit_id]
                ai_command_processor.process_command("autonomously decide next action", unit_id_array)
                ai_command_processor.process_command("autonomously decide next action", unit_id_array)

func set_match_state(new_state: String):
    match_state = new_state
    logger.info("ServerGameState", "Match state changed to: %s" % new_state)
    
    if new_state == "active":
        if ai_think_timer: ai_think_timer.start()
    else:
        if ai_think_timer: ai_think_timer.stop()

# Existing methods continue...