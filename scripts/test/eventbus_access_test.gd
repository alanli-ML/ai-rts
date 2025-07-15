# EventBusAccessTest.gd
extends Node

func _ready() -> void:
	print("=== EventBus Access Test ===")
	
	# Test from main scene
	print("Testing from main scene...")
	test_eventbus_access()
	
	# Test from CommandInput instance
	print("Testing from CommandInput instance...")
	var command_input = CommandInput.new()
	add_child(command_input)
	command_input.test_eventbus_from_commandinput()
	
	# Test from EnhancedSelectionSystem instance
	print("Testing from EnhancedSelectionSystem instance...")
	var selection_manager = EnhancedSelectionSystem.new()
	add_child(selection_manager)
	selection_manager.test_eventbus_from_selectionmanager()

func test_eventbus_access() -> void:
	if EventBus:
		print("✓ EventBus accessible from main test scene")
		EventBus.log_event("main_test", {})
	else:
		print("✗ EventBus NOT accessible from main test scene") 