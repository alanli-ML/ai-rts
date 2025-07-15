# EnhancedSelectionSystem.gd
class_name EnhancedSelectionSystem
extends Node

# Enhanced selection settings
@export var selection_layers: int = 0b1  # Layer mask for selectable objects
@export var selection_precision: float = 0.1  # Precision for selection
@export var multi_select_threshold: float = 3.0  # Minimum drag distance for box selection
@export var double_click_timeout: float = 0.3  # Double-click detection time
@export var selection_feedback_enabled: bool = true
@export var tooltip_enabled: bool = true
@export var keyboard_selection_enabled: bool = true

# Visual feedback settings
@export var selection_ring_color: Color = Color(0.2, 1.0, 0.2, 0.8)
@export var selection_ring_width: float = 0.1
@export var selection_box_color: Color = Color(0.2, 0.8, 0.2, 0.3)
@export var selection_box_border_color: Color = Color(0.2, 1.0, 0.2, 0.8)
@export var health_bar_enabled: bool = true
@export var unit_info_panel_enabled: bool = true

# Selection state
var selected_units: Array[Unit] = []
var hovered_unit: Unit = null
var selection_groups: Dictionary = {}  # Group number -> Array[Unit]
var last_click_time: float = 0.0
var last_clicked_unit: Unit = null

# Box selection
var is_box_selecting: bool = false
var box_start_position: Vector2 = Vector2.ZERO
var box_end_position: Vector2 = Vector2.ZERO
var box_selection_active: bool = false

# Visual components
var selection_box_drawer: SelectionBoxDrawer
var selection_indicators: Dictionary = {}  # unit_id -> SelectionIndicator
var health_bars: Dictionary = {}  # unit_id -> HealthBar
var unit_tooltips: Dictionary = {}  # unit_id -> Tooltip

# System references
var camera: Camera3D
var formation_system: FormationSystem
var pathfinding_system: PathfindingSystem
var canvas_layer: CanvasLayer
var ui_container: Control

# Performance optimization
var selection_update_interval: float = 0.1
var last_selection_update: float = 0.0
var selection_raycast_pool: Array[RayCast3D] = []
var max_selection_raycasts: int = 10

# Signals
signal units_selected(units: Array[Unit])
signal units_deselected(units: Array[Unit])
signal unit_hovered(unit: Unit)
signal unit_unhovered(unit: Unit)
signal selection_changed(selected_units: Array[Unit])
signal selection_group_created(group_number: int, units: Array[Unit])
signal selection_group_recalled(group_number: int, units: Array[Unit])

# Selection indicator component
class SelectionIndicator extends Node3D:
	var ring_mesh: MeshInstance3D
	var arrow_mesh: MeshInstance3D
	var unit_reference: Unit
	var animation_tween: Tween
	
	func _init(unit: Unit):
		unit_reference = unit
		_create_visuals()
	
	func _create_visuals():
		# Create selection ring
		ring_mesh = MeshInstance3D.new()
		ring_mesh.name = "SelectionRing"
		ring_mesh.mesh = TorusMesh.new()
		ring_mesh.mesh.inner_radius = 0.8
		ring_mesh.mesh.outer_radius = 1.0
		ring_mesh.position = Vector3(0, 0.1, 0)
		
		var ring_material = StandardMaterial3D.new()
		ring_material.albedo_color = Color(0.2, 1.0, 0.2, 0.8)
		ring_material.flags_transparent = true
		ring_material.emission_enabled = true
		ring_material.emission = Color(0.2, 1.0, 0.2) * 0.5
		ring_mesh.material_override = ring_material
		
		add_child(ring_mesh)
		
		# Create directional arrow
		arrow_mesh = MeshInstance3D.new()
		arrow_mesh.name = "DirectionArrow"
		arrow_mesh.mesh = BoxMesh.new()
		arrow_mesh.mesh.size = Vector3(0.2, 0.1, 0.8)
		arrow_mesh.position = Vector3(0, 1.5, 0)
		arrow_mesh.visible = false
		
		var arrow_material = StandardMaterial3D.new()
		arrow_material.albedo_color = Color.YELLOW
		arrow_material.emission_enabled = true
		arrow_material.emission = Color.YELLOW * 0.3
		arrow_mesh.material_override = arrow_material
		
		add_child(arrow_mesh)
		
		# Start animation
		_animate_selection()
	
	func _animate_selection():
		animation_tween = create_tween()
		animation_tween.set_loops()
		animation_tween.tween_property(ring_mesh, "scale", Vector3(1.2, 1.0, 1.2), 0.5)
		animation_tween.tween_property(ring_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.5)
	
	func show_direction_arrow(direction: Vector3):
		if arrow_mesh:
			arrow_mesh.visible = true
			arrow_mesh.look_at(global_position + direction, Vector3.UP)
	
	func hide_direction_arrow():
		if arrow_mesh:
			arrow_mesh.visible = false
	
	func update_position():
		if unit_reference and is_instance_valid(unit_reference):
			global_position = unit_reference.global_position

