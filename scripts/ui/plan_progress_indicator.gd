# PlanProgressIndicator.gd
class_name PlanProgressIndicator
extends Control

# Load shared constants
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Constants
const INDICATOR_OFFSET = Vector2(0, -80)  # Offset above unit (above speech bubbles)
const PROGRESS_BAR_WIDTH = 120
const PROGRESS_BAR_HEIGHT = 8
const INDICATOR_PADDING = Vector2(8, 6)
const FADE_DURATION = GameConstants.SPEECH_BUBBLE_FADE_TIME

# Visual settings
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.8)
@export var border_color: Color = Color(0.3, 0.3, 0.3, 1.0)
@export var text_color: Color = Color.WHITE
@export var progress_color: Color = Color(0.2, 0.6, 1.0, 1.0)
@export var trigger_color: Color = Color(1.0, 0.8, 0.2, 1.0)
@export var corner_radius: float = 4.0

# UI elements
var background_panel: Panel
var action_label: Label
var progress_bar: ProgressBar
var trigger_label: Label
var step_counter_label: Label

# State
var target_unit: Node3D = null
var camera: Camera3D = null
var current_plan_data: Dictionary = {}
var _is_visible: bool = false
var unit_id: String = ""
var team_id: int = 0

# Signals
signal indicator_clicked(unit_id: String)

func _ready() -> void:
    # Set up the indicator UI
    _setup_ui()
    
    # Initially hidden
    modulate.a = 0.0
    visible = false
    
    # Set mouse filter to detect clicks
    mouse_filter = Control.MOUSE_FILTER_PASS
    
    print("PlanProgressIndicator: Plan progress indicator initialized")

func _setup_ui() -> void:
    """Set up the indicator UI elements"""
    
    # Set initial size
    custom_minimum_size = Vector2(PROGRESS_BAR_WIDTH + INDICATOR_PADDING.x * 2, 50)
    set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    
    # Create background panel
    background_panel = Panel.new()
    background_panel.name = "BackgroundPanel"
    background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    
    # Create custom style for the panel
    var style_box = StyleBoxFlat.new()
    style_box.bg_color = background_color
    style_box.border_color = border_color
    style_box.border_width_left = 1
    style_box.border_width_right = 1
    style_box.border_width_top = 1
    style_box.border_width_bottom = 1
    style_box.corner_radius_top_left = corner_radius
    style_box.corner_radius_top_right = corner_radius
    style_box.corner_radius_bottom_left = corner_radius
    style_box.corner_radius_bottom_right = corner_radius
    background_panel.add_theme_stylebox_override("panel", style_box)
    
    add_child(background_panel)
    
    # Create main container
    var main_container = VBoxContainer.new()
    main_container.name = "MainContainer"
    main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    main_container.add_theme_constant_override("separation", 2)
    background_panel.add_child(main_container)
    
    # Create top row (action and step counter)
    var top_row = HBoxContainer.new()
    top_row.name = "TopRow"
    main_container.add_child(top_row)
    
    # Create action label
    action_label = Label.new()
    action_label.name = "ActionLabel"
    action_label.text = "Idle"
    action_label.add_theme_color_override("font_color", text_color)
    action_label.add_theme_constant_override("outline_size", 1)
    action_label.add_theme_color_override("font_outline_color", Color.BLACK)
    action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top_row.add_child(action_label)
    
    # Create step counter label
    step_counter_label = Label.new()
    step_counter_label.name = "StepCounterLabel"
    step_counter_label.text = "1/1"
    step_counter_label.add_theme_color_override("font_color", text_color)
    step_counter_label.add_theme_constant_override("outline_size", 1)
    step_counter_label.add_theme_color_override("font_outline_color", Color.BLACK)
    step_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    top_row.add_child(step_counter_label)
    
    # Create progress bar
    progress_bar = ProgressBar.new()
    progress_bar.name = "ProgressBar"
    progress_bar.custom_minimum_size = Vector2(PROGRESS_BAR_WIDTH, PROGRESS_BAR_HEIGHT)
    progress_bar.max_value = 100
    progress_bar.value = 0
    progress_bar.show_percentage = false
    
    # Style the progress bar
    var progress_style = StyleBoxFlat.new()
    progress_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
    progress_style.corner_radius_top_left = 2
    progress_style.corner_radius_top_right = 2
    progress_style.corner_radius_bottom_left = 2
    progress_style.corner_radius_bottom_right = 2
    progress_bar.add_theme_stylebox_override("background", progress_style)
    
    var fill_style = StyleBoxFlat.new()
    fill_style.bg_color = progress_color
    fill_style.corner_radius_top_left = 2
    fill_style.corner_radius_top_right = 2
    fill_style.corner_radius_bottom_left = 2
    fill_style.corner_radius_bottom_right = 2
    progress_bar.add_theme_stylebox_override("fill", fill_style)
    
    main_container.add_child(progress_bar)
    
    # Create trigger label
    trigger_label = Label.new()
    trigger_label.name = "TriggerLabel"
    trigger_label.text = ""
    trigger_label.add_theme_color_override("font_color", trigger_color)
    trigger_label.add_theme_constant_override("outline_size", 1)
    trigger_label.add_theme_color_override("font_outline_color", Color.BLACK)
    trigger_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    trigger_label.custom_minimum_size.x = PROGRESS_BAR_WIDTH
    main_container.add_child(trigger_label)

