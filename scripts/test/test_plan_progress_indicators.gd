# TestPlanProgressIndicators.gd
extends Node

# Test script for plan progress indicator system
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const PlanProgressManager = preload("res://scripts/ui/plan_progress_manager.gd")
const PlanExecutor = preload("res://scripts/ai/plan_executor.gd")

var plan_progress_manager: PlanProgressManager = null
var plan_executor: PlanExecutor = null
var test_units: Array = []

func _ready() -> void:
    # Create plan progress manager
    plan_progress_manager = PlanProgressManager.new()
    plan_progress_manager.name = "PlanProgressManager"
    add_child(plan_progress_manager)
    
    # Create plan executor
    plan_executor = PlanExecutor.new()
    plan_executor.name = "PlanExecutor"
    add_child(plan_executor)
    
    # Wait a bit for the scene to be ready
    await get_tree().process_frame
    
    # Find test units
    _find_test_units()
    
    # Connect signals
    _connect_signals()
    
    print("TestPlanProgressIndicators: Test script initialized")

func _find_test_units() -> void:
    """Find units in the scene to test with"""
    test_units = get_tree().get_nodes_in_group("units")
    
    if test_units.size() > 0:
        print("TestPlanProgressIndicators: Found %d units for testing" % test_units.size())
    else:
        print("TestPlanProgressIndicators: No units found for testing")

func _connect_signals() -> void:
    """Connect to plan progress manager signals"""
    
    plan_progress_manager.plan_indicator_created.connect(_on_plan_indicator_created)
    plan_progress_manager.plan_indicator_clicked.connect(_on_plan_indicator_clicked)
    plan_progress_manager.plan_indicator_finished.connect(_on_plan_indicator_finished)
    
    print("TestPlanProgressIndicators: Signals connected")

func _input(event: InputEvent) -> void:
    """Handle input for testing"""
    
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1:
                test_basic_plan_indicator()
            KEY_2:
                test_multiple_plan_indicators()
            KEY_3:
                test_plan_with_triggers()
            KEY_4:
                test_plan_with_duration()
            KEY_5:
                test_multi_step_plan()
            KEY_6:
                test_plan_interruption()
            KEY_7:
                test_team_colors()
            KEY_8:
                test_plan_progress_updates()
            KEY_9:
                show_plan_progress_stats()
            KEY_0:
                hide_all_plan_indicators()
            KEY_MINUS:
                test_plan_executor_integration()
            KEY_EQUAL:
                test_complex_plan_scenario()

