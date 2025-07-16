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

var ai_think_timer: Timer
var tick_counter: int = 0
const NETWORK_TICK_RATE = 2 # ~30 times per second if physics is 60fps

# Autonomous command rate limiting
var units_waiting_for_ai: Dictionary = {}  # unit_id -> timestamp when request was sent
var last_autonomous_request_time: float = 0.0
var autonomous_request_cooldown: float = 5.0  # Don't send autonomous requests faster than every 5 seconds

func _ready() -> void:
    # Systems will be initialized via dependency injection
    ai_think_timer = Timer.new()
    ai_think_timer.name = "AIThinkTimer"
    ai_think_timer.wait_time = 10.0 # Each unit's AI thinks every 10 seconds
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

            if plan_executor:
                # 1. Process sequential plan for UI
                var active_plan = plan_executor.active_plans.get(unit_id, [])
                var current_step = plan_executor.current_steps.get(unit_id, null)
                var current_step_index = -1
                if current_step:
                    current_step_index = active_plan.find(current_step)

                for i in range(active_plan.size()):
                    var step = active_plan[i]
                    var action = step.get("action", "unknown")
                    var params = step.get("params", {})
                    var action_display = action.capitalize().replace("_", " ")
                    if params.has("target_id"):
                        action_display += " " + str(params.target_id).right(4)
                    elif params.has("position"):
                        action_display += " (%d, %d)" % [params.position[0], params.position[2]]

                    var step_status = "pending"
                    if i < current_step_index:
                        step_status = "completed"
                    elif i == current_step_index:
                        step_status = "active"
                    
                    full_plan_data.append({"action": action_display, "status": step_status, "trigger": ""})
                
                # Set plan summary from current sequential step
                if current_step:
                    plan_summary = full_plan_data[current_step_index].action

                # 2. Process triggered actions for UI
                var triggered_actions = plan_executor.active_triggered_actions.get(unit_id, [])
                for step in triggered_actions:
                    var action = step.get("action", "unknown")
                    var params = step.get("params", {})
                    var trigger = step.get("trigger", "")
                    var action_display = action.capitalize().replace("_", " ")
                    if params.has("target_id"):
                        action_display += " " + str(params.target_id).right(4)
                    
                    full_plan_data.append({"action": action_display, "status": "triggered", "trigger": trigger})

            var unit_data = {
                "id": unit.unit_id,
                "archetype": unit.archetype,
                "team_id": unit.team_id,
                "position": { "x": unit.global_position.x, "y": unit.global_position.y, "z": unit.global_position.z },
                "velocity": { "x": unit.velocity.x, "y": unit.velocity.y, "z": unit.velocity.z },
                "health": unit.current_health,
                "is_stealthed": unit.is_stealthed if "is_stealthed" in unit else false,
                "shield_active": false,
                "shield_pct": 0.0,
                "plan_summary": plan_summary,
                "full_plan": full_plan_data
            }
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
    plan_executor = dependency_container.get_node_or_null("PlanExecutor")
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
func _on_ai_plan_processed(plans: Array, message: String) -> void:
    """Handle successful AI plan processing"""
    logger.info("ServerGameState", "AI plan processed successfully: %s" % message)
    
    # Clear waiting status for units that got plans
    for plan_data in plans:
        var unit_id = plan_data.get("unit_id", "")
        if not unit_id.is_empty() and unit_id in units_waiting_for_ai:
            units_waiting_for_ai.erase(unit_id)
            logger.info("ServerGameState", "Cleared waiting status for unit %s" % unit_id)

func _on_ai_command_failed(error: String) -> void:
    """Handle failed AI command processing"""
    logger.warning("ServerGameState", "AI command failed: %s" % error)
    
    # Clear all waiting units since the command failed
    # We don't know which specific units were affected, so clear all to prevent permanent blocking
    if not units_waiting_for_ai.is_empty():
        logger.info("ServerGameState", "Clearing waiting status for %d units due to AI command failure" % units_waiting_for_ai.size())
        var cleared_units = units_waiting_for_ai.keys()
        units_waiting_for_ai.clear()
        logger.info("ServerGameState", "Cleared waiting units: %s" % cleared_units)

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
    if unit and is_instance_valid(unit):
        var unit_id = ""
        if "unit_id" in unit:
            unit_id = unit.unit_id
        elif unit.has_method("get"):
            unit_id = unit.get("unit_id", "")
        else:
            unit_id = "unit_" + str(randi())
            
        if not unit_id.is_empty():
            units[unit_id] = unit
            
            if owner_id in players:
                players[owner_id].units.append(unit_id)
            
            if unit.has_signal("unit_died"):
                unit.unit_died.connect(_on_unit_died)
            
            unit_spawned.emit(unit_id)
            logger.info("ServerGameState", "Added unit %s (%s) to game state for team %d" % [unit_id, archetype, team_id])
            return unit_id
    
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

    # 2. Unit's Own State (including current plan)
    var unit_state = unit.get_unit_info()
    if plan_executor:
        unit_state["action_queue"] = _get_plan_info_for_unit(unit.unit_id)

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
        if dist < unit.vision_range:
            var other_info = other_unit.get_unit_info()
            
            # Skip stealthed enemies
            if other_unit.team_id != unit.team_id and other_info.get("is_stealthed", false):
                continue

            other_info["dist"] = dist
            
            # Add plan information for visible units
            if plan_executor:
                var other_plan_info = _get_plan_info_for_unit(other_unit.unit_id)
                if not other_plan_info.is_empty():
                    other_info["current_plan"] = other_plan_info
            
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
                    "capture_value": cp.capture_value # -1 (team 2) to 1 (team 1)
                    #"dist": dist
                }
                sensor_data.visible_control_points.append(cp_data)
        
        # Sort by distance
        #sensor_data.visible_control_points.sort_custom(func(a, b): return a.dist < b.dist)

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

