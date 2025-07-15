# ControlPoint.gd
class_name ControlPoint
extends StaticBody3D

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Control point identification
@export var control_point_id: String = ""
@export var control_point_name: String = ""
@export var strategic_value: int = 1

# Control point state
var current_state: GameEnums.ControlPointState = GameEnums.ControlPointState.NEUTRAL
var controlling_team: int = 0
var capture_progress: float = 0.0
var capture_start_time: float = 0.0
var is_being_captured: bool = false

# Capture mechanics
var capture_radius: float = GameConstants.CONTROL_POINT_RADIUS
var capture_time: float = GameConstants.CONTROL_POINT_CAPTURE_TIME
var units_in_range: Dictionary = {}  # team_id -> Array[Unit]
var last_capture_check: float = 0.0

# Visual components
var base_mesh: MeshInstance3D = null
var capture_indicator: MeshInstance3D = null
var progress_ring: MeshInstance3D = null
var team_flag: MeshInstance3D = null
var capture_area: Area3D = null

# Team colors
var team_colors: Dictionary = {
    0: Color(0.5, 0.5, 0.5, 1.0),  # Neutral - Gray
    1: Color(0.2, 0.4, 1.0, 1.0),  # Team 1 - Blue
    2: Color(1.0, 0.2, 0.2, 1.0)   # Team 2 - Red
}

# Signals
signal control_point_captured(point_id: String, team_id: int)
signal control_point_contested(point_id: String, teams: Array)
signal control_point_neutralized(point_id: String)
signal capture_progress_changed(point_id: String, progress: float)

func _ready() -> void:
    # Generate unique ID if not set
    if control_point_id.is_empty():
        control_point_id = "cp_" + str(randi())
    
    # Set default name
    if control_point_name.is_empty():
        control_point_name = "Control Point " + control_point_id
    
    # Create visual components
    _create_visual_components()
    
    # Create capture area
    _create_capture_area()
    
    # Add to control points group
    add_to_group("control_points")
    
    # Start processing
    set_process(true)
    
    print("ControlPoint %s (%s) initialized" % [control_point_id, control_point_name])

func _create_visual_components() -> void:
    """Create visual components for the control point"""
    
    # Create base mesh (platform)
    base_mesh = MeshInstance3D.new()
    base_mesh.name = "BaseMesh"
    base_mesh.mesh = CylinderMesh.new()
    base_mesh.mesh.top_radius = capture_radius * 0.8
    base_mesh.mesh.bottom_radius = capture_radius * 0.8
    base_mesh.mesh.height = 0.5
    
    # Base material
    var base_material = StandardMaterial3D.new()
    base_material.albedo_color = team_colors[0]
    base_material.metallic = 0.3
    base_material.roughness = 0.7
    base_mesh.material_override = base_material
    
    add_child(base_mesh)
    
    # Create capture indicator (central pillar)
    capture_indicator = MeshInstance3D.new()
    capture_indicator.name = "CaptureIndicator"
    capture_indicator.mesh = CylinderMesh.new()
    capture_indicator.mesh.top_radius = 0.3
    capture_indicator.mesh.bottom_radius = 0.5
    capture_indicator.mesh.height = 2.0
    capture_indicator.position.y = 1.25
    
    # Indicator material
    var indicator_material = StandardMaterial3D.new()
    indicator_material.albedo_color = team_colors[0]
    indicator_material.emission_enabled = true
    indicator_material.emission = team_colors[0] * 0.3
    capture_indicator.material_override = indicator_material
    
    add_child(capture_indicator)
    
    # Create progress ring
    progress_ring = MeshInstance3D.new()
    progress_ring.name = "ProgressRing"
    progress_ring.mesh = SphereMesh.new()
    progress_ring.mesh.radius = capture_radius * 1.1
    progress_ring.mesh.height = 0.2
    progress_ring.position.y = 0.1
    progress_ring.visible = false
    
    # Progress ring material
    var ring_material = StandardMaterial3D.new()
    ring_material.albedo_color = Color(1.0, 1.0, 0.0, 0.3)
    ring_material.flags_transparent = true
    ring_material.emission_enabled = true
    ring_material.emission = Color(1.0, 1.0, 0.0, 0.5)
    progress_ring.material_override = ring_material
    
    add_child(progress_ring)
    
    # Create team flag
    team_flag = MeshInstance3D.new()
    team_flag.name = "TeamFlag"
    team_flag.mesh = BoxMesh.new()
    team_flag.mesh.size = Vector3(1.0, 1.5, 0.1)
    team_flag.position = Vector3(0, 3.0, 0)
    team_flag.visible = false
    
    add_child(team_flag)

