# ComprehensiveUnitControlTest.gd
# Comprehensive test of the complete unit control system from input → LLM → execution
extends Node

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# System references
var ai_command_processor: AICommandProcessor = null
var plan_executor: Node = null
var selection_system: EnhancedSelectionSystem = null
var command_translator: CommandTranslator = null
var openai_client: OpenAIClient = null
var action_validator = null
var logger = null

# Test units
var test_units: Array[Unit] = []
var unit_spawner: UnitSpawner = null

# Demo state
var demo_active: bool = false
var current_test_phase: int = 0
var test_results: Dictionary = {}
var auto_demo_mode: bool = false
var demo_step_timer: float = 0.0
var demo_step_duration: float = 5.0

# Testing control
var testing_enabled: bool = false

# Input handling
var command_input_ui: Control = null
var command_dialog: AcceptDialog = null
var command_text_edit: TextEdit = null
var command_examples_label: RichTextLabel = null
var test_feedback_ui: RichTextLabel = null

# Test phases
enum TestPhase {
	INITIALIZATION,
	UNIT_SPAWNING,
	SELECTION_TEST,
	SIMPLE_AI_COMMANDS,
	COMPLEX_AI_PLANS,
	MULTI_UNIT_COORDINATION,
	TRIGGER_BASED_PLANS,
	PERFORMANCE_TEST,
	COMPLETE
}

# Demo commands for automated testing
var demo_commands = [
	{
		"phase": TestPhase.SIMPLE_AI_COMMANDS,
		"command": "Move the scout to explore the eastern area",
		"expected": "move command to scout unit",
		"test_type": "direct_command"
	},
	{
		"phase": TestPhase.SIMPLE_AI_COMMANDS,
		"command": "Have the sniper find cover and overwatch",
		"expected": "sniper positioning command",
		"test_type": "direct_command"
	},
	{
		"phase": TestPhase.COMPLEX_AI_PLANS,
		"command": "Scout ahead with the scout, then have the team advance if safe",
		"expected": "multi-step plan with scout reconnaissance",
		"test_type": "multi_step_plan"
	},
	{
		"phase": TestPhase.COMPLEX_AI_PLANS,
		"command": "Set up defensive positions and retreat if health drops below 30%",
		"expected": "conditional plan with health trigger",
		"test_type": "multi_step_plan"
	},
	{
		"phase": TestPhase.MULTI_UNIT_COORDINATION,
		"command": "Coordinate a flanking maneuver with scout and soldier",
		"expected": "coordinated multi-unit plan",
		"test_type": "coordination"
	},
	{
		"phase": TestPhase.TRIGGER_BASED_PLANS,
		"command": "Advance carefully and fall back if enemies are spotted",
		"expected": "plan with enemy detection trigger",
		"test_type": "trigger_plan"
	}
]

# Signals
signal test_phase_completed(phase: TestPhase, success: bool)
signal all_tests_completed(results: Dictionary)
signal command_test_result(command: String, success: bool, response_time: float)

func _ready() -> void:
	print("\n🎮 COMPREHENSIVE UNIT CONTROL TEST INITIALIZING...")
	
	# Check if this should be enabled (only in dedicated test scenes)
	var scene_name = get_tree().current_scene.name if get_tree().current_scene else ""
	testing_enabled = scene_name.contains("Test") or scene_name.contains("Demo")
	
	if testing_enabled:
		print("ComprehensiveUnitControlTest: Testing enabled for scene: %s" % scene_name)
		# Ensure this node can process input
		set_process_input(true)
		set_process_unhandled_input(true)
	else:
		print("ComprehensiveUnitControlTest: Testing disabled for scene: %s. Use Ctrl+T to enable." % scene_name)
		# Disable input processing by default
		set_process_input(false)
		set_process_unhandled_input(false)
	
	# Wait for scene setup
	await get_tree().create_timer(2.0).timeout
	
	# Initialize all systems
	await _initialize_test_systems()
	
	# Setup UI
	_setup_test_ui()
	
	# Spawn test units
	await _spawn_test_units()
	
	# Start the comprehensive test
	_start_comprehensive_test()
	
	print("🎮 COMPREHENSIVE UNIT CONTROL TEST READY!")
	print("Press ENTER to open AI Command Dialog")
	print("Press F11 for automated demo")
	print("Press F12 for detailed system status")
	print("DEBUG: demo_active = %s" % demo_active)

