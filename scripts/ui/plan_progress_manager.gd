# PlanProgressManager.gd
class_name PlanProgressManager
extends Node

# Load shared constants
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Constants
const MAX_CONCURRENT_INDICATORS = 10
const INDICATOR_CLEANUP_INTERVAL = GameConstants.NOTIFICATION_DURATION + 2.0  # seconds

# Scene references
const PlanProgressIndicatorScene = preload("res://scripts/ui/plan_progress_indicator.gd")

# UI container
var progress_indicators_container: Control
var active_indicators: Dictionary = {}  # unit_id -> PlanProgressIndicator
var cleanup_timer: Timer

# Team colors for indicators
var team_colors: Dictionary = {
    1: Color(0.2, 0.6, 1.0, 1.0),  # Blue team
    2: Color(1.0, 0.2, 0.2, 1.0),  # Red team
    0: Color(0.6, 0.6, 0.6, 1.0)   # Neutral/unknown
}

# System integration
var plan_executor: Node = null
var logger: Node = null

func setup(logger_instance, _game_constants_instance) -> void:
    """Setup the PlanProgressManager with dependencies"""
    logger = logger_instance
    # game_constants = game_constants_instance  # Can use this if needed
    
    if logger:
        logger.info("PlanProgressManager", "PlanProgressManager setup completed")
    else:
        print("PlanProgressManager setup completed")

func initialize(_plan_progress_manager_instance = null) -> void:
    """Initialize the PlanProgressManager system"""
    if logger:
        logger.info("PlanProgressManager", "PlanProgressManager initialized")
    else:
        print("PlanProgressManager initialized")

# Statistics
var stats: Dictionary = {
    "indicators_created": 0,
    "indicators_clicked": 0,
    "total_plans_tracked": 0,
    "active_plan_count": 0
}

# Signals
signal plan_indicator_created(unit_id: String)
signal plan_indicator_clicked(unit_id: String)
signal plan_indicator_finished(unit_id: String)

func _ready() -> void:
    # Add to plan_progress_managers group for easy discovery
    add_to_group("plan_progress_managers")
    
    # Create UI container
    _setup_ui_container()
    
    # Setup cleanup timer
    _setup_cleanup_timer()
    
    # Connect to plan executor
    _connect_to_plan_executor()
    
    # Connect to EventBus if available
    _connect_to_event_bus()
    
    print("PlanProgressManager: Plan progress manager initialized")

func _setup_ui_container() -> void:
    """Set up the UI container for plan progress indicators"""
    
    # Create container
    progress_indicators_container = Control.new()
    progress_indicators_container.name = "PlanProgressIndicators"
    progress_indicators_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    progress_indicators_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Add to scene tree
    # Try to find the main UI or game scene
    var main_scene = get_tree().current_scene
    if main_scene:
        main_scene.add_child(progress_indicators_container)
    else:
        # Fallback: add to self
        add_child(progress_indicators_container)
    
    print("PlanProgressManager: UI container created")

func _setup_cleanup_timer() -> void:
    """Set up timer for cleaning up old indicators"""
    
    cleanup_timer = Timer.new()
    cleanup_timer.name = "CleanupTimer"
    cleanup_timer.wait_time = INDICATOR_CLEANUP_INTERVAL
    cleanup_timer.timeout.connect(_cleanup_old_indicators)
    add_child(cleanup_timer)
    cleanup_timer.start()

func _connect_to_plan_executor() -> void:
    """Connect to the plan executor system"""
    
    # Try to find plan executor
    var plan_executors = get_tree().get_nodes_in_group("plan_executors")
    if plan_executors.size() > 0:
        plan_executor = plan_executors[0]
        
        # Connect to plan executor signals
        plan_executor.plan_started.connect(_on_plan_started)
        plan_executor.plan_completed.connect(_on_plan_completed)
        plan_executor.plan_interrupted.connect(_on_plan_interrupted)
        plan_executor.step_executed.connect(_on_step_executed)
        plan_executor.trigger_evaluated.connect(_on_trigger_evaluated)
        
        print("PlanProgressManager: Connected to plan executor")
    else:
        print("PlanProgressManager: No plan executor found")
    
    # Try to find logger
    var loggers = get_tree().get_nodes_in_group("loggers")
    if loggers.size() > 0:
        logger = loggers[0]
    else:
        # Try to get from autoload
        if has_node("/root/DependencyContainer"):
            var container = get_node("/root/DependencyContainer")
            if container.has_method("get_logger"):
                logger = container.get_logger()

