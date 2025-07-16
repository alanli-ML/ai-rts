# AIResponseSchemas.gd
class_name AIResponseSchemas
extends RefCounted

# JSON Schema definitions for OpenAI Structured Outputs
# These schemas define the exact structure expected from AI responses

# Action enums by archetype
const GENERAL_ACTIONS = ["move_to", "attack", "retreat", "patrol", "stance", "follow"]
const SCOUT_ACTIONS = ["move_to", "attack", "retreat", "patrol", "stance", "follow", "activate_stealth"]
const TANK_ACTIONS = ["move_to", "attack", "retreat", "patrol", "stance", "follow", "activate_shield", "taunt_enemies"]
const SNIPER_ACTIONS = ["move_to", "attack", "retreat", "patrol", "stance", "follow", "charge_shot", "find_cover"]
const MEDIC_ACTIONS = ["move_to", "attack", "retreat", "patrol", "stance", "follow", "heal_target"]
const ENGINEER_ACTIONS = ["move_to", "attack", "retreat", "patrol", "stance", "follow", "construct", "repair", "lay_mines"]

# Trigger source enums
const TRIGGER_SOURCES = ["health_pct", "ammo_pct", "morale", "under_fire", "target_dead", "enemies_in_range", "enemy_dist", "ally_health_low", "nearby_enemies", "is_moving", "elapsed_ms"]

# Comparison operators
const COMPARISON_OPERATORS = ["<", "<=", "=", ">=", ">", "!="]

# Helper function to get the params schema (shared between all schemas)
static func get_params_schema() -> Dictionary:
	return {
		"type": ["object", "null"],
		"description": "Parameters for the action (null for actions that don't need parameters)",
		"properties": {
			"position": {
				"type": ["array", "null"],
				"description": "3D coordinates [x, y, z] for movement or construction",
				"items": {"type": "number"},
				"minItems": 3,
				"maxItems": 3
			},
			"target_id": {
				"type": ["string", "null"],
				"description": "ID of target unit for attack/follow/heal/repair actions"
			}
		},
        "required": ["position", "target_id"],
		"additionalProperties": false
	}

# Helper function to get the triggered_actions schema (shared between all schemas)
static func get_triggered_actions_schema(allowed_actions: Array) -> Dictionary:
	return {
		"type": "array",
		"description": "Conditional actions that interrupt the main plan",
		"items": {
			"type": "object",
			"properties": {
				"action": {
					"type": "string",
					"enum": allowed_actions,
					"description": "Name of the action to perform"
				},
				"params": get_params_schema(),
				"trigger_source": {
					"type": "string",
					"enum": TRIGGER_SOURCES,
					"description": "The metric to check (e.g., health_pct, enemies_in_range)"
				},
				"trigger_comparison": {
					"type": "string",
					"enum": COMPARISON_OPERATORS,
					"description": "The comparison operator (e.g., <, >=, =)"
				},
				"trigger_value": {
					"type": ["number", "boolean"],
					"description": "The value to compare against (e.g., 50, true)"
				},
				"speech": {
					"type": ["string", "null"],
					"description": "Optional dialogue for the unit"
				}
			},
			"required": ["action", "params", "trigger_source", "trigger_comparison", "trigger_value", "speech"],
			"additionalProperties": false
		}
	}

# Helper function to get actions for a specific archetype
static func get_actions_for_archetype(archetype: String) -> Array:
	match archetype:
		"scout": return SCOUT_ACTIONS
		"tank": return TANK_ACTIONS
		"sniper": return SNIPER_ACTIONS
		"medic": return MEDIC_ACTIONS
		"engineer": return ENGINEER_ACTIONS
		_: return GENERAL_ACTIONS

