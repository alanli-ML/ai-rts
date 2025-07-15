# NodeCaptureSystem.gd
class_name NodeCaptureSystem
extends Node

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")
const ControlPoint = preload("res://scripts/gameplay/control_point.gd")

# System state
var control_points: Array[ControlPoint] = []
var control_point_map: Dictionary = {}  # id -> ControlPoint
var team_control_counts: Dictionary = {}  # team_id -> count
var total_strategic_value: Dictionary = {}  # team_id -> total value

# Victory tracking
var victory_conditions_met: bool = false
var winning_team: int = 0
var victory_check_interval: float = 1.0  # seconds
var last_victory_check: float = 0.0

# Statistics
var capture_events: Array = []
var team_statistics: Dictionary = {}

# Map layout (3x3 grid)
var map_layout: Array = [
    # Strategic positions on the map
    Vector3(-20, 0, -20),  # Top-left
    Vector3(0, 0, -20),    # Top-center
    Vector3(20, 0, -20),   # Top-right
    Vector3(-20, 0, 0),    # Middle-left
    Vector3(0, 0, 0),      # Center (most valuable)
    Vector3(20, 0, 0),     # Middle-right
    Vector3(-20, 0, 20),   # Bottom-left
    Vector3(0, 0, 20),     # Bottom-center
    Vector3(20, 0, 20)     # Bottom-right
]

# Strategic values (center point is most valuable)
var strategic_values: Array = [1, 2, 1, 2, 3, 2, 1, 2, 1]

# Control point names
var control_point_names: Array = [
    "North Outpost",
    "Northern Command",
    "Northeast Outpost",
    "West Garrison",
    "Central Spire",
    "East Garrison",
    "Southwest Outpost",
    "Southern Command",
    "South Outpost"
]

# Signals
signal control_point_captured(point_id: String, team_id: int)
signal control_point_contested(point_id: String, teams: Array)
signal control_point_neutralized(point_id: String)
signal team_control_changed(team_id: int, control_count: int)
signal victory_condition_met(team_id: int, condition_type: String)
signal capture_progress_updated(point_id: String, progress: float)

func _ready() -> void:
    # Initialize team statistics
    _initialize_team_statistics()
    
    # Create control points
    _create_control_points()
    
    # Start processing
    set_process(true)
    
    # Add to system groups
    add_to_group("node_capture_systems")
    
    print("NodeCaptureSystem: Initialized with %d control points" % control_points.size())

func _initialize_team_statistics() -> void:
    """Initialize team statistics tracking"""
    
    for team_id in range(3):  # 0 = neutral, 1 = team1, 2 = team2
        team_control_counts[team_id] = 0
        total_strategic_value[team_id] = 0
        team_statistics[team_id] = {
            "captures": 0,
            "losses": 0,
            "contests": 0,
            "total_capture_time": 0.0,
            "average_capture_time": 0.0
        }

func _create_control_points() -> void:
    """Create all control points on the map"""
    
    for i in range(GameConstants.CONTROL_POINT_COUNT):
        var control_point = ControlPoint.new()
        control_point.name = "ControlPoint_%d" % i
        control_point.control_point_id = "cp_%d" % i
        control_point.control_point_name = control_point_names[i]
        control_point.strategic_value = strategic_values[i]
        control_point.global_position = map_layout[i]
        
        # Connect signals
        control_point.control_point_captured.connect(_on_control_point_captured)
        control_point.control_point_contested.connect(_on_control_point_contested)
        control_point.control_point_neutralized.connect(_on_control_point_neutralized)
        control_point.capture_progress_changed.connect(_on_capture_progress_changed)
        
        # Add to scene
        add_child(control_point)
        
        # Track control point
        control_points.append(control_point)
        control_point_map[control_point.control_point_id] = control_point
        
        print("NodeCaptureSystem: Created control point %s at %s" % [control_point.control_point_name, control_point.global_position])

func _process(delta: float) -> void:
    """Process system updates"""
    
    # Check victory conditions periodically
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_victory_check >= victory_check_interval:
        _check_victory_conditions()
        last_victory_check = current_time

func _on_control_point_captured(point_id: String, team_id: int) -> void:
    """Handle control point captured event"""
    
    var control_point = control_point_map.get(point_id)
    if not control_point:
        return
    
    # Update statistics
    _update_team_control_counts()
    
    # Record capture event
    var capture_event = {
        "point_id": point_id,
        "team_id": team_id,
        "timestamp": Time.get_ticks_msec() / 1000.0,
        "strategic_value": control_point.strategic_value
    }
    capture_events.append(capture_event)
    
    # Update team statistics
    team_statistics[team_id].captures += 1
    
    # Emit signals
    control_point_captured.emit(point_id, team_id)
    team_control_changed.emit(team_id, team_control_counts[team_id])
    
    print("NodeCaptureSystem: %s captured by team %d" % [control_point.control_point_name, team_id])