func show_plan_progress(unit: Node3D, plan_data: Dictionary, team: int = 0) -> void:
    """Show plan progress indicator for a unit"""
    
    if not unit:
        print("PlanProgressIndicator: Cannot show progress - unit is null")
        return
    
    # Store references
    target_unit = unit
    team_id = team
    current_plan_data = plan_data
    unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Find camera for screen positioning
    camera = _find_camera()
    if not camera:
        print("PlanProgressIndicator: Cannot show progress - no camera found")
        return
    
    # Update display
    _update_plan_display()
    
    # Position indicator
    _update_position()
    
    # Show with fade in
    _show_with_animation()
    
    print("PlanProgressIndicator: Showing plan progress for unit %s" % unit_id)

func update_plan_progress(plan_data: Dictionary) -> void:
    """Update the displayed plan progress"""
    
    current_plan_data = plan_data
    _update_plan_display()

func _update_plan_display() -> void:
    """Update the plan display with current data"""
    
    if current_plan_data.is_empty():
        action_label.text = "Idle"
        progress_bar.value = 0
        trigger_label.text = ""
        step_counter_label.text = "0/0"
        return
    
    # Update action label
    var current_action = current_plan_data.get("current_step_action", "")
    if current_action.is_empty():
        action_label.text = "Idle"
    else:
        action_label.text = _format_action_name(current_action)
    
    # Update progress bar
    var progress_percent = current_plan_data.get("progress_percent", 0.0)
    progress_bar.value = progress_percent
    
    # Update trigger label
    var current_trigger = current_plan_data.get("current_step_trigger", "")
    if current_trigger.is_empty():
        trigger_label.text = ""
        trigger_label.visible = false
    else:
        trigger_label.text = "Wait: " + _format_trigger_text(current_trigger)
        trigger_label.visible = true
    
    # Update step counter
    var current_step = current_plan_data.get("current_step", 0)
    var total_steps = current_plan_data.get("total_steps", 0)
    step_counter_label.text = "%d/%d" % [current_step + 1, total_steps]
    
    # Update indicator size based on content
    _resize_indicator()

func _format_action_name(action: String) -> String:
    """Format action name for display"""
    
    match action:
        "move_to":
            return "Moving"
        "attack":
            return "Attacking"
        "retreat":
            return "Retreating"
        "patrol":
            return "Patrolling"
        "use_ability":
            return "Using Ability"
        "stance":
            return "Changing Stance"
        "formation":
            return "Forming Up"
        "heal":
            return "Healing"
        "guard":
            return "Guarding"
        "follow":
            return "Following"
        _:
            return action.capitalize()

func _format_trigger_text(trigger: String) -> String:
    """Format trigger text for display"""
    
    # Replace technical terms with user-friendly ones
    var formatted = trigger
    formatted = formatted.replace("health_pct", "health")
    formatted = formatted.replace("enemy_dist", "enemy distance")
    formatted = formatted.replace("ally_dist", "ally distance")
    formatted = formatted.replace("enemy_count", "enemies")
    formatted = formatted.replace("ally_count", "allies")
    formatted = formatted.replace(" AND ", " and ")
    formatted = formatted.replace(" OR ", " or ")
    formatted = formatted.replace("<", " < ")
    formatted = formatted.replace(">", " > ")
    formatted = formatted.replace("=", " = ")
    
    return formatted

