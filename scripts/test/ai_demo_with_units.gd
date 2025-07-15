# AIDemoWithUnits.gd
# Demo script that integrates with UnifiedMain to show AI control of visible units
extends Node

# References to main systems
var openai_client = null
var test_units: Array = []
var demo_active: bool = false

# Selection system
var selection_system: EnhancedSelectionSystem = null

# Demo state
var current_demo_step: int = 0
var demo_steps: Array = []

func _ready() -> void:
	print("\n🎮 AI-RTS DEMO WITH UNITS INITIALIZING...")
	
	# Wait for unified main to finish setup
	await get_tree().create_timer(2.0).timeout
	
	# Initialize selection system first
	_initialize_selection_system()
	
	# Initialize AI client
	await _initialize_ai_client()
	
	# Spawn demo units
	await _spawn_demo_units()
	
	# Setup demo steps
	_setup_demo_steps()
	
	# Print instructions
	_print_demo_instructions()
	
	print("🎮 AI-RTS DEMO READY!")

func _initialize_selection_system() -> void:
	"""Initialize the enhanced selection system for the demo"""
	print("Initializing selection system...")
	
	# Wait a moment for the scene to be fully ready
	await get_tree().process_frame
	
	# Ensure the camera is properly set up first
	var main_scene = get_tree().current_scene
	var camera = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld/3DView/Camera3D")
	
	# Also check for RTS camera
	if not camera:
		var scene_3d = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld/3DView")
		if scene_3d:
			# Look for any Camera3D nodes in the scene
			for child in scene_3d.get_children():
				if child is Camera3D:
					camera = child
					break
				elif child.name.contains("RTS") or child.name.contains("Camera"):
					var child_camera = child.get_node_or_null("Camera3D")
					if child_camera:
						camera = child_camera
						break
	
	if camera:
		# Add camera to proper groups for selection system discovery
		camera.add_to_group("cameras")
		camera.add_to_group("rts_cameras")
		print("Added camera %s to selection groups" % camera.name)
	else:
		print("WARNING: Camera not found for selection system")
	
	# Ensure SubViewport receives input
	var sub_viewport = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld")
	if sub_viewport:
		sub_viewport.gui_disable_input = false
		print("Enabled input for SubViewport")
	
	var EnhancedSelectionSystemClass = preload("res://scripts/core/enhanced_selection_system.gd")
	selection_system = EnhancedSelectionSystemClass.new()
	selection_system.name = "DemoSelectionSystem"
	
	# Add to the 3D scene so it can handle input properly
	var scene_3d = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld/3DView")
	
	if scene_3d:
		scene_3d.call_deferred("add_child", selection_system)
		print("Selection system added to 3D scene")
	else:
		# Fallback - add to this node
		call_deferred("add_child", selection_system)
		print("Selection system added to demo node")
	
	# Connect selection signals for feedback
	selection_system.units_selected.connect(_on_units_selected)
	selection_system.units_deselected.connect(_on_units_deselected)
	
	print("Selection system initialized")

func _initialize_ai_client() -> void:
	"""Initialize OpenAI client for the demo"""
	print("Initializing AI client for demo...")
	
	var OpenAIClientClass = preload("res://scripts/ai/openai_client.gd")
	openai_client = OpenAIClientClass.new()
	openai_client.name = "DemoOpenAIClient"
	call_deferred("add_child", openai_client)
	
	# Connect signals
	openai_client.request_completed.connect(_on_ai_response)
	openai_client.request_failed.connect(_on_ai_error)
	
	print("AI client initialized for demo")

