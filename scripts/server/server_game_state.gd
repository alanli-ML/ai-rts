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

func _ready() -> void:
    # Systems will be initialized via dependency injection
    pass

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
        
        # Connect system signals
        _connect_system_signals()
        
        logger.info("ServerGameState", "Setup complete with all systems")
    else:
        logger.error("ServerGameState", "Cannot find DependencyContainer")

func _connect_system_signals() -> void:
    """Connect signals from all integrated systems"""
    
    # Connect AI system signals
    if ai_command_processor:
        ai_command_processor.plan_created.connect(_on_ai_plan_created)
        ai_command_processor.plan_step_completed.connect(_on_ai_plan_step_completed)
        ai_command_processor.plan_failed.connect(_on_ai_plan_failed)
        ai_command_processor.plan_completed.connect(_on_ai_plan_completed)
    
    # Connect resource manager signals
    if resource_manager:
        resource_manager.resource_changed.connect(_on_resource_changed)
        resource_manager.resource_depleted.connect(_on_resource_depleted)
        resource_manager.resource_generated.connect(_on_resource_generated)
    
    # Connect node capture system signals
    if node_capture_system:
        node_capture_system.control_point_captured.connect(_on_control_point_captured)
        node_capture_system.control_point_contested.connect(_on_control_point_contested)
        node_capture_system.victory_achieved.connect(_on_victory_achieved)
    
    logger.info("ServerGameState", "System signals connected")

# AI System Integration
func _on_ai_plan_created(plan_id: String, unit_id: String, plan_data: Dictionary) -> void:
    """Handle AI plan creation"""
    logger.info("ServerGameState", "AI plan created: %s for unit %s" % [plan_id, unit_id])
    
    # Update AI progress data for clients
    ai_progress_data[unit_id] = {
        "plan_id": plan_id,
        "status": "active",
        "progress": 0.0,
        "current_step": 0,
        "total_steps": plan_data.get("steps", []).size()
    }
    
    # Broadcast to clients
    _broadcast_ai_progress_update(unit_id)

func _on_ai_plan_step_completed(plan_id: String, unit_id: String, step_data: Dictionary) -> void:
    """Handle AI plan step completion"""
    logger.info("ServerGameState", "AI plan step completed: %s for unit %s" % [plan_id, unit_id])
    
    # Update progress data
    if unit_id in ai_progress_data:
        var progress_data = ai_progress_data[unit_id]
        progress_data["current_step"] += 1
        progress_data["progress"] = float(progress_data["current_step"]) / float(progress_data["total_steps"])
        
        # Broadcast to clients
        _broadcast_ai_progress_update(unit_id)
    
    # Trigger unit speech if specified
    var speech_message = step_data.get("speech_message", "")
    if speech_message != "":
        _trigger_unit_speech(unit_id, speech_message)

func _on_ai_plan_failed(plan_id: String, unit_id: String, error_message: String) -> void:
    """Handle AI plan failure"""
    logger.info("ServerGameState", "AI plan failed: %s for unit %s - %s" % [plan_id, unit_id, error_message])
    
    # Update progress data
    if unit_id in ai_progress_data:
        ai_progress_data[unit_id]["status"] = "failed"
        ai_progress_data[unit_id]["error"] = error_message
        
        # Broadcast to clients
        _broadcast_ai_progress_update(unit_id)

func _on_ai_plan_completed(plan_id: String, unit_id: String) -> void:
    """Handle AI plan completion"""
    logger.info("ServerGameState", "AI plan completed: %s for unit %s" % [plan_id, unit_id])
    
    # Update progress data
    if unit_id in ai_progress_data:
        ai_progress_data[unit_id]["status"] = "completed"
        ai_progress_data[unit_id]["progress"] = 1.0
        
        # Broadcast to clients
        _broadcast_ai_progress_update(unit_id)
        
        # Clean up after delay
        await get_tree().create_timer(2.0).timeout
        ai_progress_data.erase(unit_id)

# Resource System Integration
func _on_resource_changed(team_id: int, resource_type: String, current_amount: int, change_amount: int) -> void:
    """Handle resource changes"""
    logger.info("ServerGameState", "Resource changed: Team %d, %s: %d (%+d)" % [team_id, resource_type, current_amount, change_amount])
    
    # Update cached resource data
    if team_id not in resource_data:
        resource_data[team_id] = {}
    
    resource_data[team_id][resource_type] = {
        "current": current_amount,
        "change": change_amount
    }
    
    # Broadcast to clients
    _broadcast_resource_update(team_id)

func _on_resource_depleted(team_id: int, resource_type: String) -> void:
    """Handle resource depletion"""
    logger.info("ServerGameState", "Resource depleted: Team %d, %s" % [team_id, resource_type])
    
    # Send notification to clients
    _broadcast_notification(team_id, "warning", "Resource depleted: %s" % resource_type)

func _on_resource_generated(team_id: int, resource_type: String, amount: int) -> void:
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
        EventBus.emit_signal("plan_progress_updated", unit_id, progress_data)

func _broadcast_resource_update(team_id: int) -> void:
    """Broadcast resource update to all clients"""
    if team_id in resource_data:
        var resources = resource_data[team_id]
        
        # Send to all clients via EventBus
        EventBus.emit_signal("resource_updated", team_id, resources)

func _broadcast_control_point_update(control_point_id: int) -> void:
    """Broadcast control point update to all clients"""
    if control_point_id in control_points_data:
        var control_point_data = control_points_data[control_point_id]
        
        # Send to all clients via EventBus
        EventBus.emit_signal("control_point_updated", control_point_id, control_point_data)

func _broadcast_notification(team_id: int, type: String, message: String) -> void:
    """Broadcast notification to team clients"""
    var notification_data = {
        "type": type,
        "message": message,
		"timestamp": Time.get_ticks_msec()
	}
	
    # Send to all clients via EventBus
    EventBus.emit_signal("notification_received", team_id, notification_data)

func _broadcast_match_ended(winning_team: int, victory_type: String) -> void:
    """Broadcast match ended to all clients"""
    var match_data = {
        "winning_team": winning_team,
        "victory_type": victory_type,
        "timestamp": Time.get_ticks_msec()
    }
    
    # Send to all clients via EventBus
    EventBus.emit_signal("match_ended", match_data)

func _trigger_unit_speech(unit_id: String, message: String) -> void:
    """Trigger unit speech bubble"""
    var unit = units.get(unit_id)
    if unit:
        var team_id = unit.team_id
        
        # Send to all clients via EventBus
        EventBus.emit_signal("unit_speech_requested", unit_id, message, team_id)

# Existing methods continue...