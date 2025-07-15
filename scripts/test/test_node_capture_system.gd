# TestNodeCaptureSystem.gd
extends Node

# Test script for node capture system
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const NodeCaptureSystem = preload("res://scripts/gameplay/node_capture_system.gd")

var node_capture_system: NodeCaptureSystem = null
var test_units: Array = []

func _ready() -> void:
    # Create node capture system
    node_capture_system = NodeCaptureSystem.new()
    node_capture_system.name = "NodeCaptureSystem"
    add_child(node_capture_system)
    
    # Wait a bit for the scene to be ready
    await get_tree().process_frame
    
    # Find test units
    _find_test_units()
    
    # Connect signals
    _connect_signals()
    
    print("TestNodeCaptureSystem: Test script initialized")

func _find_test_units() -> void:
    """Find units in the scene to test with"""
    test_units = get_tree().get_nodes_in_group("units")
    
    if test_units.size() > 0:
        print("TestNodeCaptureSystem: Found %d units for testing" % test_units.size())
    else:
        print("TestNodeCaptureSystem: No units found for testing")

func _connect_signals() -> void:
    """Connect to node capture system signals"""
    
    node_capture_system.control_point_captured.connect(_on_control_point_captured)
    node_capture_system.control_point_contested.connect(_on_control_point_contested)
    node_capture_system.control_point_neutralized.connect(_on_control_point_neutralized)
    node_capture_system.team_control_changed.connect(_on_team_control_changed)
    node_capture_system.victory_condition_met.connect(_on_victory_condition_met)
    node_capture_system.capture_progress_updated.connect(_on_capture_progress_updated)
    
    print("TestNodeCaptureSystem: Signals connected")

func _input(event: InputEvent) -> void:
    """Handle input for testing"""
    
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1:
                test_control_point_creation()
            KEY_2:
                test_force_capture_points()
            KEY_3:
                test_team_control_distribution()
            KEY_4:
                test_victory_conditions()
            KEY_5:
                test_strategic_recommendations()
            KEY_6:
                test_nearest_control_point()
            KEY_7:
                test_control_points_in_radius()
            KEY_8:
                test_reset_all_points()
            KEY_9:
                show_system_statistics()
            KEY_0:
                show_victory_progress()
            KEY_MINUS:
                test_capture_center_point()
            KEY_EQUAL:
                test_perimeter_victory()
            KEY_R:
                reset_test_scenario()
            KEY_H:
                print_help()

func test_control_point_creation() -> void:
    """Test that all control points were created properly"""
    
    var control_points = node_capture_system.get_all_control_points()
    
    print("TestNodeCaptureSystem: Control Point Creation Test")
    print("  Total control points: %d" % control_points.size())
    print("  Expected: %d" % GameConstants.CONTROL_POINT_COUNT)
    
    for i in range(control_points.size()):
        var point = control_points[i]
        print("  Point %d: %s - State: %s, Team: %d, Value: %d" % [
            i, 
            point.get_control_point_name(), 
            _get_state_string(point.get_current_state()),
            point.get_controlling_team(),
            point.get_strategic_value()
        ])
    
    # Test center point has highest value
    var center_point = node_capture_system.get_control_point("cp_4")
    if center_point:
        print("  Center point strategic value: %d" % center_point.get_strategic_value())
    
    print("TestNodeCaptureSystem: Control point creation test completed")

func test_force_capture_points() -> void:
    """Test force capturing control points"""
    
    print("TestNodeCaptureSystem: Force Capture Test")
    
    # Capture some points for team 1
    var team1_points = ["cp_0", "cp_1", "cp_4"]  # Including center
    for point_id in team1_points:
        var success = node_capture_system.force_capture_point(point_id, 1)
        if success:
            print("  Captured %s for team 1" % point_id)
        else:
            print("  Failed to capture %s for team 1" % point_id)
    
    # Capture some points for team 2
    var team2_points = ["cp_2", "cp_3", "cp_5"]
    for point_id in team2_points:
        var success = node_capture_system.force_capture_point(point_id, 2)
        if success:
            print("  Captured %s for team 2" % point_id)
        else:
            print("  Failed to capture %s for team 2" % point_id)
    
    print("TestNodeCaptureSystem: Force capture test completed")

func test_team_control_distribution() -> void:
    """Test team control distribution calculation"""
    
    print("TestNodeCaptureSystem: Team Control Distribution Test")
    
    var distribution = node_capture_system.get_control_distribution()
    
    for team_id in distribution:
        var team_data = distribution[team_id]
        print("  Team %d:" % team_id)
        print("    Control points: %d" % team_data.count)
        print("    Percentage: %.1f%%" % team_data.percentage)
        print("    Strategic value: %d" % team_data.strategic_value)
    
    print("TestNodeCaptureSystem: Team control distribution test completed")

