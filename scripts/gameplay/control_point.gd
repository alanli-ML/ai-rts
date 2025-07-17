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

# Capture mechanics
const CAPTURE_SPEED_PER_UNIT_ADVANTAGE = 0.2 # 20% progress per second per unit advantage
var capture_value: float = 0.0 # -1.0 (Team 2 controlled) to +1.0 (Team 1 controlled). 0 is neutral.
var units_in_range: Dictionary = {}  # team_id -> Array[Unit]

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
signal control_point_neutralized(point_id: String, old_team_id: int)
signal capture_progress_changed(point_id: String, progress: float, team_id: int)

func _ready() -> void:
    if control_point_id.is_empty():
        push_error("ControlPoint ID must be set externally. Falling back to node name.")
        control_point_id = name
    if control_point_name.is_empty():
        control_point_name = name
    
    _create_visual_components()
    _create_capture_area()
    
    add_to_group("control_points")
    # Server is authoritative for capture logic
    set_physics_process(multiplayer.is_server())
    
    # Configure StaticBody3D to prevent physical blocking of units
    set_collision_layer_value(1, false)  # Not on unit layer (Layer 1 is for units)
    set_collision_layer_value(3, true)   # Put on a "buildings/static structures" layer
    set_collision_mask_value(1, false)   # Do not collide with units (Layer 1)
    
    print("ControlPoint %s (%s) initialized" % [control_point_id, control_point_name])

func _physics_process(delta: float) -> void:
    if not multiplayer.is_server():
        return

    _cleanup_invalid_units()

    var team1_units = units_in_range.get(1, []).size()
    var team2_units = units_in_range.get(2, []).size()
    
    var unit_advantage = team1_units - team2_units
    
    if unit_advantage != 0:
        var capture_delta = unit_advantage * CAPTURE_SPEED_PER_UNIT_ADVANTAGE * delta
        var old_capture_value = capture_value
        capture_value = clamp(capture_value + capture_delta, -1.0, 1.0)
        
        if abs(old_capture_value - capture_value) > 0.001:
             _check_for_state_change(old_capture_value)
             capture_progress_changed.emit(control_point_id, abs(capture_value), get_controlling_team())
    
    # On host, also update visuals directly to avoid relying on network loopback
    if DisplayServer.get_name() != "headless":
        var data_for_host = {
            "team_id": get_controlling_team(),
            "capture_value": capture_value
        }
        update_client_visuals(data_for_host)

func _check_for_state_change(old_value: float):
    var old_team = _get_team_from_value(old_value)
    var new_team = get_controlling_team()
    
    if old_team != new_team:
        if new_team == 0:
            control_point_neutralized.emit(control_point_id, old_team)
            print("ControlPoint %s neutralized from Team %d" % [control_point_id, old_team])
        else:
            control_point_captured.emit(control_point_id, new_team)
            print("ControlPoint %s captured by Team %d" % [control_point_id, new_team])

func get_controlling_team() -> int:
    return _get_team_from_value(capture_value)

func _get_team_from_value(value: float) -> int:
    if value >= 1.0: return 1
    if value <= -1.0: return 2
    return 0

