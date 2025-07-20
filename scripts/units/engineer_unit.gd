# EngineerUnit.gd
class_name EngineerUnit
extends AnimatedUnit

@export var build_rate: float = 0.2 # 20% progress per second
@export var mine_laying_time: float = 3.0 # seconds to lay one mine
@export var mine_cooldown: float = 5.0 # seconds
@export var turret_construction_cooldown: float = 15.0 # seconds between turret constructions

var mine_cooldown_timer: float = 0.0
var turret_construction_timer: float = 0.0
var is_constructing_turret: bool = false  # Flag to prevent multiple simultaneous constructions

func _ready() -> void:
	archetype = "engineer"
	super._ready()
	system_prompt = "You are a combat engineer. Your main role is to build and maintain our infrastructure. Prioritize capturing neutral or enemy-controlled control points, as they are essential for victory. Use your combat abilities to support allies in capturing points. Once a point is secured, use `construct` to build structures. Your secondary role is to use `repair` on damaged buildings or allied units. When not building or repairing, you can use `lay_mines` to create defensive minefields at strategic chokepoints or to protect friendly control points."

func _physics_process(delta: float):
	super._physics_process(delta)
	if mine_cooldown_timer > 0:
		mine_cooldown_timer -= delta
	if turret_construction_timer > 0:
		turret_construction_timer -= delta

# --- Action Implementation ---

func construct(params: Dictionary):
	# Construct always builds a power_spire (single building type)
	var building_type = "power_spire"
	var position_array = params.get("position")
	if not position_array is Array or position_array.size() != 3:
		print("Engineer %s: Invalid position for construct command." % unit_id)
		return

	var position = Vector3(position_array[0], position_array[1], position_array[2])
	
	var entity_manager = get_node("/root/DependencyContainer").get_entity_manager()
	if not entity_manager:
		print("Engineer %s: EntityManager not found." % unit_id)
		return
		
	# Use EntityManager's spire creation system
	var tile_pos = Vector2i(int(position.x), int(position.z))
	var spire_id = entity_manager.create_spire(tile_pos, building_type, team_id)
	
	if not spire_id.is_empty():
		# Get the spire entity to use as target_building
		var spire = entity_manager.get_spire(spire_id)
		if is_instance_valid(spire):
			self.target_building = spire
			self.current_state = GameEnums.UnitState.CONSTRUCTING
			
			# Trigger construction animation using existing AnimatedUnit system
			play_animation("Construct")
			
			print("%s is moving to construct a %s (%s)." % [unit_id, building_type, spire_id])
		else:
			print("%s: Failed to get spire reference after creation." % unit_id)
	else:
		print("%s failed to start construction (placement validation failed)." % unit_id)

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
		
		# Trigger construction animation for repair work using existing AnimatedUnit system
		play_animation("Construct")
		
		print("%s is moving to repair building %s." % [unit_id, target_id])
	else:
		print("%s could not find building %s to repair." % [unit_id, target_id])

func lay_mines(_params: Dictionary):
	if mine_cooldown_timer > 0:
		print("Engineer %s: Mine laying is on cooldown (%.1fs remaining)." % [unit_id, mine_cooldown_timer])
		return
	
	# Check if already busy with another action
	if current_state in [GameEnums.UnitState.CONSTRUCTING, GameEnums.UnitState.LAYING_MINES, GameEnums.UnitState.REPAIRING]:
		print("Engineer %s: Currently busy, cannot lay mine" % unit_id)
		return
	
	# Check entity limits before starting using EntityManager
	var entity_manager = get_node_or_null("/root/DependencyContainer").get_entity_manager()
	if entity_manager and entity_manager.has_method("get_team_mine_count"):
		var current_mines = entity_manager.get_team_mine_count(team_id)
		var max_mines = entity_manager.get_mine_limit()
		if current_mines >= max_mines:
			print("Engineer %s: Team mine limit reached (%d/%d)" % [unit_id, current_mines, max_mines])
			return

	print("%s is laying a mine." % unit_id)
	current_state = GameEnums.UnitState.LAYING_MINES
	mine_cooldown_timer = mine_cooldown + mine_laying_time
	
	# Trigger construction animation for mine laying using existing AnimatedUnit system
	play_animation("Construct")
	
	await get_tree().create_timer(mine_laying_time).timeout
	
	if not is_instance_valid(self) or current_state != GameEnums.UnitState.LAYING_MINES:
		# Engineer was interrupted (e.g., moved or killed)
		return
		
	if not entity_manager:
		print("Engineer %s: EntityManager not found." % unit_id)
		current_state = GameEnums.UnitState.IDLE
		return

	# Check if still in tree first
	if not is_inside_tree():
		print("Engineer %s: No longer in scene tree, cannot lay mine." % unit_id)
		current_state = GameEnums.UnitState.IDLE
		return
		
	# Convert world position to tile position for EntityManager
	var tile_pos = Vector2i(int(global_position.x), int(global_position.z))
	var mine_id = entity_manager.deploy_mine(tile_pos, "standard", team_id, unit_id)
	
	if mine_id.is_empty():
		print("Engineer %s: Failed to deploy mine (placement validation failed)." % unit_id)
	else:
		print("Engineer %s: Successfully deployed mine %s." % [unit_id, mine_id])
	
	# Finish construction animation and return to idle
	play_animation("Idle")
	
	current_state = GameEnums.UnitState.IDLE

