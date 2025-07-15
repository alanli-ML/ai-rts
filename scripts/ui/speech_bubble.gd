# SpeechBubble.gd
class_name SpeechBubble
extends Control

# Load shared constants
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Constants
const MAX_WORDS = 12
const DISPLAY_DURATION = GameConstants.SPEECH_BUBBLE_DURATION
const FADE_DURATION = GameConstants.SPEECH_BUBBLE_FADE_TIME
const BUBBLE_OFFSET = Vector2(0, -50)  # Offset above unit
const MAX_BUBBLE_WIDTH = 200
const BUBBLE_PADDING = Vector2(10, 5)

# Visual settings
@export var bubble_color: Color = Color(0.2, 0.2, 0.2, 0.9)
@export var text_color: Color = Color.WHITE
@export var border_color: Color = Color(0.4, 0.4, 0.4, 1.0)
@export var border_width: float = 2.0
@export var corner_radius: float = 8.0

# UI elements
var background_panel: Panel
var text_label: Label
var fade_timer: Timer
var display_timer: Timer

# State
var target_unit: Node3D = null
var camera: Camera3D = null
var is_fading: bool = false
var original_text: String = ""
var team_id: int = 0

# Signals
signal speech_bubble_finished(unit_id: String)
signal speech_bubble_clicked(unit_id: String, text: String)

func _ready() -> void:
    # Set up the speech bubble UI
    _setup_ui()
    
    # Initially hidden
    modulate.a = 0.0
    visible = false
    
    # Set up timers
    _setup_timers()
    
    # Set mouse filter to detect clicks
    mouse_filter = Control.MOUSE_FILTER_PASS
    
    print("SpeechBubble: Speech bubble initialized")

func _setup_ui() -> void:
    """Set up the speech bubble UI elements"""
    
    # Set size and anchor
    custom_minimum_size = Vector2(50, 30)
    set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    
    # Create background panel
    background_panel = Panel.new()
    background_panel.name = "BackgroundPanel"
    background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    
    # Create custom style for the panel
    var style_box = StyleBoxFlat.new()
    style_box.bg_color = bubble_color
    style_box.border_color = border_color
    style_box.border_width_left = border_width
    style_box.border_width_right = border_width
    style_box.border_width_top = border_width
    style_box.border_width_bottom = border_width
    style_box.corner_radius_top_left = corner_radius
    style_box.corner_radius_top_right = corner_radius
    style_box.corner_radius_bottom_left = corner_radius
    style_box.corner_radius_bottom_right = corner_radius
    background_panel.add_theme_stylebox_override("panel", style_box)
    
    add_child(background_panel)
    
    # Create text label
    text_label = Label.new()
    text_label.name = "TextLabel"
    text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    text_label.add_theme_color_override("font_color", text_color)
    text_label.add_theme_constant_override("outline_size", 1)
    text_label.add_theme_color_override("font_outline_color", Color.BLACK)
    
    background_panel.add_child(text_label)

func _setup_timers() -> void:
    """Set up timers for display and fade"""
    
    # Display timer
    display_timer = Timer.new()
    display_timer.name = "DisplayTimer"
    display_timer.wait_time = DISPLAY_DURATION
    display_timer.one_shot = true
    display_timer.timeout.connect(_start_fade)
    add_child(display_timer)
    
    # Fade timer
    fade_timer = Timer.new()
    fade_timer.name = "FadeTimer"
    fade_timer.wait_time = FADE_DURATION
    fade_timer.one_shot = true
    fade_timer.timeout.connect(_finish_fade)
    add_child(fade_timer)

func show_speech(text: String, unit: Node3D, team: int = 0) -> void:
    """Show speech bubble with text above unit"""
    
    if not unit:
        print("SpeechBubble: Cannot show speech - unit is null")
        return
    
    # Store references
    target_unit = unit
    team_id = team
    original_text = text
    
    # Process text (limit words and clean up)
    var processed_text = _process_text(text)
    
    # Update text label
    text_label.text = processed_text
    
    # Resize bubble to fit text
    _resize_bubble()
    
    # Find camera for screen positioning
    camera = _find_camera()
    if not camera:
        print("SpeechBubble: Cannot show speech - no camera found")
        return
    
    # Position bubble
    _update_position()
    
    # Show with fade in
    _show_with_animation()
    
    # Start display timer
    display_timer.start()
    
    print("SpeechBubble: Showing speech for unit %s: %s" % [unit.name, processed_text])

func _process_text(text: String) -> String:
    """Process text to ensure it meets requirements"""
    
    # Clean up whitespace
    text = text.strip_edges()
    
    # Split into words
    var words = text.split(" ")
    
    # Limit to MAX_WORDS
    if words.size() > MAX_WORDS:
        words = words.slice(0, MAX_WORDS)
        text = " ".join(words) + "..."
    
    # Ensure it's not empty
    if text.is_empty():
        text = "..."
    
    return text

func _resize_bubble() -> void:
    """Resize bubble to fit text content"""
    
    # Get text size
    var text_size = text_label.get_theme_default_font().get_string_size(
        text_label.text,
        HORIZONTAL_ALIGNMENT_CENTER,
        MAX_BUBBLE_WIDTH - BUBBLE_PADDING.x * 2,
        text_label.get_theme_default_font_size()
    )
    
    # Calculate bubble size
    var bubble_size = text_size + BUBBLE_PADDING * 2
    bubble_size.x = min(bubble_size.x, MAX_BUBBLE_WIDTH)
    bubble_size.y = max(bubble_size.y, 30)  # Minimum height
    
    # Apply size
    custom_minimum_size = bubble_size
    size = bubble_size

