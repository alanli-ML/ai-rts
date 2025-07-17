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

var ai_think_timer: Timer
var tick_counter: int = 0
const NETWORK_TICK_RATE = 2 # ~30 times per second if physics is 60fps

# Autonomous command rate limiting
var units_waiting_for_ai: Dictionary = {}  # unit_id -> timestamp when request was sent

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
var per_unit_autonomous_cooldown: float = 10.0 # Each unit can only request a plan every 10s
var unit_autonomous_cooldowns: Dictionary = {} # unit_id -> timestamp
var initial_group_command_given: bool = false

func _ready() -> void:
    # Systems will be initialized via dependency injection
    ai_think_timer = Timer.new()
    ai_think_timer.name = "AIThinkTimer"
    ai_think_timer.wait_time = 2.0 # Check for idle units every 2 seconds as a fallback
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
                var current_step_index = plan_executor.current_step_indices.get(unit_id, -1)
                var current_step = null
                if current_step_index >= 0 and current_step_index < active_plan.size():
                    current_step = active_plan[current_step_index]

                for i in range(active_plan.size()):
                    var step = active_plan[i]
                    var action = step.get("action", "unknown")
                    var params = step.get("params", {})
                    if params == null: params = {}
                    var action_display = action.capitalize().replace("_", " ")
                    if params.has("target_id") and params.target_id != null:
                        action_display += " " + str(params.target_id).right(4)
                    elif params.has("position") and params.position != null and params.position is Array and params.position.size() >= 3:
                        action_display += " (%d, %d)" % [int(params.position[0]), int(params.position[2])]

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
                var triggered_actions = unit.triggered_actions if "triggered_actions" in unit else {}
                for trigger_name in triggered_actions:
                    var action = triggered_actions[trigger_name]
                    
                    # Convert trigger name to human-readable format
                    var trigger_display = trigger_name.replace("_", " ").capitalize()
                    
                    var action_display = action.capitalize().replace("_", " ")
                    
                    full_plan_data.append({"action": action_display, "status": "triggered", "trigger": trigger_display})

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
                "is_stealthed": unit.is_stealthed if "is_stealthed" in unit else false,
                "shield_active": false,
                "shield_pct": 0.0,
                "plan_summary": plan_summary,
                "full_plan": full_plan_data,
                "strategic_goal": unit.strategic_goal,
                "waiting_for_ai": unit.unit_id in units_waiting_for_ai,
                "active_triggers": unit.get_current_active_triggers() if unit.has_method("get_current_active_triggers") else [],
                "all_triggers": unit.get_all_trigger_info() if unit.has_method("get_all_trigger_info") else {}
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
func _on_ai_plan_processed(plans: Array, message: String) -> void:
    """Handle successful AI plan processing"""
    _log_info("ServerGameState", "AI plan processed successfully: %s" % message)
    
    # Clear waiting status for units that got plans
    for plan_data in plans:
        var unit_id = plan_data.get("unit_id", "")
        if not unit_id.is_empty() and unit_id in units_waiting_for_ai:
            units_waiting_for_ai.erase(unit_id)
            _log_info("ServerGameState", "Cleared waiting status for unit %s" % unit_id)
    
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
    
    # Broadcast AI command feedback (summary message and status) to all clients
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        var session_manager = get_node("/root/DependencyContainer").get_node("SessionManager")
        if session_manager and session_manager.get_session_count() > 0:
            var session_id = session_manager.sessions.keys()[0]
            var peer_ids = session_manager.get_all_peer_ids_in_session(session_id)
            for peer_id in peer_ids:
                root_node.rpc_id(peer_id, "_on_ai_command_feedback_rpc", message, "[color=green]✓ Command completed[/color]")

func _on_ai_command_failed(error: String, p_unit_ids: Array) -> void:
    """Handle failed AI command processing"""
    _log_warning("ServerGameState", "AI command failed for units %s: %s" % [str(p_unit_ids), error])
    
    var units_to_clear = p_unit_ids
    if units_to_clear.is_empty():
        # If we don't know which units, clear all to be safe.
        units_to_clear = units_waiting_for_ai.keys()
        
    for unit_id in units_to_clear:
        if unit_id in units_waiting_for_ai:
            units_waiting_for_ai.erase(unit_id)
            _log_info("ServerGameState", "Cleared waiting status for unit %s due to AI command failure" % unit_id)
    
    # Broadcast AI command failure feedback to all clients
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
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

func _on_unit_became_idle(unit_id: String):
    # This is called immediately when a unit becomes idle.
    # The 10s timer is a fallback.
    _request_autonomous_plan_for_unit(unit_id)