# Schema for unit-specific plans with enum actions
static func get_unit_specific_schema(unit_archetypes: Array, is_group_command: bool = false) -> Dictionary:
	var schema_name = "IndividualUnitPlanResponse"
	var schema_description = "A structured plan response for a single unit"
	
	if is_group_command:
		schema_name = "MultiStepPlanResponse"
		schema_description = "A structured plan response for RTS game AI commands"
	
	# Determine which actions to allow based on unit archetypes
	var allowed_actions = []
	if unit_archetypes.is_empty():
		allowed_actions = GENERAL_ACTIONS
	elif unit_archetypes.size() == 1:
		# Single archetype - use specific actions
		allowed_actions = get_actions_for_archetype(unit_archetypes[0])
	else:
		# Multiple archetypes - combine all unique actions
		var action_set = {}
		for archetype in unit_archetypes:
			var archetype_actions = get_actions_for_archetype(archetype)
			for action in archetype_actions:
				action_set[action] = true
		allowed_actions = action_set.keys()
	
	return {
		"type": "json_schema",
		"json_schema": {
			"name": schema_name,
			"description": schema_description,
			"strict": true,
			"schema": {
				"type": "object",
				"properties": {
					"type": {
						"type": "string",
						"enum": ["multi_step_plan"],
						"description": "The type of response"
					},
					"plans": {
						"type": "array",
						"description": "Array of unit plans",
						"items": {
							"type": "object",
							"properties": {
								"unit_id": {
									"type": "string",
									"description": "Unique identifier for the unit"
								},
								"goal": {
									"type": "string",
									"description": "High-level objective for this unit"
								},
								"steps": {
									"type": "array",
									"description": "Sequential list of actions to execute",
									"items": {
										"type": "object",
										"properties": {
											"action": {
												"type": "string",
												"enum": allowed_actions,
												"description": "Name of the action to perform"
											},
											"params": get_params_schema(),
											"speech": {
												"type": ["string", "null"],
												"description": "Optional dialogue for the unit"
											}
										},
										"required": ["action", "params", "speech"],
										"additionalProperties": false
									}
								},
								"triggered_actions": get_triggered_actions_schema(allowed_actions)
							},
							"required": ["unit_id", "goal", "steps", "triggered_actions"],
							"additionalProperties": false
						}
					},
					"message": {
						"type": "string",
						"description": "Confirmation message for the player"
					},
					"summary": {
						"type": "string",
						"description": "Tactical summary of the overall strategy"
					}
				},
				"required": ["type", "plans", "message", "summary"],
				"additionalProperties": false
			}
		}
	}

# Legacy schema for compatibility (updated to use structured triggers)
static func get_multi_step_plan_schema() -> Dictionary:
	return {
		"type": "json_schema",
		"json_schema": {
			"name": "MultiStepPlanResponse",
			"description": "A structured plan response for RTS game AI commands",
			"strict": true,
			"schema": {
				"type": "object",
				"properties": {
					"type": {
						"type": "string",
						"enum": ["multi_step_plan"],
						"description": "The type of response"
					},
					"plans": {
						"type": "array",
						"description": "Array of unit plans",
						"items": {
							"type": "object",
							"properties": {
								"unit_id": {
									"type": "string",
									"description": "Unique identifier for the unit"
								},
								"goal": {
									"type": "string",
									"description": "High-level objective for this unit"
								},
								"steps": {
									"type": "array",
									"description": "Sequential list of actions to execute",
									"items": {
										"type": "object",
										"properties": {
											"action": {
												"type": "string",
												"enum": GENERAL_ACTIONS,
												"description": "Name of the action to perform"
											},
											"params": get_params_schema(),
											"speech": {
												"type": ["string", "null"],
												"description": "Optional dialogue for the unit"
											}
										},
										"required": ["action", "params", "speech"],
										"additionalProperties": false
									}
								},
								"triggered_actions": get_triggered_actions_schema(GENERAL_ACTIONS)
							},
							"required": ["unit_id", "goal", "steps", "triggered_actions"],
							"additionalProperties": false
						}
					},
					"message": {
						"type": "string",
						"description": "Confirmation message for the player"
					},
					"summary": {
						"type": "string",
						"description": "Tactical summary of the overall strategy"
					}
				},
				"required": ["type", "plans", "message", "summary"],
				"additionalProperties": false
			}
		}
	}

# Helper function to get the appropriate schema based on command type and unit archetypes
static func get_schema_for_command(is_group_command: bool, unit_archetypes: Array = []) -> Dictionary:
	return get_unit_specific_schema(unit_archetypes, is_group_command)

# Legacy helper function for backward compatibility (will be deprecated)
static func get_legacy_schema_for_command(is_group_command: bool) -> Dictionary:
	if is_group_command:
		return get_multi_step_plan_schema()
	else:
		# Use the consolidated function instead of the removed get_individual_unit_plan_schema
		return get_unit_specific_schema([], false) 