func _spawn_demo_units() -> void:
	"""Spawn visible demo units"""
	print("Spawning demo units...")
	
	# Try to load the AnimatedUnit scene (with Kenny character models)
	var unit_scene_path = "res://scenes/units/AnimatedUnit.tscn"
	var unit_scene = load(unit_scene_path)
	
	if not unit_scene:
		print("ERROR: Could not load AnimatedUnit scene from %s" % unit_scene_path)
		return
	
	# Find the 3D scene to spawn units in
	var main_scene = get_tree().current_scene
	var scene_3d = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld/3DView")
	var units_container = scene_3d.get_node_or_null("Units") if scene_3d else null
	
	if not units_container:
		print("WARNING: Units container not found, creating one...")
		units_container = Node3D.new()
		units_container.name = "DemoUnits"
		if scene_3d:
			scene_3d.call_deferred("add_child", units_container)
		else:
			call_deferred("add_child", units_container)
	
	# Unit configurations with positions and archetypes
	var unit_configs = [
		{"archetype": "scout", "position": Vector3(-5, 0, -5), "team": 1},
		{"archetype": "soldier", "position": Vector3(0, 0, -5), "team": 1},
		{"archetype": "sniper", "position": Vector3(5, 0, -5), "team": 1}
	]
	
	# Spawn units
	for config in unit_configs:
		var unit = unit_scene.instantiate()
		if unit:
			# Configure unit properties
			unit.archetype = config.archetype
			unit.team_id = config.team
			unit.position = config.position
			unit.name = "unit_%d" % randi()
			
			# Add to scene using call_deferred to avoid setup conflicts
			units_container.call_deferred("add_child", unit)
			
			# Ensure unit is properly configured for selection
			await get_tree().process_frame  # Wait for unit to be ready
			await get_tree().process_frame  # Extra frame for deferred add_child
			_configure_unit_for_selection(unit)
			
			# Store reference
			test_units.append(unit)
			
			print("Unit %s (%s) initialized for team %d" % [unit.name, unit.archetype, unit.team_id])
	
	print("API key loaded from .env file" if openai_client and openai_client.api_key != "" else "WARNING: No API key found")

func _configure_unit_for_selection(unit: Node3D) -> void:
	"""Configure a unit for proper selection system interaction"""
	
	# Add to units group for selection system to find
	unit.add_to_group("units")
	
	# Wait for AnimatedUnit to finish setting up collision shapes
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Check if unit has a proper collision shape from AnimatedUnit
	var collision_shape = unit.get_node_or_null("CharacterCollisionShape3D")
	if collision_shape:
		print("Unit %s has character collision shape for selection" % unit.name)
	else:
		# Fallback - check for any collision shape
		collision_shape = unit.get_node_or_null("CollisionShape3D")
		if collision_shape:
			print("Unit %s has basic collision shape" % unit.name)
		else:
			print("WARNING: Unit %s missing collision shape - selection may not work" % unit.name)
	
	# Don't override collision layers - let AnimatedUnit handle this
	if unit is CharacterBody3D:
		print("Unit %s collision layer: %d (should be 1 for selection)" % [unit.name, unit.collision_layer])
	
	# Ensure required input actions exist
	_ensure_input_actions()
	
	print("Unit %s configured for selection" % unit.name)

func _ensure_input_actions() -> void:
	"""Ensure required input actions are defined"""
	var required_actions = ["shift", "ctrl"]
	
	for action in required_actions:
		if not InputMap.has_action(action):
			print("Adding missing input action: %s" % action)
			InputMap.add_action(action)
			
			# Add appropriate key mappings
			var key_event = InputEventKey.new()
			if action == "shift":
				key_event.keycode = KEY_SHIFT
			elif action == "ctrl":
				key_event.keycode = KEY_CTRL
			
			InputMap.action_add_event(action, key_event)

func _ensure_camera_groups() -> void:
	"""Ensure the camera is added to the proper groups for selection"""
	var main_scene = get_tree().current_scene
	var scene_3d = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld/3DView")
	
	if scene_3d:
		# Look for RTS camera
		var rts_cameras = scene_3d.get_children().filter(func(node): return node.name.contains("RTS"))
		
		for rts_camera in rts_cameras:
			rts_camera.add_to_group("cameras")
			rts_camera.add_to_group("rts_cameras")
			
			# If RTS camera has a Camera3D child, add that to groups too
			var camera_3d = rts_camera.get_node_or_null("Camera3D")
			if camera_3d:
				camera_3d.add_to_group("cameras")
				print("Camera added to groups for selection system")
			break

func _on_units_selected(units: Array) -> void:
	"""Handle unit selection"""
	print("🎯 Units selected: %d units" % units.size())
	for unit in units:
		print("  - %s (%s)" % [unit.name, unit.archetype if unit.has_method("get_archetype") else "unknown"])