func test_victory_conditions() -> void:
    """Test victory condition checking"""
    
    print("TestNodeCaptureSystem: Victory Conditions Test")
    
    # Test threshold victory (7 points)
    print("  Testing threshold victory...")
    var threshold_points = ["cp_0", "cp_1", "cp_2", "cp_3", "cp_4", "cp_5", "cp_6"]
    for point_id in threshold_points:
        node_capture_system.force_capture_point(point_id, 1)
    
    await get_tree().process_frame
    
    if node_capture_system.is_victory_achieved():
        print("  Threshold victory detected for team %d" % node_capture_system.get_winning_team())
    else:
        print("  Threshold victory not detected")
    
    # Reset for next test
    node_capture_system.reset_all_control_points()
    
    print("TestNodeCaptureSystem: Victory conditions test completed")

func test_strategic_recommendations() -> void:
    """Test strategic recommendations system"""
    
    print("TestNodeCaptureSystem: Strategic Recommendations Test")
    
    # Set up a scenario
    node_capture_system.force_capture_point("cp_1", 1)  # Team 1 has northern command
    node_capture_system.force_capture_point("cp_3", 2)  # Team 2 has west garrison
    
    # Get recommendations for both teams
    for team_id in [1, 2]:
        var recommendations = node_capture_system.get_strategic_recommendations(team_id)
        print("  Team %d recommendations:" % team_id)
        
        for rec in recommendations:
            print("    %s: %s (Priority: %s)" % [rec.type, rec.reason, rec.priority])
    
    print("TestNodeCaptureSystem: Strategic recommendations test completed")

func test_nearest_control_point() -> void:
    """Test nearest control point finding"""
    
    print("TestNodeCaptureSystem: Nearest Control Point Test")
    
    # Test various positions
    var test_positions = [
        Vector3(0, 0, 0),      # Center
        Vector3(-30, 0, -30),  # Far northwest
        Vector3(30, 0, 30),    # Far southeast
        Vector3(0, 0, -10)     # North of center
    ]
    
    for pos in test_positions:
        var nearest = node_capture_system.get_nearest_control_point(pos)
        if nearest:
            print("  Position %s -> Nearest: %s" % [pos, nearest.get_control_point_name()])
        else:
            print("  Position %s -> No nearest point found" % pos)
    
    print("TestNodeCaptureSystem: Nearest control point test completed")

func test_control_points_in_radius() -> void:
    """Test control points in radius finding"""
    
    print("TestNodeCaptureSystem: Control Points in Radius Test")
    
    # Test from center position
    var center_pos = Vector3(0, 0, 0)
    var test_radii = [10.0, 20.0, 30.0, 50.0]
    
    for radius in test_radii:
        var points = node_capture_system.get_control_points_in_radius(center_pos, radius)
        print("  Radius %.1f from center: %d points" % [radius, points.size()])
        
        for point in points:
            var distance = center_pos.distance_to(point.global_position)
            print("    %s (%.1f units away)" % [point.get_control_point_name(), distance])
    
    print("TestNodeCaptureSystem: Control points in radius test completed")

func test_reset_all_points() -> void:
    """Test resetting all control points"""
    
    print("TestNodeCaptureSystem: Reset All Points Test")
    
    # Capture some points first
    node_capture_system.force_capture_point("cp_0", 1)
    node_capture_system.force_capture_point("cp_4", 2)
    
    print("  Before reset:")
    _show_control_point_summary()
    
    # Reset all points
    node_capture_system.reset_all_control_points()
    
    print("  After reset:")
    _show_control_point_summary()
    
    print("TestNodeCaptureSystem: Reset all points test completed")

func test_capture_center_point() -> void:
    """Test strategic victory via center point control"""
    
    print("TestNodeCaptureSystem: Center Point Strategic Test")
    
    # Give team 1 center + 4 other points
    var strategic_points = ["cp_4", "cp_0", "cp_1", "cp_2", "cp_3"]  # Center + 4 others
    for point_id in strategic_points:
        node_capture_system.force_capture_point(point_id, 1)
    
    await get_tree().process_frame
    
    if node_capture_system.is_victory_achieved():
        print("  Strategic victory detected for team %d" % node_capture_system.get_winning_team())
    else:
        print("  Strategic victory not detected")
    
    # Reset for next test
    node_capture_system.reset_all_control_points()
    
    print("TestNodeCaptureSystem: Center point strategic test completed")

func test_perimeter_victory() -> void:
    """Test perimeter victory condition"""
    
    print("TestNodeCaptureSystem: Perimeter Victory Test")
    
    # Give team 1 all outer points (not center)
    var outer_points = ["cp_0", "cp_1", "cp_2", "cp_3", "cp_5", "cp_6", "cp_7", "cp_8"]
    for point_id in outer_points:
        node_capture_system.force_capture_point(point_id, 1)
    
    await get_tree().process_frame
    
    if node_capture_system.is_victory_achieved():
        print("  Perimeter victory detected for team %d" % node_capture_system.get_winning_team())
    else:
        print("  Perimeter victory not detected")
    
    # Reset for next test
    node_capture_system.reset_all_control_points()
    
    print("TestNodeCaptureSystem: Perimeter victory test completed")

