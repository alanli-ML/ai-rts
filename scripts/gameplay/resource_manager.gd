# ResourceManager.gd
class_name ResourceManager
extends Node

# Resource types
enum ResourceType { ENERGY }

const ENERGY_PER_NODE = 5
const STARTING_ENERGY = 1000

# Team resources
var team_resources: Dictionary = {
    1: {"energy": STARTING_ENERGY},
    2: {"energy": STARTING_ENERGY}
}
var team_income_rates: Dictionary = {
    1: {"energy": 0},
    2: {"energy": 0}
}

signal resource_changed(team_id: int, resource_type: ResourceType, new_amount: int)

func _process(delta: float) -> void:
    # Update resources for all teams
    for team_id in team_resources:
        var income = team_income_rates[team_id].energy * delta
        if income > 0:  # Only update and emit signal if there's actual income
            var old_energy = team_resources[team_id].energy
            team_resources[team_id].energy += income
            # Only emit signal if the value actually changed meaningfully (> 0.1 to avoid micro-changes)
            if abs(team_resources[team_id].energy - old_energy) > 0.1:
                resource_changed.emit(team_id, ResourceType.ENERGY, team_resources[team_id].energy)

func start_match() -> void:
    # Reset resources at the start of a match
    team_resources = {
        1: {"energy": STARTING_ENERGY},
        2: {"energy": STARTING_ENERGY}
    }
    team_income_rates = {
        1: {"energy": 0},
        2: {"energy": 0}
    }

func set_income_rate_for_team(team_id: int, controlled_nodes: int) -> void:
    if team_id in team_income_rates:
        team_income_rates[team_id].energy = controlled_nodes * ENERGY_PER_NODE

func consume_resources(team_id: int, cost: Dictionary) -> bool:
    if not cost.has("energy"): return true

    var energy_cost = cost.energy
    if team_resources[team_id].energy >= energy_cost:
        team_resources[team_id].energy -= energy_cost
        resource_changed.emit(team_id, ResourceType.ENERGY, team_resources[team_id].energy)
        return true
    
    return false