# ActionValidator.gd
class_name ActionValidator
extends Node

# Load shared constants
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Safety limits
const MAX_PLAN_DURATION = 6.0  # seconds
const MAX_STEPS_PER_PLAN = 8
const MAX_SPEECH_LENGTH = GameConstants.MAX_SPEECH_LENGTH / 8  # Convert characters to approximate words
const ALLOWED_ACTIONS = ["move_to", "attack", "peek_and_fire", "lay_mines", "hijack_enemy_spire", "retreat", "patrol", "use_ability", "formation", "stance"]

# Valid parameter ranges
const MAX_COORDINATE = 100.0
const MIN_COORDINATE = -100.0
const VALID_FORMATIONS = ["line", "column", "wedge", "scattered"]
const VALID_STANCES = ["aggressive", "defensive", "passive"]

# Speech content filtering
const INAPPROPRIATE_WORDS = ["shit", "fuck", "damn", "hell", "stupid", "noob", "ez", "rekt"]

func validate_command(command: Dictionary) -> bool:
    """
    Validate a single command
    
    Args:
        command: Dictionary with command data
        
    Returns:
        bool: True if command is valid, False otherwise
    """
    # Check basic command structure
    if not command.has("action"):
        print("ActionValidator: Command missing 'action' field")
        return false
    
    var action = command.get("action", "")
    if action.is_empty():
        print("ActionValidator: Command action is empty")
        return false
    
    # Check if action is allowed
    if action not in ALLOWED_ACTIONS:
        print("ActionValidator: Invalid action '%s'" % action)
        return false
    
    # Validate parameters if present
    if command.has("parameters"):
        var params = command.get("parameters", {})
        if not _validate_command_parameters(action, params):
            return false
    
    return true

func _validate_command_parameters(action: String, params: Dictionary) -> bool:
    """Validate parameters for a specific command action"""
    match action:
        "move_to":
            if params.has("position"):
                var pos = params.position
                if pos is Array and pos.size() >= 2:
                    var x = pos[0]
                    var z = pos[1] if pos.size() > 1 else 0
                    if x < MIN_COORDINATE or x > MAX_COORDINATE or z < MIN_COORDINATE or z > MAX_COORDINATE:
                        print("ActionValidator: Position out of bounds: [%s, %s]" % [x, z])
                        return false
        "formation":
            if params.has("formation"):
                if params.formation not in VALID_FORMATIONS:
                    print("ActionValidator: Invalid formation: %s" % params.formation)
                    return false
        "stance":
            if params.has("stance"):
                if params.stance not in VALID_STANCES:
                    print("ActionValidator: Invalid stance: %s" % params.stance)
                    return false
    
    return true

func validate_plan(plan: Dictionary) -> Dictionary:
    """
    Validate a multi-step AI plan
    
    Args:
        plan: Dictionary with plan data
        
    Returns:
        Dictionary with validation result: {"valid": bool, "error": String, "warnings": Array}
    """
    var result = {
        "valid": true,
        "error": "",
        "warnings": []
    }
    
    # Check plan schema
    if not _validate_schema(plan):
        result.valid = false
        result.error = "Invalid plan schema - missing required fields"
        return result
    
    # Verify action whitelist
    var action_check = _validate_actions(plan)
    if not action_check.valid:
        result.valid = false
        result.error = action_check.error
        return result
    
    # Validate parameters
    var param_check = _validate_parameters(plan)
    if not param_check.valid:
        result.valid = false
        result.error = param_check.error
        return result
    
    # Check duration limits
    var duration_check = _validate_duration(plan)
    if not duration_check.valid:
        result.valid = false
        result.error = duration_check.error
        return result
    
    # Moderate speech content
    var speech_check = _moderate_speech(plan)
    if not speech_check.valid:
        result.valid = false
        result.error = speech_check.error
        return result
    
    # Add any warnings
    result.warnings.append_array(speech_check.warnings)
    
    return result

func _validate_schema(plan: Dictionary) -> bool:
    """Validate plan has required structure"""
    if not plan.has("steps"):
        return false
    
    if not plan.steps is Array:
        return false
    
    if plan.steps.size() == 0:
        return false
    
    # Check each step has required fields
    for step in plan.steps:
        if not step is Dictionary:
            return false
        
        if not step.has("action"):
            return false
        
        # Optional fields: params, duration_ms, trigger, speech, conditions
    
    return true

func _validate_actions(plan: Dictionary) -> Dictionary:
    """Validate all actions are whitelisted"""
    var result = {"valid": true, "error": ""}
    
    for step in plan.steps:
        var action = step.get("action", "")
        if not action in ALLOWED_ACTIONS:
            result.valid = false
            result.error = "Invalid action: %s. Allowed actions: %s" % [action, ALLOWED_ACTIONS]
            return result
    
    return result