func _initialize_test_systems() -> void:
	"""Initialize all required systems for the test"""
	print("Initializing test systems...")
	
	# Get dependency container
	var dependency_container = null
	if has_node("/root/DependencyContainer"):
		dependency_container = get_node("/root/DependencyContainer")
		if dependency_container.has_method("get_logger"):
			logger = dependency_container.get_logger()
	
	# Initialize logger fallback
	if not logger:
		print("No dependency container found, using fallback logging")
	
	# Initialize AI Command Processor
	var AICommandProcessorClass = preload("res://scripts/ai/ai_command_processor.gd")
	ai_command_processor = AICommandProcessorClass.new()
	ai_command_processor.name = "TestAICommandProcessor"
	add_child(ai_command_processor)
	
	# Connect AI processor signals
	ai_command_processor.command_processed.connect(_on_command_processed)
	ai_command_processor.plan_processed.connect(_on_plan_processed)
	ai_command_processor.command_failed.connect(_on_command_failed)
	ai_command_processor.processing_started.connect(_on_processing_started)
	ai_command_processor.processing_finished.connect(_on_processing_finished)
	ai_command_processor.plan_execution_started.connect(_on_plan_execution_started)
	ai_command_processor.plan_execution_completed.connect(_on_plan_execution_completed)
	
	# Initialize Selection System
	await _initialize_selection_system()
	
	# Initialize Command Translator
	var CommandTranslatorClass = preload("res://scripts/ai/command_translator.gd")
	command_translator = CommandTranslatorClass.new()
	command_translator.name = "TestCommandTranslator"
	add_child(command_translator)
	
	# Connect command translator signals
	command_translator.command_executed.connect(_on_command_executed)
	command_translator.command_failed.connect(_on_translator_command_failed)
	
	# Initialize Action Validator
	var ActionValidatorClass = preload("res://scripts/ai/action_validator.gd")
	action_validator = ActionValidatorClass.new()
	action_validator.name = "TestActionValidator"
	add_child(action_validator)
	
	# Setup AI processor with dependencies
	ai_command_processor.setup(logger, GameConstants, action_validator, null)
	
	if logger:
		logger.info("ComprehensiveTest", "All test systems initialized")
	else:
		print("All test systems initialized")

func _initialize_selection_system() -> void:
	"""Initialize the selection system for the test"""
	print("Initializing selection system...")
	
	# Find camera
	var main_scene = get_tree().current_scene
	var camera = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld/3DView/Camera3D")
	
	if camera:
		camera.add_to_group("cameras")
		camera.add_to_group("rts_cameras")
		print("Found and configured camera: %s" % camera.name)
	else:
		print("WARNING: Camera not found for selection system")
	
	# Create enhanced selection system
	var EnhancedSelectionSystemClass = preload("res://scripts/core/enhanced_selection_system.gd")
	selection_system = EnhancedSelectionSystemClass.new()
	selection_system.name = "TestSelectionSystem"
	
	# Add to 3D scene
	var scene_3d = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld/3DView")
	if scene_3d:
		scene_3d.call_deferred("add_child", selection_system)
		print("Selection system added to 3D scene")
	else:
		call_deferred("add_child", selection_system)
		print("Selection system added to test node")
	
	# Connect selection signals
	selection_system.units_selected.connect(_on_units_selected)
	selection_system.units_deselected.connect(_on_units_deselected)
	selection_system.selection_changed.connect(_on_selection_changed)
	
	# Link selection system to AI processor
	ai_command_processor.selection_manager = selection_system
	
	print("Selection system initialized")

