# CommandTranslator.gd
class_name CommandTranslator
extends Node

# Dependencies
var selection_manager: SelectionManager = null
var game_manager: GameManager = null

# Command execution settings
@export var max_waypoints: int = 5
@export var formation_spacing: float = 3.0
@export var group_move_delay: float = 0.1

# Internal variables
var unit_formations: Dictionary = {}
var active_commands: Array[Dictionary] = []
var command_id_counter: int = 0

# Formation definitions
var formations: Dictionary = {
	"line": {"type": "line", "spacing": formation_spacing},
	"column": {"type": "column", "spacing": formation_spacing},
	"wedge": {"type": "wedge", "spacing": formation_spacing},
	"scattered": {"type": "scattered", "spacing": formation_spacing * 2}
}

# Signals
signal command_executed(command_id: int, result: String)
signal command_failed(command_id: int, error: String)
signal units_not_found(target_units: Array)

func _ready() -> void:
	# Get references to managers
	selection_manager = _find_selection_manager()
	game_manager = GameManager
	
	Logger.info("CommandTranslator", "Command translator initialized")

func _find_selection_manager() -> SelectionManager:
	"""Find the selection manager in the scene"""
	var selection_managers = get_tree().get_nodes_in_group("selection_managers")
	if not selection_managers.is_empty():
		return selection_managers[0]
	
	# Fallback: search by class name
	var nodes = get_tree().get_nodes_in_group("selection_manager")
	for node in nodes:
		if node is SelectionManager:
			return node
	
	Logger.warning("CommandTranslator", "Selection manager not found")
	return null

func execute_commands(commands: Array) -> void:
	"""
	Execute a list of AI commands
	
	Args:
		commands: Array of command dictionaries from AICommandProcessor
	"""
	for command in commands:
		execute_command(command)

func execute_command(command: Dictionary) -> int:
	"""
	Execute a single AI command
	
	Args:
		command: Command dictionary with action, target_units, and parameters
	
	Returns:
		Command ID for tracking
	"""
	var command_id = command_id_counter
	command_id_counter += 1
	
	# Store active command
	active_commands.append({
		"id": command_id,
		"command": command,
		"timestamp": Time.get_ticks_msec() / 1000.0
	})
	
	# Get target units
	var target_units = _resolve_target_units(command.target_units)
	
	if target_units.is_empty():
		Logger.warning("CommandTranslator", "No target units found for command: " + str(command.action))
		units_not_found.emit(command.target_units)
		command_failed.emit(command_id, "No target units found")
		return command_id
	
	# Execute based on action type
	var result = ""
	match command.action:
		"MOVE":
			result = _execute_move(target_units, command.parameters)
		"ATTACK":
			result = _execute_attack(target_units, command.parameters)
		"FOLLOW":
			result = _execute_follow(target_units, command.parameters)
		"PATROL":
			result = _execute_patrol(target_units, command.parameters)
		"STOP":
			result = _execute_stop(target_units, command.parameters)
		"USE_ABILITY":
			result = _execute_ability(target_units, command.parameters)
		"FORMATION":
			result = _execute_formation(target_units, command.parameters)
		"STANCE":
			result = _execute_stance(target_units, command.parameters)
		_:
			result = "Unknown command: " + str(command.action)
			command_failed.emit(command_id, result)
			return command_id
	
	Logger.info("CommandTranslator", "Command executed: " + str(command.action) + " - " + result)
	command_executed.emit(command_id, result)
	
	return command_id

func _resolve_target_units(target_specs: Array) -> Array:
	"""Resolve target unit specifications to actual unit nodes"""
	var units = []
	
	for spec in target_specs:
		match spec:
			"selected":
				if selection_manager:
					units.append_array(selection_manager.selected_units)
			"all":
				var all_units = get_tree().get_nodes_in_group("units")
				units.append_array(all_units)
			_:
				if spec.begins_with("type:"):
					var unit_type = spec.substr(5)
					var typed_units = _get_units_by_type(unit_type)
					units.append_array(typed_units)
				else:
					# Assume it's a unit ID
					var unit = _get_unit_by_id(spec)
					if unit:
						units.append(unit)
	
	# Remove duplicates
	var unique_units = []
	for unit in units:
		if unit not in unique_units:
			unique_units.append(unit)
	
	return unique_units

