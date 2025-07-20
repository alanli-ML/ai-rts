class_name VisibilityManager
extends Node

var map_size: Vector2
var cell_size: float
var grid_width: int
var grid_height: int
var map_origin: Vector2

var visibility_grid_team1: PackedByteArray
var visibility_grid_team2: PackedByteArray

func _init():
	pass

func setup(p_map_size: Vector2, p_cell_size: float):
	map_size = p_map_size
	cell_size = p_cell_size
	grid_width = int(map_size.x / cell_size)
	grid_height = int(map_size.y / cell_size)
	map_origin = -map_size / 2.0
	
	_initialize_grids()

func _initialize_grids():
	var grid_size = grid_width * grid_height
	visibility_grid_team1 = PackedByteArray()
	visibility_grid_team1.resize(grid_size)
	visibility_grid_team2 = PackedByteArray()
	visibility_grid_team2.resize(grid_size)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var grid_x = int((world_pos.x - map_origin.x) / cell_size)
	var grid_y = int((world_pos.z - map_origin.y) / cell_size)
	return Vector2i(grid_x, grid_y)

func update_visibility(all_units: Dictionary, all_control_points: Array):
	# Reset grids to 0 (fogged)
	visibility_grid_team1.fill(0)
	visibility_grid_team2.fill(0)

	# Process units
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if is_instance_valid(unit) and not unit.is_dead:
			_add_vision_source(unit.team_id, unit.global_position, unit.vision_range)

	# Process control points
	for cp in all_control_points:
		if is_instance_valid(cp) and cp.get_controlling_team() != 0:
			_add_vision_source(cp.get_controlling_team(), cp.global_position, cp.vision_range)

func _add_vision_source(team_id: int, position: Vector3, vision_range: float):
	var grid = visibility_grid_team1 if team_id == 1 else visibility_grid_team2
	if grid.is_empty(): return

	var vision_range_sq = vision_range * vision_range
	var grid_pos = world_to_grid(position)
	var grid_radius = int(vision_range / cell_size) + 1

	var min_x = max(0, grid_pos.x - grid_radius)
	var max_x = min(grid_width - 1, grid_pos.x + grid_radius)
	var min_y = max(0, grid_pos.y - grid_radius)
	var max_y = min(grid_height - 1, grid_pos.y + grid_radius)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell_world_pos_x = (x * cell_size) + map_origin.x + (cell_size / 2.0)
			var cell_world_pos_z = (y * cell_size) + map_origin.y + (cell_size / 2.0)
			var cell_world_pos = Vector3(cell_world_pos_x, position.y, cell_world_pos_z)
			if position.distance_squared_to(cell_world_pos) <= vision_range_sq:
				var index = y * grid_width + x
				if index >= 0 and index < grid.size():
					grid[index] = 255 # Visible

func is_position_visible(team_id: int, position: Vector3) -> bool:
	var grid = visibility_grid_team1 if team_id == 1 else visibility_grid_team2
	var grid_pos = world_to_grid(position)

	if grid_pos.x < 0 or grid_pos.x >= grid_width or grid_pos.y < 0 or grid_pos.y >= grid_height:
		return false # Outside map

	var index = grid_pos.y * grid_width + grid_pos.x
	if index < 0 or index >= grid.size():
		return false

	return grid[index] == 255

func get_visibility_grid_data(team_id: int) -> PackedByteArray:
	if team_id == 1:
		return visibility_grid_team1
	else:
		return visibility_grid_team2

func get_grid_metadata() -> Dictionary:
	return {
		"width": grid_width,
		"height": grid_height,
		"cell_size": cell_size,
		"origin": map_origin
	}