# UnitStatusBar.gd - Billboard status bar for units showing action queues
class_name UnitStatusBar
extends Node3D

# References
var status_quad: MeshInstance3D
var status_viewport: SubViewport
var status_label: RichTextLabel
var camera: Camera3D
var parent_unit: Unit

# Status bar settings
@export var offset_height: float = 2.5
@export var always_visible: bool = false
@export var fade_distance: float = 50.0
@export var min_alpha: float = 0.3
@export var max_alpha: float = 1.0

# AI processing state
var is_ai_processing: bool = false
var processing_animation_time: float = 0.0

# Auto-update tracking for behavior matrix changes
var last_known_action_scores: Dictionary = {}
var last_known_reactive_state: String = ""
var auto_update_timer: float = 0.0
const AUTO_UPDATE_INTERVAL: float = 0.05  # Update 20 times per second for more responsive display

# Material for the quad
var status_material: StandardMaterial3D

# Team colors for borders
var team_colors: Dictionary = {
	1: Color(0.2, 0.4, 1.0),    # Blue team
	2: Color(1.0, 0.3, 0.2),    # Red team
	3: Color(0.2, 1.0, 0.4),    # Green team
	4: Color(1.0, 0.8, 0.2)     # Yellow team
}

# Status panel reference
var status_panel: Panel

func _ready() -> void:
	# Get node references
	status_quad = $StatusQuad
	status_viewport = $StatusQuad/SubViewport
	status_panel = $StatusQuad/SubViewport/StatusPanel
	status_label = $StatusQuad/SubViewport/StatusPanel/StatusLabel
	
	# Expand viewport size to accommodate all triggers and content (larger for complete trigger display)
	if status_viewport:
		status_viewport.size = Vector2i(800, 600)  # Increased to fit all triggers
	
	# Expand panel size to match viewport
	if status_panel:
		status_panel.custom_minimum_size = Vector2(800, 600)
		status_panel.size = Vector2(800, 600)
		# Set panel anchors to fill the viewport
		status_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Expand and configure the status label to use full area
	if status_label:
		status_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		status_label.custom_minimum_size = Vector2(780, 580)  # Leave some margin
		status_label.size = Vector2(780, 580)
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP  # Align content to top
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Enable text wrapping
	
	# Expand status quad size to match the larger viewport
	if status_quad:
		status_quad.scale = Vector3(8.0, 6.0, 1.0)  # Scale to match the larger viewport size
	
	# Set up the material for the quad
	_setup_material()
	
	# Find the parent unit
	parent_unit = get_parent() as Unit
	
	# Set up team-colored border
	_setup_team_border()
	
	# Find the camera
	_find_camera()
	
	# Position the status bar
	position.y = offset_height
	
	# Connect to parent unit's signal for immediate behavior matrix updates if available
	call_deferred("_connect_to_parent_signals")

func _setup_material() -> void:
	"""Setup the material for the status quad"""
	status_material = StandardMaterial3D.new()
	status_material.flags_transparent = true
	status_material.flags_unshaded = true
	status_material.flags_do_not_receive_shadows = true
	status_material.albedo_texture = status_viewport.get_texture()
	status_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	status_material.no_depth_test = true
	
	status_quad.material_override = status_material

func _setup_team_border() -> void:
	"""Setup team-colored border around the status panel"""
	if not status_panel or not parent_unit:
		return
	
	# Get team color
	var team_id = parent_unit.team_id if parent_unit.team_id > 0 else 1
	var border_color = team_colors.get(team_id, Color.WHITE)
	
	# Create a StyleBoxFlat for the panel
	var style_box = StyleBoxFlat.new()
	
	# Set background color (keep original semi-transparent black)
	style_box.bg_color = Color(0, 0, 0, 0.7)
	
	# Set border properties
	style_box.border_width_left = 6
	style_box.border_width_right = 6  
	style_box.border_width_top = 6
	style_box.border_width_bottom = 6
	style_box.border_color = border_color
	
	# Set corner rounding for a polished look
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	
	# Apply the style to the panel
	status_panel.add_theme_stylebox_override("panel", style_box)

func _find_camera() -> void:
	"""Find the active camera in the scene"""
	# Look for cameras in groups first
	var camera_nodes = get_tree().get_nodes_in_group("cameras")
	if camera_nodes.size() > 0:
		camera = camera_nodes[0] as Camera3D
		return
	
	# Fallback: search for any Camera3D node
	var all_cameras = get_tree().get_nodes_in_group("rts_cameras")
	if all_cameras.size() > 0:
		camera = all_cameras[0] as Camera3D
		return
	
	# Last resort: search the whole tree
	camera = get_viewport().get_camera_3d()

