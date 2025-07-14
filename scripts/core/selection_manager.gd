# SelectionManager.gd
class_name SelectionManager
extends Node

# Selection visual settings
@export var selection_box_color: Color = Color(0.2, 0.8, 0.2, 0.3)
@export var selection_box_border_color: Color = Color(0.2, 1.0, 0.2, 0.8)
@export var selection_box_border_width: float = 2.0

# Selection behavior settings
@export var min_drag_distance: float = 5.0
@export var double_click_time: float = 0.3

# Internal variables
var selected_units: Array[Node] = []
var is_box_selecting: bool = false
var box_start_position: Vector2 = Vector2.ZERO
var box_end_position: Vector2 = Vector2.ZERO
var last_click_time: float = 0.0
var last_clicked_unit: Node = null

# UI elements
var selection_box_drawer: SelectionBoxDrawer = null
var camera: Camera3D = null

# Signals
signal units_selected(units: Array)
signal units_deselected(units: Array)
signal unit_double_clicked(unit: Node)

# Custom drawing class for selection box
class SelectionBoxDrawer extends Control:
    var parent_manager: SelectionManager
    
    func _draw() -> void:
        if not parent_manager or not parent_manager.is_box_selecting:
            return
        
        var rect = Rect2()
        rect.position = Vector2(
            min(parent_manager.box_start_position.x, parent_manager.box_end_position.x),
            min(parent_manager.box_start_position.y, parent_manager.box_end_position.y)
        )
        rect.size = Vector2(
            abs(parent_manager.box_end_position.x - parent_manager.box_start_position.x),
            abs(parent_manager.box_end_position.y - parent_manager.box_start_position.y)
        )
        
        # Draw filled rectangle
        draw_rect(rect, parent_manager.selection_box_color)
        
        # Draw border
        draw_rect(rect, parent_manager.selection_box_border_color, false, parent_manager.selection_box_border_width)

func _ready() -> void:
    # Create selection box UI element
    selection_box_drawer = SelectionBoxDrawer.new()
    selection_box_drawer.parent_manager = self
    selection_box_drawer.name = "SelectionBox"
    selection_box_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    selection_box_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    selection_box_drawer.visible = false
    
    # Add to viewport
    var canvas_layer = CanvasLayer.new()
    canvas_layer.name = "SelectionUI"
    add_child(canvas_layer)
    canvas_layer.add_child(selection_box_drawer)
    
    # Connect to EventBus signals
    EventBus.unit_spawned.connect(_on_unit_spawned)
    EventBus.unit_died.connect(_on_unit_died)
    
    Logger.info("SelectionManager", "Selection Manager initialized")

func _input(event: InputEvent) -> void:
    if not camera:
        _find_camera()
    
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _on_left_click_pressed(event.position)
            else:
                _on_left_click_released(event.position)
        elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            _on_right_click(event.position)
    
    elif event is InputEventMouseMotion and is_box_selecting:
        box_end_position = event.position
        _update_selection_box()

func _find_camera() -> void:
    # Try to find the camera in the scene
    var cameras = get_tree().get_nodes_in_group("cameras")
    if cameras.size() > 0:
        var cam_node = cameras[0]
        if cam_node is Camera3D:
            camera = cam_node
        elif cam_node.has_node("Camera3D"):
            camera = cam_node.get_node("Camera3D")
    else:
        # Look for RTSCamera or Camera3D in the current scene
        var viewport = get_viewport()
        camera = viewport.get_camera_3d()

func _on_left_click_pressed(position: Vector2) -> void:
    box_start_position = position
    box_end_position = position
    is_box_selecting = true
    
    # Check for double-click
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_click_time < double_click_time:
        var unit = _get_unit_at_position(position)
        if unit and unit == last_clicked_unit:
            unit_double_clicked.emit(unit)
            _select_all_units_of_type(unit)
            is_box_selecting = false
            return
    
    last_click_time = current_time

func _on_left_click_released(position: Vector2) -> void:
    if not is_box_selecting:
        return
    
    is_box_selecting = false
    selection_box_drawer.visible = false
    
    var drag_distance = box_start_position.distance_to(position)
    
    if drag_distance < min_drag_distance:
        # Single click selection
        _handle_single_selection(position)
    else:
        # Box selection
        _handle_box_selection()

func _on_right_click(position: Vector2) -> void:
    if selected_units.is_empty():
        return
    
    # Issue move command to selected units
    var world_position = _get_world_position_from_screen(position)
    if world_position:
        for unit in selected_units:
            EventBus.emit_unit_command(unit.name, "move_to:%s,%s" % [world_position.x, world_position.z])

func _handle_single_selection(position: Vector2) -> void:
    var unit = _get_unit_at_position(position)
    
    if Input.is_action_pressed("shift"):
        # Add to selection
        if unit and unit not in selected_units:
            _add_to_selection([unit])
    elif Input.is_action_pressed("ctrl"):
        # Toggle selection
        if unit:
            if unit in selected_units:
                _remove_from_selection([unit])
            else:
                _add_to_selection([unit])
    else:
        # Replace selection
        _clear_selection()
        if unit:
            _add_to_selection([unit])
            last_clicked_unit = unit

