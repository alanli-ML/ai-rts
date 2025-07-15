# scripts/ai/action_trigger.gd
class_name ActionTrigger
extends Resource

## The conditions that must all be met for this trigger to fire.
@export var conditions: Array[TriggerCondition] = []
## The action to execute when the conditions are met.
@export var action: UnitAction
## The priority of this trigger. Higher priority triggers are evaluated first.
@export var priority: int = 1
## The cooldown in seconds after this trigger fires before it can fire again.
@export var cooldown: float = 2.0

## Internal state, not meant to be set from the editor.
var last_triggered_time: float = 0.0

func _init(p_conditions: Array[TriggerCondition] = [], p_action: UnitAction = null, p_priority: int = 1, p_cooldown: float = 2.0):
    conditions = p_conditions
    action = p_action
    priority = p_priority
    cooldown = p_cooldown

func can_trigger() -> bool:
    return Time.get_ticks_msec() / 1000.0 > last_triggered_time + cooldown

func evaluate(unit: Node) -> bool:
    if not can_trigger():
        return false
    
    for condition in conditions:
        if not condition.evaluate(unit):
            return false # All conditions must be met (AND logic)
    
    return true

func triggered() -> void:
    last_triggered_time = Time.get_ticks_msec() / 1000.0