func _setup_test_ui() -> void:
	"""Setup test UI for command input and feedback"""
	var main_scene = get_tree().current_scene
	var game_ui = main_scene.get_node_or_null("GameUI")
	
	if not game_ui:
		print("WARNING: Could not find GameUI for test interface")
		return
	
	# Create test UI container
	var test_ui_container = Control.new()
	test_ui_container.name = "ComprehensiveTestUI"
	test_ui_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_ui.add_child(test_ui_container)
	
	# Create command dialog box
	_create_command_dialog(test_ui_container)
	
	# Create feedback display
	test_feedback_ui = RichTextLabel.new()
	test_feedback_ui.name = "TestFeedback"
	test_feedback_ui.position = Vector2(50, 100)
	test_feedback_ui.size = Vector2(600, 400)
	test_feedback_ui.bbcode_enabled = true
	test_feedback_ui.text = "[b]🎮 Comprehensive Unit Control Test[/b]\n\n[color=green]Systems initialized![/color]\n\nControls:\n• [b]ENTER[/b]: AI Command Dialog\n• [b]F11[/b]: Auto demo mode\n• [b]F12[/b]: System status\n• [b]Click units[/b]: Select for commands\n• [b]ESC[/b]: Cancel/Exit\n\n[color=yellow]Ready for testing![/color]"
	test_ui_container.add_child(test_feedback_ui)
	
	# Create button panel for alternative input
	var button_panel = Panel.new()
	button_panel.name = "ButtonPanel"
	button_panel.position = Vector2(50, 520)
	button_panel.size = Vector2(600, 60)
	test_ui_container.add_child(button_panel)
	
	var button_container = HBoxContainer.new()
	button_container.name = "ButtonContainer"
	button_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button_container.add_theme_constant_override("separation", 10)
	button_panel.add_child(button_container)
	
	# Create AI Command button
	var ai_command_button = Button.new()
	ai_command_button.name = "AICommandButton"
	ai_command_button.text = "🧠 Open AI Command Dialog"
	ai_command_button.custom_minimum_size = Vector2(200, 40)
	ai_command_button.pressed.connect(_toggle_command_input)
	button_container.add_child(ai_command_button)
	
	# Create Auto Demo button
	var auto_demo_button = Button.new()
	auto_demo_button.name = "AutoDemoButton"
	auto_demo_button.text = "🤖 Start Auto Demo"
	auto_demo_button.custom_minimum_size = Vector2(150, 40)
	auto_demo_button.pressed.connect(_start_auto_demo)
	button_container.add_child(auto_demo_button)
	
	# Create System Status button
	var status_button = Button.new()
	status_button.name = "StatusButton"
	status_button.text = "📊 System Status"
	status_button.custom_minimum_size = Vector2(150, 40)
	status_button.pressed.connect(_show_system_status)
	button_container.add_child(status_button)
	
	print("Test UI setup complete")

func _create_command_dialog(parent: Control) -> void:
	"""Create the AI command input dialog"""
	# Create the main dialog
	command_dialog = AcceptDialog.new()
	command_dialog.name = "AICommandDialog"
	command_dialog.title = "🧠 AI Command Input"
	command_dialog.size = Vector2(600, 500)
	command_dialog.unresizable = false
	command_dialog.popup_window = false
	parent.add_child(command_dialog)
	
	# Center the dialog
	command_dialog.popup_centered()
	command_dialog.visible = false
	
	# Create main container
	var dialog_container = VBoxContainer.new()
	dialog_container.name = "DialogContainer"
	dialog_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog_container.add_theme_constant_override("separation", 10)
	command_dialog.add_child(dialog_container)
	
	# Create title and instructions
	var title_label = RichTextLabel.new()
	title_label.name = "TitleLabel"
	title_label.custom_minimum_size = Vector2(0, 80)
	title_label.bbcode_enabled = true
	title_label.text = "[center][b][color=cyan]🎮 AI Command Center[/color][/b][/center]\n[center]Give natural language commands to your animated units![/center]"
	title_label.fit_content = true
	dialog_container.add_child(title_label)
	
	# Create command input area
	var input_label = Label.new()
	input_label.text = "Enter your command:"
	input_label.add_theme_font_size_override("font_size", 14)
	dialog_container.add_child(input_label)
	
	# Create multi-line text input
	command_text_edit = TextEdit.new()
	command_text_edit.name = "CommandTextEdit"
	command_text_edit.custom_minimum_size = Vector2(0, 120)
	command_text_edit.placeholder_text = "Type your AI command here...\nExample: 'Move the scout to explore the eastern area'"
	command_text_edit.wrap_mode = 1  # Word wrapping
	dialog_container.add_child(command_text_edit)
	
	# Create examples section
	var examples_label = Label.new()
	examples_label.text = "💡 Example Commands:"
	examples_label.add_theme_font_size_override("font_size", 12)
	dialog_container.add_child(examples_label)
	
	command_examples_label = RichTextLabel.new()
	command_examples_label.name = "ExamplesLabel"
	command_examples_label.custom_minimum_size = Vector2(0, 150)
	command_examples_label.bbcode_enabled = true
	command_examples_label.text = """[color=yellow]• "Move the scout to explore the eastern area"[/color]
[color=yellow]• "Have the sniper find cover and overwatch"[/color]
[color=yellow]• "Scout ahead, then advance if safe"[/color]
[color=yellow]• "Set up defensive positions and retreat if health drops below 30%"[/color]
[color=yellow]• "Coordinate a flanking maneuver with scout and soldier"[/color]
[color=yellow]• "All units move to the center in formation"[/color]

[color=gray][i]💡 Tip: Select units first, then give commands for better targeting![/i][/color]"""
	command_examples_label.fit_content = true
	dialog_container.add_child(command_examples_label)
	
	# Create button container
	var button_container = HBoxContainer.new()
	button_container.name = "ButtonContainer"
	button_container.add_theme_constant_override("separation", 10)
	dialog_container.add_child(button_container)
	
	# Add spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_container.add_child(spacer)
	
	# Create Submit button
	var submit_button = Button.new()
	submit_button.name = "SubmitButton"
	submit_button.text = "🚀 Execute Command"
	submit_button.custom_minimum_size = Vector2(150, 40)
	button_container.add_child(submit_button)
	
	# Create Clear button
	var clear_button = Button.new()
	clear_button.name = "ClearButton"
	clear_button.text = "🗑️ Clear"
	clear_button.custom_minimum_size = Vector2(100, 40)
	button_container.add_child(clear_button)
	
	# Create Cancel button (AcceptDialog already has OK button, we'll customize it)
	command_dialog.get_ok_button().text = "❌ Cancel"
	command_dialog.get_ok_button().custom_minimum_size = Vector2(100, 40)
	
	# Connect signals
	submit_button.pressed.connect(_on_submit_command)
	clear_button.pressed.connect(_on_clear_command)
	command_dialog.confirmed.connect(_on_dialog_cancelled)
	command_dialog.canceled.connect(_on_dialog_cancelled)
	
	# Allow Enter to submit (with Ctrl+Enter for new line)
	command_text_edit.gui_input.connect(_on_text_edit_input)
	
	print("Command dialog created")