func _handle_box_selection() -> void:
    var units_in_box = _get_units_in_box(box_start_position, box_end_position)
    
    if Input.is_action_pressed("shift"):
        # Add to selection
        _add_to_selection(units_in_box)
    elif Input.is_action_pressed("ctrl"):
        # Toggle selection
        var to_add = []
        var to_remove = []
        for unit in units_in_box:
            if unit in selected_units:
                to_remove.append(unit)
            else:
                to_add.append(unit)
        _remove_from_selection(to_remove)
        _add_to_selection(to_add)
    else:
        # Replace selection
        _clear_selection()
        _add_to_selection(units_in_box)

func _get_unit_at_position(screen_position: Vector2) -> Node:
    if not camera:
        return null
    
    var from = camera.project_ray_origin(screen_position)
    var to = from + camera.project_ray_normal(screen_position) * 1000
    
    var space_state = camera.get_world_3d().direct_space_state
    var query = PhysicsRayQueryParameters3D.create(from, to)
    query.collide_with_areas = true
    
    var result = space_state.intersect_ray(query)
    if result:
        var collider = result.collider
        # Check if it's a unit (you'll need to tag units appropriately)
        if collider.is_in_group("units"):
            return collider
    
    return null

func _get_units_in_box(start: Vector2, end: Vector2) -> Array[Node]:
    var units = []
    var all_units = get_tree().get_nodes_in_group("units")
    
    if not camera:
        return units
    
    # Create rectangle from start and end positions
    var rect = Rect2()
    rect.position = Vector2(min(start.x, end.x), min(start.y, end.y))
    rect.size = Vector2(abs(end.x - start.x), abs(end.y - start.y))
    
    for unit in all_units:
        if unit is Node3D:
            var screen_pos = camera.unproject_position(unit.global_position)
            if rect.has_point(screen_pos):
                units.append(unit)
    
    return units

func _get_world_position_from_screen(screen_position: Vector2) -> Vector3:
    if not camera:
        return Vector3.ZERO
    
    var from = camera.project_ray_origin(screen_position)
    var to = from + camera.project_ray_normal(screen_position) * 1000
    
    # Raycast to ground plane (y = 0)
    var space_state = camera.get_world_3d().direct_space_state
    var query = PhysicsRayQueryParameters3D.create(from, to)
    
    var result = space_state.intersect_ray(query)
    if result:
        return result.position
    
    # If no collision, calculate intersection with y=0 plane
    var normal = Vector3.UP
    var plane_point = Vector3.ZERO
    var ray_direction = (to - from).normalized()
    
    var denominator = normal.dot(ray_direction)
    if abs(denominator) > 0.0001:
        var t = (plane_point - from).dot(normal) / denominator
        if t >= 0:
            return from + ray_direction * t
    
    return Vector3.ZERO

func _select_all_units_of_type(unit: Node) -> void:
    # Select all units of the same type/archetype
    var all_units = get_tree().get_nodes_in_group("units")
    var same_type_units = []
    
    # You'll need to implement a way to check unit type
    # For now, we'll just select all units
    for u in all_units:
        if u.get("archetype") == unit.get("archetype"):
            same_type_units.append(u)
    
    _clear_selection()
    _add_to_selection(same_type_units)

func _add_to_selection(units: Array) -> void:
    for unit in units:
        if unit not in selected_units:
            selected_units.append(unit)
            _set_unit_selected(unit, true)
            EventBus.unit_selected.emit(unit)
    
    if units.size() > 0:
        units_selected.emit(selected_units)

func _remove_from_selection(units: Array) -> void:
    for unit in units:
        if unit in selected_units:
            selected_units.erase(unit)
            _set_unit_selected(unit, false)
            EventBus.unit_deselected.emit(unit)
    
    if units.size() > 0:
        units_deselected.emit(units)

func _clear_selection() -> void:
    var previous_selection = selected_units.duplicate()
    
    for unit in selected_units:
        _set_unit_selected(unit, false)
        EventBus.unit_deselected.emit(unit)
    
    selected_units.clear()
    
    if previous_selection.size() > 0:
        units_deselected.emit(previous_selection)

func _set_unit_selected(unit: Node, selected: bool) -> void:
    # This will be implemented when we have units
    # For now, just log
    if unit.has_method("set_selected"):
        unit.set_selected(selected)

func _update_selection_box() -> void:
    if not is_box_selecting:
        return
    
    selection_box_drawer.visible = true
    selection_box_drawer.queue_redraw()

func _on_unit_spawned(unit: Variant) -> void:
    # Add unit to appropriate groups for selection
    if unit is Node:
        unit.add_to_group("units")

func _on_unit_died(unit: Variant) -> void:
    # Remove from selection if selected
    if unit in selected_units:
        _remove_from_selection([unit])

func get_selected_units() -> Array[Node]:
    return selected_units

func has_selection() -> bool:
    return selected_units.size() > 0 