func _connect_to_event_bus() -> void:
    """Connect to EventBus signals"""
    
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        
        # Connect to plan execution signals
        if event_bus.has_signal("plan_execution_started"):
            event_bus.plan_execution_started.connect(_on_plan_execution_started)
        
        if event_bus.has_signal("plan_execution_updated"):
            event_bus.plan_execution_updated.connect(_on_plan_execution_updated)
        
        print("PlanProgressManager: Connected to EventBus")

func show_plan_progress(unit_id: String, plan_data: Dictionary, team_id: int = 0) -> bool:
    """Show plan progress indicator for a unit"""
    
    # Find the unit
    var unit = _find_unit_by_id(unit_id)
    if not unit:
        print("PlanProgressManager: Unit not found: %s" % unit_id)
        return false
    
    # Check if unit already has an indicator
    if unit_id in active_indicators:
        # Update existing indicator
        var existing_indicator = active_indicators[unit_id]
        existing_indicator.update_plan_progress(plan_data)
        existing_indicator.set_team_color(team_id)
        return true
    
    # Check indicator limit
    if active_indicators.size() >= MAX_CONCURRENT_INDICATORS:
        # Remove oldest indicator
        _remove_oldest_indicator()
    
    # Create new indicator
    var indicator = PlanProgressIndicatorScene.new()
    indicator.name = "PlanProgressIndicator_" + unit_id
    
    # Connect signals
    indicator.indicator_clicked.connect(_on_indicator_clicked)
    
    # Set team color
    indicator.set_team_color(team_id)
    
    # Add to container
    progress_indicators_container.add_child(indicator)
    
    # Show progress
    indicator.show_plan_progress(unit, plan_data, team_id)
    
    # Track indicator
    active_indicators[unit_id] = indicator
    
    # Update stats
    stats.indicators_created += 1
    stats.total_plans_tracked += 1
    stats.active_plan_count = active_indicators.size()
    
    plan_indicator_created.emit(unit_id)
    
    if logger:
        logger.info("PlanProgressManager", "Showing plan progress for unit %s" % unit_id)
    
    return true

func update_plan_progress(unit_id: String, plan_data: Dictionary) -> bool:
    """Update plan progress for a unit"""
    
    if unit_id in active_indicators:
        var indicator = active_indicators[unit_id]
        indicator.update_plan_progress(plan_data)
        return true
    
    return false

func hide_plan_progress(unit_id: String) -> bool:
    """Hide plan progress indicator for a unit"""
    
    if unit_id in active_indicators:
        var indicator = active_indicators[unit_id]
        indicator.hide_indicator()
        return true
    
    return false

func hide_all_plan_progress() -> void:
    """Hide all plan progress indicators"""
    
    for unit_id in active_indicators:
        var indicator = active_indicators[unit_id]
        indicator.hide_immediately()
    
    active_indicators.clear()
    stats.active_plan_count = 0

func _find_unit_by_id(unit_id: String) -> Node3D:
    """Find a unit by its ID"""
    
    # Try to find in units group
    var units = get_tree().get_nodes_in_group("units")
    for unit in units:
        if unit.has_method("get_unit_id") and unit.get_unit_id() == unit_id:
            return unit
        elif unit.name == unit_id:
            return unit
    
    return null

