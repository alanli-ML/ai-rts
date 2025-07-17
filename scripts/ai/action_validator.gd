# ActionValidator.gd
class_name ActionValidator
extends Node

const ALLOWED_ACTIONS = [
    "move_to", "attack", "retreat", "patrol", "follow", # General
    "activate_stealth", # Scout
    "activate_shield", "taunt_enemies", # Tank
    "charge_shot", "find_cover", # Sniper
    "heal_target", # Medic
    "construct", "repair", "lay_mines" # Engineer
]

const MAX_COORDINATE = 120.0
const MIN_COORDINATE = -120.0

const REQUIRED_TRIGGERS = [
    "on_enemy_sighted",
    "on_under_attack",
    "on_health_low",
    "on_health_critical",
    "on_ally_health_low"
]

func get_allowed_actions() -> Array:
    return ALLOWED_ACTIONS.duplicate()

func validate_plan(plan: Dictionary) -> Dictionary:
    var result = {"valid": true, "error": ""}

    if not plan.has("goal") or not plan.goal is String or plan.goal.is_empty():
        result.valid = false
        result.error = "Plan must include a non-empty 'goal' string."
        return result

    # Validate sequential steps
    if not plan.has("steps") or not plan.steps is Array:
        result.valid = false
        result.error = "Plan must have a 'steps' array for the sequential plan."
        return result

    if plan.steps.is_empty():
        result.valid = false
        result.error = "Plan must have at least one action in the 'steps' array."
        return result

    for step in plan.steps:
        if not step is Dictionary or not step.has("action"):
            result.valid = false
            result.error = "Each step must be a dictionary with an 'action' key."
            return result
        
        if step.has("trigger") and not step.trigger.is_empty():
            result.valid = false
            result.error = "Actions in the 'steps' array cannot have triggers. Triggers belong in 'triggered_actions'."
            return result

        var action = step.get("action")
        if action not in ALLOWED_ACTIONS:
            result.valid = false
            result.error = "Action '%s' is not allowed. Allowed: %s" % [action, ALLOWED_ACTIONS]
            return result

        var params = step.get("params", {})
        # Handle null params (valid for some actions like activate_stealth, lay_mines, patrol)
        if params == null:
            params = {}
        if not _validate_parameters(action, params, false):
            result.valid = false
            result.error = "Invalid parameters for action '%s'." % action
            return result

    # Validate triggered actions
    if not plan.has("triggered_actions") or not plan.triggered_actions is Dictionary:
        result.valid = false
        result.error = "Plan must have a 'triggered_actions' dictionary."
        return result

    var triggered_actions = plan.get("triggered_actions", {})
    for trigger_key in REQUIRED_TRIGGERS:
        if not triggered_actions.has(trigger_key):
            result.valid = false
            result.error = "Plan is missing required triggered_action key: '%s'." % trigger_key
            return result
        
        var action = triggered_actions[trigger_key]
        if not action is String:
            result.valid = false
            result.error = "Action for trigger '%s' must be a string." % trigger_key
            return result
            
        if action not in ALLOWED_ACTIONS:
            result.valid = false
            result.error = "Action '%s' for trigger '%s' is not allowed. Allowed: %s" % [action, trigger_key, ALLOWED_ACTIONS]
            return result
            
        # For triggered actions, we don't need to validate params because they are context-sensitive
        # and often don't have explicit params in the plan. The unit will supply them.

    if not triggered_actions.has("on_enemy_sighted") or triggered_actions.on_enemy_sighted.is_empty():
        result.valid = false
        result.error = "Plan is invalid. It MUST have a valid action for 'on_enemy_sighted' for self-defense."
        return result

    return result

func _validate_parameters(action: String, params: Dictionary, is_triggered_action: bool = false) -> bool:
    match action:
        "move_to":
            if not params.has("position") or params.position == null or not params.position is Array or params.position.size() != 3:
                return false
            for coord in params.position:
                if not coord is float and not coord is int: return false
                if coord < MIN_COORDINATE or coord > MAX_COORDINATE: return false
        "attack", "follow", "heal_target", "repair", "charge_shot":
            # For triggered actions, target_id is optional as it can come from the trigger context.
            # For sequential steps, it's required.
            if is_triggered_action:
                # If target_id is provided and not null, it must be a string.
                if params.has("target_id") and params.target_id != null and not params.target_id is String:
                    return false
            else:
                # For sequential steps, target_id is mandatory and must not be null.
                if not params.has("target_id") or params.target_id == null or not params.target_id is String:
                    return false

        "construct":
            #if not params.has("building_type") or not params.building_type is String:
            #    return false
            if not params.has("position") or params.position == null or not params.position is Array or params.position.size() != 3:
                return false
        "lay_mines", "patrol", "activate_stealth", "activate_shield", "taunt_enemies", "find_cover":
            pass # No parameters needed or parameters are optional
    
    return true