func _on_units_deselected(units: Array) -> void:
	"""Handle unit deselection"""
	print("🎯 Units deselected: %d units" % units.size())

func _setup_demo_steps() -> void:
	"""Setup the demo sequence"""
	demo_steps = [
		{
			"name": "Basic Movement",
			"prompt": "Move all units forward to scout the area",
			"description": "Testing basic movement commands"
		},
		{
			"name": "Formation Command", 
			"prompt": "Arrange units in a defensive line formation",
			"description": "Testing formation commands"
		},
		{
			"name": "Tactical Movement",
			"prompt": "Have the scout move ahead while others provide cover",
			"description": "Testing coordinated unit commands"
		},
		{
			"name": "Attack Command",
			"prompt": "All units attack the enemy position at coordinates (10, 0, 10)",
			"description": "Testing attack commands"
		}
	]

func _input(event: InputEvent) -> void:
	"""Handle input for the demo"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_D:
				start_ai_demo()
			KEY_N:
				next_demo_step()
			KEY_1:
				test_specific_command("Move units to forward positions")
			KEY_2:
				test_specific_command("Form defensive line with all units")
			KEY_3:
				test_specific_command("Scout ahead with the lead unit")
			KEY_4:
				test_specific_command("Attack enemy position")
			KEY_R:
				reset_demo()
			KEY_H:
				_print_demo_instructions()

func start_ai_demo() -> void:
	"""Start the AI demonstration"""
	print("\n🚀 STARTING AI-RTS DEMONSTRATION")
	
	if test_units.is_empty():
		print("❌ No demo units available!")
		return
	
	if not openai_client or openai_client.api_key == "sk-test-key-for-development":
		print("❌ OpenAI API key not configured!")
		print("Set OPENAI_API_KEY in .env file")
		return
	
	demo_active = true
	current_demo_step = 0
	
	print("✅ Demo started with %d units" % test_units.size())
	next_demo_step()

func next_demo_step() -> void:
	"""Execute the next step in the demo"""
	if not demo_active or current_demo_step >= demo_steps.size():
		print("📋 Demo completed!")
		demo_active = false
		return
	
	var step = demo_steps[current_demo_step]
	print("\n--- DEMO STEP %d: %s ---" % [current_demo_step + 1, step.name])
	print("Description: %s" % step.description)
	print("Command: %s" % step.prompt)
	
	await _send_ai_command(step.prompt)
	
	current_demo_step += 1
	
	print("Press 'N' for next step or 'D' to restart demo")

func test_specific_command(command: String) -> void:
	"""Test a specific AI command"""
	print("\n🧪 TESTING SPECIFIC COMMAND: %s" % command)
	
	if test_units.is_empty():
		print("❌ No demo units available!")
		return
	
	if not openai_client or openai_client.api_key == "sk-test-key-for-development":
		print("❌ OpenAI API key not configured!")
		return
	
	await _send_ai_command(command)

func _send_ai_command(command: String) -> void:
	"""Send command to AI and process response"""
	var system_prompt = """
You are an AI assistant for a Real-Time Strategy (RTS) game demo.
Convert the user's natural language command into a structured JSON response.

AVAILABLE UNITS:
- scout: Fast reconnaissance unit
- soldier: Standard infantry unit  
- sniper: Long-range precision unit

AVAILABLE COMMANDS:
- move: Move units to a position
- formation: Arrange units in formation
- attack: Attack a target
- patrol: Patrol an area
- defend: Take defensive positions

Respond with JSON in this format:
{
  "type": "rts_command",
  "action": "move|formation|attack|patrol|defend",
  "units": ["scout", "soldier", "sniper"] or ["all"],
  "target": {"x": 0, "y": 0, "z": 0},
  "formation": "line|column|scattered|defensive",
  "message": "Confirmation message for the player"
}