func _request_autonomous_plan_for_unit(unit_id: String):
    # Do not allow autonomous actions until the player has issued their first group command.
    if not initial_group_command_given:
        return

    if not units.has(unit_id): return
    if unit_id in units_waiting_for_ai: return
    
    var current_time = Time.get_unix_time_from_system()

    # Check per-unit cooldown
    var last_unit_request_time = unit_autonomous_cooldowns.get(unit_id, 0.0)
    if current_time - last_unit_request_time < per_unit_autonomous_cooldown:
        return # Unit is on its own cooldown.
    
    _log_info("ServerGameState", "Requesting autonomous individual plan for unit %s" % unit_id)
    
    # Update cooldown timestamps
    unit_autonomous_cooldowns[unit_id] = current_time

    units_waiting_for_ai[unit_id] = current_time
    
    # The command "autonomously decide next action" will trigger an individual prompt in AICommandProcessor
    var unit_ids: Array[String] = [unit_id]
    ai_command_processor.process_command("autonomously decide next action", unit_ids)

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
        _log_info("ServerGameState", "Unit %s died and will remain in scene." % unit_id)
        # The unit's 'is_dead' flag is now true and will be broadcast in the next state update.
        # No need to remove it from the 'units' dictionary.
        unit_destroyed.emit(unit_id)

func _on_unit_respawned(unit_id: String):
    if units.has(unit_id):
        _log_info("ServerGameState", "Unit %s has respawned and is back in action." % unit_id)
        # The unit's 'is_dead' flag is now false and will be broadcast in the next state update.
        # Unit remains in the 'units' dictionary and is fully functional again.

func _get_team_transform(team_id: int) -> Transform3D:
    var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
    if not home_base_manager:
        _log_error("ServerGameState", "HomeBaseManager not found!")
        return Transform3D.IDENTITY

    var my_base_pos = home_base_manager.get_home_base_position(team_id)
    var enemy_team_id = 2 if team_id == 1 else 1
    var enemy_base_pos = home_base_manager.get_home_base_position(enemy_team_id)

    if my_base_pos == Vector3.ZERO or enemy_base_pos == Vector3.ZERO:
        _log_error("ServerGameState", "Home base positions not set up correctly.")
        return Transform3D.IDENTITY
        
    var forward_vec = (enemy_base_pos - my_base_pos).normalized()
    var right_vec = forward_vec.cross(Vector3.UP).normalized()
    var up_vec = right_vec.cross(forward_vec).normalized()

    return Transform3D(right_vec, up_vec, forward_vec, my_base_pos)

func _transform_pos_to_relative_array(world_pos: Vector3, transform: Transform3D) -> Array:
    var relative_pos = transform.affine_inverse() * world_pos
    # Round to keep the context clean for the LLM
    return [round(relative_pos.x), round(relative_pos.y), round(relative_pos.z)]

func _convert_to_team_relative_data(data: Dictionary, requesting_team_id: int) -> Dictionary:
    """Convert team IDs to relative values and round numeric values to 2 decimal places"""
    var converted_data = data.duplicate(true)
    
    # Convert team_id to relative value
    if converted_data.has("team_id"):
        var absolute_team_id = converted_data["team_id"]
        if absolute_team_id == requesting_team_id:
            converted_data["team_id"] = 1  # Our team
        elif absolute_team_id == 0:
            converted_data["team_id"] = 0  # Neutral
        else:
            converted_data["team_id"] = -1  # Enemy team
    
    # Round numeric values to 2 decimal places
    for key in converted_data:
        var value = converted_data[key]
        if value is float:
            converted_data[key] = round(value * 100.0) / 100.0
        elif value is Array:
            # Handle position arrays and other arrays with floats
            for i in range(value.size()):
                if value[i] is float:
                    value[i] = round(value[i] * 100.0) / 100.0
        elif value is Dictionary and key != "position":  # Don't recurse into position dict to avoid nested processing
            # Handle nested dictionaries like position objects
            for nested_key in value:
                if value[nested_key] is float:
                    value[nested_key] = round(value[nested_key] * 100.0) / 100.0
    
    return converted_data