func _get_plan_info_for_unit(unit_id: String) -> Dictionary:
    """Helper method to extract current plan information for a unit for the AI context."""
    if not plan_executor:
        return {}

    var plan_context = {
        "steps": [],
        "triggered_actions": []
    }

    # Get sequential plan
    var active_plan = plan_executor.active_plans.get(unit_id, [])
    for step in active_plan:
        plan_context.steps.append(step)

    # Get triggered actions
    var triggered_actions = plan_executor.active_triggered_actions.get(unit_id, [])
    for step in triggered_actions:
        plan_context.triggered_actions.append(step)

    return plan_context

func _on_ai_think_timer_timeout():
    if match_state != "active":
        return

    # Get idle units and request plans
    var plan_executor = get_node_or_null("/root/DependencyContainer/PlanExecutor")
    if not plan_executor:
        logger.error("ServerGameState", "PlanExecutor not found for AI thinking.")
        return

    var current_time = Time.get_unix_time_from_system()
    
    # Clean up old waiting units (units that have been waiting too long)
    var units_to_remove = []
    for unit_id in units_waiting_for_ai:
        var wait_time = current_time - units_waiting_for_ai[unit_id]
        if wait_time > 60.0:  # 60 second timeout
            logger.warning("ServerGameState", "Unit %s has been waiting for AI response for %.1f seconds - clearing" % [unit_id, wait_time])
            units_to_remove.append(unit_id)
    
    for unit_id in units_to_remove:
        units_waiting_for_ai.erase(unit_id)
    
    # Check cooldown to prevent spam
    if current_time - last_autonomous_request_time < autonomous_request_cooldown:
        var remaining_cooldown = autonomous_request_cooldown - (current_time - last_autonomous_request_time)
        logger.info("ServerGameState", "Autonomous command cooldown active - %.1f seconds remaining" % remaining_cooldown)
        return
    
    # Find ALL idle units for group command
    var idle_units_by_team: Dictionary = {}  # team_id -> Array[String]
    
    for unit_id in units:
        # Skip units already waiting for AI response
        if unit_id in units_waiting_for_ai:
            continue
            
        # A unit is considered "idle" for autonomous action if it has no active plan.
        if not plan_executor.active_plans.has(unit_id) or plan_executor.active_plans.get(unit_id, []).is_empty():
            var unit = units[unit_id]
            if is_instance_valid(unit) and not unit.is_dead:
                var team_id = unit.team_id
                if not idle_units_by_team.has(team_id):
                    var typed_array: Array[String] = []
                    idle_units_by_team[team_id] = typed_array

                idle_units_by_team[team_id].append(unit_id)
    
    # Process autonomous commands for each team that has idle units
    for team_id in idle_units_by_team:
        var team_idle_units: Array[String] = idle_units_by_team[team_id]  # Properly type the variable
        
        if team_idle_units.size() > 0:
            logger.info("ServerGameState", "Requesting autonomous group plan for %d idle units from team %d: %s" % [team_idle_units.size(), team_id, team_idle_units])
            
            # Mark all units as waiting for AI response
            for unit_id in team_idle_units:
                units_waiting_for_ai[unit_id] = current_time
            
            last_autonomous_request_time = current_time
            
            # Send group command for autonomous action
            # Empty unit_ids array will trigger group command processing in AICommandProcessor
            ai_command_processor.process_command("autonomously coordinate team tactics", team_idle_units)
            
            # Only process one team per timer cycle to avoid overwhelming the AI
            break
    
    if idle_units_by_team.is_empty():
        logger.info("ServerGameState", "No idle units found for autonomous actions (total units: %d, waiting: %d)" % [units.size(), units_waiting_for_ai.size()])

func set_match_state(new_state: String):
    match_state = new_state
    logger.info("ServerGameState", "Match state changed to: %s" % new_state)
    
    if new_state == "active":
        if ai_think_timer: ai_think_timer.start()
    else:
        if ai_think_timer: ai_think_timer.stop()

# Existing methods continue...