func _spawn_test_units() -> void:
	"""Spawn test units for the comprehensive test"""
	print("Spawning test units...")
	
	# Try to load the AnimatedUnit scene
	var unit_scene_path = "res://scenes/units/AnimatedUnit.tscn"
	var unit_scene = load(unit_scene_path)
	
	if not unit_scene:
		print("ERROR: Could not load AnimatedUnit scene from %s" % unit_scene_path)
		_log_feedback("[color=red]ERROR: Could not load AnimatedUnit scene[/color]")
		return
	
	# Find the 3D scene to spawn units in
	var main_scene = get_tree().current_scene
	var scene_3d = main_scene.get_node_or_null("GameUI/GameWorldContainer/GameWorld/3DView")
	var units_container = scene_3d.get_node_or_null("Units") if scene_3d else null
	
	if not units_container:
		units_container = Node3D.new()
		units_container.name = "TestUnits"
		if scene_3d:
			scene_3d.add_child(units_container)
		else:
			add_child(units_container)
	
	# Unit configurations for comprehensive testing
	var unit_configs = [
		{"archetype": "scout", "position": Vector3(-8, 0, -5), "team": 1, "name": "Scout Alpha"},
		{"archetype": "soldier", "position": Vector3(-3, 0, -5), "team": 1, "name": "Soldier Bravo"},
		{"archetype": "sniper", "position": Vector3(2, 0, -5), "team": 1, "name": "Sniper Charlie"},
		{"archetype": "medic", "position": Vector3(7, 0, -5), "team": 1, "name": "Medic Delta"},
		{"archetype": "engineer", "position": Vector3(12, 0, -5), "team": 1, "name": "Engineer Echo"}
	]
	
	# Spawn units
	for config in unit_configs:
		var unit = unit_scene.instantiate()
		if not unit:
			print("ERROR: Failed to instantiate unit")
			continue
		
		# Configure unit
		unit.archetype = config.archetype
		unit.team_id = config.team
		unit.unit_id = "%s_%d" % [config.archetype, config.team]
		unit.name = config.name
		unit.position = config.position
		
		# Add to scene
		units_container.add_child(unit)
		test_units.append(unit)
		
		# Ensure unit is in units group for selection
		unit.add_to_group("units")
		
		print("Spawned %s at %s" % [config.name, config.position])
	
	# Log spawn results
	_log_feedback("[color=green]Spawned %d test units:[/color]" % test_units.size())
	for unit in test_units:
		_log_feedback("• %s (%s) - Team %d" % [unit.name, unit.archetype, unit.team_id])
	
	print("Test units spawned: %d" % test_units.size())

