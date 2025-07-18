# AIResponseSchemas.gd
class_name AIResponseSchemas
extends RefCounted

# This class provides structured JSON schemas for OpenAI function calls.
# This ensures the AI's response is always in the correct format.

# Load the ActionValidator to get the list of allowed actions and state variables.
const ActionValidator = preload("res://scripts/ai/action_validator.gd")

static func get_schema_for_command(_is_group_command: bool, _unit_archetypes: Array) -> Dictionary:
	var validator = ActionValidator.new()
	var all_actions = validator.get_all_reactive_actions()
	var all_state_vars = validator.DEFINED_STATE_VARIABLES

	# --- Compact Behavior Matrix Schema ---
	# Use a simple structure that allows any string keys with number values
	# This is much more compact than defining every field individually
	var behavior_matrix_schema = {
		"type": "object",
		"description": "Behavior matrix: action names as keys, each containing state variable weights (-1.0 to 1.0)",
		"additionalProperties": {
			"type": "object",
			"description": "State variable weights for an action",
			"additionalProperties": {
				"type": "number",
				"minimum": -1.0,
				"maximum": 1.0
			}
		}
	}

	# --- Plan Schema ---
	var plan_schema = {
		"type": "object",
		"properties": {
			"unit_id": {
				"type": "string",
				"description": "Unique identifier for the unit."
			},
			"goal": {
				"type": "string",
				"description": "High-level tactical objective for this unit."
			},
			"control_point_attack_sequence": {
				"type": "array",
				"description": "Ordered list of control point IDs to attack.",
				"items": {
					"type": "string"
				}
			},
			"behavior_matrix": behavior_matrix_schema
		},
		"required": ["unit_id", "goal", "control_point_attack_sequence", "behavior_matrix"],
		"additionalProperties": false
	}

	# --- Top-Level Response Schema ---
	var response_schema = {
		"type": "json_schema",
		"json_schema": {
			"name": "process_behavior_plan",
			"strict": true,
			"schema": {
				"type": "object",
				"properties": {
					"plans": {
						"type": "array",
						"description": "An array of plans, one for each unit being commanded.",
						"items": plan_schema
					},
					"message": {
						"type": "string",
						"description": "A confirmation message for the player about the overall plan."
					},
					"summary": {
						"type": "string",
						"description": "A brief summary of the tactical situation or plan."
					}
				},
				"required": ["plans", "message", "summary"],
				"additionalProperties": false
			}
		}
	}

	return response_schema