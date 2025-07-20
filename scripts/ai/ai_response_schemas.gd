# AIResponseSchemas.gd
class_name AIResponseSchemas
extends RefCounted

# This class provides structured JSON schemas for OpenAI function calls.
# This ensures the AI's response is always in the correct format.

# Load the ActionValidator to get the list of allowed actions and state variables.
const ActionValidator = preload("res://scripts/ai/action_validator.gd")

const VALID_NODE_NAMES = [
	"Northwest", "North", "Northeast",
	"West", "Center", "East",
	"Southwest", "South", "Southeast"
]

static func get_schema_for_command(_is_group_command: bool, _unit_archetypes: Array) -> Dictionary:
	var validator = ActionValidator.new()

	# --- Plan Schema (for a single unit) ---
	var plan_schema = {
		"type": "object",
		"properties": {
			"unit_id": {
				"type": "string",
				"description": "The unique ID of the unit this plan is for."
			},
			"goal": {
				"type": "string",
				"description": "High-level tactical objective for this unit."
			},
			"primary_state_priority_list": {
				"type": "array",
				"description": "An ordered list of the four primary states: attack, defend, retreat, follow.",
				"items": {
					"type": "string",
					"enum": validator.MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS
				},
				"minItems": 4,
				"maxItems": 4,
				"uniqueItems": true
			},
			"control_point_attack_sequence": {
				"type": "array",
				"description": "Ordered list of control point IDs for this unit to capture.",
				"items": {
					"type": "string",
					"enum": VALID_NODE_NAMES
				}
			}
		},
		"required": ["unit_id", "goal", "primary_state_priority_list", "control_point_attack_sequence"],
		"additionalProperties": false
	}

	# --- Top-Level Response Schema ---
	var response_schema = {
		"type": "json_schema",
		"json_schema": {
			"name": "process_strategic_plan",
			"strict": true,
			"schema": {
				"type": "object",
				"properties": {
					"plans": {
						"type": "array",
						"description": "An array of strategic plans, one for each group of units.",
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