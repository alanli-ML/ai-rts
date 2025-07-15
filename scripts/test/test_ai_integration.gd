# TestAIIntegration.gd
extends Node

# Test script for AI integration with enhanced plan execution system
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const AICommandProcessor = preload("res://scripts/ai/ai_command_processor.gd")
const PlanExecutor = preload("res://scripts/ai/plan_executor.gd")
const ActionValidator = preload("res://scripts/ai/action_validator.gd")

var ai_command_processor: AICommandProcessor = null
var plan_executor: PlanExecutor = null
var action_validator: ActionValidator = null
var test_units: Array = []

func _ready() -> void:
    # Create AI system components
    _setup_ai_components()
    
    # Wait for scene to be ready
    await get_tree().process_frame
    
    # Find test units
    _find_test_units()
    
    print("TestAIIntegration: AI integration test script initialized")

func _setup_ai_components() -> void:
    """Set up AI system components for testing"""
    
    # Create AI command processor
    ai_command_processor = AICommandProcessor.new()
    ai_command_processor.name = "AICommandProcessor"
    add_child(ai_command_processor)
    
    # Create plan executor
    plan_executor = PlanExecutor.new()
    plan_executor.name = "PlanExecutor"
    add_child(plan_executor)
    
    # Create action validator
    action_validator = ActionValidator.new()
    action_validator.name = "ActionValidator"
    add_child(action_validator)
    
    # Connect signals
    plan_executor.plan_started.connect(_on_plan_started)
    plan_executor.plan_completed.connect(_on_plan_completed)
    plan_executor.plan_interrupted.connect(_on_plan_interrupted)
    plan_executor.step_executed.connect(_on_step_executed)
    plan_executor.trigger_evaluated.connect(_on_trigger_evaluated)
    
    print("TestAIIntegration: AI components created and connected")

func _find_test_units() -> void:
    """Find units in the scene to test with"""
    test_units = get_tree().get_nodes_in_group("units")
    
    if test_units.size() > 0:
        print("TestAIIntegration: Found %d units for testing" % test_units.size())
    else:
        print("TestAIIntegration: No units found for testing")

func _input(event: InputEvent) -> void:
    """Handle input for testing"""
    
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_F1:
                test_conditional_retreat()
            KEY_F2:
                test_enemy_proximity_trigger()
            KEY_F3:
                test_multi_step_plan()
            KEY_F4:
                test_compound_conditions()
            KEY_F5:
                test_plan_interruption()
            KEY_F6:
                test_plan_retry_logic()
            KEY_F7:
                test_speech_bubble_integration()
            KEY_F8:
                test_plan_validation()
            KEY_F9:
                show_ai_system_stats()
            KEY_F10:
                test_complex_scenario()
            KEY_F11:
                test_all_trigger_types()
            KEY_F12:
                interrupt_all_plans()