# Health bar component
class HealthBar extends Control:
	var background_rect: ColorRect
	var health_rect: ColorRect
	var shield_rect: ColorRect
	var unit_reference: Unit
	var camera_reference: Camera3D
	
	func _init(unit: Unit, camera: Camera3D):
		unit_reference = unit
		camera_reference = camera
		_create_visuals()
	
	func _create_visuals():
		set_custom_minimum_size(Vector2(60, 8))
		
		# Background
		background_rect = ColorRect.new()
		background_rect.color = Color(0.2, 0.2, 0.2, 0.8)
		background_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(background_rect)
		
		# Health bar
		health_rect = ColorRect.new()
		health_rect.color = Color(0.8, 0.2, 0.2, 0.9)
		health_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(health_rect)
		
		# Shield bar (if unit has shields)
		shield_rect = ColorRect.new()
		shield_rect.color = Color(0.2, 0.6, 1.0, 0.7)
		shield_rect.visible = false
		add_child(shield_rect)
	
	func update_health(health_percentage: float):
		if health_rect:
			health_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			health_rect.size.x = size.x * health_percentage
	
	func update_shield(shield_percentage: float):
		if shield_rect:
			shield_rect.visible = shield_percentage > 0
			shield_rect.size.x = size.x * shield_percentage
	
	func update_position():
		if unit_reference and is_instance_valid(unit_reference) and camera_reference:
			var screen_pos = camera_reference.unproject_position(unit_reference.global_position + Vector3(0, 3, 0))
			position = screen_pos - size / 2

# Selection box drawer
class SelectionBoxDrawer extends Control:
	var parent_system: EnhancedSelectionSystem
	
	func _init(system: EnhancedSelectionSystem):
		parent_system = system
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	func _draw():
		if not parent_system or not parent_system.is_box_selecting:
			return
		
		var start_pos = parent_system.box_start_position
		var end_pos = parent_system.box_end_position
		
		var rect = Rect2()
		rect.position = Vector2(
			min(start_pos.x, end_pos.x),
			min(start_pos.y, end_pos.y)
		)
		rect.size = Vector2(
			abs(end_pos.x - start_pos.x),
			abs(end_pos.y - start_pos.y)
		)
		
		# Draw selection box
		draw_rect(rect, parent_system.selection_box_color)
		draw_rect(rect, parent_system.selection_box_border_color, false, 2.0)
		
		# Draw corner indicators
		_draw_corner_indicators(rect)
	
	func _draw_corner_indicators(rect: Rect2):
		var corner_size = 8.0
		var corners = [
			rect.position,
			rect.position + Vector2(rect.size.x, 0),
			rect.position + rect.size,
			rect.position + Vector2(0, rect.size.y)
		]
		
		for corner in corners:
			draw_rect(Rect2(corner - Vector2(corner_size/2, corner_size/2), 
				Vector2(corner_size, corner_size)), Color.WHITE)