func _physics_process(delta: float) -> void:
	# Update camera reference if needed
	if not is_instance_valid(camera):
		_find_camera()
	
	# Update visibility based on distance
	if camera and not always_visible:
		_update_visibility()
	
	# Update AI processing animation
	if is_ai_processing:
		processing_animation_time += delta
		_update_processing_animation()
	
	# Auto-update behavior matrix display
	auto_update_timer += delta
	if auto_update_timer >= AUTO_UPDATE_INTERVAL:
		auto_update_timer = 0.0
		_check_and_update_behavior_display()

func _update_visibility() -> void:
	"""Update visibility based on distance to camera"""
	if not camera:
		return
	
	var distance = global_position.distance_to(camera.global_position)
	var alpha = 1.0
	
	if distance > fade_distance:
		alpha = min_alpha
	else:
		# Interpolate alpha based on distance
		var fade_factor = clamp(distance / fade_distance, 0.0, 1.0)
		alpha = lerp(max_alpha, min_alpha, fade_factor)
	
	# Apply alpha to the material
	if status_material:
		var current_color = status_material.albedo_color
		current_color.a = alpha
		status_material.albedo_color = current_color

func update_status(new_status: String) -> void:
	"""Update the status text displayed on the bar"""
	if not status_label:
		return
	
	# Get unit goal if available
	var goal_text = ""
	if parent_unit and "strategic_goal" in parent_unit and not parent_unit.strategic_goal.is_empty():
		var short_goal = _shorten_goal(parent_unit.strategic_goal)
		goal_text = "[color=lightgreen][font_size=50][b]%s[/b][/font_size][/color]\n" % short_goal
	
	# Add AI processing indicator if needed
	var processing_text = ""
	if is_ai_processing:
		processing_text = "[color=yellow][font_size=52]🤖 Processing...[/font_size][/color]\n"
	
	# Add control point attack sequence display
	var control_points_text = _get_control_points_display()
	
	# Add active triggers display
	var active_triggers_text = _get_active_triggers_display()
	
	# Format the status with color coding
	var formatted_status = _format_status(new_status)
	# Use larger font sizes for better readability in expanded box
	status_label.text = "[center]%s%s%s%s[font_size=56]%s[/font_size][/center]" % [goal_text, processing_text, control_points_text, active_triggers_text, formatted_status]

func update_full_plan(plan_data: Array) -> void:
	"""Update the status bar with full action plan"""
	if not status_label:
		return
	
	if plan_data.is_empty():
		update_status("Idle")
		return
	
	# Get unit goal if available
	var goal_text = ""
	if parent_unit and "strategic_goal" in parent_unit and not parent_unit.strategic_goal.is_empty():
		var short_goal = _shorten_goal(parent_unit.strategic_goal)
		goal_text = "[color=lightgreen][font_size=50][b]%s[/b][/font_size][/color]\n" % short_goal
	
	# Add AI processing indicator if needed (above the plan)
	var processing_text = ""
	if is_ai_processing:
		processing_text = "[color=yellow][font_size=52]🤖 Processing...[/font_size][/color]\n"
	
	# Add control point attack sequence display
	var control_points_text = _get_control_points_display()
	
	# Add active triggers display
	var active_triggers_text = _get_active_triggers_display()
	
	# Build formatted plan display
	var plan_text = ""
	
	for i in range(plan_data.size()):
		var step = plan_data[i]
		var action = step.get("action", "Unknown")
		var status = step.get("status", "pending")
		var trigger = step.get("trigger", "")
		
		# Status indicator
		var status_icon = ""
		var status_color = "white"
		match status:
			"completed":
				status_icon = "✓"
				status_color = "green"
			"active":
				status_icon = "►"
				status_color = "yellow"
			"pending":
				status_icon = "○"
				status_color = "gray"
		
		# Action color
		var action_color = _get_action_color(action)
		
		# Build line
		plan_text += "[color=%s]%s[/color] [color=%s]%s[/color]" % [status_color, status_icon, action_color, action]
		
		# Add trigger info if available and step is not completed
		if not trigger.is_empty() and status != "completed":
			var short_trigger = _shorten_trigger(trigger)
			plan_text += " [color=lightgray][font_size=46](%s)[/font_size][/color]" % short_trigger
		
		# Add newline if not last item
		if i < plan_data.size() - 1:
			plan_text += "\n"
	
	# Use larger font sizes for better readability in expanded box
	status_label.text = "[center]%s%s%s%s[font_size=52]%s[/font_size][/center]" % [goal_text, processing_text, control_points_text, active_triggers_text, plan_text]