func _find_camera() -> Camera3D:
    """Find the main camera in the scene"""
    
    # Try to find camera in various ways
    var cameras = get_tree().get_nodes_in_group("cameras")
    if cameras.size() > 0:
        return cameras[0]
    
    # Try to find RTS camera
    var rts_cameras = get_tree().get_nodes_in_group("rts_cameras")
    if rts_cameras.size() > 0:
        return rts_cameras[0]
    
    # Try to find any Camera3D
    var all_cameras = get_tree().get_nodes_in_group("Camera3D")
    if all_cameras.size() > 0:
        return all_cameras[0]
    
    # Last resort: search by type
    var scene_root = get_tree().current_scene
    if scene_root:
        var camera_nodes = _find_nodes_by_type(scene_root, "Camera3D")
        if camera_nodes.size() > 0:
            return camera_nodes[0]
    
    return null

func _find_nodes_by_type(node: Node, type_name: String) -> Array:
    """Recursively find nodes of a specific type"""
    var result = []
    
    # Check if the node is the type we're looking for
    if node.get_class() == type_name:
        result.append(node)
    
    for child in node.get_children():
        result.append_array(_find_nodes_by_type(child, type_name))
    
    return result

func _update_position() -> void:
    """Update bubble position to follow unit"""
    
    if not target_unit or not camera:
        return
    
    # Get unit's screen position
    var unit_pos_3d = target_unit.global_position + Vector3(0, 1, 0)  # Slightly above unit
    var screen_pos = camera.unproject_position(unit_pos_3d)
    
    # Apply offset
    screen_pos += BUBBLE_OFFSET
    
    # Clamp to screen bounds
    var viewport_size = get_viewport().get_visible_rect().size
    screen_pos.x = clamp(screen_pos.x - size.x / 2, 0, viewport_size.x - size.x)
    screen_pos.y = clamp(screen_pos.y - size.y, 0, viewport_size.y - size.y)
    
    # Set position
    position = screen_pos

func _show_with_animation() -> void:
    """Show bubble with fade-in animation"""
    
    visible = true
    is_fading = false
    
    # Create fade-in tween
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, 0.2)
    
    # Scale animation for more impact
    modulate.a = 0.0
    scale = Vector2(0.8, 0.8)
    tween.parallel().tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
    tween.set_ease(Tween.EASE_OUT)
    tween.set_trans(Tween.TRANS_BACK)

func _start_fade() -> void:
    """Start fade-out animation"""
    
    is_fading = true
    fade_timer.start()
    
    # Create fade-out tween
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
    tween.parallel().tween_property(self, "scale", Vector2(0.8, 0.8), FADE_DURATION)
    tween.set_ease(Tween.EASE_IN)

func _finish_fade() -> void:
    """Finish fade animation and hide bubble"""
    
    visible = false
    is_fading = false
    
    # Emit signal
    if target_unit:
        var unit_id = target_unit.get("unit_id") if target_unit.has_method("get") else target_unit.name
        speech_bubble_finished.emit(unit_id)
    
    # Clean up
    target_unit = null
    camera = null
    
    # Remove from parent if it's a dynamic bubble
    if get_parent() and get_parent().name == "SpeechBubbles":
        queue_free()

func _process(_delta: float) -> void:
    """Update bubble position every frame"""
    
    if target_unit and camera and visible and not is_fading:
        _update_position()

func _gui_input(event: InputEvent) -> void:
    """Handle input events on the speech bubble"""
    
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if target_unit:
            var unit_id = target_unit.get("unit_id") if target_unit.has_method("get") else target_unit.name
            speech_bubble_clicked.emit(unit_id, original_text)
            print("SpeechBubble: Clicked on speech bubble for unit %s" % unit_id)

func hide_immediately() -> void:
    """Hide bubble immediately without animation"""
    
    display_timer.stop()
    fade_timer.stop()
    
    visible = false
    is_fading = false
    
    # Emit signal
    if target_unit:
        var unit_id = target_unit.get("unit_id") if target_unit.has_method("get") else target_unit.name
        speech_bubble_finished.emit(unit_id)
    
    # Clean up
    target_unit = null
    camera = null

func set_bubble_color(color: Color) -> void:
    """Set the bubble background color"""
    bubble_color = color
    if background_panel:
        var style_box = background_panel.get_theme_stylebox("panel")
        if style_box is StyleBoxFlat:
            style_box.bg_color = color

func set_text_color(color: Color) -> void:
    """Set the text color"""
    text_color = color
    if text_label:
        text_label.add_theme_color_override("font_color", color)

func get_display_text() -> String:
    """Get the currently displayed text"""
    return text_label.text if text_label else ""

func get_original_text() -> String:
    """Get the original unprocessed text"""
    return original_text

func get_unit_id() -> String:
    """Get the unit ID this bubble belongs to"""
    if target_unit:
        return target_unit.get("unit_id") if target_unit.has_method("get") else target_unit.name
    return ""

func is_visible_to_team(viewer_team: int) -> bool:
    """Check if this bubble should be visible to a specific team"""
    # For now, all bubbles are visible to all teams for cooperative gameplay
    # This can be modified later for team-specific visibility
    return true

func extend_display_time(additional_seconds: float) -> void:
    """Extend the display time of the bubble"""
    if display_timer and not display_timer.is_stopped():
        display_timer.wait_time += additional_seconds
        display_timer.start()  # Restart with new time 