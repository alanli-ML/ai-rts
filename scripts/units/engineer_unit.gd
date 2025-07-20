# EngineerUnit.gd
class_name EngineerUnit
extends AnimatedUnit

@export var build_rate: float = 0.2 # 20% progress per second
@export var mine_laying_time: float = 3.0 # seconds to lay one mine
@export var mine_cooldown: float = 5.0 # seconds
var mine_cooldown_timer: float = 0.0

func _ready() -> void:
	archetype = "engineer"
	super._ready()
	system_prompt = "You are a combat engineer. Your main role is to build and maintain our infrastructure. Prioritize capturing neutral or enemy-controlled control points, as they are essential for victory. Use your combat abilities to support allies in capturing points. Once a point is secured, use `construct` to build structures. Your secondary role is to use `repair` on damaged buildings or allied units. When not building or repairing, you can use `lay_mines` to create defensive minefields at strategic chokepoints or to protect friendly control points."

func _physics_process(delta: float):
	super._physics_process(delta)
	if mine_cooldown_timer > 0:
		mine_cooldown_timer -= delta

# --- Action Implementation ---

func construct(params: Dictionary):
	# Construct always builds a power_spire (single building type)
	var building_type = "power_spire"
	var position_array = params.get("position")
	if not position_array is Array or position_array.size() != 3:
		print("Engineer %s: Invalid position for construct command." % unit_id)
		return

	var position = Vector3(position_array[0], position_array[1], position_array[2])
	
	var entity_manager = get_node("/root/DependencyContainer").get_placeable_entity_manager()
	if not entity_manager:
		print("Engineer %s: PlaceableEntityManager not found." % unit_id)
		return
		
	var building = entity_manager.spawn_building(building_type, position, team_id)
	if is_instance_valid(building):
		self.target_building = building
		self.current_state = GameEnums.UnitState.CONSTRUCTING
		print("%s is moving to construct a %s." % [unit_id, building_type])
	else:
		print("%s failed to start construction." % unit_id)

func repair(params: Dictionary):
	var target_id = params.get("target_id", "")
	if target_id.is_empty():
		print("Engineer %s: No target specified for repair command." % unit_id)
		return
		
	var entity_manager = get_node("/root/DependencyContainer").get_placeable_entity_manager()
	if not entity_manager:
		print("Engineer %s: PlaceableEntityManager not found." % unit_id)
		return
	
	var building = entity_manager.get_building(target_id)
	if is_instance_valid(building):
		self.target_building = building
		self.current_state = GameEnums.UnitState.REPAIRING # Assumes REPAIRING works like CONSTRUCTING
		print("%s is moving to repair building %s." % [unit_id, target_id])
	else:
		print("%s could not find building %s to repair." % [unit_id, target_id])

func lay_mines(_params: Dictionary):
	if mine_cooldown_timer > 0:
		print("Engineer %s: Mine laying is on cooldown." % unit_id)
		return

	print("%s is laying a mine." % unit_id)
	current_state = GameEnums.UnitState.LAYING_MINES
	mine_cooldown_timer = mine_cooldown + mine_laying_time
	
	await get_tree().create_timer(mine_laying_time).timeout
	
	if not is_instance_valid(self) or current_state != GameEnums.UnitState.LAYING_MINES:
		# Engineer was interrupted (e.g., moved or killed)
		return
		
	var entity_manager = get_node("/root/DependencyContainer").get_placeable_entity_manager()
	if not entity_manager:
		print("Engineer %s: PlaceableEntityManager not found." % unit_id)
		current_state = GameEnums.UnitState.IDLE
		return

	# Spawn mine at current position (check if still in tree first)
	if not is_inside_tree():
		print("Engineer %s: No longer in scene tree, cannot lay mine." % unit_id)
		current_state = GameEnums.UnitState.IDLE
		return
		
	entity_manager.spawn_mine(global_position, team_id)
	
	current_state = GameEnums.UnitState.IDLE

func construct_turret(_params: Dictionary):
	if current_state == GameEnums.UnitState.CONSTRUCTING:
		return # Already building something

	print("%s is starting to construct a turret." % unit_id)
	current_state = GameEnums.UnitState.CONSTRUCTING
	can_move = false
	
	# Get construction time from turret config
	var turret_config = GameConstants.get_unit_config("turret")
	var construction_time = turret_config.get("build_time", 15.0)

	await get_tree().create_timer(construction_time).timeout

	if not is_instance_valid(self) or current_state != GameEnums.UnitState.CONSTRUCTING:
		# Engineer was interrupted
		can_move = true
		return

	var game_state = get_node_or_null("/root/DependencyContainer/GameState")
	if not game_state:
		print("Engineer %s: GameState not found." % unit_id)
		current_state = GameEnums.UnitState.IDLE
		can_move = true
		return

	# Spawn turret in front of the engineer
	var spawn_pos = global_position + transform.basis.z * -3.0 # 3 units in front
	var turret_unit_id = await game_state.spawn_unit("turret", team_id, spawn_pos, unit_id)

	if not turret_unit_id.is_empty():
		print("%s finished constructing turret %s." % [unit_id, turret_unit_id])
	else:
		print("%s failed to construct turret." % unit_id)
		
	current_state = GameEnums.UnitState.IDLE
	can_move = true