func _start_comprehensive_test() -> void:
	"""Start the comprehensive test sequence"""
	demo_active = true
	current_test_phase = TestPhase.INITIALIZATION
	
	_log_feedback("\n[b][color=cyan]🚀 COMPREHENSIVE TEST STARTED[/color][/b]")
	_log_feedback("Phase: Initialization Complete")
	_log_feedback("Ready for manual commands or automated demo")
	
	# Mark initialization as complete
	test_results[TestPhase.INITIALIZATION] = {"success": true, "time": Time.get_ticks_msec()}
	current_test_phase = TestPhase.SELECTION_TEST
	
	test_phase_completed.emit(TestPhase.INITIALIZATION, true)

func _input(event: InputEvent) -> void:
	"""Handle test input events"""
	if event is InputEventKey and event.pressed:
		# Always allow Ctrl+T to toggle testing mode
		if event.keycode == KEY_T and Input.is_action_pressed("ctrl"):
			testing_enabled = !testing_enabled
			print("ComprehensiveUnitControlTest: Testing mode %s" % ("enabled" if testing_enabled else "disabled"))
			set_process_input(testing_enabled)
			set_process_unhandled_input(testing_enabled)
			if testing_enabled:
				print("ComprehensiveUnitControlTest: Testing mode enabled. Use Enter to open command input, F11 for auto demo, F12 for system status.")
			return
		
		# Only handle other inputs if testing is enabled
		if not testing_enabled:
			return
			
		# Debug logging
		print("ComprehensiveTest: Key pressed: %s (demo_active: %s)" % [event.keycode, demo_active])
		
		match event.keycode:
			KEY_ENTER:
				if demo_active:
					_toggle_command_input()
					get_viewport().set_input_as_handled()
			KEY_F11:
				if demo_active:
					_start_auto_demo()
					get_viewport().set_input_as_handled()
			KEY_F12:
				if demo_active:
					_show_system_status()
					get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if demo_active:
					_cancel_current_operation()
					get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	"""Handle unhandled input events as fallback"""
	if not testing_enabled:
		return
		
	if event is InputEventKey and event.pressed:
		print("ComprehensiveTest: Unhandled key: %s (demo_active: %s)" % [event.keycode, demo_active])
		
		if demo_active:
			match event.keycode:
				KEY_ENTER:
					_toggle_command_input()
					get_viewport().set_input_as_handled()
				KEY_F11:
					_start_auto_demo()
					get_viewport().set_input_as_handled()
				KEY_F12:
					_show_system_status()
					get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_cancel_current_operation()
					get_viewport().set_input_as_handled()

func _toggle_command_input() -> void:
	"""Toggle command input dialog"""
	print("ComprehensiveTest: _toggle_command_input called")
	
	if command_dialog:
		print("ComprehensiveTest: command_dialog exists, visible = %s" % command_dialog.visible)
		if command_dialog.visible:
			command_dialog.hide()
			_log_feedback("[color=gray]Command dialog closed[/color]")
		else:
			command_dialog.popup_centered()
			command_text_edit.grab_focus()
			_log_feedback("[color=yellow]💬 AI Command Dialog opened - enter your command![/color]")
	else:
		print("ComprehensiveTest: ERROR - command_dialog is null!")
		_log_feedback("[color=red]ERROR: Command dialog not available![/color]")

func _start_auto_demo() -> void:
	"""Start automated demo sequence"""
	auto_demo_mode = true
	demo_step_timer = 0.0
	current_test_phase = TestPhase.SIMPLE_AI_COMMANDS
	
	_log_feedback("\n[b][color=cyan]🤖 AUTOMATED DEMO STARTED[/color][/b]")
	_log_feedback("Running through all test phases automatically...")
	
	# Start with first demo command
	_execute_next_demo_step()

func _execute_next_demo_step() -> void:
	"""Execute the next step in the automated demo"""
	if not auto_demo_mode:
		return
	
	# Find next command for current phase
	var next_command = null
	for cmd in demo_commands:
		if cmd.phase == current_test_phase:
			next_command = cmd
			break
	
	if next_command:
		_log_feedback("\n[color=cyan]🎯 Testing: %s[/color]" % next_command.command)
		_log_feedback("Expected: %s" % next_command.expected)
		
		# Process the command
		_process_ai_command(next_command.command)
		
		# Remove processed command
		demo_commands.erase(next_command)
	else:
		# Move to next phase
		_advance_to_next_phase()

