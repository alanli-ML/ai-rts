# TankUnit.gd
class_name TankUnit
extends AnimatedUnit

# Shield properties
var shield_active: bool = false
var shield_health: float = 0.0
@export var max_shield_health: float = 100.0
@export var shield_cooldown: float = 15.0
var shield_cooldown_timer: float = 0.0
var shield_node: Node3D = null

func _ready() -> void:
	archetype = "tank"
	super._ready()
	system_prompt = "You are a heavy tank, the spearhead of our assault. Your job is to absorb damage and protect your allies. Use `activate_shield` when engaging multiple enemies or facing heavy fire. Always try to be at the front of your squad, drawing enemy fire. Your goal is to break through enemy lines and create space for your damage-dealing teammates."

func _physics_process(delta: float):
	if shield_cooldown_timer > 0:
		shield_cooldown_timer -= delta
	super._physics_process(delta)

# --- Action Implementation ---

func activate_shield(_params: Dictionary):
	if shield_cooldown_timer > 0:
		return # Ability is on cooldown
	shield_active = true
	shield_health = max_shield_health
	shield_cooldown_timer = shield_cooldown
	print("%s activated its shield." % unit_id)

func taunt_enemies(_params: Dictionary):
	print("%s is taunting nearby enemies." % unit_id)
	pass

# Override take_damage to use the shield
func take_damage(damage: float) -> void:
	if is_dead: return
	
	if shield_active:
		var damage_to_shield = min(shield_health, damage)
		shield_health -= damage_to_shield
		damage -= damage_to_shield
		if shield_health <= 0:
			shield_active = false
			print("%s's shield was broken." % unit_id)
			
	if damage > 0:
		super.take_damage(damage) # Call the original method in Unit.gd