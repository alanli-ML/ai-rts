# ActionValidator.gd
class_name ActionValidator
extends Node

const ALLOWED_ACTIONS = [
    "move_to", "attack", "retreat", "patrol", "stance", "follow", # General
    "activate_stealth", # Scout
    "activate_shield", "taunt_enemies", # Tank
    "charge_shot", "find_cover", # Sniper
    "heal_target", # Medic
    "construct", "repair", "lay_mines" # Engineer
]
const VALID_FORMATIONS = ["line", "column", "wedge", "scattered"]
const VALID_STANCES = ["aggressive", "defensive", "passive"]
const MAX_COORDINATE = 100.0
const MIN_COORDINATE = -100.0

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
        if not _validate_parameters(action, params):
            result.valid = false
            result.error = "Invalid parameters for action '%s'." % action
            return result

    # Validate triggered actions
    var has_enemies_in_range_trigger = false
    if not plan.has("triggered_actions") or not plan.triggered_actions is Array:
        result.valid = false
        result.error = "Plan must have a 'triggered_actions' array."
        return result
        
    for step in plan.triggered_actions:
        if not step is Dictionary or not step.has("action"):
            result.valid = false
            result.error = "Each item in 'triggered_actions' must be a dictionary with an 'action' key."
            return result
        
        # Check for new trigger format (trigger_source, trigger_comparison, trigger_value)
        if step.has("trigger_source") and step.has("trigger_comparison") and step.has("trigger_value"):
            # New structured trigger format
            if step.trigger_source == "enemies_in_range":
                has_enemies_in_range_trigger = true
        elif step.has("trigger") and not step.trigger.is_empty():
            # Legacy trigger format for backward compatibility
            if "enemies_in_range" in step.trigger:
                has_enemies_in_range_trigger = true
        else:
            result.valid = false
            result.error = "Each item in 'triggered_actions' must have either the new trigger format (trigger_source, trigger_comparison, trigger_value) or legacy trigger format."
            return result

        var action = step.get("action")
        if action not in ALLOWED_ACTIONS:
            result.valid = false
            result.error = "Triggered action '%s' is not allowed. Allowed: %s" % [action, ALLOWED_ACTIONS]
            return result

        var params = step.get("params", {})
        if not _validate_parameters(action, params):
            result.valid = false
            result.error = "Invalid parameters for triggered action '%s'." % action
            return result

    if not has_enemies_in_range_trigger:
        result.valid = false
        result.error = "Plan must have at least one triggered_action with 'enemies_in_range' as a trigger for self-defense."
        return result

    return result

func _validate_parameters(action: String, params: Dictionary) -> bool:
    match action:
        "move_to":
            if not params.has("position") or not params.position is Array or params.position.size() != 3:
                return false
            for coord in params.position:
                if not coord is float and not coord is int: return false
                if coord < MIN_COORDINATE or coord > MAX_COORDINATE: return false
        "attack":
            if params.has("target_id") and not params.target_id is String:
                return false
        "formation":
            if not params.has("formation") or not params.formation in VALID_FORMATIONS:
                return false
        "stance":
            if not params.has("stance") or not params.stance in VALID_STANCES:
                return false

        "follow":
            if not params.has("target_id") or not params.target_id is String:
                return false
        "heal_target":
            if not params.has("target_id") or not params.target_id is String:
                return false
        "construct":
            if not params.has("building_type") or not params.building_type is String:
                return false
            if not params.has("position") or not params.position is Array or params.position.size() != 3:
                return false
        "repair":
            if not params.has("target_id") or not params.target_id is String:
                return false
        "lay_mines":
            pass # No parameters needed
        "patrol":
            pass # No parameters needed
    
    return true