func _advance_to_next_phase() -> void:
	"""Advance to the next test phase"""
	var next_phase = current_test_phase + 1
	
	if next_phase >= TestPhase.COMPLETE:
		_complete_all_tests()
		return
	
	current_test_phase = next_phase
	var phase_name = _get_phase_name(current_test_phase)
	
	_log_feedback("\n[b][color=magenta]📈 ADVANCING TO PHASE: %s[/color][/b]" % phase_name)
	
	# Continue with next phase after delay
	await get_tree().create_timer(2.0).timeout
	if auto_demo_mode:
		_execute_next_demo_step()

func _show_system_status() -> void:
	"""Show detailed system status"""
	var status_text = "\n[b][color=cyan]🔍 SYSTEM STATUS[/color][/b]\n"
	
	# AI Command Processor status
	if ai_command_processor:
		status_text += "• [color=green]AI Command Processor: ACTIVE[/color]\n"
		status_text += "  - Processing: %s\n" % ai_command_processor.is_command_processing()
		status_text += "  - Queue Size: %d\n" % ai_command_processor.get_queue_size()
		var stats = ai_command_processor.get_plan_statistics()
		status_text += "  - Plans Executed: %d\n" % stats.get("total_plans", 0)
		status_text += "  - Success Rate: %.1f%%\n" % stats.get("success_rate", 0.0)
	else:
		status_text += "• [color=red]AI Command Processor: NOT FOUND[/color]\n"
	
	# Selection System status
	if selection_system:
		status_text += "• [color=green]Selection System: ACTIVE[/color]\n"
		status_text += "  - Selected Units: %d\n" % selection_system.get_selection_count()
		if selection_system.has_selection():
			var selected = selection_system.get_selected_units()
			for unit in selected:
				status_text += "    - %s (%s)\n" % [unit.name, unit.archetype]
	else:
		status_text += "• [color=red]Selection System: NOT FOUND[/color]\n"
	
	# Units status
	status_text += "• [color=green]Test Units: %d[/color]\n" % test_units.size()
	for unit in test_units:
		if unit and is_instance_valid(unit):
			var state_name = "Unknown"
			if unit.has_method("get_current_state"):
				state_name = str(unit.get_current_state())
			status_text += "  - %s: %s (HP: %.0f/%.0f)\n" % [unit.name, state_name, unit.current_health, unit.max_health]
	
	# Test Results
	status_text += "• [color=yellow]Test Results:[/color]\n"
	for phase in test_results:
		var result = test_results[phase]
		var phase_name = _get_phase_name(phase)
		var success_color = "green" if result.success else "red"
		status_text += "  - %s: [color=%s]%s[/color]\n" % [phase_name, success_color, "PASS" if result.success else "FAIL"]
	
	_log_feedback(status_text)

func _process_ai_command(command_text: String) -> void:
	"""Process an AI command through the full system"""
	if not ai_command_processor:
		_log_feedback("[color=red]ERROR: AI Command Processor not available[/color]")
		return
	
	var start_time = Time.get_ticks_msec()
	_log_feedback("[color=cyan]🧠 Processing AI Command:[/color] '%s'" % command_text)
	
	# Get current selection for context
	var selected_units = []
	if selection_system and selection_system.has_selection():
		selected_units = selection_system.get_selected_units()
		_log_feedback("Using %d selected units" % selected_units.size())
	
	# Build game state for AI context
	var game_state = _build_game_state()
	
	# Process the command
	ai_command_processor.process_command(command_text, selected_units, game_state)

