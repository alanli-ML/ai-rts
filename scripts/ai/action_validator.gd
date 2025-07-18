# ActionValidator.gd
class_name ActionValidator
extends Node

# These are the normalized input variables the unit's brain will use.
# The LLM must provide weights for each of these for every action.
const DEFINED_STATE_VARIABLES = [
    "enemies_in_range",     # Normalized count of enemies within weapon range
    "current_health",       # Health percentage from 0.0 to 1.0
    "under_attack",         # 1.0 if recently took damage, 0.0 otherwise
    "allies_in_range",      # Normalized count of allies within vision range
    "ally_low_health",  # Highest missing health percentage of a nearby ally (0.0 to 1.0)
    "enemy_nodes_controlled", # Normalized count of enemy-controlled nodes
    "ally_nodes_controlled",  # Normalized count of ally-controlled nodes
    "bias"                  # A constant value of 1.0 to act as a bias weight
]

# These actions are primary states. The one with the highest activation will be chosen.
const MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS = [
    "attack", "retreat", "defend", "follow"
]

# These actions are special abilities. They can be activated if their activation
# level exceeds a threshold, independent of the primary state.
const INDEPENDENT_REACTIVE_ACTIONS = [
    "activate_stealth", "activate_shield", "taunt_enemies", "charge_shot",
    "heal_ally", "lay_mines", "repair", "find_cover", "construct_turret"
]

# Actions available to each unit archetype
const ARCHETYPE_ACTIONS = {
    "scout": ["attack", "retreat", "defend", "follow", "activate_stealth", "find_cover"],
    "tank": ["attack", "retreat", "defend", "follow", "activate_shield", "taunt_enemies", "find_cover"],
    "sniper": ["attack", "retreat", "defend", "follow", "charge_shot", "find_cover"],
    "medic": ["attack", "retreat", "defend", "follow", "heal_ally", "find_cover"],
    "engineer": ["attack", "retreat", "defend", "follow", "repair", "lay_mines", "find_cover", "construct_turret"],
    "general": ["attack", "retreat", "defend", "follow", "find_cover"]
}

const MAX_COORDINATE = 120.0
const MIN_COORDINATE = -120.0

func get_all_reactive_actions() -> Array[String]:
    var all_actions: Array[String] = []
    all_actions.append_array(MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS)
    all_actions.append_array(INDEPENDENT_REACTIVE_ACTIONS)
    return all_actions

func get_valid_actions_for_archetype(archetype: String) -> Array[String]:
    """Get the list of actions valid for a specific unit archetype"""
    var actions = ARCHETYPE_ACTIONS.get(archetype, ARCHETYPE_ACTIONS.get("general", []))
    var typed_actions: Array[String] = []
    typed_actions.assign(actions)
    return typed_actions

func is_action_valid_for_archetype(action: String, archetype: String) -> bool:
    """Check if an action is valid for a specific unit archetype"""
    var valid_actions = get_valid_actions_for_archetype(archetype)
    return action in valid_actions

func validate_plan(plan: Dictionary, unit_archetype: String = "") -> Dictionary:
    var result = {"valid": true, "error": ""}

    # 1. Validate control_point_attack_sequence
    if not plan.has("control_point_attack_sequence") or not plan.control_point_attack_sequence is Array:
        result.valid = false
        result.error = "Plan must have a 'control_point_attack_sequence' array."
        return result
    
    for node_id in plan.control_point_attack_sequence:
        if not node_id is String or not node_id.begins_with("Node"):
            result.valid = false
            result.error = "All items in 'control_point_attack_sequence' must be valid node ID strings (e.g., 'Node1')."
            return result

    # 2. Validate behavior_matrix
    if not plan.has("behavior_matrix") or not plan.behavior_matrix is Dictionary:
        result.valid = false
        result.error = "Plan must have a 'behavior_matrix' dictionary."
        return result

    var matrix_validation = _validate_behavior_matrix(plan.behavior_matrix, unit_archetype)
    if not matrix_validation.valid:
        return matrix_validation # Return the error from the helper

    return result

func _validate_behavior_matrix(matrix: Dictionary, unit_archetype: String = "") -> Dictionary:
    var result = {"valid": true, "error": ""}
    
    # Get valid actions for the unit archetype if provided
    var valid_actions = []
    if not unit_archetype.is_empty():
        valid_actions = get_valid_actions_for_archetype(unit_archetype)
    
    # Always require primary states (mutually exclusive actions)
    for action in MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS:
        # Skip validation if archetype filtering is enabled and action is not valid for this archetype
        if not unit_archetype.is_empty() and action not in valid_actions:
            continue
            
        if not matrix.has(action):
            result.valid = false
            result.error = "Behavior matrix is missing required primary state: '%s'." % action
            return result
    
    # Validate all actions that are present (including optional independent actions)
    for action in matrix.keys():
        # Verify this is a known action
        if not (action in MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS or action in INDEPENDENT_REACTIVE_ACTIONS):
            result.valid = false
            result.error = "Unknown action in behavior matrix: '%s'." % action
            return result
        
        # Check if action is valid for the unit's archetype
        if not unit_archetype.is_empty() and action not in valid_actions:
            result.valid = false
            result.error = "Action '%s' is not valid for unit archetype '%s'. Valid actions: %s" % [action, unit_archetype, str(valid_actions)]
            return result
        
        var weights = matrix[action]
        if not weights is Dictionary:
            result.valid = false
            result.error = "Weights for action '%s' must be a dictionary." % action
            return result

        # Check that the weights dictionary has a key for every defined state variable
        for state_var in DEFINED_STATE_VARIABLES:
            if not weights.has(state_var):
                result.valid = false
                result.error = "Weights for action '%s' are missing state variable: '%s'." % [action, state_var]
                return result
            
            var weight = weights[state_var]
            if not (weight is float or weight is int):
                result.valid = false
                result.error = "Weight for '%s' -> '%s' must be a number. Got: %s" % [action, state_var, str(weight)]
                return result
        
        # Check for any extra, undefined state variables in the weights
        for state_var in weights:
            if state_var not in DEFINED_STATE_VARIABLES:
                result.valid = false
                result.error = "Behavior matrix for action '%s' contains an undefined state variable: '%s'." % [action, state_var]
                return result

    return result