func test_conditional_retreat() -> void:
    """Test conditional retreat scenario: 'If health < 20%, retreat and heal'"""
    
    if test_units.size() == 0:
        print("TestAIIntegration: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Simulate low health for testing
    if unit.has_method("take_damage"):
        unit.take_damage(unit.current_health - 15)  # Reduce health to ~15%
    
    # Create conditional retreat plan
    var plan_data = {
        "steps": [
            {
                "action": "retreat",
                "params": {"position": [5, 0, 5]},
                "trigger": "health_pct < 20",
                "speech": "Taking damage! Retreating to safety!",
                "duration_ms": 0
            },
            {
                "action": "use_ability",
                "params": {"ability_name": "heal"},
                "trigger": "",
                "speech": "Healing wounds",
                "duration_ms": 3000
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestAIIntegration: Conditional retreat plan started for unit %s" % unit_id)
    else:
        print("TestAIIntegration: Failed to start conditional retreat plan")

func test_enemy_proximity_trigger() -> void:
    """Test enemy proximity trigger scenario"""
    
    if test_units.size() < 2:
        print("TestAIIntegration: Need at least 2 units for proximity test")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Create proximity-based plan
    var plan_data = {
        "steps": [
            {
                "action": "patrol",
                "params": {"waypoints": [[0, 0, 0], [10, 0, 10]]},
                "trigger": "enemy_dist > 15",
                "speech": "Patrolling area",
                "duration_ms": 0
            },
            {
                "action": "attack",
                "params": {},
                "trigger": "enemy_dist < 10",
                "speech": "Enemy spotted! Engaging!",
                "duration_ms": 0
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestAIIntegration: Enemy proximity plan started for unit %s" % unit_id)
    else:
        print("TestAIIntegration: Failed to start enemy proximity plan")

func test_multi_step_plan() -> void:
    """Test complex multi-step plan execution"""
    
    if test_units.size() == 0:
        print("TestAIIntegration: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Create complex multi-step plan
    var plan_data = {
        "steps": [
            {
                "action": "move_to",
                "params": {"position": [5, 0, 5]},
                "trigger": "",
                "speech": "Moving to position",
                "duration_ms": 2000
            },
            {
                "action": "stance",
                "params": {"stance": "defensive"},
                "trigger": "",
                "speech": "Taking defensive stance",
                "duration_ms": 1000
            },
            {
                "action": "patrol",
                "params": {"waypoints": [[5, 0, 5], [15, 0, 15]]},
                "trigger": "time > 1",
                "speech": "Beginning patrol",
                "duration_ms": 0
            },
            {
                "action": "retreat",
                "params": {"position": [0, 0, 0]},
                "trigger": "health_pct < 50",
                "speech": "Retreating for safety",
                "duration_ms": 0
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestAIIntegration: Multi-step plan started for unit %s" % unit_id)
    else:
        print("TestAIIntegration: Failed to start multi-step plan")

func test_compound_conditions() -> void:
    """Test compound conditions with AND/OR logic"""
    
    if test_units.size() == 0:
        print("TestAIIntegration: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Create plan with compound conditions
    var plan_data = {
        "steps": [
            {
                "action": "move_to",
                "params": {"position": [10, 0, 10]},
                "trigger": "health_pct > 80 AND enemy_dist > 20",
                "speech": "Advancing - conditions favorable",
                "duration_ms": 0
            },
            {
                "action": "attack",
                "params": {},
                "trigger": "enemy_dist < 5 OR health_pct < 30",
                "speech": "Emergency engagement!",
                "duration_ms": 0
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestAIIntegration: Compound conditions plan started for unit %s" % unit_id)
    else:
        print("TestAIIntegration: Failed to start compound conditions plan")

func test_plan_interruption() -> void:
    """Test plan interruption scenarios"""
    
    if test_units.size() == 0:
        print("TestAIIntegration: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Start a long plan
    var plan_data = {
        "steps": [
            {
                "action": "move_to",
                "params": {"position": [20, 0, 20]},
                "trigger": "",
                "speech": "Moving to distant location",
                "duration_ms": 10000  # 10 seconds
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestAIIntegration: Long plan started for unit %s" % unit_id)
        
        # Interrupt after 2 seconds
        await get_tree().create_timer(2.0).timeout
        plan_executor.interrupt_plan(unit_id, "test_interruption")
        print("TestAIIntegration: Plan interrupted for unit %s" % unit_id)
    else:
        print("TestAIIntegration: Failed to start long plan")

func test_plan_retry_logic() -> void:
    """Test plan retry logic for failed actions"""
    
    if test_units.size() == 0:
        print("TestAIIntegration: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Create plan with potentially failing action
    var plan_data = {
        "steps": [
            {
                "action": "use_ability",
                "params": {"ability_name": "nonexistent_ability"},
                "trigger": "",
                "speech": "Trying to use ability",
                "duration_ms": 1000
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestAIIntegration: Retry logic plan started for unit %s" % unit_id)
    else:
        print("TestAIIntegration: Failed to start retry logic plan")

func test_speech_bubble_integration() -> void:
    """Test speech bubble integration with plan execution"""
    
    if test_units.size() == 0:
        print("TestAIIntegration: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Create plan with speech bubbles
    var plan_data = {
        "steps": [
            {
                "action": "move_to",
                "params": {"position": [3, 0, 3]},
                "trigger": "",
                "speech": "Moving to new position",
                "duration_ms": 2000
            },
            {
                "action": "stance",
                "params": {"stance": "aggressive"},
                "trigger": "",
                "speech": "Ready for combat!",
                "duration_ms": 1000
            },
            {
                "action": "patrol",
                "params": {"waypoints": [[3, 0, 3], [7, 0, 7]]},
                "trigger": "",
                "speech": "Beginning patrol route",
                "duration_ms": 0
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestAIIntegration: Speech bubble integration plan started for unit %s" % unit_id)
    else:
        print("TestAIIntegration: Failed to start speech bubble integration plan")

func test_plan_validation() -> void:
    """Test plan validation with various scenarios"""
    
    # Test valid plan
    var valid_plan = {
        "steps": [
            {
                "action": "move_to",
                "params": {"position": [5, 0, 5]},
                "trigger": "",
                "speech": "Moving",
                "duration_ms": 1000
            }
        ]
    }
    
    var validation_result = action_validator.validate_plan(valid_plan)
    print("TestAIIntegration: Valid plan validation result: %s" % validation_result.valid)
    
    # Test invalid plan (unknown action)
    var invalid_plan = {
        "steps": [
            {
                "action": "invalid_action",
                "params": {},
                "trigger": "",
                "speech": "Invalid action",
                "duration_ms": 1000
            }
        ]
    }
    
    validation_result = action_validator.validate_plan(invalid_plan)
    print("TestAIIntegration: Invalid plan validation result: %s (error: %s)" % [validation_result.valid, validation_result.error])
    
    # Test plan with too many steps
    var long_plan = {"steps": []}
    for i in range(15):  # More than MAX_STEPS_PER_PLAN
        long_plan.steps.append({
            "action": "move_to",
            "params": {"position": [i, 0, i]},
            "trigger": "",
            "speech": "Step %d" % i,
            "duration_ms": 1000
        })
    
    validation_result = action_validator.validate_plan(long_plan)
    print("TestAIIntegration: Long plan validation result: %s" % validation_result.valid)

func test_all_trigger_types() -> void:
    """Test all available trigger types"""
    
    if test_units.size() == 0:
        print("TestAIIntegration: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    var trigger_tests = [
        {"trigger": "health_pct < 50", "description": "Health percentage trigger"},
        {"trigger": "enemy_dist < 15", "description": "Enemy distance trigger"},
        {"trigger": "ally_dist > 10", "description": "Ally distance trigger"},
        {"trigger": "time > 2", "description": "Time trigger"},
        {"trigger": "enemy_count > 1", "description": "Enemy count trigger"},
        {"trigger": "ally_count < 3", "description": "Ally count trigger"}
    ]
    
    for i in range(trigger_tests.size()):
        var trigger_test = trigger_tests[i]
        
        var plan_data = {
            "steps": [
                {
                    "action": "move_to",
                    "params": {"position": [i * 2, 0, i * 2]},
                    "trigger": trigger_test.trigger,
                    "speech": "Testing: %s" % trigger_test.description,
                    "duration_ms": 0
                }
            ]
        }
        
        var success = plan_executor.execute_plan(unit_id + "_trigger_" + str(i), plan_data)
        
        if success:
            print("TestAIIntegration: %s plan started" % trigger_test.description)
        else:
            print("TestAIIntegration: Failed to start %s plan" % trigger_test.description)
        
        # Small delay between tests
        await get_tree().create_timer(0.5).timeout

func test_complex_scenario() -> void:
    """Test complex real-world scenario"""
    
    if test_units.size() == 0:
        print("TestAIIntegration: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Complex tactical scenario
    var plan_data = {
        "steps": [
            {
                "action": "move_to",
                "params": {"position": [10, 0, 10]},
                "trigger": "health_pct > 70",
                "speech": "Moving to forward position",
                "duration_ms": 0
            },
            {
                "action": "stance",
                "params": {"stance": "defensive"},
                "trigger": "enemy_dist < 20",
                "speech": "Enemy detected! Taking defensive stance",
                "duration_ms": 0
            },
            {
                "action": "attack",
                "params": {},
                "trigger": "enemy_dist < 8 AND health_pct > 30",
                "speech": "Engaging enemy!",
                "duration_ms": 0
            },
            {
                "action": "retreat",
                "params": {"position": [0, 0, 0]},
                "trigger": "health_pct < 25 OR enemy_count > 2",
                "speech": "Tactical retreat!",
                "duration_ms": 0
            },
            {
                "action": "use_ability",
                "params": {"ability_name": "heal"},
                "trigger": "health_pct < 40 AND ally_dist < 15",
                "speech": "Healing with ally support",
                "duration_ms": 0
            }
        ]
    }
    
    var success = plan_executor.execute_plan(unit_id, plan_data)
    
    if success:
        print("TestAIIntegration: Complex scenario plan started for unit %s" % unit_id)
    else:
        print("TestAIIntegration: Failed to start complex scenario plan")

func show_ai_system_stats() -> void:
    """Show AI system statistics"""
    
    var plan_stats = plan_executor.get_execution_stats()
    print("TestAIIntegration: AI System Statistics:")
    print("  Plans executed: %d" % plan_stats.plans_executed)
    print("  Plans completed: %d" % plan_stats.plans_completed)
    print("  Plans failed: %d" % plan_stats.plans_failed)
    print("  Steps executed: %d" % plan_stats.steps_executed)
    print("  Average execution time: %.2f seconds" % plan_stats.average_execution_time)
    print("  Active plans: %d" % plan_executor.get_active_plan_count())
    print("  Units with plans: %s" % str(plan_executor.get_units_with_plans()))

func interrupt_all_plans() -> void:
    """Interrupt all active plans"""
    
    var units_with_plans = plan_executor.get_units_with_plans()
    
    for unit_id in units_with_plans:
        plan_executor.interrupt_plan(unit_id, "test_interrupt_all")
    
    print("TestAIIntegration: Interrupted %d active plans" % units_with_plans.size())

# Signal handlers
func _on_plan_started(unit_id: String, plan: Array) -> void:
    print("TestAIIntegration: Plan started for unit %s with %d steps" % [unit_id, plan.size()])

func _on_plan_completed(unit_id: String, success: bool) -> void:
    var status = "successfully" if success else "with errors"
    print("TestAIIntegration: Plan completed %s for unit %s" % [status, unit_id])

func _on_plan_interrupted(unit_id: String, reason: String) -> void:
    print("TestAIIntegration: Plan interrupted for unit %s: %s" % [unit_id, reason])

func _on_step_executed(unit_id: String, step) -> void:
    print("TestAIIntegration: Step executed for unit %s: %s" % [unit_id, step.action])

func _on_trigger_evaluated(unit_id: String, trigger: String, result: bool) -> void:
    print("TestAIIntegration: Trigger evaluated for unit %s: '%s' = %s" % [unit_id, trigger, result])

func print_help() -> void:
    """Print help information"""
    
    print("TestAIIntegration: Function key shortcuts:")
    print("  F1  - Test conditional retreat ('If health < 20%, retreat and heal')")
    print("  F2  - Test enemy proximity trigger")
    print("  F3  - Test multi-step plan execution")
    print("  F4  - Test compound conditions (AND/OR)")
    print("  F5  - Test plan interruption")
    print("  F6  - Test plan retry logic")
    print("  F7  - Test speech bubble integration")
    print("  F8  - Test plan validation")
    print("  F9  - Show AI system statistics")
    print("  F10 - Test complex scenario")
    print("  F11 - Test all trigger types")
    print("  F12 - Interrupt all plans")

func _enter_tree() -> void:
    """Called when entering the tree"""
    
    # Wait a bit then print help
    await get_tree().create_timer(1.0).timeout
    print_help() 