func _build_game_state() -> Dictionary:
	"""Build game state for AI processing"""
	var game_state = {
		"units": [],
		"map_info": {
			"size": Vector2(100, 100),
			"terrain": "mixed"
		},
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	
	# Add unit information
	for unit in test_units:
		if unit and is_instance_valid(unit) and not unit.is_dead:
			var unit_data = {
				"unit_id": unit.unit_id,
				"name": unit.name,
				"archetype": unit.archetype,
				"team_id": unit.team_id,
				"position": [unit.global_position.x, unit.global_position.y, unit.global_position.z],
				"health": unit.current_health,
				"max_health": unit.max_health,
				"health_percentage": unit.current_health / unit.max_health * 100.0
			}
			
			if unit.has_method("get_current_state"):
				unit_data["state"] = str(unit.get_current_state())
			
			if unit.has_method("get_available_abilities"):
				unit_data["abilities"] = unit.get_available_abilities()
			
			game_state.units.append(unit_data)
	
	return game_state

func _cancel_current_operation() -> void:
	"""Cancel current operation"""
	if command_dialog and command_dialog.visible:
		command_dialog.hide()
		command_text_edit.text = ""
		_log_feedback("[color=gray]Command dialog cancelled[/color]")
		return
	
	if auto_demo_mode:
		auto_demo_mode = false
		_log_feedback("[color=yellow]Automated demo cancelled[/color]")
		return

func _complete_all_tests() -> void:
	"""Complete all tests and show results"""
	auto_demo_mode = false
	current_test_phase = TestPhase.COMPLETE
	
	_log_feedback("\n[b][color=green]🎉 ALL TESTS COMPLETED![/color][/b]")
	
	# Calculate overall results
	var total_tests = test_results.size()
	var passed_tests = 0
	for phase in test_results:
		if test_results[phase].success:
			passed_tests += 1
	
	var success_rate = float(passed_tests) / float(total_tests) * 100.0
	_log_feedback("Overall Success Rate: [b]%.1f%%[/b] (%d/%d)" % [success_rate, passed_tests, total_tests])
	
	# Show detailed results
	_log_feedback("\n[b]Detailed Results:[/b]")
	for phase in test_results:
		var result = test_results[phase]
		var phase_name = _get_phase_name(phase)
		var success_color = "green" if result.success else "red"
		var status = "PASS" if result.success else "FAIL"
		_log_feedback("• %s: [color=%s][b]%s[/b][/color]" % [phase_name, success_color, status])
	
	all_tests_completed.emit(test_results)

func _get_phase_name(phase: TestPhase) -> String:
	"""Get human-readable phase name"""
	match phase:
		TestPhase.INITIALIZATION: return "Initialization"
		TestPhase.UNIT_SPAWNING: return "Unit Spawning"
		TestPhase.SELECTION_TEST: return "Selection Test"
		TestPhase.SIMPLE_AI_COMMANDS: return "Simple AI Commands"
		TestPhase.COMPLEX_AI_PLANS: return "Complex AI Plans"
		TestPhase.MULTI_UNIT_COORDINATION: return "Multi-Unit Coordination"
		TestPhase.TRIGGER_BASED_PLANS: return "Trigger-Based Plans"
		TestPhase.PERFORMANCE_TEST: return "Performance Test"
		TestPhase.COMPLETE: return "Complete"
		_: return "Unknown"

func _log_feedback(message: String) -> void:
	"""Log feedback to UI and console"""
	if test_feedback_ui:
		test_feedback_ui.text += "\n" + message
		# Auto-scroll to bottom
		test_feedback_ui.scroll_to_line(test_feedback_ui.get_line_count() - 1)
	
	print("ComprehensiveTest: " + message.strip_edges())

# Signal handlers for dialog
func _on_submit_command() -> void:
	"""Handle command submission from dialog"""
	if not command_text_edit:
		return
	
	var command_text = command_text_edit.text.strip_edges()
	if command_text.is_empty():
		_log_feedback("[color=red]Please enter a command before submitting![/color]")
		return
	
	# Hide dialog and process command
	command_dialog.hide()
	_log_feedback("[color=cyan]📝 Command submitted:[/color] '%s'" % command_text)
	
	# Clear the text for next time
	command_text_edit.text = ""
	
	# Process the AI command
	_process_ai_command(command_text)

func _on_clear_command() -> void:
	"""Handle clearing the command text"""
	if command_text_edit:
		command_text_edit.text = ""
		command_text_edit.grab_focus()
		_log_feedback("[color=gray]Command text cleared[/color]")

func _on_dialog_cancelled() -> void:
	"""Handle dialog cancellation"""
	_log_feedback("[color=gray]Command dialog cancelled[/color]")

func _on_text_edit_input(event: InputEvent) -> void:
	"""Handle TextEdit input for keyboard shortcuts"""
	if event is InputEventKey and event.pressed:
		# Ctrl+Enter to submit
		if event.keycode == KEY_ENTER and event.ctrl_pressed:
			_on_submit_command()
			get_viewport().set_input_as_handled()
		# Escape to cancel
		elif event.keycode == KEY_ESCAPE:
			command_dialog.hide()
			get_viewport().set_input_as_handled()

# Legacy signal handler (kept for compatibility)
func _on_command_submitted(text: String) -> void:
	"""Handle manual command submission (legacy)"""
	if text.strip_edges().is_empty():
		return
	
	_process_ai_command(text)

func _on_units_selected(units: Array) -> void:
	"""Handle unit selection"""
	_log_feedback("[color=yellow]📋 Selected %d units:[/color]" % units.size())
	for unit in units:
		_log_feedback("• %s (%s)" % [unit.name, unit.archetype])

func _on_units_deselected(units: Array) -> void:
	"""Handle unit deselection"""
	_log_feedback("[color=gray]📋 Deselected %d units[/color]" % units.size())

func _on_selection_changed(selected_units: Array) -> void:
	"""Handle selection changes"""
	if selected_units.size() > 0:
		_log_feedback("[color=cyan]Current selection: %d units[/color]" % selected_units.size())

func _on_processing_started() -> void:
	"""Handle AI processing start"""
	_log_feedback("[color=cyan]🧠 AI processing started...[/color]")

func _on_processing_finished() -> void:
	"""Handle AI processing completion"""
	_log_feedback("[color=green]🧠 AI processing completed[/color]")

func _on_command_processed(commands: Array, message: String) -> void:
	"""Handle direct command processing"""
	_log_feedback("[color=green]✅ Direct commands processed:[/color] %s" % message)
	_log_feedback("Commands: %d" % commands.size())
	
	for i in range(commands.size()):
		var cmd = commands[i]
		_log_feedback("• Command %d: %s → %s" % [i+1, cmd.get("action", "unknown"), str(cmd.get("target_units", []))])
	
	# Mark test success
	_record_test_success("direct_command")

func _on_plan_processed(plans: Array, message: String) -> void:
	"""Handle multi-step plan processing"""
	_log_feedback("[color=green]🎯 Multi-step plans processed:[/color] %s" % message)
	_log_feedback("Plans: %d" % plans.size())
	
	for i in range(plans.size()):
		var plan = plans[i]
		var unit_id = plan.get("unit_id", "unknown")
		var steps = plan.get("steps", [])
		_log_feedback("• Plan %d: Unit %s → %d steps" % [i+1, unit_id, steps.size()])
		
		# Show first few steps
		for j in range(min(3, steps.size())):
			var step = steps[j]
			_log_feedback("  - Step %d: %s" % [j+1, step.get("action", "unknown")])
	
	# Mark test success
	_record_test_success("multi_step_plan")

func _on_command_failed(error: String) -> void:
	"""Handle command processing failure"""
	_log_feedback("[color=red]❌ AI command failed:[/color] %s" % error)
	_record_test_failure("ai_command", error)

func _on_plan_execution_started(unit_id: String, plan: Dictionary) -> void:
	"""Handle plan execution start"""
	_log_feedback("[color=cyan]▶️ Plan execution started for unit:[/color] %s" % unit_id)
	var steps = plan.get("steps", [])
	_log_feedback("Plan has %d steps" % steps.size())

func _on_plan_execution_completed(unit_id: String, success: bool) -> void:
	"""Handle plan execution completion"""
	var status_color = "green" if success else "red"
	var status_text = "SUCCESS" if success else "FAILED"
	_log_feedback("[color=%s]⏹️ Plan execution %s for unit:[/color] %s" % [status_color, status_text, unit_id])
	
	if success:
		_record_test_success("plan_execution")
	else:
		_record_test_failure("plan_execution", "Plan failed for unit " + unit_id)

func _on_command_executed(command_id: int, result: String) -> void:
	"""Handle command execution by translator"""
	_log_feedback("[color=green]⚡ Command %d executed:[/color] %s" % [command_id, result])

func _on_translator_command_failed(command_id: int, error: String) -> void:
	"""Handle command execution failure"""
	_log_feedback("[color=red]❌ Command %d failed:[/color] %s" % [command_id, error])

func _record_test_success(test_type: String) -> void:
	"""Record a successful test"""
	var current_time = Time.get_ticks_msec()
	if not test_results.has(current_test_phase):
		test_results[current_test_phase] = {"success": true, "time": current_time, "tests": []}
	
	test_results[current_test_phase].tests.append({
		"type": test_type,
		"success": true,
		"time": current_time
	})
	
	# Advance demo if in auto mode
	if auto_demo_mode:
		await get_tree().create_timer(2.0).timeout
		_execute_next_demo_step()

func _record_test_failure(test_type: String, error: String) -> void:
	"""Record a failed test"""
	var current_time = Time.get_ticks_msec()
	if not test_results.has(current_test_phase):
		test_results[current_test_phase] = {"success": false, "time": current_time, "tests": []}
	
	test_results[current_test_phase].success = false
	test_results[current_test_phase].tests.append({
		"type": test_type,
		"success": false,
		"time": current_time,
		"error": error
	}) 