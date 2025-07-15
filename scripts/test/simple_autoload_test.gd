# SimpleAutoloadTest.gd
extends Node

func _ready() -> void:
	print("=== AUTOLOAD TEST ===")
	
	# Test Logger
	if Logger:
		print("✓ Logger autoload is available")
		Logger.info("AutoloadTest", "Logger is working")
	else:
		print("✗ Logger autoload NOT available")
	
	# Test EventBus
	if EventBus:
		print("✓ EventBus autoload is available")
		EventBus.log_event("test_event", {"data": "test"})
	else:
		print("✗ EventBus autoload NOT available")
	
	# Test DependencyContainer
	if DependencyContainer:
		print("✓ DependencyContainer autoload is available")
	else:
		print("✗ DependencyContainer autoload NOT available")
	
	print("=== END AUTOLOAD TEST ===") 