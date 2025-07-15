# InputManager.gd - Handle input events and testing functionality
extends Node

# Dependencies
var logger
var network_manager
var ui_manager

# System references
var ai_command_processor
var resource_manager
var node_capture_system

# Signals
signal ai_test_requested(test_id: int)
signal control_point_test_requested(control_point_id: int)
signal control_point_status_test_requested()
signal control_point_reset_test_requested()
signal control_point_victory_test_requested()
signal resource_management_test_requested()
signal resource_help_test_requested()
signal plan_progress_test_requested()
signal speech_bubbles_test_requested()

func setup(logger_instance, network_manager_instance, ui_manager_instance) -> void:
    """Setup the input manager with dependencies"""
    logger = logger_instance
    network_manager = network_manager_instance
    ui_manager = ui_manager_instance
    
    logger.info("InputManager", "Input manager setup complete")

func set_system_references(ai_command_processor_ref, resource_manager_ref, node_capture_system_ref) -> void:
    """Set system references for testing"""
    ai_command_processor = ai_command_processor_ref
    resource_manager = resource_manager_ref
    node_capture_system = node_capture_system_ref
    
    logger.info("InputManager", "System references set for testing")

func handle_unhandled_input(event: InputEvent) -> bool:
    """Handle unhandled input events, return true if handled"""
    if event is InputEventKey and event.pressed:
        # Testing mode toggle
        if event.keycode == KEY_T:
            if ui_manager:
                ui_manager.toggle_testing_mode()
            return true
        
        # Only handle test inputs if in testing mode
        if ui_manager and ui_manager.get_testing_mode():
            return _handle_test_input(event.keycode)
    
    return false

func handle_regular_input(event: InputEvent) -> bool:
    """Handle regular input events, return true if handled"""
    if not network_manager or not network_manager.get_connection_state():
        return false
    
    # Handle AI commands (placeholder)
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_T:
            # Test AI command
            var test_command = "Move selected units to the center"
            network_manager.send_ai_command(test_command, [])
            logger.info("InputManager", "Sent AI command: %s" % test_command)
            return true
    
    return false

func _handle_test_input(keycode: int) -> bool:
    """Handle test input based on keycode, return true if handled"""
    match keycode:
        KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12:
            _test_ai_integration(keycode - KEY_F1 + 1)
            return true
        KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
            _test_control_point_capture(keycode - KEY_1 + 1)
            return true
        KEY_0:
            _test_control_point_status()
            return true
        KEY_MINUS:
            _test_control_point_reset()
            return true
        KEY_EQUAL:
            _test_control_point_victory()
            return true
        KEY_R:
            _test_resource_management()
            return true
        KEY_H:
            _test_resource_help()
            return true
        KEY_P:
            _test_plan_progress()
            return true
        KEY_S:
            _test_speech_bubbles()
            return true
    
    return false

# Testing methods
func _test_ai_integration(test_id: int) -> void:
    """Test AI integration system"""
    logger.info("InputManager", "Testing AI integration scenario %d" % test_id)
    
    if ai_command_processor:
        # Simulate AI command processing
        var test_command = "Test AI command %d" % test_id
        logger.info("InputManager", "Executing AI test: %s" % test_command)
    else:
        logger.warning("InputManager", "AI command processor not available for testing")
    
    ai_test_requested.emit(test_id)

func _test_control_point_capture(control_point_id: int) -> void:
    """Test control point capture"""
    logger.info("InputManager", "Testing control point %d capture" % control_point_id)
    
    if node_capture_system:
        # Simulate control point capture
        logger.info("InputManager", "Capturing control point %d" % control_point_id)
    else:
        logger.warning("InputManager", "Node capture system not available for testing")
    
    control_point_test_requested.emit(control_point_id)

func _test_control_point_status() -> void:
    """Test control point status display"""
    logger.info("InputManager", "Testing control point status")
    
    if node_capture_system:
        logger.info("InputManager", "Displaying control point status")
    else:
        logger.warning("InputManager", "Node capture system not available for testing")
    
    control_point_status_test_requested.emit()

func _test_control_point_reset() -> void:
    """Test control point reset"""
    logger.info("InputManager", "Testing control point reset")
    
    if node_capture_system:
        logger.info("InputManager", "Resetting control points")
    else:
        logger.warning("InputManager", "Node capture system not available for testing")
    
    control_point_reset_test_requested.emit()

func _test_control_point_victory() -> void:
    """Test control point victory conditions"""
    logger.info("InputManager", "Testing control point victory")
    
    if node_capture_system:
        logger.info("InputManager", "Checking victory conditions")
    else:
        logger.warning("InputManager", "Node capture system not available for testing")
    
    control_point_victory_test_requested.emit()

func _test_resource_management() -> void:
    """Test resource management system"""
    logger.info("InputManager", "Testing resource management")
    
    if resource_manager:
        logger.info("InputManager", "Resource management test")
    else:
        logger.warning("InputManager", "Resource manager not available for testing")
    
    resource_management_test_requested.emit()

func _test_resource_help() -> void:
    """Test resource help display"""
    logger.info("InputManager", "Testing resource help")
    
    if resource_manager:
        logger.info("InputManager", "Displaying resource help")
    else:
        logger.warning("InputManager", "Resource manager not available for testing")
    
    resource_help_test_requested.emit()

func _test_plan_progress() -> void:
    """Test plan progress indicators"""
    logger.info("InputManager", "Testing plan progress indicators")
    
    plan_progress_test_requested.emit()

func _test_speech_bubbles() -> void:
    """Test speech bubble system"""
    logger.info("InputManager", "Testing speech bubbles")
    
    speech_bubbles_test_requested.emit()

# Utility methods
func get_testing_help() -> String:
    """Get help text for testing commands"""
    var help_text = """
Testing Commands:
- T: Toggle testing mode
- F1-F12: Test AI integration scenarios
- 1-9: Test control point capture
- 0: Test control point status
- -: Test control point reset
- =: Test control point victory
- R: Test resource management
- H: Test resource help
- P: Test plan progress
- S: Test speech bubbles
"""
    return help_text

func cleanup() -> void:
    """Cleanup input manager resources"""
    logger.info("InputManager", "Input manager cleanup complete") 