func _get_units_by_type(unit_type: String) -> Array:
	"""Get units of a specific type"""
	var units = []
	var all_units = get_tree().get_nodes_in_group("units")
	
	for unit in all_units:
		if unit.has_method("get_archetype") and unit.get_archetype() == unit_type:
			units.append(unit)
		elif unit.has_property("archetype") and unit.archetype == unit_type:
			units.append(unit)
	
	return units

func _get_unit_by_id(unit_id: String) -> Node:
	"""Get a unit by its ID"""
	var all_units = get_tree().get_nodes_in_group("units")
	
	for unit in all_units:
		if unit.has_method("get_unit_id") and unit.get_unit_id() == unit_id:
			return unit
		elif unit.has_property("unit_id") and unit.unit_id == unit_id:
			return unit
	
	return null

func _execute_move(units: Array, parameters: Dictionary) -> String:
	"""Execute move command"""
	if not parameters.has("position"):
		return "Move command missing position parameter"
	
	var position = parameters.position
	var target_pos = Vector3(position[0], position[1], position[2])
	
	# Apply formation if units are in formation
	if units.size() > 1:
		var positions = _calculate_formation_positions(units, target_pos, "line")
		for i in range(units.size()):
			if i < positions.size():
				_move_unit(units[i], positions[i])
			else:
				_move_unit(units[i], target_pos)
	else:
		_move_unit(units[0], target_pos)
	
	return "Moving " + str(units.size()) + " units to position " + str(target_pos)

func _execute_attack(units: Array, parameters: Dictionary) -> String:
	"""Execute attack command"""
	if not parameters.has("target_id"):
		return "Attack command missing target_id parameter"
	
	var target = _get_unit_by_id(parameters.target_id)
	if not target:
		return "Attack target not found: " + parameters.target_id
	
	for unit in units:
		if unit.has_method("attack_target"):
			unit.attack_target(target)
		elif unit.has_method("set_target"):
			unit.set_target(target)
	
	return "Attacking target " + parameters.target_id + " with " + str(units.size()) + " units"

func _execute_follow(units: Array, parameters: Dictionary) -> String:
	"""Execute follow command"""
	if not parameters.has("target_id"):
		return "Follow command missing target_id parameter"
	
	var target = _get_unit_by_id(parameters.target_id)
	if not target:
		return "Follow target not found: " + parameters.target_id
	
	for unit in units:
		if unit.has_method("follow_unit"):
			unit.follow_unit(target)
		elif unit.has_method("set_follow_target"):
			unit.set_follow_target(target)
	
	return "Following target " + parameters.target_id + " with " + str(units.size()) + " units"

func _execute_patrol(units: Array, parameters: Dictionary) -> String:
	"""Execute patrol command"""
	if not parameters.has("waypoints"):
		return "Patrol command missing waypoints parameter"
	
	var waypoints = parameters.waypoints
	if waypoints.size() < 2:
		return "Patrol requires at least 2 waypoints"
	
	if waypoints.size() > max_waypoints:
		waypoints = waypoints.slice(0, max_waypoints)
	
	var patrol_points = []
	for waypoint in waypoints:
		patrol_points.append(Vector3(waypoint[0], waypoint[1], waypoint[2]))
	
	for unit in units:
		if unit.has_method("start_patrol"):
			unit.start_patrol(patrol_points)
		elif unit.has_method("set_patrol_points"):
			unit.set_patrol_points(patrol_points)
	
	return "Starting patrol with " + str(units.size()) + " units and " + str(patrol_points.size()) + " waypoints"

func _execute_stop(units: Array, parameters: Dictionary) -> String:
	"""Execute stop command"""
	for unit in units:
		if unit.has_method("stop"):
			unit.stop()
		elif unit.has_method("halt"):
			unit.halt()
		elif unit.has_method("set_state"):
			unit.set_state("idle")
	
	return "Stopping " + str(units.size()) + " units"