func _remove_oldest_indicator() -> void:
    """Remove the oldest plan progress indicator"""
    
    if active_indicators.is_empty():
        return
    
    # Find the oldest indicator (this is a simple approach)
    var oldest_unit_id = active_indicators.keys()[0]
    var oldest_indicator = active_indicators[oldest_unit_id]
    
    oldest_indicator.hide_immediately()
    active_indicators.erase(oldest_unit_id)
    stats.active_plan_count = active_indicators.size()

func _cleanup_old_indicators() -> void:
    """Clean up old or invalid indicators"""
    
    var indicators_to_remove = []
    
    for unit_id in active_indicators:
        var indicator = active_indicators[unit_id]
        
        # Check if indicator is still valid
        if not is_instance_valid(indicator) or not indicator.target_unit:
            indicators_to_remove.append(unit_id)
    
    # Remove invalid indicators
    for unit_id in indicators_to_remove:
        active_indicators.erase(unit_id)
        print("PlanProgressManager: Cleaned up invalid indicator for unit %s" % unit_id)
    
    # Update stats
    stats.active_plan_count = active_indicators.size()

# Signal handlers for plan executor events
func _on_plan_started(unit_id: String, _plan: Array) -> void:
    """Handle plan started signal from plan executor"""
    
    if not plan_executor:
        return
    
    # Get plan progress data
    var plan_data = plan_executor.get_plan_progress(unit_id)
    
    if not plan_data.is_empty():
        # Find unit to get team ID
        var unit = _find_unit_by_id(unit_id)
        var team_id = unit.get_team_id() if unit and unit.has_method("get_team_id") else 0
        
        show_plan_progress(unit_id, plan_data, team_id)

func _on_plan_completed(unit_id: String, _success: bool) -> void:
    """Handle plan completed signal from plan executor"""
    
    # Hide the indicator after a short delay
    await get_tree().create_timer(1.0).timeout
    hide_plan_progress(unit_id)
    
    plan_indicator_finished.emit(unit_id)

func _on_plan_interrupted(unit_id: String, _reason: String) -> void:
    """Handle plan interrupted signal from plan executor"""
    
    # Hide the indicator immediately
    hide_plan_progress(unit_id)
    
    plan_indicator_finished.emit(unit_id)

func _on_step_executed(unit_id: String, _step) -> void:
    """Handle step executed signal from plan executor"""
    
    if not plan_executor:
        return
    
    # Update the indicator with new progress
    var plan_data = plan_executor.get_plan_progress(unit_id)
    if not plan_data.is_empty():
        update_plan_progress(unit_id, plan_data)

func _on_trigger_evaluated(unit_id: String, _trigger: String, _result: bool) -> void:
    """Handle trigger evaluated signal from plan executor"""
    
    if not plan_executor:
        return
    
    # Update the indicator with current progress
    var plan_data = plan_executor.get_plan_progress(unit_id)
    if not plan_data.is_empty():
        update_plan_progress(unit_id, plan_data)

func _on_indicator_clicked(unit_id: String) -> void:
    """Handle indicator clicked signal"""
    
    stats.indicators_clicked += 1
    plan_indicator_clicked.emit(unit_id)
    
    if logger:
        logger.info("PlanProgressManager", "Plan indicator clicked for unit %s" % unit_id)

func _on_plan_execution_started(unit_id: String, plan: Dictionary) -> void:
    """Handle plan execution started via EventBus"""
    
    var unit = _find_unit_by_id(unit_id)
    var team_id = unit.get_team_id() if unit and unit.has_method("get_team_id") else 0
    
    # Create plan data from the plan
    var plan_data = {
        "unit_id": unit_id,
        "total_steps": plan.get("steps", []).size(),
        "current_step": 0,
        "progress_percent": 0.0,
        "current_step_action": "",
        "current_step_trigger": ""
    }
    
    show_plan_progress(unit_id, plan_data, team_id)

func _on_plan_execution_updated(unit_id: String, plan_data: Dictionary) -> void:
    """Handle plan execution updated via EventBus"""
    
    update_plan_progress(unit_id, plan_data)