func _create_capture_area() -> void:
    """Create capture area for detecting units"""
    
    capture_area = Area3D.new()
    capture_area.name = "CaptureArea"
    
    # Create collision shape
    var collision_shape = CollisionShape3D.new()
    collision_shape.name = "CollisionShape3D"
    var shape = CylinderShape3D.new()
    shape.height = 4.0  # Tall enough to detect units
    shape.radius = capture_radius  # Use radius instead of top_radius/bottom_radius
    collision_shape.shape = shape
    collision_shape.position.y = 2.0  # Center the detection area
    
    capture_area.add_child(collision_shape)
    
    # Connect signals
    capture_area.body_entered.connect(_on_unit_entered)
    capture_area.body_exited.connect(_on_unit_exited)
    
    add_child(capture_area)

func _process(delta: float) -> void:
    """Process capture mechanics"""
    
    # Update capture progress
    if is_being_captured:
        _update_capture_progress(delta)
    
    # Update visual effects
    _update_visual_effects()
    
    # Check for state changes every 0.1 seconds
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_capture_check >= 0.1:
        _check_capture_state()
        last_capture_check = current_time

func _on_unit_entered(body: Node3D) -> void:
    """Handle unit entering capture area"""
    
    if not body.is_in_group("units"):
        return
    
    if not body.has_method("get_team_id"):
        return
    
    var team_id = body.get_team_id()
    var unit_id = body.get_unit_id() if body.has_method("get_unit_id") else body.name
    
    # Add unit to tracking
    if not team_id in units_in_range:
        units_in_range[team_id] = []
    
    if not body in units_in_range[team_id]:
        units_in_range[team_id].append(body)
    
    print("ControlPoint %s: Unit %s (Team %d) entered capture area" % [control_point_id, unit_id, team_id])
    
    # Check if capture state changed
    _check_capture_state()

func _on_unit_exited(body: Node3D) -> void:
    """Handle unit exiting capture area"""
    
    if not body.is_in_group("units"):
        return
    
    if not body.has_method("get_team_id"):
        return
    
    var team_id = body.get_team_id()
    var unit_id = body.get_unit_id() if body.has_method("get_unit_id") else body.name
    
    # Remove unit from tracking
    if team_id in units_in_range:
        units_in_range[team_id].erase(body)
        if units_in_range[team_id].is_empty():
            units_in_range.erase(team_id)
    
    print("ControlPoint %s: Unit %s (Team %d) exited capture area" % [control_point_id, unit_id, team_id])
    
    # Check if capture state changed
    _check_capture_state()

func _check_capture_state() -> void:
    """Check and update capture state based on units in range"""
    
    # Clean up invalid units
    _cleanup_invalid_units()
    
    # Get valid teams with units in range
    var teams_present = []
    for team_id in units_in_range:
        if units_in_range[team_id].size() > 0:
            teams_present.append(team_id)
    
    # Determine new state
    var new_state = current_state
    var capturing_team = 0
    
    if teams_present.size() == 0:
        # No units present
        new_state = GameEnums.ControlPointState.NEUTRAL
        is_being_captured = false
        
    elif teams_present.size() == 1:
        # Single team present
        capturing_team = teams_present[0]
        
        if controlling_team == capturing_team:
            # Same team that already controls it
            new_state = GameEnums.ControlPointState.CONTROLLED
            is_being_captured = false
        else:
            # Different team trying to capture
            new_state = GameEnums.ControlPointState.CONTESTED
            is_being_captured = true
            if capture_progress == 0.0:
                capture_start_time = Time.get_ticks_msec() / 1000.0
        
    else:
        # Multiple teams present - contested
        new_state = GameEnums.ControlPointState.CONTESTED
        is_being_captured = false
        capturing_team = 0
    
    # Update state if changed
    if new_state != current_state:
        _change_state(new_state, capturing_team, teams_present)

func _change_state(new_state: GameEnums.ControlPointState, capturing_team: int, teams_present: Array) -> void:
    """Change control point state"""
    
    var old_state = current_state
    current_state = new_state
    
    # Reset capture progress if not being captured
    if not is_being_captured:
        capture_progress = 0.0
    
    # Handle state-specific logic
    match new_state:
        GameEnums.ControlPointState.NEUTRAL:
            controlling_team = 0
            if old_state == GameEnums.ControlPointState.CONTROLLED:
                control_point_neutralized.emit(control_point_id)
                print("ControlPoint %s neutralized" % control_point_id)
        
        GameEnums.ControlPointState.CONTESTED:
            if teams_present.size() > 1:
                control_point_contested.emit(control_point_id, teams_present)
                print("ControlPoint %s contested by teams: %s" % [control_point_id, teams_present])
        
        GameEnums.ControlPointState.CONTROLLED:
            if not is_being_captured:
                # Already controlled by the same team
                pass
    
    # Update visual state
    _update_visual_state()