func _format_status(status: String) -> String:
	"""Format status text with appropriate colors"""
	var color = "white"
	
	# Color code based on status type
	if status.begins_with("Moving"):
		color = "cyan"
	elif status.begins_with("Attacking"):
		color = "red"
	elif status.begins_with("Healing"):
		color = "green"
	elif status.begins_with("Building"):
		color = "yellow"
	elif status.begins_with("Retreating"):
		color = "orange"
	elif status.begins_with("Patrolling"):
		color = "lightblue"
	elif status == "Idle":
		color = "gray"
	
	return "[color=%s]%s[/color]" % [color, status]

func _get_action_color(action: String) -> String:
	"""Get color for action type"""
	var action_lower = action.to_lower()
	
	if "move" in action_lower or "patrol" in action_lower:
		return "cyan"
	elif "attack" in action_lower or "charge" in action_lower:
		return "red"
	elif "heal" in action_lower:
		return "green"
	elif "construct" in action_lower or "repair" in action_lower:
		return "yellow"
	elif "retreat" in action_lower or "cover" in action_lower:
		return "orange"
	elif "stealth" in action_lower or "shield" in action_lower:
		return "purple"
	elif "follow" in action_lower:
		return "lightblue"
	else:
		return "white"

func _shorten_trigger(trigger: String) -> String:
	"""Shorten trigger text for display"""
	# Replace common trigger phrases with shorter versions
	var shortened = trigger
	shortened = shortened.replace("enemies_in_range", "enemies in range")
	shortened = shortened.replace("health_pct", "HP")
	shortened = shortened.replace("ammo_pct", "ammo")
	shortened = shortened.replace("elapsed_ms", "time")
	shortened = shortened.replace("under_fire", "taking dmg")
	shortened = shortened.replace("target_dead", "target down")
	shortened = shortened.replace("ally_health_low", "ally hurt")
	shortened = shortened.replace("nearby_enemies", "enemies near")
	shortened = shortened.replace("is_moving", "moving")
	
	# Limit length
	if shortened.length() > 20:
		shortened = shortened.substr(0, 17) + "..."
	
	return shortened

func _shorten_goal(goal: String) -> String:
	"""Shorten goal text for display above units"""
	# Remove common filler words to save space
	var shortened = goal
	shortened = shortened.replace("Act autonomously based on my unit type.", "Auto")
	shortened = shortened.replace("No specific goal assigned", "No Goal")
	
	# Replace common goal phrases with shorter versions
	shortened = shortened.replace("Capture", "Cap")
	shortened = shortened.replace("Defend", "Def")
	shortened = shortened.replace("Attack", "Att")
	shortened = shortened.replace("Patrol", "Pat")
	shortened = shortened.replace("position", "pos")
	shortened = shortened.replace("objective", "obj")
	shortened = shortened.replace("control point", "CP")
	shortened = shortened.replace("enemy", "E")
	shortened = shortened.replace("the ", "")
	shortened = shortened.replace("and ", "& ")
	
	# Limit length for status bar display
	if shortened.length() > 30:
		shortened = shortened.substr(0, 27) + "..."
	
	return shortened

func set_height_offset(new_height: float) -> void:
	"""Set the height offset for the status bar"""
	offset_height = new_height
	position.y = offset_height

func set_visibility(visible: bool) -> void:
	"""Set the visibility of the status bar"""
	self.visible = visible

func get_status_text() -> String:
	"""Get the current status text"""
	if status_label:
		return status_label.get_parsed_text()
	return ""

func set_ai_processing(processing: bool) -> void:
	"""Set AI processing status and start/stop animation"""
	is_ai_processing = processing
	if processing:
		processing_animation_time = 0.0
	else:
		# Refresh display when processing ends
		call_deferred("_refresh_current_display")

func force_refresh() -> void:
	"""Manually force a refresh of the status bar display"""
	if parent_unit:
		# Force update of behavior matrix tracking variables to trigger refresh
		last_known_action_scores.clear()
		last_known_reactive_state = ""
		
		if not parent_unit.full_plan.is_empty():
			update_full_plan(parent_unit.full_plan)
		else:
			update_status(parent_unit.plan_summary)

func _update_processing_animation() -> void:
	"""Update the processing animation visual effects"""
	if not status_label:
		return
	
	# Create a pulsing effect for the processing indicator
	var pulse = abs(sin(processing_animation_time * 3.0))  # 3 Hz pulsing
	var processing_alpha = 0.5 + (pulse * 0.5)  # Pulse between 0.5 and 1.0
	
	# Apply processing effect to the material
	if status_material:
		var base_color = status_material.albedo_color
		base_color.a = processing_alpha
		status_material.albedo_color = base_color

