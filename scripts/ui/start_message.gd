# StartMessage.gd - Tutorial overlay that appears at game start
class_name StartMessage
extends Control

# UI node references
@onready var got_it_button: Button = $CenterContainer/MessagePanel/VBoxContainer/ButtonContainer/GotItButton

# State tracking
var has_shown: bool = false
var is_visible: bool = false

# Signals
signal start_message_dismissed()

func _ready() -> void:
    # Connect button signal
    got_it_button.pressed.connect(_on_got_it_pressed)
    
    # Ensure start message appears above all other UI
    z_index = 90  # Below victory screen (100) but above everything else
    
    # Hide by default
    visible = false
    is_visible = false

func show_start_message() -> void:
    """Display the start message with fade-in animation"""
    if has_shown:
        return  # Only show once per game session
    
    print("StartMessage: Showing tutorial overlay")
    
    # Ensure we're on top of other UI (except victory screen)
    move_to_front()
    
    # Show with fade-in animation
    visible = true
    is_visible = true
    modulate.a = 0.0
    
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, 0.3)
    
    has_shown = true

func hide_start_message() -> void:
    """Hide the start message with fade-out animation"""
    if not is_visible:
        return
    
    print("StartMessage: Hiding tutorial overlay")
    
    is_visible = false
    
    # Fade out animation
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.2)
    tween.tween_callback(func(): visible = false)
    
    # Emit signal so other systems know it was dismissed
    start_message_dismissed.emit()

func _on_got_it_pressed() -> void:
    """Handle Got It button press"""
    print("StartMessage: Got It button pressed")
    hide_start_message()

func _unhandled_input(event: InputEvent) -> void:
    """Handle unhandled input while start message is visible - only keyboard events"""
    if not is_visible:
        return
    
    # Only handle keyboard events, let mouse events pass through to UI elements
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            _on_got_it_pressed()
            get_viewport().set_input_as_handled()

func is_currently_visible() -> bool:
    """Check if start message is currently visible"""
    return is_visible

func reset_for_new_game() -> void:
    """Reset the start message for a new game"""
    has_shown = false
    is_visible = false
    visible = false
    modulate.a = 1.0 