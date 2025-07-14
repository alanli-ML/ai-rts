# TestMultiplayer.gd
extends Node

# Test the multiplayer lobby system
func _ready() -> void:
	Logger.info("TestMultiplayer", "Starting multiplayer test...")
	
	# Test by creating a simple test scene
	_create_test_scene()

func _create_test_scene() -> void:
	# Create a simple window to test lobby functionality
	var window = AcceptDialog.new()
	window.title = "AI-RTS Multiplayer Test"
	window.size = Vector2i(600, 400)
	add_child(window)
	
	# Load the lobby scene
	var lobby_scene = load("res://scenes/ui/lobby.tscn")
	if lobby_scene:
		var lobby_instance = lobby_scene.instantiate()
		
		# Attach the lobby script
		var lobby_script = load("res://scripts/ui/lobby_ui.gd")
		if lobby_script:
			lobby_instance.script = lobby_script
		
		window.add_child(lobby_instance)
		window.show()
		
		Logger.info("TestMultiplayer", "Lobby UI loaded successfully")
	else:
		Logger.error("TestMultiplayer", "Failed to load lobby scene")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit() 