# Public API
func get_active_indicator_count() -> int:
    """Get number of active plan progress indicators"""
    return active_indicators.size()

func get_indicator_for_unit(unit_id: String) -> PlanProgressIndicator:
    """Get the plan progress indicator for a specific unit"""
    return active_indicators.get(unit_id, null)

func is_unit_showing_progress(unit_id: String) -> bool:
    """Check if a unit is currently showing a plan progress indicator"""
    return unit_id in active_indicators

func set_team_color(team_id: int, color: Color) -> void:
    """Set the color for a team's plan progress indicators"""
    team_colors[team_id] = color
    
    # Update existing indicators
    for unit_id in active_indicators:
        var indicator = active_indicators[unit_id]
        if indicator.team_id == team_id:
            indicator.set_team_color(team_id)

func get_statistics() -> Dictionary:
    """Get plan progress statistics"""
    return stats.duplicate()

func reset_statistics() -> void:
    """Reset plan progress statistics"""
    stats = {
        "indicators_created": 0,
        "indicators_clicked": 0,
        "total_plans_tracked": 0,
        "active_plan_count": active_indicators.size()
    }

func set_max_concurrent_indicators(max_indicators: int) -> void:
    """Set the maximum number of concurrent plan progress indicators"""
    # Remove excess indicators if needed
    while active_indicators.size() > max_indicators:
        _remove_oldest_indicator()

func get_all_active_progress() -> Dictionary:
    """Get all currently active plan progress data"""
    var progress_data = {}
    
    for unit_id in active_indicators:
        var indicator = active_indicators[unit_id]
        progress_data[unit_id] = {
            "plan_data": indicator.get_current_plan_data(),
            "team_id": indicator.team_id,
            "is_visible": indicator.is_indicator_visible()
        }
    
    return progress_data

func force_refresh_all_indicators() -> void:
    """Force refresh all indicators from plan executor"""
    
    if not plan_executor:
        return
    
    var units_with_plans = plan_executor.get_units_with_plans()
    
    # Update existing indicators
    for unit_id in units_with_plans:
        var plan_data = plan_executor.get_plan_progress(unit_id)
        if not plan_data.is_empty():
            if unit_id in active_indicators:
                update_plan_progress(unit_id, plan_data)
            else:
                # Create new indicator
                var unit = _find_unit_by_id(unit_id)
                var team_id = unit.get_team_id() if unit and unit.has_method("get_team_id") else 0
                show_plan_progress(unit_id, plan_data, team_id)
    
    # Remove indicators for units without plans
    var indicators_to_remove = []
    for unit_id in active_indicators:
        if not unit_id in units_with_plans:
            indicators_to_remove.append(unit_id)
    
    for unit_id in indicators_to_remove:
        hide_plan_progress(unit_id)

func _process(_delta: float) -> void:
    """Update plan progress indicators"""
    
    # Refresh indicators periodically
    if plan_executor:
        var frame = Engine.get_process_frames()
        if frame % 30 == 0:  # Every 30 frames (about 0.5 seconds at 60 FPS)
            _refresh_indicators()

func _refresh_indicators() -> void:
    """Refresh indicators with current plan data"""
    
    if not plan_executor:
        return
    
    for unit_id in active_indicators:
        var plan_data = plan_executor.get_plan_progress(unit_id)
        if not plan_data.is_empty():
            update_plan_progress(unit_id, plan_data)
        else:
            # Plan might have finished, hide indicator
            hide_plan_progress(unit_id)

func enable_auto_refresh(enabled: bool) -> void:
    """Enable or disable automatic refresh of indicators"""
    
    set_process(enabled)

func get_indicator_positions() -> Dictionary:
    """Get positions of all active indicators (for debugging)"""
    
    var positions = {}
    
    for unit_id in active_indicators:
        var indicator = active_indicators[unit_id]
        positions[unit_id] = {
            "screen_position": indicator.position,
            "size": indicator.size,
            "visible": indicator.is_indicator_visible()
        }
    
    return positions 