func construct_turret(_params: Dictionary):
	GameConstants.debug_print("Engineer %s - construct_turret called (is_constructing_turret: %s, current_state: %s)" % [unit_id, is_constructing_turret, current_state], "UNITS")
	
	# Check if already constructing something
	if current_state == GameEnums.UnitState.CONSTRUCTING:
		print("Engineer %s: Already constructing something, cannot build turret" % unit_id)
		return
	
	# Check if already constructing a turret (prevents race conditions)
	if is_constructing_turret:
		print("Engineer %s: Already constructing a turret, ignoring duplicate request" % unit_id)
		return
	
	# Check turret construction cooldown
	if turret_construction_timer > 0:
		print("Engineer %s: Turret construction on cooldown (%.1fs remaining)" % [unit_id, turret_construction_timer])
		return
	
	# Simple turret limit check by counting existing turret units
	var game_state = get_node_or_null("/root/DependencyContainer/GameState")
	print("DEBUG: Engineer %s - GameState found: %s" % [unit_id, game_state != null])
	
	# Turret limit management - remove oldest if at limit
	if game_state and game_state.has_method("get_units_by_archetype"):
		var existing_turrets = game_state.get_units_by_archetype("turret", team_id)
		var max_turrets = 5  # Team limit
		print("DEBUG: Engineer %s - Current turrets: %d/%d" % [unit_id, existing_turrets.size(), max_turrets])
		
		if existing_turrets.size() >= max_turrets:
			print("Engineer %s: Team turret limit reached (%d/%d), removing oldest turret" % [unit_id, existing_turrets.size(), max_turrets])
			
			# Find the oldest turret (use unit_id as age indicator - earlier IDs are older)
			var oldest_turret = null
			
			for turret in existing_turrets:
				if is_instance_valid(turret) and not turret.is_dead:
					if oldest_turret == null or turret.unit_id < oldest_turret.unit_id:
						oldest_turret = turret
			
			if oldest_turret != null:
				print("Engineer %s: Removing oldest turret %s to make room for new one" % [unit_id, oldest_turret.unit_id])
				oldest_turret.die()  # This will trigger cleanup via _on_unit_died
				strategic_goal = "Replacing oldest turret..."
			else:
				print("Engineer %s: Could not find valid turret to remove" % unit_id)
				return

	print("DEBUG: Engineer %s - Starting turret construction process" % unit_id)
	print("%s is starting to construct a turret." % unit_id)
	
	# Set turret construction flags but DON'T use CONSTRUCTING state (that's for buildings)
	is_constructing_turret = true
	can_move = false
	
	# Update strategic goal for UI display
	strategic_goal = "Constructing turret..."
	
	# Refresh status bar to show new goal
	if has_method("refresh_status_bar"):
		refresh_status_bar()
	
	# Trigger construction animation using existing AnimatedUnit system
	play_animation("Construct")
	print("DEBUG: Engineer %s - Construction animation started" % unit_id)
	print("DEBUG: Engineer %s - is_constructing_turret: %s, can_move: %s" % [unit_id, is_constructing_turret, can_move])
	
	# Get construction time from turret config
	var turret_config = GameConstants.get_unit_config("turret")
	var construction_time = turret_config.get("build_time", 5.0)
	print("DEBUG: Engineer %s - Construction time: %.1f seconds" % [unit_id, construction_time])

	await get_tree().create_timer(construction_time).timeout
	print("DEBUG: Engineer %s - Construction timer completed" % unit_id)

	# Check if construction was interrupted
	if not is_instance_valid(self) or not is_constructing_turret:
		print("DEBUG: Engineer %s - Construction interrupted (valid: %s, constructing: %s)" % [unit_id, is_instance_valid(self), is_constructing_turret])
		is_constructing_turret = false
		can_move = true
		strategic_goal = "Construction interrupted"
		return

	if not game_state:
		print("Engineer %s: GameState not found." % unit_id)
		is_constructing_turret = false
		can_move = true
		strategic_goal = "Construction failed - no game state"
		return

	# Spawn turret in front of the engineer
	var spawn_pos = global_position + transform.basis.z * -3.0 # 3 units in front
	print("DEBUG: Engineer %s - Attempting to spawn turret at position: %s" % [unit_id, spawn_pos])
	
	var turret_unit_id = await game_state.spawn_unit("turret", team_id, spawn_pos, unit_id)
	print("DEBUG: Engineer %s - spawn_unit returned: '%s'" % [unit_id, turret_unit_id])

	if not turret_unit_id.is_empty():
		print("%s finished constructing turret %s." % [unit_id, turret_unit_id])
		strategic_goal = "Turret construction complete"
		# Set cooldown on successful construction
		turret_construction_timer = turret_construction_cooldown
	else:
		print("Engineer %s: FAILED to construct turret - spawn_unit returned empty string" % unit_id)
		strategic_goal = "Turret construction failed"
	
	# Refresh status bar to show completion status
	if has_method("refresh_status_bar"):
		refresh_status_bar()
	
	# Finish construction animation and return to idle
	play_animation("Idle")
		
	# Reset construction state
	is_constructing_turret = false
	can_move = true
	print("DEBUG: Engineer %s - Construction process completed" % unit_id)