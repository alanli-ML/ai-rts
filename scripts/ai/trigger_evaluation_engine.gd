# scripts/ai/trigger_evaluation_engine.gd
class_name TriggerEvaluationEngine
extends Node

var active_unit_triggers: Dictionary = {} # unit_id -> { "unit": Node, "triggers": Array[ActionTrigger] }
var evaluation_timer: Timer

func _ready():
    name = "TriggerEvaluationEngine"
    evaluation_timer = Timer.new()
    evaluation_timer.wait_time = 0.1 # 10Hz
    evaluation_timer.timeout.connect(_evaluate_all_triggers)
    add_child(evaluation_timer)
    evaluation_timer.start()

func register_unit(unit: Node):
    if not unit.has_method("get_unit_id"):
        return
        
    var unit_id = unit.get_unit_id()
    if not active_unit_triggers.has(unit_id):
        if unit.has_method("get_triggers"):
            var triggers = unit.get_triggers()
            if not triggers.is_empty():
                active_unit_triggers[unit_id] = {
                    "unit": unit,
                    "triggers": triggers
                }

func unregister_unit(unit_id: String):
    if active_unit_triggers.has(unit_id):
        active_unit_triggers.erase(unit_id)

func _evaluate_all_triggers():
    for unit_id in active_unit_triggers:
        var unit_data = active_unit_triggers[unit_id]
        var unit = unit_data.unit
        var triggers = unit_data.triggers
        
        if not is_instance_valid(unit):
            # Defer removal to avoid modifying dictionary while iterating
            call_deferred("unregister_unit", unit_id)
            continue
        
        var highest_priority_action = null
        var highest_priority = -1
        var trigger_to_fire = null

        for trigger in triggers:
            if trigger.evaluate(unit) and trigger.priority > highest_priority:
                highest_priority = trigger.priority
                highest_priority_action = trigger.action
                trigger_to_fire = trigger
        
        if highest_priority_action:
            highest_priority_action.execute(unit)
            if trigger_to_fire:
                trigger_to_fire.triggered()