func _update_capture_progress(delta: float) -> void:
    """Update capture progress"""
    
    if not is_being_captured:
        return
    
    # Calculate progress
    var progress_rate = 1.0 / capture_time
    capture_progress += progress_rate * delta
    
    # Check if capture is complete
    if capture_progress >= 1.0:
        _complete_capture()
    
    # Emit progress signal
    capture_progress_changed.emit(control_point_id, capture_progress)

func _complete_capture() -> void:
    """Complete the capture process"""
    
    # Find the capturing team
    var capturing_team = 0
    for team_id in units_in_range:
        if units_in_range[team_id].size() > 0:
            capturing_team = team_id
            break
    
    # Update state
    controlling_team = capturing_team
    current_state = GameEnums.ControlPointState.CONTROLLED
    capture_progress = 1.0
    is_being_captured = false
    
    # Emit signal
    control_point_captured.emit(control_point_id, controlling_team)
    print("ControlPoint %s captured by team %d" % [control_point_id, controlling_team])
    
    # Update visual state
    _update_visual_state()

func _cleanup_invalid_units() -> void:
    """Clean up invalid or dead units from tracking"""
    
    var teams_to_remove = []
    
    for team_id in units_in_range:
        var valid_units = []
        
        for unit in units_in_range[team_id]:
            if is_instance_valid(unit) and not unit.is_in_group("dead"):
                valid_units.append(unit)
        
        if valid_units.size() > 0:
            units_in_range[team_id] = valid_units
        else:
            teams_to_remove.append(team_id)
    
    # Remove teams with no valid units
    for team_id in teams_to_remove:
        units_in_range.erase(team_id)

func _update_visual_state() -> void:
    """Update visual components based on current state"""
    
    var color = team_colors[controlling_team]
    
    # Update base mesh color
    if base_mesh and base_mesh.material_override:
        base_mesh.material_override.albedo_color = color
    
    # Update capture indicator
    if capture_indicator and capture_indicator.material_override:
        capture_indicator.material_override.albedo_color = color
        capture_indicator.material_override.emission = color * 0.3
    
    # Update team flag
    if team_flag:
        if controlling_team > 0:
            team_flag.visible = true
            var flag_material = StandardMaterial3D.new()
            flag_material.albedo_color = color
            flag_material.emission_enabled = true
            flag_material.emission = color * 0.2
            team_flag.material_override = flag_material
        else:
            team_flag.visible = false

func _update_visual_effects() -> void:
    """Update visual effects based on capture progress"""
    
    if progress_ring:
        if is_being_captured:
            progress_ring.visible = true
            # Scale ring based on progress
            var scale = 0.5 + (capture_progress * 0.5)
            progress_ring.scale = Vector3(scale, 1.0, scale)
            
            # Update ring color intensity
            var ring_color = Color(1.0, 1.0, 0.0, 0.3 + capture_progress * 0.4)
            progress_ring.material_override.albedo_color = ring_color
        else:
            progress_ring.visible = false

# Public API
func get_control_point_id() -> String:
    return control_point_id

func get_control_point_name() -> String:
    return control_point_name

func get_controlling_team() -> int:
    return controlling_team

func get_current_state() -> GameEnums.ControlPointState:
    return current_state

func get_capture_progress() -> float:
    return capture_progress

func get_strategic_value() -> int:
    return strategic_value

func get_units_in_range() -> Dictionary:
    return units_in_range.duplicate()

func get_teams_present() -> Array:
    var teams = []
    for team_id in units_in_range:
        if units_in_range[team_id].size() > 0:
            teams.append(team_id)
    return teams

func is_contested() -> bool:
    return current_state == GameEnums.ControlPointState.CONTESTED

func is_controlled() -> bool:
    return current_state == GameEnums.ControlPointState.CONTROLLED

func is_neutral() -> bool:
    return current_state == GameEnums.ControlPointState.NEUTRAL

func force_capture(team_id: int) -> void:
    """Force capture by a specific team (for testing/admin)"""
    
    controlling_team = team_id
    current_state = GameEnums.ControlPointState.CONTROLLED
    capture_progress = 1.0
    is_being_captured = false
    
    _update_visual_state()
    control_point_captured.emit(control_point_id, controlling_team)

func reset_control_point() -> void:
    """Reset control point to neutral state"""
    
    controlling_team = 0
    current_state = GameEnums.ControlPointState.NEUTRAL
    capture_progress = 0.0
    is_being_captured = false
    units_in_range.clear()
    
    _update_visual_state()
    control_point_neutralized.emit(control_point_id)

func get_control_point_data() -> Dictionary:
    """Get control point data for networking/UI"""
    
    return {
        "id": control_point_id,
        "name": control_point_name,
        "controlling_team": controlling_team,
        "state": current_state,
        "capture_progress": capture_progress,
        "strategic_value": strategic_value,
        "position": [global_position.x, global_position.y, global_position.z],
        "teams_present": get_teams_present(),
        "is_contested": is_contested(),
        "is_controlled": is_controlled(),
        "is_neutral": is_neutral()
    } 