func _refresh_current_display() -> void:
	"""Refresh the current display after processing ends"""
	if parent_unit:
		if not parent_unit.full_plan.is_empty():
			update_full_plan(parent_unit.full_plan)
		else:
			update_status(parent_unit.plan_summary)

func _check_and_update_behavior_display() -> void:
	"""Check if behavior matrix data has changed and update display if needed"""
	if not parent_unit or not status_label:
		return
	
	# Get current behavior matrix data
	var current_action_scores = {}
	var current_reactive_state = ""
	
	if "last_action_scores" in parent_unit and parent_unit.last_action_scores != null:
		current_action_scores = parent_unit.last_action_scores
	
	if "current_reactive_state" in parent_unit:
		current_reactive_state = parent_unit.current_reactive_state
	
	# Check if data has changed
	var scores_changed = not _dictionaries_equal(current_action_scores, last_known_action_scores)
	var state_changed = current_reactive_state != last_known_reactive_state
	
	if scores_changed or state_changed:
		# Update our tracking
		last_known_action_scores = current_action_scores.duplicate()
		last_known_reactive_state = current_reactive_state
		
		# Refresh the display
		if not parent_unit.full_plan.is_empty():
			update_full_plan(parent_unit.full_plan)
		else:
			update_status(parent_unit.plan_summary)

func _dictionaries_equal(dict1: Dictionary, dict2: Dictionary) -> bool:
	"""Compare two dictionaries for equality (including nested values)"""
	if dict1.is_empty() and dict2.is_empty():
		return true
	if dict1.size() != dict2.size():
		return false
	
	for key in dict1:
		if not dict2.has(key):
			return false
		# Use small epsilon for float comparison
		var val1 = dict1[key]
		var val2 = dict2[key]
		if typeof(val1) == TYPE_FLOAT and typeof(val2) == TYPE_FLOAT:
			if abs(val1 - val2) > 0.001:  # Small epsilon for float comparison
				return false
		elif val1 != val2:
			return false
	
	return true

func update_team_border(team_id: int) -> void:
	"""Update the border color for a different team (if needed)"""
	if not status_panel:
		return
	
	var border_color = team_colors.get(team_id, Color.WHITE)
	var current_style = status_panel.get_theme_stylebox("panel")
	
	if current_style is StyleBoxFlat:
		current_style.border_color = border_color

func _connect_to_parent_signals() -> void:
	"""Connect to parent unit signals for immediate updates"""
	if not parent_unit:
		return
	
	# If the parent unit has a behavior matrix update signal, connect to it
	# For now, we'll rely on the timer-based approach and client sync
	# This method is here for future extensibility if we add dedicated signals

# Called when parent unit's plan_summary changes
func _on_plan_summary_changed(new_summary: String) -> void:
	update_status(new_summary)

