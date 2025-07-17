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
        # Handle null params (valid for some actions like activate_stealth, lay_mines, patrol)
        if params == null:
            params = {}
        if not _validate_parameters(action, params, true):
            result.valid = false
            result.error = "Invalid parameters for triggered action '%s'." % action
            return result

    if not has_enemies_in_range_trigger:
        result.valid = false
        result.error = "Plan is invalid. It MUST have at least one triggered_action with 'enemies_in_range' as the trigger for self-defense."
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