class_name VisibilityManager
extends Node

var map_size: Vector2
var cell_size: float
var grid_width: int
var grid_height: int

var visibility_grid_team1: Array
var visibility_grid_team2: Array

func _init(p_map_size: Vector2, p_cell_size: float):
	map_size = p_map_size
	cell_size = p_cell_size
	grid_width = int(map_size.x / cell_size)
	grid_height = int(map_size.y / cell_size)
	
	_initialize_grids()

func _initialize_grids():
	visibility_grid_team1 = []
	visibility_grid_team2 = []
	for _i in range(grid_width):
		visibility_grid_team1.append(PackedInt32Array())
		visibility_grid_team2.append(PackedInt32Array())
		visibility_grid_team1.back().resize(grid_height)
		visibility_grid_team2.back().resize(grid_height)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	# Assuming map is centered at origin
	var grid_x = int((world_pos.x + map_size.x / 2.0) / cell_size)
	var grid_y = int((world_pos.z + map_size.y / 2.0) / cell_size)
	return Vector2i(grid_x, grid_y)

func update_visibility(all_units: Dictionary, all_control_points: Array):
	# Reset grids
	for x in range(grid_width):
		for y in range(grid_height):
			visibility_grid_team1[x][y] = 0
			visibility_grid_team2[x][y] = 0

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
	if not grid: return

	var vision_range_sq = vision_range * vision_range
	var grid_pos = world_to_grid(position)
	var grid_radius = int(vision_range / cell_size) + 1

	var min_x = max(0, grid_pos.x - grid_radius)
	var max_x = min(grid_width - 1, grid_pos.x + grid_radius)
	var min_y = max(0, grid_pos.y - grid_radius)
	var max_y = min(grid_height - 1, grid_pos.y + grid_radius)

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var cell_world_pos_x = (x * cell_size) - (map_size.x / 2.0) + (cell_size / 2.0)
			var cell_world_pos_z = (y * cell_size) - (map_size.y / 2.0) + (cell_size / 2.0)
			var cell_world_pos = Vector3(cell_world_pos_x, position.y, cell_world_pos_z)
			if position.distance_squared_to(cell_world_pos) <= vision_range_sq:
				grid[x][y] = 1

func is_position_visible(team_id: int, position: Vector3) -> bool:
	var grid = visibility_grid_team1 if team_id == 1 else visibility_grid_team2
	var grid_pos = world_to_grid(position)

	if grid_pos.x < 0 or grid_pos.x >= grid_width or grid_pos.y < 0 or grid_pos.y >= grid_height:
		return false # Outside map

	return grid[grid_pos.x][grid_pos.y] == 1

func get_visibility_data_for_team(team_id: int) -> Array:
	if team_id == 1:
		return visibility_grid_team1
	else:
		return visibility_grid_team2