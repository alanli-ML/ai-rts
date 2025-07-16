# MedicUnit.gd
class_name MedicUnit
extends AnimatedUnit

@export var heal_rate: float = 15.0 # HP per second

func _ready() -> void:
	archetype = "medic"
	super._ready()
	system_prompt = "You are a combat medic. Your primary directive is to keep your teammates alive. Stay near your squad and automatically use `heal_target` on any injured ally who is not at full health. Prioritize healing units that are under fire or have the lowest health. You should avoid direct combat and position yourself safely behind your teammates."

# --- Action Implementation ---

func heal_target(params: Dictionary):
	var target_id = params.get("target_id", "")
	if target_id.is_empty():
		print("Medic %s: No target specified for heal command." % unit_id)
		return

	var game_state = get_node("/root/DependencyContainer").get_game_state()
	if not game_state: return

	var target = game_state.units.get(target_id)
	
	# Validate target
	if not is_instance_valid(target):
		print("Medic %s: Heal target %s is not valid." % [unit_id, target_id])
		return
	if target.team_id != self.team_id:
		print("Medic %s: Cannot heal enemy target %s." % [unit_id, target_id])
		return
	if target.get_health_percentage() >= 1.0:
		print("Medic %s: Target %s is already at full health." % [unit_id, target_id])
		return

	# Set state to HEALING
	self.target_unit = target
	self.current_state = GameEnums.UnitState.HEALING
	print("%s is moving to heal target %s." % [unit_id, target_id])


func triage(_params: Dictionary):
	print("%s is performing triage on nearby allies." % unit_id)
	pass