func _validate_parameters(plan: Dictionary) -> Dictionary:
    """Validate action parameters are safe and within bounds"""
    var result = {"valid": true, "error": ""}
    
    for step in plan.steps:
        var action = step.get("action", "")
        var params = step.get("params", {})
        
        match action:
            "move_to":
                if params.has("position"):
                    var pos = params.position
                    if not pos is Array or pos.size() != 3:
                        result.valid = false
                        result.error = "move_to requires position array with 3 elements"
                        return result
                    
                    for coord in pos:
                        if not coord is float and not coord is int:
                            result.valid = false
                            result.error = "move_to position coordinates must be numbers"
                            return result
                        
                        if coord < MIN_COORDINATE or coord > MAX_COORDINATE:
                            result.valid = false
                            result.error = "move_to position coordinates out of bounds (%s to %s)" % [MIN_COORDINATE, MAX_COORDINATE]
                            return result
            
            "attack":
                if params.has("target_position"):
                    var pos = params.target_position
                    if not pos is Array or pos.size() != 3:
                        result.valid = false
                        result.error = "attack requires target_position array with 3 elements"
                        return result
            
            "formation":
                if params.has("formation"):
                    var formation = params.formation
                    if not formation in VALID_FORMATIONS:
                        result.valid = false
                        result.error = "Invalid formation: %s. Valid formations: %s" % [formation, VALID_FORMATIONS]
                        return result
            
            "stance":
                if params.has("stance"):
                    var stance = params.stance
                    if not stance in VALID_STANCES:
                        result.valid = false
                        result.error = "Invalid stance: %s. Valid stances: %s" % [stance, VALID_STANCES]
                        return result
    
    return result

func _validate_duration(plan: Dictionary) -> Dictionary:
    """Validate plan duration is within limits"""
    var result = {"valid": true, "error": ""}
    
    var total_duration = 0.0
    var step_count = plan.steps.size()
    
    # Check step count
    if step_count > MAX_STEPS_PER_PLAN:
        result.valid = false
        result.error = "Plan exceeds maximum steps: %d (max: %d)" % [step_count, MAX_STEPS_PER_PLAN]
        return result
    
    # Check total duration
    for step in plan.steps:
        var duration_ms = step.get("duration_ms", 0)
        if duration_ms > 0:
            total_duration += duration_ms / 1000.0
    
    if total_duration > MAX_PLAN_DURATION:
        result.valid = false
        result.error = "Plan exceeds maximum duration: %.1fs (max: %.1fs)" % [total_duration, MAX_PLAN_DURATION]
        return result
    
    return result

func _moderate_speech(plan: Dictionary) -> Dictionary:
    """Moderate speech content for inappropriate language"""
    var result = {"valid": true, "error": "", "warnings": []}
    
    for step in plan.steps:
        var speech = step.get("speech", "")
        if speech == "":
            continue
        
        # Check length
        var words = speech.split(" ")
        if words.size() > MAX_SPEECH_LENGTH:
            result.valid = false
            result.error = "Speech too long: %d words (max: %d)" % [words.size(), MAX_SPEECH_LENGTH]
            return result
        
        # Check for inappropriate content
        var lower_speech = speech.to_lower()
        for word in INAPPROPRIATE_WORDS:
            if word in lower_speech:
                result.valid = false
                result.error = "Inappropriate language detected in speech: %s" % speech
                return result
        
        # Check for excessive caps
        var caps_count = 0
        for character in speech:
            if character == character.to_upper() and character != character.to_lower():
                caps_count += 1
        
        var caps_ratio = float(caps_count) / float(speech.length())
        if caps_ratio > 0.6 and speech.length() > 5:
            result.warnings.append("Speech contains excessive caps: %s" % speech)
    
    return result

func get_action_requirements(action: String) -> Dictionary:
    """Get parameter requirements for a specific action"""
    match action:
        "move_to":
            return {
                "required": ["position"],
                "optional": [],
                "description": "Move units to specified position [x, y, z]"
            }
        "attack":
            return {
                "required": [],
                "optional": ["target_id", "target_position"],
                "description": "Attack target unit or position"
            }
        "peek_and_fire":
            return {
                "required": [],
                "optional": ["target_id"],
                "description": "Take cover and attack target"
            }
        "lay_mines":
            return {
                "required": [],
                "optional": ["count", "position"],
                "description": "Place mines for area denial"
            }
        "formation":
            return {
                "required": ["formation"],
                "optional": [],
                "description": "Change unit formation: %s" % str(VALID_FORMATIONS)
            }
        "stance":
            return {
                "required": ["stance"],
                "optional": [],
                "description": "Change combat stance: %s" % str(VALID_STANCES)
            }
        _:
            return {
                "required": [],
                "optional": [],
                "description": "Unknown action"
            }

func is_action_allowed(action: String) -> bool:
    """Check if action is in whitelist"""
    return action in ALLOWED_ACTIONS

func get_allowed_actions() -> Array:
    """Get list of allowed actions"""
    return ALLOWED_ACTIONS.duplicate()

func get_safety_limits() -> Dictionary:
    """Get current safety limits"""
    return {
        "max_plan_duration": MAX_PLAN_DURATION,
        "max_steps_per_plan": MAX_STEPS_PER_PLAN,
        "max_speech_length": MAX_SPEECH_LENGTH,
        "coordinate_bounds": [MIN_COORDINATE, MAX_COORDINATE]
    } 