func _resize_indicator() -> void:
    """Resize indicator based on content"""
    
    var height = INDICATOR_PADDING.y * 2
    
    # Height for action label
    height += 20
    
    # Height for progress bar
    height += PROGRESS_BAR_HEIGHT + 2
    
    # Height for trigger label (if visible)
    if trigger_label.visible and not trigger_label.text.is_empty():
        height += 16
    
    # Update size
    custom_minimum_size = Vector2(PROGRESS_BAR_WIDTH + INDICATOR_PADDING.x * 2, height)
    size = custom_minimum_size

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
    
    if node.get_class() == type_name:
        result.append(node)
    
    for child in node.get_children():
        result.append_array(_find_nodes_by_type(child, type_name))
    
    return result

func _update_position() -> void:
    """Update indicator position to follow unit"""
    
    if not target_unit or not camera:
        return
    
    # Get unit's screen position
    var unit_pos_3d = target_unit.global_position + Vector3(0, 2, 0)  # Above unit
    var screen_pos = camera.unproject_position(unit_pos_3d)
    
    # Apply offset
    screen_pos += INDICATOR_OFFSET
    
    # Center horizontally
    screen_pos.x -= size.x / 2
    
    # Clamp to screen bounds
    var viewport_size = get_viewport().get_visible_rect().size
    screen_pos.x = clamp(screen_pos.x, 0, viewport_size.x - size.x)
    screen_pos.y = clamp(screen_pos.y, 0, viewport_size.y - size.y)
    
    # Set position
    position = screen_pos

func _show_with_animation() -> void:
    """Show indicator with fade-in animation"""
    
    visible = true
    _is_visible = true
    
    # Create fade-in tween
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION)
    
    # Scale animation
    modulate.a = 0.0
    scale = Vector2(0.9, 0.9)
    tween.parallel().tween_property(self, "scale", Vector2(1.0, 1.0), FADE_DURATION)
    tween.set_ease(Tween.EASE_OUT)

func hide_indicator() -> void:
    """Hide indicator with fade-out animation"""
    
    if not _is_visible:
        return
    
    _is_visible = false
    
    # Create fade-out tween
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
    tween.parallel().tween_property(self, "scale", Vector2(0.9, 0.9), FADE_DURATION)
    tween.set_ease(Tween.EASE_IN)
    
    # Hide after animation
    tween.tween_callback(func(): 
        visible = false
        target_unit = null
        camera = null
    )

func hide_immediately() -> void:
    """Hide indicator immediately without animation"""
    
    visible = false
    _is_visible = false
    target_unit = null
    camera = null

func _process(_delta: float) -> void:
    """Update indicator position every frame"""
    
    if target_unit and camera and _is_visible:
        _update_position()

func _gui_input(event: InputEvent) -> void:
    """Handle input events on the indicator"""
    
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if target_unit:
            indicator_clicked.emit(unit_id)
            print("PlanProgressIndicator: Clicked on plan indicator for unit %s" % unit_id)

func set_team_color(team: int) -> void:
    """Set the team color for the indicator"""
    
    team_id = team
    
    # Update progress bar color based on team
    if team == 1:
        progress_color = Color(0.2, 0.6, 1.0, 1.0)  # Blue
    elif team == 2:
        progress_color = Color(1.0, 0.2, 0.2, 1.0)  # Red
    else:
        progress_color = Color(0.6, 0.6, 0.6, 1.0)  # Gray
    
    # Update progress bar style
    if progress_bar:
        var fill_style = StyleBoxFlat.new()
        fill_style.bg_color = progress_color
        fill_style.corner_radius_top_left = 2
        fill_style.corner_radius_top_right = 2
        fill_style.corner_radius_bottom_left = 2
        fill_style.corner_radius_bottom_right = 2
        progress_bar.add_theme_stylebox_override("fill", fill_style)

func get_unit_id() -> String:
    """Get the unit ID this indicator belongs to"""
    return unit_id

func get_current_plan_data() -> Dictionary:
    """Get current plan data"""
    return current_plan_data.duplicate()

func is_indicator_visible() -> bool:
    """Check if indicator is currently visible"""
    return _is_visible

func get_display_height() -> float:
    """Get the height of the indicator for positioning"""
    return size.y 