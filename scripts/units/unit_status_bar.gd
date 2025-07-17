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

# Material for the quad
var status_material: StandardMaterial3D

func _ready() -> void:
	# Get node references
	status_quad = $StatusQuad
	status_viewport = $StatusQuad/SubViewport
	status_label = $StatusQuad/SubViewport/StatusPanel/StatusLabel
	
	# Set up the material for the quad
	_setup_material()
	
	# Find the parent unit
	parent_unit = get_parent() as Unit
	
	# Find the camera
	_find_camera()
	
	# Position the status bar
	position.y = offset_height

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
		goal_text = "[color=lightgreen][font_size=40][b]%s[/b][/font_size][/color]\n" % short_goal
	
	# Add AI processing indicator if needed
	var processing_text = ""
	if is_ai_processing:
		processing_text = "[color=yellow][font_size=44]🤖 Processing...[/font_size][/color]\n"
	
	# Format the status with color coding
	var formatted_status = _format_status(new_status)
	status_label.text = "[center]%s%s[font_size=48]%s[/font_size][/center]" % [goal_text, processing_text, formatted_status]

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
		goal_text = "[color=lightgreen][font_size=40][b]%s[/b][/font_size][/color]\n" % short_goal
	
	# Add AI processing indicator if needed (above the plan)
	var processing_text = ""
	if is_ai_processing:
		processing_text = "[color=yellow][font_size=44]🤖 Processing...[/font_size][/color]\n"
	
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
			plan_text += " [color=lightgray][font_size=40](%s)[/font_size][/color]" % short_trigger
		
		# Add newline if not last item
		if i < plan_data.size() - 1:
			plan_text += "\n"
	
	status_label.text = "[center]%s%s[font_size=44]%s[/font_size][/center]" % [goal_text, processing_text, plan_text]

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

# Called when parent unit's plan_summary changes
func _on_plan_summary_changed(new_summary: String) -> void:
	update_status(new_summary) 