func show_system_statistics() -> void:
    """Show system statistics"""
    
    var stats = node_capture_system.get_system_statistics()
    print("TestNodeCaptureSystem: System Statistics")
    print("  Total control points: %d" % stats.total_control_points)
    print("  Contested points: %d" % stats.contested_points)
    print("  Neutral points: %d" % stats.neutral_points)
    print("  Capture events: %d" % stats.capture_events)
    print("  Victory achieved: %s" % stats.victory_conditions_met)
    print("  Winning team: %d" % stats.winning_team)
    
    print("  Team Control Counts:")
    for team_id in stats.team_control_counts:
        print("    Team %d: %d points" % [team_id, stats.team_control_counts[team_id]])
    
    print("  Strategic Values:")
    for team_id in stats.total_strategic_value:
        print("    Team %d: %d value" % [team_id, stats.total_strategic_value[team_id]])

func show_victory_progress() -> void:
    """Show victory progress for all teams"""
    
    print("TestNodeCaptureSystem: Victory Progress")
    
    for team_id in [1, 2]:
        var progress = node_capture_system.get_victory_progress(team_id)
        print("  Team %d:" % team_id)
        print("    Control points: %d/%d (%.1f%%)" % [
            progress.control_points,
            progress.control_threshold,
            progress.control_progress
        ])
        print("    Strategic value: %d" % progress.strategic_value)
        print("    Has center: %s" % progress.has_center_control)
        print("    Strategic victory possible: %s" % progress.strategic_victory_possible)
        print("    Perimeter victory possible: %s" % progress.perimeter_victory_possible)

func reset_test_scenario() -> void:
    """Reset to clean test scenario"""
    
    print("TestNodeCaptureSystem: Resetting test scenario")
    node_capture_system.reset_all_control_points()
    print("  All control points reset to neutral")

func _show_control_point_summary() -> void:
    """Show summary of all control points"""
    
    var control_points = node_capture_system.get_all_control_points()
    
    for point in control_points:
        print("    %s: %s (Team %d)" % [
            point.get_control_point_name(),
            _get_state_string(point.get_current_state()),
            point.get_controlling_team()
        ])

func _get_state_string(state: int) -> String:
    """Convert state enum to string"""
    
    match state:
        0: return "NEUTRAL"
        1: return "CONTESTED"
        2: return "CONTROLLED"
        _: return "UNKNOWN"

# Signal handlers
func _on_control_point_captured(point_id: String, team_id: int) -> void:
    """Handle control point captured signal"""
    var point = node_capture_system.get_control_point(point_id)
    if point:
        print("TestNodeCaptureSystem: %s captured by team %d" % [point.get_control_point_name(), team_id])

func _on_control_point_contested(point_id: String, teams: Array) -> void:
    """Handle control point contested signal"""
    var point = node_capture_system.get_control_point(point_id)
    if point:
        print("TestNodeCaptureSystem: %s contested by teams %s" % [point.get_control_point_name(), teams])

func _on_control_point_neutralized(point_id: String) -> void:
    """Handle control point neutralized signal"""
    var point = node_capture_system.get_control_point(point_id)
    if point:
        print("TestNodeCaptureSystem: %s neutralized" % point.get_control_point_name())

func _on_team_control_changed(team_id: int, control_count: int) -> void:
    """Handle team control changed signal"""
    print("TestNodeCaptureSystem: Team %d now controls %d points" % [team_id, control_count])

func _on_victory_condition_met(team_id: int, condition_type: String) -> void:
    """Handle victory condition met signal"""
    print("TestNodeCaptureSystem: 🎉 VICTORY! Team %d achieved %s victory!" % [team_id, condition_type])

func _on_capture_progress_updated(point_id: String, progress: float) -> void:
    """Handle capture progress updated signal"""
    var point = node_capture_system.get_control_point(point_id)
    if point:
        print("TestNodeCaptureSystem: %s capture progress: %.1f%%" % [point.get_control_point_name(), progress * 100])

func print_help() -> void:
    """Print help information"""
    
    print("TestNodeCaptureSystem: Number key shortcuts:")
    print("  1 - Test control point creation")
    print("  2 - Test force capture points")
    print("  3 - Test team control distribution")
    print("  4 - Test victory conditions")
    print("  5 - Test strategic recommendations")
    print("  6 - Test nearest control point")
    print("  7 - Test control points in radius")
    print("  8 - Test reset all points")
    print("  9 - Show system statistics")
    print("  0 - Show victory progress")
    print("  - - Test capture center point")
    print("  = - Test perimeter victory")
    print("  R - Reset test scenario")
    print("  H - Show this help")

func _enter_tree() -> void:
    """Called when entering the tree"""
    
    # Wait a bit then print help
    await get_tree().create_timer(1.0).timeout
    print_help() 