# Unit tooltip component
class UnitTooltip extends PanelContainer:
	var unit_reference: Unit
	var info_label: RichTextLabel
	var abilities_label: Label
	
	func _init(unit: Unit):
		unit_reference = unit
		_create_visuals()
	
	func _create_visuals():
		# Main container
		var vbox = VBoxContainer.new()
		add_child(vbox)
		
		# Unit info
		info_label = RichTextLabel.new()
		info_label.bbcode_enabled = true
		info_label.custom_minimum_size = Vector2(200, 60)
		info_label.scroll_active = false
		vbox.add_child(info_label)
		
		# Abilities
		abilities_label = Label.new()
		abilities_label.text = "Abilities:"
		abilities_label.add_theme_font_size_override("font_size", 12)
		vbox.add_child(abilities_label)
		
		# Style
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = Color(0.1, 0.1, 0.1, 0.9)
		style_box.corner_radius_top_left = 4
		style_box.corner_radius_top_right = 4
		style_box.corner_radius_bottom_left = 4
		style_box.corner_radius_bottom_right = 4
		add_theme_stylebox_override("panel", style_box)
	
	func update_info():
		if not unit_reference or not is_instance_valid(unit_reference):
			return
		
		var health_pct = unit_reference.get_health_percentage()
		var health_color = Color.GREEN if health_pct > 0.6 else (Color.YELLOW if health_pct > 0.3 else Color.RED)
		
		info_label.text = "[b]%s[/b] (Team %d)\n[color=#%s]Health: %.0f%%[/color]\nState: %s" % [
			unit_reference.archetype.capitalize(),
			unit_reference.team_id,
			health_color.to_html(),
			health_pct * 100,
			_get_state_string(unit_reference.current_state)
		]
		
		# Update abilities
		var abilities = unit_reference.get_available_abilities() if unit_reference.has_method("get_available_abilities") else []
		abilities_label.text = "Abilities: " + ", ".join(abilities)
	
	func _get_state_string(state) -> String:
		return "Active"  # Simplified for now

func _ready():
	# Initialize systems
	_find_system_references()
	_setup_ui_components()
	_setup_input_handling()
	_create_raycast_pool()
	
	# Connect signals
	_connect_signals()
	
	print("EnhancedSelectionSystem: Enhanced selection system initialized")

func _find_system_references():
	"""Find references to other systems"""
	# Find camera
	var cameras = get_tree().get_nodes_in_group("cameras")
	for cam in cameras:
		if cam is Camera3D:
			camera = cam
			break
		elif cam.has_method("get_camera"):
			camera = cam.get_camera()
			break
	
	# Find formation system
	var formation_systems = get_tree().get_nodes_in_group("formation_systems")
	if formation_systems.size() > 0:
		formation_system = formation_systems[0]
	
	# Find pathfinding system
	var pathfinding_systems = get_tree().get_nodes_in_group("pathfinding_systems")
	if pathfinding_systems.size() > 0:
		pathfinding_system = pathfinding_systems[0]

func _setup_ui_components():
	"""Setup UI components"""
	# Create canvas layer
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "SelectionUI"
	canvas_layer.layer = 100  # High layer for UI
	add_child(canvas_layer)
	
	# Create UI container
	ui_container = Control.new()
	ui_container.name = "SelectionUIContainer"
	ui_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(ui_container)
	
	# Create selection box drawer
	selection_box_drawer = SelectionBoxDrawer.new(self)
	selection_box_drawer.name = "SelectionBoxDrawer"
	ui_container.add_child(selection_box_drawer)

func _setup_input_handling():
	"""Setup input handling"""
	set_process_input(true)
	set_process_unhandled_input(true)

func _create_raycast_pool():
	"""Create pool of raycasts for performance"""
	for i in range(max_selection_raycasts):
		var raycast = RayCast3D.new()
		raycast.enabled = false
		raycast.collision_mask = selection_layers
		add_child(raycast)
		selection_raycast_pool.append(raycast)