func test_basic_plan_indicator() -> void:
    """Test basic plan progress indicator"""
    
    if test_units.size() == 0:
        print("TestPlanProgressIndicators: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Create basic plan data
    var plan_data = {
        "unit_id": unit_id,
        "total_steps": 3,
        "current_step": 0,
        "progress_percent": 25.0,
        "current_step_action": "move_to",
        "current_step_trigger": ""
    }
    
    var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
    var success = plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    if success:
        print("TestPlanProgressIndicators: Basic plan indicator shown for unit %s" % unit_id)
    else:
        print("TestPlanProgressIndicators: Failed to show basic plan indicator")

func test_multiple_plan_indicators() -> void:
    """Test multiple plan progress indicators at once"""
    
    if test_units.size() < 2:
        print("TestPlanProgressIndicators: Need at least 2 units for this test")
        return
    
    var actions = ["move_to", "attack", "retreat", "patrol", "use_ability"]
    var triggers = ["", "health_pct < 50", "enemy_dist < 10", "time > 5", "enemy_count > 2"]
    
    for i in range(min(test_units.size(), 5)):
        var unit = test_units[i]
        var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
        var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
        
        var plan_data = {
            "unit_id": unit_id,
            "total_steps": 4,
            "current_step": i % 4,
            "progress_percent": (i * 25.0) % 100.0,
            "current_step_action": actions[i % actions.size()],
            "current_step_trigger": triggers[i % triggers.size()]
        }
        
        plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    print("TestPlanProgressIndicators: Multiple plan indicators created")

func test_plan_with_triggers() -> void:
    """Test plan indicator with trigger conditions"""
    
    if test_units.size() == 0:
        print("TestPlanProgressIndicators: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
    
    # Create plan data with complex trigger
    var plan_data = {
        "unit_id": unit_id,
        "total_steps": 2,
        "current_step": 0,
        "progress_percent": 0.0,
        "current_step_action": "move_to",
        "current_step_trigger": "health_pct > 70 AND enemy_dist > 15"
    }
    
    var success = plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    if success:
        print("TestPlanProgressIndicators: Plan with triggers shown for unit %s" % unit_id)
    else:
        print("TestPlanProgressIndicators: Failed to show plan with triggers")

func test_plan_with_duration() -> void:
    """Test plan indicator with duration-based progress"""
    
    if test_units.size() == 0:
        print("TestPlanProgressIndicators: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
    
    # Create plan data with duration
    var plan_data = {
        "unit_id": unit_id,
        "total_steps": 1,
        "current_step": 0,
        "progress_percent": 0.0,
        "current_step_action": "use_ability",
        "current_step_trigger": ""
    }
    
    var success = plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    if success:
        print("TestPlanProgressIndicators: Plan with duration shown for unit %s" % unit_id)
        
        # Simulate progress updates
        _simulate_progress_updates(unit_id)
    else:
        print("TestPlanProgressIndicators: Failed to show plan with duration")

func _simulate_progress_updates(unit_id: String) -> void:
    """Simulate progress updates for a plan"""
    
    for i in range(10):
        await get_tree().create_timer(0.3).timeout
        
        var updated_plan_data = {
            "unit_id": unit_id,
            "total_steps": 1,
            "current_step": 0,
            "progress_percent": i * 10.0,
            "current_step_action": "use_ability",
            "current_step_trigger": ""
        }
        
        plan_progress_manager.update_plan_progress(unit_id, updated_plan_data)

func test_multi_step_plan() -> void:
    """Test multi-step plan progression"""
    
    if test_units.size() == 0:
        print("TestPlanProgressIndicators: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
    
    # Create multi-step plan
    var steps = [
        {"action": "move_to", "trigger": ""},
        {"action": "stance", "trigger": "time > 2"},
        {"action": "attack", "trigger": "enemy_dist < 8"},
        {"action": "retreat", "trigger": "health_pct < 30"}
    ]
    
    # Show initial step
    var plan_data = {
        "unit_id": unit_id,
        "total_steps": steps.size(),
        "current_step": 0,
        "progress_percent": 0.0,
        "current_step_action": steps[0].action,
        "current_step_trigger": steps[0].trigger
    }
    
    var success = plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    if success:
        print("TestPlanProgressIndicators: Multi-step plan shown for unit %s" % unit_id)
        
        # Simulate step progression
        _simulate_step_progression(unit_id, steps)
    else:
        print("TestPlanProgressIndicators: Failed to show multi-step plan")

func _simulate_step_progression(unit_id: String, steps: Array) -> void:
    """Simulate step progression for a multi-step plan"""
    
    for i in range(steps.size()):
        await get_tree().create_timer(2.0).timeout
        
        var updated_plan_data = {
            "unit_id": unit_id,
            "total_steps": steps.size(),
            "current_step": i,
            "progress_percent": (i / float(steps.size())) * 100.0,
            "current_step_action": steps[i].action,
            "current_step_trigger": steps[i].trigger
        }
        
        plan_progress_manager.update_plan_progress(unit_id, updated_plan_data)

func test_plan_interruption() -> void:
    """Test plan interruption"""
    
    if test_units.size() == 0:
        print("TestPlanProgressIndicators: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
    
    # Create plan data
    var plan_data = {
        "unit_id": unit_id,
        "total_steps": 1,
        "current_step": 0,
        "progress_percent": 50.0,
        "current_step_action": "move_to",
        "current_step_trigger": ""
    }
    
    var success = plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    if success:
        print("TestPlanProgressIndicators: Plan shown for interruption test")
        
        # Hide after 3 seconds
        await get_tree().create_timer(3.0).timeout
        plan_progress_manager.hide_plan_progress(unit_id)
        print("TestPlanProgressIndicators: Plan interrupted for unit %s" % unit_id)
    else:
        print("TestPlanProgressIndicators: Failed to show plan for interruption test")

func test_team_colors() -> void:
    """Test team-colored plan indicators"""
    
    if test_units.size() < 2:
        print("TestPlanProgressIndicators: Need at least 2 units for team color test")
        return
    
    # Set custom team colors
    plan_progress_manager.set_team_color(1, Color.BLUE)
    plan_progress_manager.set_team_color(2, Color.RED)
    
    # Show indicators for different teams
    for i in range(min(test_units.size(), 4)):
        var unit = test_units[i]
        var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
        var team_id = (i % 2) + 1  # Alternate between team 1 and 2
        
        var plan_data = {
            "unit_id": unit_id,
            "total_steps": 2,
            "current_step": 0,
            "progress_percent": 30.0,
            "current_step_action": "move_to",
            "current_step_trigger": ""
        }
        
        plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    print("TestPlanProgressIndicators: Team-colored plan indicators created")

func test_plan_progress_updates() -> void:
    """Test real-time plan progress updates"""
    
    if test_units.size() == 0:
        print("TestPlanProgressIndicators: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
    
    # Show initial indicator
    var plan_data = {
        "unit_id": unit_id,
        "total_steps": 3,
        "current_step": 0,
        "progress_percent": 0.0,
        "current_step_action": "move_to",
        "current_step_trigger": ""
    }
    
    var success = plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    if success:
        print("TestPlanProgressIndicators: Testing real-time updates")
        
        # Simulate various updates
        _simulate_realtime_updates(unit_id)
    else:
        print("TestPlanProgressIndicators: Failed to show plan for update test")

func _simulate_realtime_updates(unit_id: String) -> void:
    """Simulate real-time plan updates"""
    
    var actions = ["move_to", "attack", "retreat"]
    var triggers = ["", "enemy_dist < 10", "health_pct < 50"]
    
    for i in range(15):
        await get_tree().create_timer(0.5).timeout
        
        var step_index = i % 3
        var progress = (i * 10.0) % 100.0
        
        var updated_plan_data = {
            "unit_id": unit_id,
            "total_steps": 3,
            "current_step": step_index,
            "progress_percent": progress,
            "current_step_action": actions[step_index],
            "current_step_trigger": triggers[step_index]
        }
        
        plan_progress_manager.update_plan_progress(unit_id, updated_plan_data)

func test_plan_executor_integration() -> void:
    """Test integration with actual plan executor"""
    
    if test_units.size() == 0:
        print("TestPlanProgressIndicators: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Create a real plan for the plan executor
    var plan_data = {
        "steps": [
            {
                "action": "move_to",
                "params": {"position": [5, 0, 5]},
                "trigger": "",
                "speech": "Moving to position",
                "duration_ms": 3000
            },
            {
                "action": "attack",
                "params": {},
                "trigger": "enemy_dist < 8",
                "speech": "Engaging enemy!",
                "duration_ms": 0
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestPlanProgressIndicators: Plan executor integration test started")
    else:
        print("TestPlanProgressIndicators: Failed to start plan executor integration test")

func test_complex_plan_scenario() -> void:
    """Test complex plan scenario with multiple units"""
    
    if test_units.size() < 3:
        print("TestPlanProgressIndicators: Need at least 3 units for complex scenario")
        return
    
    # Create different plans for different units
    var scenarios = [
        {
            "action": "patrol",
            "trigger": "enemy_dist > 20",
            "steps": 5,
            "progress": 40.0
        },
        {
            "action": "attack",
            "trigger": "health_pct > 30 AND enemy_dist < 15",
            "steps": 3,
            "progress": 75.0
        },
        {
            "action": "retreat",
            "trigger": "health_pct < 25 OR enemy_count > 3",
            "steps": 2,
            "progress": 20.0
        }
    ]
    
    for i in range(min(test_units.size(), scenarios.size())):
        var unit = test_units[i]
        var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
        var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
        var scenario = scenarios[i]
        
        var plan_data = {
            "unit_id": unit_id,
            "total_steps": scenario.steps,
            "current_step": 0,
            "progress_percent": scenario.progress,
            "current_step_action": scenario.action,
            "current_step_trigger": scenario.trigger
        }
        
        plan_progress_manager.show_plan_progress(unit_id, plan_data, team_id)
    
    print("TestPlanProgressIndicators: Complex scenario with %d units created" % scenarios.size())

func show_plan_progress_stats() -> void:
    """Show plan progress statistics"""
    
    var stats = plan_progress_manager.get_statistics()
    print("TestPlanProgressIndicators: Plan Progress Statistics:")
    print("  Indicators created: %d" % stats.indicators_created)
    print("  Indicators clicked: %d" % stats.indicators_clicked)
    print("  Total plans tracked: %d" % stats.total_plans_tracked)
    print("  Active plan count: %d" % stats.active_plan_count)
    print("  Active indicator count: %d" % plan_progress_manager.get_active_indicator_count())

func hide_all_plan_indicators() -> void:
    """Hide all plan progress indicators"""
    
    plan_progress_manager.hide_all_plan_progress()
    print("TestPlanProgressIndicators: All plan progress indicators hidden")

# Signal handlers
func _on_plan_indicator_created(unit_id: String) -> void:
    """Handle plan indicator created signal"""
    print("TestPlanProgressIndicators: Plan indicator created for unit %s" % unit_id)

func _on_plan_indicator_clicked(unit_id: String) -> void:
    """Handle plan indicator clicked signal"""
    print("TestPlanProgressIndicators: Plan indicator clicked for unit %s" % unit_id)

func _on_plan_indicator_finished(unit_id: String) -> void:
    """Handle plan indicator finished signal"""
    print("TestPlanProgressIndicators: Plan indicator finished for unit %s" % unit_id)

func print_help() -> void:
    """Print help information"""
    
    print("TestPlanProgressIndicators: Number key shortcuts:")
    print("  1 - Test basic plan indicator")
    print("  2 - Test multiple plan indicators")
    print("  3 - Test plan with triggers")
    print("  4 - Test plan with duration")
    print("  5 - Test multi-step plan")
    print("  6 - Test plan interruption")
    print("  7 - Test team colors")
    print("  8 - Test plan progress updates")
    print("  9 - Show plan progress stats")
    print("  0 - Hide all plan indicators")
    print("  - - Test plan executor integration")
    print("  = - Test complex plan scenario")

func _enter_tree() -> void:
    """Called when entering the tree"""
    
    # Wait a bit then print help
    await get_tree().create_timer(1.0).timeout
    print_help() 