# NodeCaptureSystem.gd
class_name NodeCaptureSystem
extends Node

var control_points: Array[Node] = []
var team_control_counts: Dictionary = {1: 0, 2: 0}

signal team_node_count_changed(team_id: int, new_count: int)

func _ready() -> void:
    add_to_group("node_capture_systems")

func initialize_control_points(map_node: Node) -> void:
    control_points = map_node.get_node("CaptureNodes").get_children()
    for cp in control_points:
        # Simplified: connect to a signal if ControlPoint had one
        # For now, we'll just manage state here.
        pass
    
    update_team_control_counts()

func start_match() -> void:
    # Reset state at match start
    team_control_counts = {1: 0, 2: 0}
    # Logic to reset control points to neutral would go here.
    emit_team_node_count_changed()

func _on_control_point_captured(_point_id: String, _team_id: int) -> void:
    # This would be called by a signal from a ControlPoint
    update_team_control_counts()

func update_team_control_counts() -> void:
    var new_counts = {1: 0, 2: 0}
    for cp in control_points:
        var controlling_team = cp.get_meta("controlling_team", 0)
        if controlling_team in new_counts:
            new_counts[controlling_team] += 1
    
    var changed = false
    if new_counts[1] != team_control_counts[1]:
        team_control_counts[1] = new_counts[1]
        changed = true
    if new_counts[2] != team_control_counts[2]:
        team_control_counts[2] = new_counts[2]
        changed = true
        
    if changed:
        emit_team_node_count_changed()

func emit_team_node_count_changed() -> void:
    team_node_count_changed.emit(1, team_control_counts[1])
    team_node_count_changed.emit(2, team_control_counts[2])