func get_group_context_for_ai(p_units: Array) -> Dictionary:
    if p_units.is_empty():
        return {}

    var requesting_team = p_units[0].team_id if not p_units.is_empty() else 1
    var team_transform = _get_team_transform(requesting_team)

    # 1. Global State (get once)
    var global_state = {
        "game_time_sec": round(game_time * 100.0) / 100.0,
        "team_resources": team_resources.get(requesting_team, {}),
        "controlled_nodes": node_capture_system.team_control_counts if node_capture_system else {}
    }

    # 2. Allied Units' States (converted to team-relative)
    var group_allies = []
    for unit in p_units:
        if is_instance_valid(unit):
            var unit_info = unit.get_unit_info()
            unit_info["position"] = _transform_pos_to_relative_array(unit.global_position, team_transform)
            var converted_unit_info = _convert_to_team_relative_data(unit_info, requesting_team)
            group_allies.append(converted_unit_info)

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
                other_info["position"] = _transform_pos_to_relative_array(other_unit.global_position, team_transform)
                var converted_other_info = _convert_to_team_relative_data(other_info, requesting_team)

                converted_other_info["dist"] = round(dist * 100.0) / 100.0
                
                if other_unit.team_id != unit.team_id:
                    if not converted_other_info.get("is_stealthed", false):
                        if not group_enemies.has(other_unit_id):
                            group_enemies[other_unit_id] = converted_other_info
                else:
                    var is_in_group = false
                    for group_unit in p_units:
                        if group_unit.unit_id == other_unit_id:
                            is_in_group = true
                            break
                    if not is_in_group and not group_allies_sensed.has(other_unit_id):
                        group_allies_sensed[other_unit_id] = converted_other_info

    var sorted_enemies = group_enemies.values()
    if not sorted_enemies.is_empty():
        sorted_enemies.sort_custom(func(a, b): return a.dist < b.dist)
        
    var sorted_allies = group_allies_sensed.values()
    if not sorted_allies.is_empty():
        sorted_allies.sort_custom(func(a, b): return a.dist < b.dist)

    # 4. Control Points (get once, adjusted relative to team)
    var group_control_points = []
    if node_capture_system and not node_capture_system.control_points.is_empty():
        for cp in node_capture_system.control_points:
            if is_instance_valid(cp):
                var absolute_controlling_team = cp.get_controlling_team()
                var absolute_capture_value = cp.capture_value
                
                var relative_controlling_team = 0
                if absolute_controlling_team == requesting_team:
                    relative_controlling_team = 1
                elif absolute_controlling_team != 0:
                    relative_controlling_team = -1
                
                var relative_capture_value = 0.0
                if absolute_controlling_team == requesting_team:
                    relative_capture_value = abs(absolute_capture_value)
                elif absolute_controlling_team != 0:
                    relative_capture_value = -abs(absolute_capture_value)
                else:
                    if absolute_capture_value > 0 and requesting_team == 1:
                        relative_capture_value = absolute_capture_value
                    elif absolute_capture_value < 0 and requesting_team == 2:
                        relative_capture_value = -absolute_capture_value
                    elif absolute_capture_value > 0 and requesting_team == 2:
                        relative_capture_value = -absolute_capture_value
                    elif absolute_capture_value < 0 and requesting_team == 1:
                        relative_capture_value = absolute_capture_value
                
                relative_capture_value = round(relative_capture_value * 100.0) / 100.0
                
                group_control_points.append({
                    "id": cp.control_point_id,
                    "position": _transform_pos_to_relative_array(cp.global_position, team_transform),
                    "controlling_team": relative_controlling_team,
                    "capture_value": relative_capture_value
                })

    # Assemble the final context
    var group_context = {
        "global_state": global_state,
        "allied_units": group_allies,
        "sensor_data": {
            "visible_enemies": sorted_enemies,
            "visible_allies": sorted_allies, # Other allies visible to the group
            "visible_control_points": group_control_points
        }
    }
    
    return group_context

