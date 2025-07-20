# NodeCaptureSystem.gd
class_name NodeCaptureSystem
extends Node

const NODES_TO_WIN = 9

var control_points: Array[Node] = []
var team_control_counts: Dictionary = {0: 0, 1: 0, 2: 0}

signal team_node_count_changed(team_id: int, new_count: int)
signal victory_achieved(team_id: int)

func _ready() -> void:
    add_to_group("node_capture_systems")

func initialize_control_points(map_node: Node) -> void:
    if not is_instance_valid(map_node) or not map_node.has_node("CaptureNodes"):
        print("NodeCaptureSystem: Invalid map node or CaptureNodes not found.")
        return

    control_points = map_node.get_node("CaptureNodes").get_children()
    team_control_counts[0] = control_points.size()
    
    for cp in control_points:
        if not cp.control_point_captured.is_connected(_on_control_point_state_changed):
            cp.control_point_captured.connect(_on_control_point_state_changed)
        if not cp.control_point_neutralized.is_connected(_on_control_point_state_changed):
            cp.control_point_neutralized.connect(_on_control_point_state_changed)
    
    update_team_control_counts()
    print("NodeCaptureSystem: Initialized with %d control points." % control_points.size())

func start_match() -> void:
    # Reset state at match start
    team_control_counts = {0: control_points.size(), 1: 0, 2: 0}
    for cp in control_points:
        if cp.has_method("reset_control_point"):
            cp.reset_control_point()
    emit_team_node_count_changed()
    print("NodeCaptureSystem: Match started, all points reset.")

func _on_control_point_state_changed(_point_id: String, _team_id: int):
    update_team_control_counts()

func update_team_control_counts() -> void:
    var new_counts = {0: 0, 1: 0, 2: 0}
    for cp in control_points:
        if not is_instance_valid(cp): continue
        var controlling_team = cp.get_controlling_team()
        if controlling_team in new_counts:
            new_counts[controlling_team] += 1
    
    var changed = false
    for team_id in new_counts:
        if not team_control_counts.has(team_id) or new_counts[team_id] != team_control_counts[team_id]:
            team_control_counts[team_id] = new_counts[team_id]
            changed = true
        
    if changed:
        emit_team_node_count_changed()
        check_for_victory()

func emit_team_node_count_changed() -> void:
    team_node_count_changed.emit(1, team_control_counts.get(1, 0))
    team_node_count_changed.emit(2, team_control_counts.get(2, 0))
    print("NodeCaptureSystem: Control counts updated: Team 1: %d, Team 2: %d, Neutral: %d" % [team_control_counts.get(1,0), team_control_counts.get(2,0), team_control_counts.get(0,0)])

func check_for_victory():
    if team_control_counts.get(1, 0) >= NODES_TO_WIN:
        victory_achieved.emit(1)
        print("NodeCaptureSystem: Victory condition met for Team 1.")
    elif team_control_counts.get(2, 0) >= NODES_TO_WIN:
        victory_achieved.emit(2)
        print("NodeCaptureSystem: Victory condition met for Team 2.")

func get_team_control_counts() -> Dictionary:
    """Returns the current count of controlled nodes for each team."""
    return team_control_counts.duplicate()

func get_closest_friendly_node(position: Vector3, team_id: int) -> Node:
    """Find the closest control point controlled by the specified team."""
    var friendly_nodes = []
    
    # Find all nodes controlled by this team
    for cp in control_points:
        if not is_instance_valid(cp): continue
        if cp.get_controlling_team() == team_id:
            friendly_nodes.append(cp)
    
    if friendly_nodes.is_empty():
        return null
    
    # Find the closest one
    var closest_node = null
    var closest_distance = INF
    
    for node in friendly_nodes:
        var distance = position.distance_to(node.global_position)
        if distance < closest_distance:
            closest_distance = distance
            closest_node = node
    
    return closest_node

func get_control_point_by_id(node_id: String) -> Node:
    """Get a control point by its ID."""
    for cp in control_points:
        if not is_instance_valid(cp): continue
        if cp.control_point_id == node_id:
            return cp
    return null

func get_control_points() -> Array[Node]:
    """Get all control points."""
    return control_points