func _connect_signals():
	"""Connect to system signals"""
	# Connect to EventBus if available
	if EventBus:
		EventBus.unit_spawned.connect(_on_unit_spawned)
		EventBus.unit_died.connect(_on_unit_died)

func _input(event: InputEvent):
	"""Handle input events"""
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and keyboard_selection_enabled:
		_handle_keyboard_input(event)

func _handle_mouse_button(event: InputEventMouseButton):
	"""Handle mouse button events"""
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_selection(event.position)
		else:
			_finish_selection(event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_handle_right_click(event.position)

func _handle_mouse_motion(event: InputEventMouseMotion):
	"""Handle mouse motion events"""
	if is_box_selecting:
		box_end_position = event.position
		_update_box_selection()
	else:
		_update_hover(event.position)

func _handle_keyboard_input(event: InputEventKey):
	"""Handle keyboard input"""
	if event.pressed:
		# Selection groups (Ctrl+1-9 to create, 1-9 to recall)
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var group_num = event.keycode - KEY_1 + 1
			if Input.is_action_pressed("ctrl"):
				_create_selection_group(group_num)
			else:
				_recall_selection_group(group_num)
		
		# Select all units of same type
		elif event.keycode == KEY_A and Input.is_action_pressed("ctrl"):
			_select_all_units_of_type()
		
		# Deselect all
		elif event.keycode == KEY_ESCAPE:
			clear_selection()

func _start_selection(position: Vector2):
	"""Start selection process"""
	box_start_position = position
	box_end_position = position
	
	# Check for double-click
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_click_time < double_click_timeout:
		var unit = _get_unit_at_position(position)
		if unit and unit == last_clicked_unit:
			_handle_double_click(unit)
			return
	
	last_click_time = current_time
	is_box_selecting = true

func _finish_selection(position: Vector2):
	"""Finish selection process"""
	if not is_box_selecting:
		return
	
	is_box_selecting = false
	selection_box_drawer.queue_redraw()
	
	var drag_distance = box_start_position.distance_to(position)
	
	if drag_distance < multi_select_threshold:
		_handle_click_selection(position)
	else:
		_handle_box_selection()

func _handle_click_selection(position: Vector2):
	"""Handle single click selection"""
	var unit = _get_unit_at_position(position)
	last_clicked_unit = unit
	
	if Input.is_action_pressed("shift"):
		# Add to selection
		if unit and unit not in selected_units:
			add_to_selection([unit])
	elif Input.is_action_pressed("ctrl"):
		# Toggle selection
		if unit:
			if unit in selected_units:
				remove_from_selection([unit])
			else:
				add_to_selection([unit])
	else:
		# Replace selection
		if unit:
			select_units([unit])
		else:
			clear_selection()

func _handle_box_selection():
	"""Handle box selection"""
	var units_in_box = _get_units_in_box()
	
	if Input.is_action_pressed("shift"):
		add_to_selection(units_in_box)
	elif Input.is_action_pressed("ctrl"):
		# Toggle each unit
		for unit in units_in_box:
			if unit in selected_units:
				remove_from_selection([unit])
			else:
				add_to_selection([unit])
	else:
		select_units(units_in_box)

func _handle_double_click(unit: Unit):
	"""Handle double-click selection"""
	if unit:
		_select_all_units_of_type(unit.archetype)

func _handle_right_click(position: Vector2):
	"""Handle right-click commands"""
	if selected_units.is_empty():
		return
	
	var world_pos = _screen_to_world(position)
	if world_pos == Vector3.ZERO:
		return
	
	# Check if clicking on enemy unit
	var target_unit = _get_unit_at_position(position)
	if target_unit and target_unit.team_id != selected_units[0].team_id:
		# Attack command
		_issue_attack_command(target_unit)
	else:
		# Move command
		_issue_move_command(world_pos)

func _get_unit_at_position(screen_pos: Vector2) -> Unit:
	"""Get unit at screen position using enhanced raycast"""
	if not camera:
		return null
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000
	
	# Use multiple raycasts for better precision
	var raycast_results = []
	var offsets = [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	
	for i in range(min(offsets.size(), selection_raycast_pool.size())):
		var offset_pos = screen_pos + offsets[i] * selection_precision
		var raycast = selection_raycast_pool[i]
		
		raycast.global_position = camera.project_ray_origin(offset_pos)
		raycast.target_position = raycast.global_position + camera.project_ray_normal(offset_pos) * 1000
		raycast.enabled = true
		raycast.force_raycast_update()
		
		if raycast.is_colliding():
			var collider = raycast.get_collider()
			if collider and collider.is_in_group("units"):
				raycast_results.append(collider)
		
		raycast.enabled = false
	
	# Return closest unit
	if raycast_results.size() > 0:
		var closest_unit = raycast_results[0]
		var closest_distance = camera.global_position.distance_to(closest_unit.global_position)
		
		for unit in raycast_results:
			var distance = camera.global_position.distance_to(unit.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_unit = unit
		
		return closest_unit
	
	return null

func _get_units_in_box() -> Array[Unit]:
	"""Get units within selection box"""
	var units = []
	
	if not camera:
		return units
	
	var selection_rect = Rect2()
	selection_rect.position = Vector2(
		min(box_start_position.x, box_end_position.x),
		min(box_start_position.y, box_end_position.y)
	)
	selection_rect.size = Vector2(
		abs(box_end_position.x - box_start_position.x),
		abs(box_end_position.y - box_start_position.y)
	)
	
	# Get all units in scene
	var all_units = get_tree().get_nodes_in_group("units")
	
	for unit in all_units:
		if unit is Unit and not unit.is_dead:
			var screen_pos = camera.unproject_position(unit.global_position)
			if selection_rect.has_point(screen_pos):
				units.append(unit)
	
	return units

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	"""Convert screen position to world position"""
	if not camera:
		return Vector3.ZERO
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000
	
	# Intersect with ground plane
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b10  # Ground layer
	
	var result = space_state.intersect_ray(query)
	if result:
		return result.position
	
	# Fallback to y=0 plane intersection
	var direction = (to - from).normalized()
	var t = -from.y / direction.y
	if t > 0:
		return from + direction * t
	
	return Vector3.ZERO

func _update_hover(position: Vector2):
	"""Update hover state"""
	var unit = _get_unit_at_position(position)
	
	if unit != hovered_unit:
		if hovered_unit:
			_hide_unit_tooltip(hovered_unit)
			unit_unhovered.emit(hovered_unit)
		
		hovered_unit = unit
		
		if hovered_unit:
			_show_unit_tooltip(hovered_unit, position)
			unit_hovered.emit(hovered_unit)

func _update_box_selection():
	"""Update box selection visual"""
	if selection_box_drawer:
		selection_box_drawer.queue_redraw()

func select_units(units: Array[Unit]):
	"""Select units (replace current selection)"""
	clear_selection()
	add_to_selection(units)

func add_to_selection(units: Array[Unit]):
	"""Add units to selection"""
	var newly_selected = []
	
	for unit in units:
		if unit and unit is Unit and not unit.is_dead and unit not in selected_units:
			selected_units.append(unit)
			newly_selected.append(unit)
			
			# Create visual feedback
			_create_selection_indicator(unit)
			_create_health_bar(unit)
			
			# Notify unit
			if unit.has_method("select"):
				unit.select()
	
	if newly_selected.size() > 0:
		units_selected.emit(newly_selected)
		selection_changed.emit(selected_units)
		_update_selection_ui()

func remove_from_selection(units: Array[Unit]):
	"""Remove units from selection"""
	var removed_units = []
	
	for unit in units:
		if unit in selected_units:
			selected_units.erase(unit)
			removed_units.append(unit)
			
			# Remove visual feedback
			_remove_selection_indicator(unit)
			_remove_health_bar(unit)
			
			# Notify unit
			if unit.has_method("deselect"):
				unit.deselect()
	
	if removed_units.size() > 0:
		units_deselected.emit(removed_units)
		selection_changed.emit(selected_units)
		_update_selection_ui()

func clear_selection():
	"""Clear all selection"""
	if selected_units.is_empty():
		return
	
	var cleared_units = selected_units.duplicate()
	
	for unit in selected_units:
		_remove_selection_indicator(unit)
		_remove_health_bar(unit)
		
		if unit.has_method("deselect"):
			unit.deselect()
	
	selected_units.clear()
	
	units_deselected.emit(cleared_units)
	selection_changed.emit(selected_units)
	_update_selection_ui()

func _create_selection_indicator(unit: Unit):
	"""Create visual selection indicator for unit"""
	if unit.unit_id in selection_indicators:
		return
	
	var indicator = SelectionIndicator.new(unit)
	indicator.name = "SelectionIndicator_" + unit.unit_id
	unit.add_child(indicator)
	selection_indicators[unit.unit_id] = indicator

func _remove_selection_indicator(unit: Unit):
	"""Remove selection indicator from unit"""
	if unit.unit_id in selection_indicators:
		var indicator = selection_indicators[unit.unit_id]
		if indicator and is_instance_valid(indicator):
			indicator.queue_free()
		selection_indicators.erase(unit.unit_id)

func _create_health_bar(unit: Unit):
	"""Create health bar for unit"""
	if not health_bar_enabled or not camera:
		return
	
	if unit.unit_id in health_bars:
		return
	
	var health_bar = HealthBar.new(unit, camera)
	health_bar.name = "HealthBar_" + unit.unit_id
	ui_container.add_child(health_bar)
	health_bars[unit.unit_id] = health_bar

func _remove_health_bar(unit: Unit):
	"""Remove health bar from unit"""
	if unit.unit_id in health_bars:
		var health_bar = health_bars[unit.unit_id]
		if health_bar and is_instance_valid(health_bar):
			health_bar.queue_free()
		health_bars.erase(unit.unit_id)

func _show_unit_tooltip(unit: Unit, position: Vector2):
	"""Show tooltip for unit"""
	if not tooltip_enabled:
		return
	
	if unit.unit_id in unit_tooltips:
		return
	
	var tooltip = UnitTooltip.new(unit)
	tooltip.name = "Tooltip_" + unit.unit_id
	tooltip.position = position + Vector2(10, 10)
	ui_container.add_child(tooltip)
	unit_tooltips[unit.unit_id] = tooltip
	
	tooltip.update_info()

func _hide_unit_tooltip(unit: Unit):
	"""Hide tooltip for unit"""
	if unit.unit_id in unit_tooltips:
		var tooltip = unit_tooltips[unit.unit_id]
		if tooltip and is_instance_valid(tooltip):
			tooltip.queue_free()
		unit_tooltips.erase(unit.unit_id)

func _update_selection_ui():
	"""Update selection-related UI"""
	# Update health bars
	for unit_id in health_bars:
		var health_bar = health_bars[unit_id]
		if health_bar and is_instance_valid(health_bar):
			health_bar.update_position()
			var unit = _get_unit_by_id(unit_id)
			if unit:
				health_bar.update_health(unit.get_health_percentage())

func _select_all_units_of_type(archetype: String = ""):
	"""Select all units of specific type"""
	var type_to_select = archetype
	if type_to_select == "" and not selected_units.is_empty():
		type_to_select = selected_units[0].archetype
	
	if type_to_select == "":
		return
	
	var units_of_type = []
	var all_units = get_tree().get_nodes_in_group("units")
	
	for unit in all_units:
		if unit is Unit and not unit.is_dead:
			if unit.archetype == type_to_select and unit.team_id == selected_units[0].team_id:
				units_of_type.append(unit)
	
	select_units(units_of_type)

func _create_selection_group(group_number: int):
	"""Create selection group"""
	if selected_units.is_empty():
		return
	
	selection_groups[group_number] = selected_units.duplicate()
	selection_group_created.emit(group_number, selected_units)
	
	print("Selection group %d created with %d units" % [group_number, selected_units.size()])

func _recall_selection_group(group_number: int):
	"""Recall selection group"""
	if group_number not in selection_groups:
		return
	
	var group_units = selection_groups[group_number]
	var valid_units = []
	
	# Filter out dead units
	for unit in group_units:
		if unit and is_instance_valid(unit) and not unit.is_dead:
			valid_units.append(unit)
	
	if valid_units.size() > 0:
		select_units(valid_units)
		selection_group_recalled.emit(group_number, valid_units)
		print("Selection group %d recalled with %d units" % [group_number, valid_units.size()])

func _issue_move_command(world_pos: Vector3):
	"""Issue move command to selected units"""
	if selected_units.is_empty():
		return
	
	# If we have formation system, move as formation
	if formation_system and selected_units.size() > 1:
		# Create temporary formation or move existing formation
		var formation = formation_system.get_unit_formation(selected_units[0])
		if formation:
			formation_system.move_formation(formation.formation_id, world_pos)
		else:
			# Create temporary formation
			var formation_id = formation_system.create_formation(
				formation_system.FormationType.LINE,
				selected_units[0],
				selected_units.slice(1)
			)
			if formation_id:
				formation_system.move_formation(formation_id, world_pos)
	else:
		# Individual unit movement
		for unit in selected_units:
			if unit.has_method("move_to"):
				unit.move_to(world_pos)
			elif pathfinding_system:
				pathfinding_system.request_path(unit.unit_id, unit.global_position, world_pos)

func _issue_attack_command(target_unit: Unit):
	"""Issue attack command to selected units"""
	if selected_units.is_empty():
		return
	
	for unit in selected_units:
		if unit.has_method("attack_target"):
			unit.attack_target(target_unit)

func _get_unit_by_id(unit_id: String) -> Unit:
	"""Get unit by ID"""
	var all_units = get_tree().get_nodes_in_group("units")
	for unit in all_units:
		if unit is Unit and unit.unit_id == unit_id:
			return unit
	return null

func _on_unit_spawned(unit: Unit):
	"""Handle unit spawned event"""
	if unit and unit.is_in_group("units"):
		# Unit is already in group, nothing to do
		pass

func _on_unit_died(unit: Unit):
	"""Handle unit death event"""
	if unit in selected_units:
		remove_from_selection([unit])
	
	# Remove from selection groups
	for group_num in selection_groups:
		var group = selection_groups[group_num]
		if unit in group:
			group.erase(unit)

func _process(delta: float):
	"""Process selection system"""
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Update selection UI periodically
	if current_time - last_selection_update >= selection_update_interval:
		_update_selection_ui()
		last_selection_update = current_time
	
	# Update selection indicators
	for unit_id in selection_indicators:
		var indicator = selection_indicators[unit_id]
		if indicator and is_instance_valid(indicator):
			indicator.update_position()

# Public API
func get_selected_units() -> Array[Unit]:
	"""Get currently selected units"""
	return selected_units.duplicate()

func has_selection() -> bool:
	"""Check if any units are selected"""
	return selected_units.size() > 0

func get_selection_count() -> int:
	"""Get number of selected units"""
	return selected_units.size()

func get_selection_groups() -> Dictionary:
	"""Get all selection groups"""
	return selection_groups.duplicate()

func set_selection_enabled(enabled: bool):
	"""Enable/disable selection system"""
	set_process_input(enabled)
	set_process_unhandled_input(enabled)

func get_selection_statistics() -> Dictionary:
	"""Get selection system statistics"""
	return {
		"selected_units": selected_units.size(),
		"selection_groups": selection_groups.size(),
		"active_indicators": selection_indicators.size(),
		"active_health_bars": health_bars.size(),
		"hovered_unit": hovered_unit != null
	} 