func get_context_for_ai(unit: Unit) -> Dictionary:
    if not is_instance_valid(unit):
        return {}

    var team_transform = _get_team_transform(unit.team_id)

    # 1. Global State
    var global_state = {
        "game_time_sec": round(game_time * 100.0) / 100.0,
        "team_resources": team_resources.get(unit.team_id, {}),
        "controlled_nodes": node_capture_system.team_control_counts if node_capture_system else {}
    }

    # 2. Unit's Own State (including current plan, converted to team-relative)
    var unit_info = unit.get_unit_info()
    unit_info["position"] = _transform_pos_to_relative_array(unit.global_position, team_transform)
    var unit_state = _convert_to_team_relative_data(unit_info, unit.team_id)
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

        var dist = unit.global_position.distance_to(other_unit.global_position)
        if dist < unit.vision_range:
            var other_info = other_unit.get_unit_info()
            other_info["position"] = _transform_pos_to_relative_array(other_unit.global_position, team_transform)
            var converted_other_info = _convert_to_team_relative_data(other_info, unit.team_id)
            
            if other_unit.team_id != unit.team_id and converted_other_info.get("is_stealthed", false):
                continue

            converted_other_info["dist"] = round(dist * 100.0) / 100.0
            
            if plan_executor:
                var other_plan_info = _get_plan_info_for_unit(other_unit.unit_id)
                if not other_plan_info.is_empty():
                    converted_other_info["current_plan"] = other_plan_info
            
            if other_unit.team_id != unit.team_id:
                sensor_data.visible_enemies.append(converted_other_info)
            else:
                sensor_data.visible_allies.append(converted_other_info)
    
    sensor_data.visible_enemies.sort_custom(func(a, b): return a.dist < b.dist)
    sensor_data.visible_allies.sort_custom(func(a, b): return a.dist < b.dist)

    var placeable_entity_manager = get_node("/root/DependencyContainer").get_placeable_entity_manager()
    if placeable_entity_manager:
        var all_mines = placeable_entity_manager.get_all_mines_data()
        for mine_data in all_mines:
            var mine_pos = Vector3(mine_data.position.x, mine_data.position.y, mine_data.position.z)
            var dist = unit.global_position.distance_to(mine_pos)
            if dist < 40.0:
                var mine_info = mine_data.duplicate()
                mine_info["position"] = _transform_pos_to_relative_array(mine_pos, team_transform)
                var converted_mine_info = _convert_to_team_relative_data(mine_info, unit.team_id)
                converted_mine_info["dist"] = round(dist * 100.0) / 100.0
                sensor_data.visible_mines.append(converted_mine_info)

    if node_capture_system and not node_capture_system.control_points.is_empty():
        for cp in node_capture_system.control_points:
            if is_instance_valid(cp):
                var absolute_controlling_team = cp.get_controlling_team()
                var absolute_capture_value = cp.capture_value
                
                var relative_controlling_team = 0
                if absolute_controlling_team == unit.team_id:
                    relative_controlling_team = 1
                elif absolute_controlling_team != 0:
                    relative_controlling_team = -1
                
                var relative_capture_value = 0.0
                if absolute_controlling_team == unit.team_id:
                    relative_capture_value = abs(absolute_capture_value)
                elif absolute_controlling_team != 0:
                    relative_capture_value = -abs(absolute_capture_value)
                else:
                    if absolute_capture_value > 0 and unit.team_id == 1:
                        relative_capture_value = absolute_capture_value
                    elif absolute_capture_value < 0 and unit.team_id == 2:
                        relative_capture_value = -absolute_capture_value
                    elif absolute_capture_value > 0 and unit.team_id == 2:
                        relative_capture_value = -absolute_capture_value
                    elif absolute_capture_value < 0 and unit.team_id == 1:
                        relative_capture_value = absolute_capture_value
                
                relative_capture_value = round(relative_capture_value * 100.0) / 100.0
                
                var cp_data = {
                    "id": cp.control_point_id,
                    "position": _transform_pos_to_relative_array(cp.global_position, team_transform),
                    "controlling_team": relative_controlling_team,
                    "capture_value": relative_capture_value
                }
                sensor_data.visible_control_points.append(cp_data)

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
    var unit = units.get(unit_id)
    var triggered_actions = []
    if unit and "triggered_actions" in unit:
        triggered_actions = unit.triggered_actions
    for step in triggered_actions:
        plan_context.triggered_actions.append(step)

    return plan_context

func _on_ai_think_timer_timeout():
    if match_state != "active":
        return

    # The timer now acts as a fallback check for any idle units that might have been missed.
    for unit_id in units:
        var unit = units[unit_id]
        if not is_instance_valid(unit) or unit.is_dead:
            continue
            
        var is_idle = not plan_executor.active_plans.has(unit_id) or plan_executor.active_plans.get(unit_id, []).is_empty()
        
        if is_idle:
            # This will respect all cooldowns defined in the function.
            _request_autonomous_plan_for_unit(unit_id)

func set_match_state(new_state: String):
    match_state = new_state
    _log_info("ServerGameState", "Match state changed to: %s" % new_state)
    
    if new_state == "active":
        if ai_think_timer: ai_think_timer.start()
    else:
        if ai_think_timer: ai_think_timer.stop()

func set_initial_group_command_given():
    if not initial_group_command_given:
        initial_group_command_given = true
        _log_info("ServerGameState", "Initial group command received. Autonomous unit prompts are now enabled.")

func _generate_fallback_unit_id(archetype: String, team_id: int) -> String:
    """Generate a fallback unit ID when unit doesn't have one"""
    # Use a simple counter approach for fallback
    var counter_key = "%s_t%d" % [archetype, team_id]
    var counter = units.size() + 1  # Simple fallback counter
    return "%s_%02d_fallback" % [counter_key, counter]

# Existing methods continue...