func _create_visual_components():
    base_mesh = MeshInstance3D.new()
    base_mesh.name = "BaseMesh"
    base_mesh.mesh = CylinderMesh.new()
    base_mesh.mesh.top_radius = GameConstants.CONTROL_POINT_RADIUS * 0.8
    base_mesh.mesh.bottom_radius = GameConstants.CONTROL_POINT_RADIUS * 0.8
    base_mesh.mesh.height = 1.0 # Make it taller
    base_mesh.position.y = 0.5 # Lift it so its bottom is at y=0 relative to the control point
    var base_material = StandardMaterial3D.new()
    base_material.albedo_color = team_colors[0]
    base_material.metallic = 0.3
    base_material.roughness = 0.7
    base_mesh.material_override = base_material
    add_child(base_mesh)

    # Add progress ring for capture visualization
    progress_ring = MeshInstance3D.new()
    progress_ring.name = "ProgressRing"
    var ring_mesh = TorusMesh.new()
    ring_mesh.inner_radius = GameConstants.CONTROL_POINT_RADIUS - 0.5 # Make it thicker
    ring_mesh.outer_radius = GameConstants.CONTROL_POINT_RADIUS
    progress_ring.mesh = ring_mesh
    progress_ring.rotation_degrees.x = 90
    progress_ring.position.y = 1.01 # Place it on top of the taller base mesh
    var ring_material = StandardMaterial3D.new()
    ring_material.albedo_color = Color.YELLOW
    ring_material.emission_enabled = true
    ring_material.emission = Color.YELLOW
    ring_material.emission_energy_multiplier = 2.0
    ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED # To make it visible from both sides
    progress_ring.material_override = ring_material
    progress_ring.visible = false
    add_child(progress_ring)

    # Add a label for the node number
    var number_label = Label3D.new()
    number_label.name = "NumberLabel"
    
    # Extract number from ID (e.g., "Node1" -> "1")
    var node_number_str = control_point_id.trim_prefix("Node")
    number_label.text = node_number_str
    
    number_label.font_size = 128
    number_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
    number_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
    number_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    number_label.position = Vector3(0, 2.5, 0) # Position it above the cylinder
    number_label.modulate = Color(1, 1, 1, 0.8) # White, slightly transparent
    add_child(number_label)

func _create_capture_area():
    capture_area = Area3D.new()
    capture_area.name = "CaptureArea"
    var collision_shape = CollisionShape3D.new()
    collision_shape.name = "CollisionShape3D"
    var shape = CylinderShape3D.new()
    shape.height = 4.0
    shape.radius = GameConstants.CONTROL_POINT_RADIUS
    collision_shape.shape = shape
    collision_shape.position.y = 2.0
    capture_area.add_child(collision_shape)
    capture_area.body_entered.connect(_on_unit_entered)
    capture_area.body_exited.connect(_on_unit_exited)
    add_child(capture_area)

func _on_unit_entered(body: Node3D):
    if not body is Unit: return
    var team_id = body.team_id
    if not units_in_range.has(team_id):
        units_in_range[team_id] = []
    if not body in units_in_range[team_id]:
        units_in_range[team_id].append(body)

func _on_unit_exited(body: Node3D):
    if not body is Unit: return
    var team_id = body.team_id
    if units_in_range.has(team_id):
        units_in_range[team_id].erase(body)
        if units_in_range[team_id].is_empty():
            units_in_range.erase(team_id)

func _cleanup_invalid_units():
    for team_id in units_in_range.keys():
        units_in_range[team_id] = units_in_range[team_id].filter(
            func(unit): return is_instance_valid(unit) and not unit.is_dead
        )
        if units_in_range[team_id].is_empty():
            units_in_range.erase(team_id)

func update_client_visuals(data: Dictionary):
    var team_id = data.get("team_id", 0)
    var new_capture_value = data.get("capture_value", 0.0)

    # Update base color
    if base_mesh and base_mesh.material_override:
        var target_color = team_colors.get(team_id, team_colors[0])
        # Set color directly for immediate feedback
        base_mesh.material_override.albedo_color = target_color

    # Update progress ring
    if progress_ring and progress_ring.material_override:
        var is_contested = (abs(new_capture_value) < 1.0 and new_capture_value != 0.0)
        progress_ring.visible = is_contested

        if is_contested:
            var progress = abs(new_capture_value)
            
            # Determine which team is capturing to set the color
            var capturing_team_id
            if new_capture_value > 0: # Team 1 is capturing/losing
                capturing_team_id = 1
            else: # Team 2 is capturing/losing
                capturing_team_id = 2
            
            var ring_color = team_colors.get(capturing_team_id, Color.YELLOW)
            progress_ring.material_override.albedo_color = ring_color
            progress_ring.material_override.emission = ring_color
            
            # Animate progress by scaling.
            # This makes the ring grow from the center as a point is captured.
            # Scale on X and Y because the Torus is rotated to lie flat in the XY plane.
            progress_ring.scale = Vector3(progress, progress, 1.0)

func reset_control_point():
    capture_value = 0.0
    units_in_range.clear()
    _check_for_state_change(1) # Force state check and signal emit
    print("ControlPoint %s has been reset." % control_point_id)