Current situation: 3 demo units available (scout, soldier, sniper) at defensive positions.
"""
	
	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": command}
	]
	
	print("💭 Sending command to AI: %s" % command)
	
	var response_received = false
	var ai_response = null
	
	# Setup response handler
	var response_handler = func(response: Dictionary):
		ai_response = response
		response_received = true
		print("🤖 AI response received")
	
	var error_handler = func(error_type, error_message: String):
		print("❌ AI Error: %s" % error_message)
		response_received = true
	
	# Connect signals temporarily
	if not openai_client.request_completed.is_connected(response_handler):
		openai_client.request_completed.connect(response_handler, CONNECT_ONE_SHOT)
	if not openai_client.request_failed.is_connected(error_handler):
		openai_client.request_failed.connect(error_handler, CONNECT_ONE_SHOT)
	
	# Send request
	openai_client.send_chat_completion(messages, func(response, error_type, error_message): pass)
	
	# Wait for response
	var timeout = 30.0
	var elapsed = 0.0
	
	while not response_received and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	
	if ai_response:
		_process_ai_response(ai_response, command)
	else:
		print("⏱️ AI request timed out")

func _process_ai_response(response: Dictionary, original_command: String) -> void:
	"""Process and execute the AI response"""
	print("🔄 Processing AI response...")
	
	# Extract content from OpenAI response
	var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
	
	if content.is_empty():
		print("❌ Empty AI response")
		return
	
	print("📝 AI Response Content: %s" % content)
	
	# Try to parse as JSON
	var json = JSON.new()
	var parse_result = json.parse(content)
	
	if parse_result != OK:
		print("⚠️ Response not JSON, treating as text response")
		_simulate_command_execution(original_command)
		return
	
	var ai_data = json.data
	
	# Validate response structure
	if not ai_data.has("type") or not ai_data.has("action"):
		print("⚠️ Invalid response structure, simulating command")
		_simulate_command_execution(original_command)
		return
	
	# Execute the command
	var action = ai_data.get("action", "")
	var units = ai_data.get("units", ["all"])
	var target = ai_data.get("target", {"x": 0, "y": 0, "z": 0})
	var formation = ai_data.get("formation", "")
	var message = ai_data.get("message", "Executing command")
	
	print("✅ AI Command Parsed:")
	print("  Action: %s" % action)
	print("  Units: %s" % str(units))
	print("  Target: (%s, %s, %s)" % [target.get("x", 0), target.get("y", 0), target.get("z", 0)])
	print("  Formation: %s" % formation)
	print("  Message: %s" % message)
	
	# Execute the parsed command
	_execute_parsed_command(action, units, target, formation, message)

func _execute_parsed_command(action: String, units: Array, target: Dictionary, formation: String, message: String) -> void:
	"""Execute the parsed AI command on the demo units"""
	print("🎮 Executing command: %s" % action)
	
	var target_pos = Vector3(target.get("x", 0), target.get("y", 0), target.get("z", 0))
	var affected_units = []
	
	# Determine which units to affect
	if "all" in units:
		affected_units = test_units
	else:
		for unit in test_units:
			if unit.get("archetype", "") in units:
				affected_units.append(unit)
	
	print("🎯 Affecting %d units" % affected_units.size())
	
	# Execute command based on action
	match action:
		"move":
			_execute_move_command(affected_units, target_pos, formation)
		"formation":
			_execute_formation_command(affected_units, formation)
		"attack":
			_execute_attack_command(affected_units, target_pos)
		"patrol":
			_execute_patrol_command(affected_units, target_pos)
		"defend":
			_execute_defend_command(affected_units)
		_:
			print("⚠️ Unknown action: %s, simulating movement" % action)
			_execute_move_command(affected_units, target_pos, formation)
	
	print("💬 AI Message: %s" % message)

func _execute_move_command(units: Array, target_pos: Vector3, formation: String) -> void:
	"""Execute movement command with optional formation"""
	print("👥 Moving %d units to %s" % [units.size(), target_pos])
	
	for i in range(units.size()):
		var unit = units[i]
		var final_pos = target_pos
		
		# Apply formation offset
		if formation == "line":
			final_pos.x += (i - units.size() / 2.0) * 3.0
		elif formation == "column":
			final_pos.z += i * 2.0
		elif formation == "scattered":
			final_pos.x += randf_range(-5, 5)
			final_pos.z += randf_range(-5, 5)
		
		# Move unit
		var tween = create_tween()
		tween.tween_property(unit, "position", final_pos, 2.0)
		
		if unit.has_method("set_state"):
			unit.set_state("moving")
		
		print("  Moving %s to %s" % [unit.name, final_pos])

func _execute_formation_command(units: Array, formation: String) -> void:
	"""Execute formation command"""
	print("📐 Arranging %d units in %s formation" % [units.size(), formation])
	
	var center_pos = Vector3.ZERO
	if units.size() > 0:
		for unit in units:
			center_pos += unit.position
		center_pos /= units.size()
	
	_execute_move_command(units, center_pos, formation)

func _execute_attack_command(units: Array, target_pos: Vector3) -> void:
	"""Execute attack command"""
	print("⚔️ %d units attacking position %s" % [units.size(), target_pos])
	
	# Move units towards target first
	_execute_move_command(units, target_pos + Vector3(0, 0, -3), "line")
	
	# Simulate attack animations
	for unit in units:
		if unit.has_method("set_state"):
			unit.set_state("attacking")

func _execute_patrol_command(units: Array, target_pos: Vector3) -> void:
	"""Execute patrol command"""
	print("🚶 %d units patrolling around %s" % [units.size(), target_pos])
	_execute_move_command(units, target_pos, "scattered")

func _execute_defend_command(units: Array) -> void:
	"""Execute defend command"""
	print("🛡️ %d units taking defensive positions" % units.size())
	_execute_formation_command(units, "defensive")

func _simulate_command_execution(command: String) -> void:
	"""Simulate command execution when AI parsing fails"""
	print("🎭 Simulating command: %s" % command)
	
	var action = "move"
	var target_pos = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	
	if "attack" in command.to_lower():
		action = "attack"
		target_pos = Vector3(10, 0, 10)
	elif "formation" in command.to_lower() or "line" in command.to_lower():
		action = "formation"
	elif "defend" in command.to_lower():
		action = "defend"
	
	_execute_parsed_command(action, ["all"], {"x": target_pos.x, "y": target_pos.y, "z": target_pos.z}, "line", "Simulating: " + command)

func reset_demo() -> void:
	"""Reset the demo to initial state"""
	print("🔄 Resetting demo...")
	
	demo_active = false
	current_demo_step = 0
	
	# Reset unit positions
	var initial_positions = [
		Vector3(-5, 0, -5),
		Vector3(0, 0, -5),
		Vector3(5, 0, -5)
	]
	
	for i in range(min(test_units.size(), initial_positions.size())):
		var unit = test_units[i]
		var tween = create_tween()
		tween.tween_property(unit, "position", initial_positions[i], 1.0)
		
		if unit.has_method("set_state"):
			unit.set_state("idle")
	
	print("✅ Demo reset complete")

func _print_demo_instructions() -> void:
	"""Print demo instructions"""
	print("\n🎮 AI-RTS DEMO CONTROLS:")
	print("  D - Start automated AI demo")
	print("  N - Next demo step")
	print("  1 - Test movement command")
	print("  2 - Test formation command") 
	print("  3 - Test scout command")
	print("  4 - Test attack command")
	print("  R - Reset demo")
	print("  H - Show this help")
	print("\n🎯 SELECTION CONTROLS:")
	print("  Left Click - Select unit")
	print("  Left Drag - Box select units")
	print("  Shift+Click - Add to selection")
	print("  Ctrl+Click - Toggle selection")
	print("  Right Click - Move selected units")
	print("\nDemo Features:")
	print("  🤖 Real OpenAI GPT-4 integration")
	print("  🎯 Natural language → Game commands")
	print("  👥 Visible units with formations")
	print("  🖱️ Mouse selection system")
	print("  ⚡ Real-time command execution")

# Signal handlers
func _on_ai_response(response: Dictionary) -> void:
	print("  🤖 AI response received for demo")

func _on_ai_error(error_type, error_message: String) -> void:
	print("  ❌ AI error in demo: %s" % error_message)

# Simple demo unit class
class SimpleDemoUnit:
	extends CharacterBody3D
	
	var archetype: String = "demo"
	var team_id: int = 1
	var unit_state: String = "idle"
	
	func get_unit_id() -> String:
		return name
	
	func get_team_id() -> int:
		return team_id
		
	func set_state(new_state: String) -> void:
		unit_state = new_state
		print("Unit %s state: %s" % [name, new_state]) 