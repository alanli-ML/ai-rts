# CommandInputSimple.gd
class_name CommandInputSimple
extends Control

# UI settings
@export var input_field_width: int = 400
@export var input_field_height: int = 40

# Internal variables
var command_input_field: LineEdit = null
var command_history: Array[String] = []
var history_index: int = -1

func _ready() -> void:
    Logger.info("CommandInputSimple", "Initializing command input UI")
    _setup_ui()

func _setup_ui() -> void:
    # Set control to full rect
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Create input field
    command_input_field = LineEdit.new()
    command_input_field.name = "CommandInput"
    command_input_field.placeholder_text = "Enter command..."
    command_input_field.visible = false
    command_input_field.custom_minimum_size = Vector2(input_field_width, input_field_height)
    
    # Position at bottom center
    command_input_field.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    command_input_field.set_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    command_input_field.position.y = -100
    
    # Connect signals
    command_input_field.text_submitted.connect(_on_command_submitted)
    command_input_field.gui_input.connect(_on_input_field_gui_input)
    
    add_child(command_input_field)

func _input(event: InputEvent) -> void:
    # Toggle command input with Enter key
    if event.is_action_pressed("ui_text_submit") and not command_input_field.visible:
        show_command_input()
    elif event.is_action_pressed("ui_cancel") and command_input_field.visible:
        hide_command_input()

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
    command_history.push_front(text)
    if command_history.size() > 10:
        command_history.resize(10)
    
    # Emit command event
    EventBus.ui_command_entered.emit(text)
    Logger.info("CommandInputSimple", "Command submitted: " + text)
    
    # Clear and hide input
    command_input_field.clear()
    hide_command_input()

func show_command_input() -> void:
    command_input_field.visible = true
    command_input_field.grab_focus()
    history_index = -1

func hide_command_input() -> void:
    command_input_field.visible = false
    command_input_field.clear()

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