func _on_control_point_contested(point_id: String, teams: Array) -> void:
    """Handle control point contested event"""
    
    var control_point = control_point_map.get(point_id)
    if not control_point:
        return
    
    # Update contest statistics
    for team_id in teams:
        team_statistics[team_id].contests += 1
    
    # Emit signal
    control_point_contested.emit(point_id, teams)
    
    print("NodeCaptureSystem: %s contested by teams %s" % [control_point.control_point_name, teams])

func _on_control_point_neutralized(point_id: String) -> void:
    """Handle control point neutralized event"""
    
    var control_point = control_point_map.get(point_id)
    if not control_point:
        return
    
    # Update statistics
    _update_team_control_counts()
    
    # Emit signal
    control_point_neutralized.emit(point_id)
    
    print("NodeCaptureSystem: %s neutralized" % control_point.control_point_name)

func _on_capture_progress_changed(point_id: String, progress: float) -> void:
    """Handle capture progress change"""
    
    capture_progress_updated.emit(point_id, progress)

func _update_team_control_counts() -> void:
    """Update team control counts and strategic values"""
    
    # Reset counts
    for team_id in team_control_counts:
        team_control_counts[team_id] = 0
        total_strategic_value[team_id] = 0
    
    # Count controlled points
    for control_point in control_points:
        if control_point.is_controlled():
            var team_id = control_point.get_controlling_team()
            team_control_counts[team_id] += 1
            total_strategic_value[team_id] += control_point.strategic_value

func _check_victory_conditions() -> void:
    """Check if any team has met victory conditions"""
    
    if victory_conditions_met:
        return
    
    # Update counts first
    _update_team_control_counts()
    
    # Check victory conditions
    for team_id in [1, 2]:  # Only check actual teams, not neutral
        # Victory condition: Control threshold number of points
        if team_control_counts[team_id] >= GameConstants.CONTROL_POINT_VICTORY_THRESHOLD:
            _trigger_victory(team_id, "control_points")
            return
        
        # Victory condition: Control center point + 4 others
        if _has_strategic_victory(team_id):
            _trigger_victory(team_id, "strategic_control")
            return
        
        # Victory condition: Control all outer points (surrounding center)
        if _has_perimeter_victory(team_id):
            _trigger_victory(team_id, "perimeter_control")
            return

func _has_strategic_victory(team_id: int) -> bool:
    """Check if team has strategic victory (center + 4 others)"""
    
    # Check if team controls the center point
    var center_point = control_point_map.get("cp_4")  # Center point
    if not center_point or not center_point.is_controlled() or center_point.get_controlling_team() != team_id:
        return false
    
    # Check if team has at least 4 other points
    var other_points = 0
    for i in range(control_points.size()):
        if i == 4:  # Skip center point
            continue
        
        var point = control_points[i]
        if point.is_controlled() and point.get_controlling_team() == team_id:
            other_points += 1
    
    return other_points >= 4

func _has_perimeter_victory(team_id: int) -> bool:
    """Check if team has perimeter victory (all outer points)"""
    
    var outer_points = [0, 1, 2, 3, 5, 6, 7, 8]  # All except center (4)
    
    for point_index in outer_points:
        var point = control_points[point_index]
        if not point.is_controlled() or point.get_controlling_team() != team_id:
            return false
    
    return true

func _trigger_victory(team_id: int, condition_type: String) -> void:
    """Trigger victory for a team"""
    
    victory_conditions_met = true
    winning_team = team_id
    
    print("NodeCaptureSystem: Team %d achieved victory via %s!" % [team_id, condition_type])
    
    # Emit victory signal
    victory_condition_met.emit(team_id, condition_type)
    
    # Notify EventBus if available
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        if event_bus.has_signal("victory_achieved"):
            event_bus.victory_achieved.emit(team_id, condition_type)

# Public API
func get_control_point(point_id: String) -> ControlPoint:
    """Get control point by ID"""
    return control_point_map.get(point_id)

func get_all_control_points() -> Array[ControlPoint]:
    """Get all control points"""
    return control_points.duplicate()

func get_team_control_count(team_id: int) -> int:
    """Get number of points controlled by team"""
    return team_control_counts.get(team_id, 0)

func get_team_strategic_value(team_id: int) -> int:
    """Get total strategic value controlled by team"""
    return total_strategic_value.get(team_id, 0)

func get_contested_points() -> Array[ControlPoint]:
    """Get all contested control points"""
    var contested = []
    for point in control_points:
        if point.is_contested():
            contested.append(point)
    return contested

func get_neutral_points() -> Array[ControlPoint]:
    """Get all neutral control points"""
    var neutral = []
    for point in control_points:
        if point.is_neutral():
            neutral.append(point)
    return neutral

