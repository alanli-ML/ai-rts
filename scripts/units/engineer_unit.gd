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
	var building_type = params.get("building_type", "power_spire")
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

	# Spawn mine at current position
	entity_manager.spawn_mine(global_position, team_id)
	
	current_state = GameEnums.UnitState.IDLE