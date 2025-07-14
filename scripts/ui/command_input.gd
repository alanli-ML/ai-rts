# CommandInput.gd
class_name CommandInput
extends Control

# UI settings
@export var input_field_width: int = 400
@export var input_field_height: int = 40
@export var radial_menu_radius: float = 100.0
@export var radial_menu_button_size: float = 64.0

# Command settings
@export var command_history_size: int = 10
@export var quick_commands: Array[Dictionary] = [
	{"id": "attack", "label": "Attack", "icon": null, "command": "attack"},
	{"id": "defend", "label": "Defend", "icon": null, "command": "defend"},
	{"id": "patrol", "label": "Patrol", "icon": null, "command": "patrol"},
	{"id": "halt", "label": "Halt", "icon": null, "command": "halt"},
	{"id": "retreat", "label": "Retreat", "icon": null, "command": "retreat"},
	{"id": "build", "label": "Build", "icon": null, "command": "build"}
]

# UI elements
var command_input_field: LineEdit
var radial_menu: Control
var radial_buttons: Array[Button] = []

# Internal state
var command_history: Array[String] = []
var history_index: int = -1
var radial_menu_active: bool = false
var radial_menu_center: Vector2

func _ready() -> void:
	# Set up main container
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Create command input field
	_create_command_input()
	
	# Create radial menu
	_create_radial_menu()
	
	# Hide UI elements initially
	command_input_field.visible = false
	radial_menu.visible = false
	
	Logger.info("CommandInput", "Command Input UI initialized")

func _create_command_input() -> void:
	    # Container for input field
    var input_container = MarginContainer.new()
    input_container.name = "InputContainer"
    input_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    input_container.set_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    input_container.position.y = -100
    add_child(input_container)
	
	# Style the container
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(input_field_width, input_field_height)
	input_container.add_child(panel)
	
	# Create input field
	command_input_field = LineEdit.new()
	command_input_field.name = "CommandInput"
	command_input_field.placeholder_text = "Enter command..."
	command_input_field.clear_button_enabled = true
	panel.add_child(command_input_field)
	
	# Connect signals
	command_input_field.text_submitted.connect(_on_command_submitted)
	command_input_field.gui_input.connect(_on_input_field_gui_input)

func _create_radial_menu() -> void:
	# Container for radial menu
	radial_menu = Control.new()
	radial_menu.name = "RadialMenu"
	radial_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radial_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(radial_menu)
	
	# Create buttons for each quick command
	for i in range(quick_commands.size()):
		var command_data = quick_commands[i]
		var button = _create_radial_button(command_data)
		radial_buttons.append(button)
		radial_menu.add_child(button)

func _create_radial_button(command_data: Dictionary) -> Button:
	var button = Button.new()
	button.name = "RadialButton_" + command_data.id
	button.text = command_data.label
	button.custom_minimum_size = Vector2(radial_menu_button_size, radial_menu_button_size)
	button.pressed.connect(_on_radial_button_pressed.bind(command_data.command))
	
	# Style the button (you can customize this further)
	button.add_theme_font_size_override("font_size", 12)
	
	return button

func _input(event: InputEvent) -> void:
	# Toggle command input with Enter key
	if event.is_action_pressed("ui_text_submit") and not command_input_field.visible:
		show_command_input()
	elif event.is_action_pressed("ui_cancel") and command_input_field.visible:
		hide_command_input()
	
	# Radial menu with Q key (or customizable key)
	if event.is_action_pressed("quick_command"):
		if not radial_menu_active:
			show_radial_menu(get_global_mouse_position())
	elif event.is_action_released("quick_command"):
		if radial_menu_active:
			hide_radial_menu()

func _on_input_field_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Command history navigation
		if event.keycode == KEY_UP:
			_navigate_history(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_navigate_history(1)
			get_viewport().set_input_as_handled()

func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	
	# Add to history
	_add_to_history(text)
	
	# Emit command event
	EventBus.ui_command_entered.emit(text)
	Logger.info("CommandInput", "Command submitted: " + text)
	
	# Clear and hide input
	command_input_field.clear()
	hide_command_input()

func _on_radial_button_pressed(command: String) -> void:
	EventBus.ui_radial_command.emit(command)
	Logger.info("CommandInput", "Radial command: " + command)
	hide_radial_menu()

func show_command_input() -> void:
	command_input_field.visible = true
	command_input_field.grab_focus()
	history_index = -1

func hide_command_input() -> void:
	command_input_field.visible = false
	command_input_field.clear()

func show_radial_menu(position: Vector2) -> void:
	radial_menu_active = true
	radial_menu_center = position
	radial_menu.visible = true
	
	# Position buttons in a circle
	var angle_step = TAU / radial_buttons.size()
	for i in range(radial_buttons.size()):
		var angle = i * angle_step - PI / 2  # Start from top
		var button_pos = radial_menu_center + Vector2(
			cos(angle) * radial_menu_radius,
			sin(angle) * radial_menu_radius
		)
		
		var button = radial_buttons[i]
		button.position = button_pos - button.size / 2
		button.visible = true

func hide_radial_menu() -> void:
	radial_menu_active = false
	radial_menu.visible = false

func _add_to_history(command: String) -> void:
	# Remove duplicate if exists
	var existing_index = command_history.find(command)
	if existing_index != -1:
		command_history.remove_at(existing_index)
	
	# Add to front
	command_history.push_front(command)
	
	# Limit history size
	if command_history.size() > command_history_size:
		command_history.resize(command_history_size)

func _navigate_history(direction: int) -> void:
	if command_history.is_empty():
		return
	
	# Update index
	if history_index == -1 and direction < 0:
		history_index = 0
	else:
		history_index = clamp(history_index + direction, -1, command_history.size() - 1)
	
	# Update input field
	if history_index >= 0 and history_index < command_history.size():
		command_input_field.text = command_history[history_index]
		command_input_field.caret_column = command_input_field.text.length()
	else:
		command_input_field.clear()

func get_command_history() -> Array[String]:
	return command_history

func set_quick_commands(commands: Array[Dictionary]) -> void:
	quick_commands = commands
	
	# Recreate radial menu with new commands
	for button in radial_buttons:
		button.queue_free()
	radial_buttons.clear()
	
	for command_data in quick_commands:
		var button = _create_radial_button(command_data)
		radial_buttons.append(button)
		radial_menu.add_child(button) 