func get_team_controlled_points(team_id: int) -> Array[ControlPoint]:
    """Get all points controlled by a specific team"""
    var controlled = []
    for point in control_points:
        if point.is_controlled() and point.get_controlling_team() == team_id:
            controlled.append(point)
    return controlled

func get_control_distribution() -> Dictionary:
    """Get distribution of control points by team"""
    var distribution = {}
    for team_id in team_control_counts:
        distribution[team_id] = {
            "count": team_control_counts[team_id],
            "percentage": (team_control_counts[team_id] / float(control_points.size())) * 100.0,
            "strategic_value": total_strategic_value[team_id]
        }
    return distribution

func get_system_statistics() -> Dictionary:
    """Get system statistics"""
    return {
        "total_control_points": control_points.size(),
        "team_control_counts": team_control_counts.duplicate(),
        "total_strategic_value": total_strategic_value.duplicate(),
        "team_statistics": team_statistics.duplicate(),
        "capture_events": capture_events.size(),
        "contested_points": get_contested_points().size(),
        "neutral_points": get_neutral_points().size(),
        "victory_conditions_met": victory_conditions_met,
        "winning_team": winning_team
    }

func get_victory_progress(team_id: int) -> Dictionary:
    """Get victory progress for a team"""
    var control_count = team_control_counts.get(team_id, 0)
    var strategic_value = total_strategic_value.get(team_id, 0)
    
    return {
        "team_id": team_id,
        "control_points": control_count,
        "control_threshold": GameConstants.CONTROL_POINT_VICTORY_THRESHOLD,
        "control_progress": (control_count / float(GameConstants.CONTROL_POINT_VICTORY_THRESHOLD)) * 100.0,
        "strategic_value": strategic_value,
        "has_center_control": _has_center_control(team_id),
        "strategic_victory_possible": _has_strategic_victory(team_id),
        "perimeter_victory_possible": _has_perimeter_victory(team_id)
    }

func _has_center_control(team_id: int) -> bool:
    """Check if team controls the center point"""
    var center_point = control_point_map.get("cp_4")
    return center_point and center_point.is_controlled() and center_point.get_controlling_team() == team_id

func reset_all_control_points() -> void:
    """Reset all control points to neutral (for testing/reset)"""
    
    for point in control_points:
        point.reset_control_point()
    
    _update_team_control_counts()
    victory_conditions_met = false
    winning_team = 0
    
    print("NodeCaptureSystem: All control points reset to neutral")

func force_capture_point(point_id: String, team_id: int) -> bool:
    """Force capture a control point (for testing/admin)"""
    
    var point = control_point_map.get(point_id)
    if not point:
        return false
    
    point.force_capture(team_id)
    _update_team_control_counts()
    
    return true

func get_nearest_control_point(position: Vector3) -> ControlPoint:
    """Get nearest control point to a position"""
    
    var nearest_point = null
    var min_distance = INF
    
    for point in control_points:
        var distance = position.distance_to(point.global_position)
        if distance < min_distance:
            min_distance = distance
            nearest_point = point
    
    return nearest_point

func get_control_points_in_radius(position: Vector3, radius: float) -> Array[ControlPoint]:
    """Get control points within radius of position"""
    
    var points_in_radius = []
    
    for point in control_points:
        var distance = position.distance_to(point.global_position)
        if distance <= radius:
            points_in_radius.append(point)
    
    return points_in_radius

func get_strategic_recommendations(team_id: int) -> Array:
    """Get strategic recommendations for a team"""
    
    var recommendations = []
    
    # Recommend capturing center if not controlled
    var center_point = control_point_map.get("cp_4")
    if center_point and not center_point.is_controlled():
        recommendations.append({
            "type": "capture_center",
            "priority": "high",
            "point_id": "cp_4",
            "reason": "Center point has highest strategic value"
        })
    elif center_point and center_point.get_controlling_team() != team_id:
        recommendations.append({
            "type": "contest_center",
            "priority": "high",
            "point_id": "cp_4",
            "reason": "Prevent enemy from holding center"
        })
    
    # Recommend capturing contested points
    for point in get_contested_points():
        recommendations.append({
            "type": "resolve_contest",
            "priority": "medium",
            "point_id": point.control_point_id,
            "reason": "Contested point needs resolution"
        })
    
    # Recommend capturing neutral points
    for point in get_neutral_points():
        recommendations.append({
            "type": "expand_control",
            "priority": "low",
            "point_id": point.control_point_id,
            "reason": "Expand territorial control"
        })
    
    return recommendations

func get_all_control_point_data() -> Array:
    """Get data for all control points (for UI/networking)"""
    
    var data = []
    for point in control_points:
        data.append(point.get_control_point_data())
    
    return data

func is_victory_achieved() -> bool:
    """Check if victory has been achieved"""
    return victory_conditions_met

func get_winning_team() -> int:
    """Get the winning team ID"""
    return winning_team 