func _get_active_triggers_display() -> String:
	"""Get formatted display text for behavior matrix activations and current state"""
	if not parent_unit:
		return ""
	
	# Get behavior matrix activation scores from the unit
	var action_scores = {}
	var current_state = ""
	
	if "last_action_scores" in parent_unit and parent_unit.last_action_scores != null:
		action_scores = parent_unit.last_action_scores
	
	if "current_reactive_state" in parent_unit:
		current_state = parent_unit.current_reactive_state
	
	if action_scores.is_empty():
		return ""
	
	# Get ActionValidator constants for categorization
	var validator_script = preload("res://scripts/ai/action_validator.gd")
	var validator = validator_script.new()
	
	# Filter actions to only include those valid for this unit's archetype
	var unit_archetype = parent_unit.archetype if "archetype" in parent_unit else "general"
	var valid_actions = validator.get_valid_actions_for_archetype(unit_archetype)
	
	var exclusive_actions = []
	for action in validator.MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS:
		if action in valid_actions:
			exclusive_actions.append(action)
	
	var independent_actions = []
	for action in validator.INDEPENDENT_REACTIVE_ACTIONS:
		if action in valid_actions:
			independent_actions.append(action)
	
	var display_lines = []
	
	# Show current reactive state first
	if not current_state.is_empty():
		var state_color = _get_action_color(current_state)
		var line = "[color=%s]★ Current State: %s[/color]" % [state_color, current_state.capitalize()]
		display_lines.append(line)
		display_lines.append("") # Empty line for spacing
	
	# Show mutually exclusive actions (sorted by activation level)
	var exclusive_scores = []
	for action in exclusive_actions:
		if action in action_scores:
			exclusive_scores.append({"action": action, "score": action_scores[action]})
	
	exclusive_scores.sort_custom(func(a, b): return a.score > b.score)
	
	if not exclusive_scores.is_empty():
		display_lines.append("[color=white][b]Primary States:[/b][/color]")
		for item in exclusive_scores:
			var action = item.action
			var score = item.score
			var is_current = (action == current_state)
			var activation_bar = _create_activation_bar(score)
			var action_color = _get_action_color(action)
			var state_indicator = "►" if is_current else "○"
			
			var line = "[color=%s]%s %s[/color] %s [color=gray]%.2f[/color]" % [
				action_color, state_indicator, action.capitalize(), activation_bar, score
			]
			display_lines.append(line)
	
	# Show independent actions that are above threshold
	var independent_threshold = 0.6  # Match the threshold from unit.gd
	var active_independent = []
	
	for action in independent_actions:
		if action in action_scores and action_scores[action] > independent_threshold:
			active_independent.append({"action": action, "score": action_scores[action]})
	
	if not active_independent.is_empty():
		active_independent.sort_custom(func(a, b): return a.score > b.score)
		display_lines.append("") # Empty line for spacing
		display_lines.append("[color=yellow][b]Active Abilities:[/b][/color]")
		
		for item in active_independent:
			var action = item.action
			var score = item.score
			var activation_bar = _create_activation_bar(score)
			var action_color = _get_action_color(action)
			
			var line = "[color=%s]⚡ %s[/color] %s [color=gray]%.2f[/color]" % [
				action_color, action.replace("_", " ").capitalize(), activation_bar, score
			]
			display_lines.append(line)
	
	if display_lines.is_empty():
		return "[color=gray]No active behaviors[/color]\n"
	
	return "[font_size=44]%s[/font_size]\n" % "\n".join(display_lines)

func _create_activation_bar(score: float) -> String:
	"""Create a visual bar representing activation level"""
	var bar_length = 8
	var filled_length = int(clamp(abs(score) * bar_length, 0, bar_length))
	var empty_length = bar_length - filled_length
	
	var color = "green" if score > 0 else "red"
	var filled_bar = "█".repeat(filled_length)
	var empty_bar = "░".repeat(empty_length)
	
	return "[color=%s]%s[/color][color=gray]%s[/color]" % [color, filled_bar, empty_bar]

func _format_trigger_name(trigger_name: String) -> String:
	"""Convert action name to user-friendly display format (updated for behavior matrix)"""
	# Convert underscores to spaces and capitalize
	var display_name = trigger_name.replace("_", " ").capitalize()
	
	# Specific action name improvements
	match trigger_name:
		"activate_stealth": return "Stealth Mode"
		"activate_shield": return "Shield Up"
		"taunt_enemies": return "Taunt"
		"charge_shot": return "Charge Shot"
		"heal_ally": return "Heal Ally"
		"lay_mines": return "Deploy Mines"
		"find_cover": return "Take Cover"
		_: return display_name

func _get_trigger_color(trigger_name: String) -> String:
	"""Get color for action type highlighting (updated for behavior matrix actions)"""
	return _get_action_color(trigger_name)

func _get_control_points_display() -> String:
	"""Get formatted display text for control point attack sequence"""
	if not parent_unit:
		return ""
	
	# Get control point attack sequence from the unit
	var attack_sequence = []
	if "control_point_attack_sequence" in parent_unit and parent_unit.control_point_attack_sequence is Array:
		attack_sequence = parent_unit.control_point_attack_sequence
	
	if attack_sequence.is_empty():
		return ""
	
	# Get current index to highlight next target
	var current_index = 0
	if "current_attack_sequence_index" in parent_unit:
		current_index = parent_unit.current_attack_sequence_index
	
	var display_lines = []
	display_lines.append("[color=cyan][b]Target Nodes:[/b][/color]")
	
	for i in range(attack_sequence.size()):
		var node_name = attack_sequence[i]
		var is_current = (i == current_index)
		var is_completed = (i < current_index)
		
		var icon = ""
		var color = "white"
		
		if is_completed:
			icon = "✓"
			color = "green"
		elif is_current:
			icon = "►"
			color = "yellow"
		else:
			icon = "○"
			color = "lightgray"
		
		var line = "[color=%s]%s %s[/color]" % [color, icon, node_name]
		display_lines.append(line)
	
	return "[font_size=46]%s[/font_size]\n" % "\n".join(display_lines) 