# scripts/ai/trigger_condition.gd
class_name TriggerCondition
extends Resource

enum Operator { LESS_THAN, GREATER_THAN, EQUAL_TO, NOT_EQUAL_TO, LESS_THAN_OR_EQUAL_TO, GREATER_THAN_OR_EQUAL_TO }

## The type of condition to check (e.g., "health_pct", "enemy_dist").
@export var condition_type: String = ""
## The comparison operator.
@export var operator: Operator = Operator.LESS_THAN
## The value to compare against.
@export var value: float = 0.0

func _init(p_condition_type: String = "", p_operator: Operator = Operator.LESS_THAN, p_value: float = 0.0):
    condition_type = p_condition_type
    operator = p_operator
    value = p_value

func evaluate(unit: Node) -> bool:
    if not is_instance_valid(unit):
        printerr("TriggerCondition: evaluate() called with an invalid unit.")
        return false

    var unit_value = _get_unit_value(unit, condition_type)
    if unit_value is bool and unit_value == false and typeof(unit_value) == TYPE_BOOL: # Check for error
        return false
        
    return _compare(unit_value, operator, value)

func _get_unit_value(unit: Node, type: String):
    match type:
        "health_pct":
            if unit.has_method("get_health_percentage"):
                return unit.get_health_percentage() * 100.0
        "enemy_dist":
            if unit.has_method("get_nearest_enemy_distance"):
                 return unit.get_nearest_enemy_distance()
        "ally_dist":
             if unit.has_method("get_nearest_ally_distance"):
                 return unit.get_nearest_ally_distance()
        "energy":
            if unit.has_method("get_energy"):
                return unit.get_energy()
        "ammo":
             if unit.has_method("get_ammo"):
                 return unit.get_ammo()
        "enemy_count":
             if unit.has_method("get_enemy_count_in_range"):
                 # The 'value' in the condition is used as the range here.
                 return unit.get_enemy_count_in_range(value)
        "ally_count":
             if unit.has_method("get_ally_count_in_range"):
                 return unit.get_ally_count_in_range(value)
        _:
            printerr("TriggerCondition: Unknown condition type '%s'" % type)
            return false
            
    printerr("TriggerCondition: Unit does not have method for condition type '%s'" % type)
    return false

func _compare(val1: float, op: Operator, val2: float) -> bool:
    match op:
        Operator.LESS_THAN:
            return val1 < val2
        Operator.GREATER_THAN:
            return val1 > val2
        Operator.EQUAL_TO:
            return abs(val1 - val2) < 0.001
        Operator.NOT_EQUAL_TO:
            return abs(val1 - val2) >= 0.001
        Operator.LESS_THAN_OR_EQUAL_TO:
            return val1 <= val2
        Operator.GREATER_THAN_OR_EQUAL_TO:
            return val1 >= val2
    return false