func _execute_ability(units: Array, parameters: Dictionary) -> String:
	"""Execute ability command"""
	if not parameters.has("ability_name"):
		return "Ability command missing ability_name parameter"
	
	var ability_name = parameters.ability_name
	var success_count = 0
	
	for unit in units:
		if unit.has_method("use_ability"):
			if unit.use_ability(ability_name):
				success_count += 1
		elif unit.has_method("activate_ability"):
			if unit.activate_ability(ability_name):
				success_count += 1
	
	return "Used ability '" + ability_name + "' on " + str(success_count) + "/" + str(units.size()) + " units"

func _execute_formation(units: Array, parameters: Dictionary) -> String:
	"""Execute formation command"""
	if not parameters.has("formation"):
		return "Formation command missing formation parameter"
	
	var formation_type = parameters.formation
	if not formation_type in formations:
		return "Unknown formation type: " + formation_type
	
	# Store formation for these units
	for unit in units:
		if unit.has_method("get_unit_id"):
			unit_formations[unit.get_unit_id()] = formation_type
		elif unit.has_property("unit_id"):
			unit_formations[unit.unit_id] = formation_type
	
	return "Set formation '" + formation_type + "' for " + str(units.size()) + " units"

func _execute_stance(units: Array, parameters: Dictionary) -> String:
	"""Execute stance command"""
	if not parameters.has("stance"):
		return "Stance command missing stance parameter"
	
	var stance = parameters.stance
	
	for unit in units:
		if unit.has_method("set_stance"):
			unit.set_stance(stance)
		elif unit.has_method("set_combat_stance"):
			unit.set_combat_stance(stance)
	
	return "Set stance to '" + stance + "' for " + str(units.size()) + " units"

func _move_unit(unit: Node, target_position: Vector3) -> void:
	"""Move a single unit to a position"""
	if unit.has_method("move_to"):
		unit.move_to(target_position)
	elif unit.has_method("set_destination"):
		unit.set_destination(target_position)
	elif unit.has_method("navigate_to"):
		unit.navigate_to(target_position)
	else:
		Logger.warning("CommandTranslator", "Unit has no move method: " + str(unit.name))

func _calculate_formation_positions(units: Array, center_position: Vector3, formation_type: String) -> Array:
	"""Calculate positions for units in formation"""
	var positions = []
	var formation_data = formations.get(formation_type, formations["line"])
	var spacing = formation_data.spacing
	
	match formation_data.type:
		"line":
			var half_width = (units.size() - 1) * spacing * 0.5
			for i in range(units.size()):
				var offset = Vector3(i * spacing - half_width, 0, 0)
				positions.append(center_position + offset)
		"column":
			var half_depth = (units.size() - 1) * spacing * 0.5
			for i in range(units.size()):
				var offset = Vector3(0, 0, i * spacing - half_depth)
				positions.append(center_position + offset)
		"wedge":
			positions.append(center_position)  # Leader at front
			for i in range(1, units.size()):
				var row = (i - 1) / 2 + 1
				var side = -1 if i % 2 == 1 else 1
				var offset = Vector3(side * spacing, 0, -row * spacing)
				positions.append(center_position + offset)
		"scattered":
			for i in range(units.size()):
				var angle = i * 2 * PI / units.size()
				var radius = spacing * sqrt(units.size())
				var offset = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
				positions.append(center_position + offset)
	
	return positions

func get_active_commands() -> Array:
	"""Get list of active commands"""
	return active_commands.duplicate()

func cancel_command(command_id: int) -> bool:
	"""Cancel an active command"""
	for i in range(active_commands.size()):
		if active_commands[i].id == command_id:
			active_commands.remove_at(i)
			Logger.info("CommandTranslator", "Command cancelled: " + str(command_id))
			return true
	return false

func clear_all_commands() -> void:
	"""Clear all active commands"""
	active_commands.clear()
	Logger.info("CommandTranslator", "All commands cleared") 