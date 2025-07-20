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

const VALID_NODE_NAMES = [
    "Northwest", "North", "Northeast",
    "West", "Center", "East",
    "Southwest", "South", "Southeast"
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

func validate_plan(plan: Dictionary, _unit_archetype: String = "") -> Dictionary:
    var result = {"valid": true, "error": ""}

    # 1. Validate unit_id
    if not plan.has("unit_id") or not plan.unit_id is String or plan.unit_id.is_empty():
        result.valid = false
        result.error = "Plan must have a non-empty 'unit_id' string."
        return result

    # 2. Validate control_point_attack_sequence
    if not plan.has("control_point_attack_sequence") or not plan.control_point_attack_sequence is Array:
        result.valid = false
        result.error = "Plan must have a 'control_point_attack_sequence' array."
        return result
    
    for node_id in plan.control_point_attack_sequence:
        if not node_id is String or not node_id in VALID_NODE_NAMES:
            result.valid = false
            result.error = "Item '%s' in 'control_point_attack_sequence' is not a valid node name. Must be one of: %s" % [node_id, str(VALID_NODE_NAMES)]
            return result

    # 3. Validate primary_state_priority_list
    if not plan.has("primary_state_priority_list") or not plan.primary_state_priority_list is Array:
        result.valid = false
        result.error = "Plan must have a 'primary_state_priority_list' array."
        return result
    
    var priority_list = plan.primary_state_priority_list
    if priority_list.size() != 4:
        result.valid = false
        result.error = "'primary_state_priority_list' must contain exactly 4 states."
        return result
    
    var seen_states = {}
    for state in priority_list:
        if not state is String or state not in MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS:
            result.valid = false
            result.error = "Invalid state '%s' in 'primary_state_priority_list'. Must be one of: %s" % [state, str(MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS)]
            return result
        if state in seen_states:
            result.valid = false
            result.error = "Duplicate state '%s' found in 'primary_state_priority_list'." % state
            return result
        seen_states[state] = true

    return result