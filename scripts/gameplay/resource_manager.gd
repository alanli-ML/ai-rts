# ResourceManager.gd
class_name ResourceManager
extends Node

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Resource types
enum ResourceType {
    ENERGY,
    MATERIALS,
    RESEARCH_POINTS
}

# Team resources
var team_resources: Dictionary = {}  # team_id -> Dictionary of resources

# Resource generation/consumption tracking
var resource_generators: Dictionary = {}  # team_id -> Array[ResourceGenerator]
var resource_consumers: Dictionary = {}   # team_id -> Array[ResourceConsumer]

# Resource production rates
var base_income_rates: Dictionary = {
    ResourceType.ENERGY: GameConstants.BASE_ENERGY_INCOME,
    ResourceType.MATERIALS: GameConstants.BASE_MATERIAL_INCOME,
    ResourceType.RESEARCH_POINTS: GameConstants.BASE_RESEARCH_INCOME
}

# Resource storage limits
var storage_limits: Dictionary = {
    ResourceType.ENERGY: GameConstants.MAX_ENERGY_STORAGE,
    ResourceType.MATERIALS: GameConstants.MAX_MATERIAL_STORAGE,
    ResourceType.RESEARCH_POINTS: GameConstants.MAX_RESEARCH_STORAGE
}

# Resource update timing
var resource_update_interval: float = GameConstants.RESOURCE_UPDATE_INTERVAL
var last_resource_update: float = 0.0

# Resource history for UI graphs
var resource_history: Dictionary = {}  # team_id -> Array[Dictionary]
var max_history_length: int = 100

# Signals
signal resource_changed(team_id: int, resource_type: ResourceType, amount: int)
signal resource_insufficient(team_id: int, resource_type: ResourceType, required: int, available: int)
signal resource_cap_reached(team_id: int, resource_type: ResourceType, amount: int)
signal resource_generation_changed(team_id: int, resource_type: ResourceType, rate: float)

func _ready() -> void:
    # Initialize team resources
    _initialize_team_resources()
    
    # Start resource processing
    set_process(true)
    
    # Add to resource manager group
    add_to_group("resource_managers")
    
    print("ResourceManager: Initialized")

func _initialize_team_resources() -> void:
    """Initialize resources for all teams"""
    
    for team_id in range(3):  # 0 = neutral, 1 = team1, 2 = team2
        team_resources[team_id] = {
            ResourceType.ENERGY: GameConstants.STARTING_ENERGY,
            ResourceType.MATERIALS: GameConstants.STARTING_MATERIALS,
            ResourceType.RESEARCH_POINTS: GameConstants.STARTING_RESEARCH
        }
        
        resource_generators[team_id] = []
        resource_consumers[team_id] = []
        resource_history[team_id] = []
        
        # Record initial resources
        _record_resource_snapshot(team_id)

func _process(delta: float) -> void:
    """Process resource generation and consumption"""
    
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_resource_update >= resource_update_interval:
        _update_all_resources()
        last_resource_update = current_time

func _update_all_resources() -> void:
    """Update resources for all teams"""
    
    for team_id in team_resources:
        if team_id == 0:  # Skip neutral team
            continue
        
        _update_team_resources(team_id)
        _record_resource_snapshot(team_id)

func _update_team_resources(team_id: int) -> void:
    """Update resources for a specific team"""
    
    var old_resources = team_resources[team_id].duplicate()
    
    # Calculate net generation/consumption
    var net_rates = _calculate_net_resource_rates(team_id)
    
    # Update resources based on rates
    for resource_type in net_rates:
        var rate_per_second = net_rates[resource_type]
        var change = rate_per_second * resource_update_interval
        
        var old_amount = team_resources[team_id][resource_type]
        var new_amount = old_amount + change
        
        # Apply storage limits
        var max_storage = storage_limits[resource_type]
        if new_amount > max_storage:
            new_amount = max_storage
            if old_amount < max_storage:
                resource_cap_reached.emit(team_id, resource_type, max_storage)
        
        # Don't go below zero
        if new_amount < 0:
            new_amount = 0
        
        # Update resource amount
        team_resources[team_id][resource_type] = int(new_amount)
        
        # Emit signal if changed
        if old_resources[resource_type] != team_resources[team_id][resource_type]:
            resource_changed.emit(team_id, resource_type, team_resources[team_id][resource_type])

func _calculate_net_resource_rates(team_id: int) -> Dictionary:
    """Calculate net resource generation/consumption rates for a team"""
    
    var net_rates = {}
    
    # Initialize with base income
    for resource_type in base_income_rates:
        net_rates[resource_type] = base_income_rates[resource_type]
    
    # Add generator contributions
    for generator in resource_generators[team_id]:
        if is_instance_valid(generator) and generator.is_active():
            var rates = generator.get_generation_rates()
            for resource_type in rates:
                if resource_type in net_rates:
                    net_rates[resource_type] += rates[resource_type]
                else:
                    net_rates[resource_type] = rates[resource_type]
    
    # Subtract consumer consumption
    for consumer in resource_consumers[team_id]:
        if is_instance_valid(consumer) and consumer.is_active():
            var rates = consumer.get_consumption_rates()
            for resource_type in rates:
                if resource_type in net_rates:
                    net_rates[resource_type] -= rates[resource_type]
                else:
                    net_rates[resource_type] = -rates[resource_type]
    
    return net_rates

func _record_resource_snapshot(team_id: int) -> void:
    """Record current resource state for history tracking"""
    
    var snapshot = {
        "timestamp": Time.get_ticks_msec() / 1000.0,
        "resources": team_resources[team_id].duplicate(),
        "generation_rates": _calculate_net_resource_rates(team_id)
    }
    
    resource_history[team_id].append(snapshot)
    
    # Limit history length
    if resource_history[team_id].size() > max_history_length:
        resource_history[team_id].pop_front()

# Public API - Resource Access
func get_team_resource(team_id: int, resource_type: ResourceType) -> int:
    """Get current amount of a specific resource for a team"""
    
    if team_id in team_resources and resource_type in team_resources[team_id]:
        return team_resources[team_id][resource_type]
    return 0

func get_team_resources(team_id: int) -> Dictionary:
    """Get all resources for a team"""
    
    if team_id in team_resources:
        return team_resources[team_id].duplicate()
    return {}

func has_sufficient_resources(team_id: int, costs: Dictionary) -> bool:
    """Check if team has sufficient resources for costs"""
    
    if not team_id in team_resources:
        return false
    
    for resource_type in costs:
        var required = costs[resource_type]
        var available = team_resources[team_id].get(resource_type, 0)
        
        if available < required:
            return false
    
    return true

func consume_resources(team_id: int, costs: Dictionary) -> bool:
    """Consume resources from a team's reserves"""
    
    if not has_sufficient_resources(team_id, costs):
        # Emit insufficient resource signals
        for resource_type in costs:
            var required = costs[resource_type]
            var available = team_resources[team_id].get(resource_type, 0)
            if available < required:
                resource_insufficient.emit(team_id, resource_type, required, available)
        return false
    
    # Consume resources
    for resource_type in costs:
        var cost = costs[resource_type]
        var old_amount = team_resources[team_id][resource_type]
        team_resources[team_id][resource_type] -= cost
        
        # Emit change signal
        resource_changed.emit(team_id, resource_type, team_resources[team_id][resource_type])
    
    return true

func add_resources(team_id: int, amounts: Dictionary) -> void:
    """Add resources to a team's reserves"""
    
    if not team_id in team_resources:
        return
    
    for resource_type in amounts:
        var amount = amounts[resource_type]
        var old_amount = team_resources[team_id][resource_type]
        var new_amount = old_amount + amount
        
        # Apply storage limits
        var max_storage = storage_limits[resource_type]
        if new_amount > max_storage:
            new_amount = max_storage
            resource_cap_reached.emit(team_id, resource_type, max_storage)
        
        team_resources[team_id][resource_type] = new_amount
        
        # Emit change signal
        resource_changed.emit(team_id, resource_type, team_resources[team_id][resource_type])

func set_team_resource(team_id: int, resource_type: ResourceType, amount: int) -> void:
    """Set a specific resource amount for a team (for testing/admin)"""
    
    if not team_id in team_resources:
        return
    
    # Apply storage limits
    var max_storage = storage_limits[resource_type]
    if amount > max_storage:
        amount = max_storage
    
    if amount < 0:
        amount = 0
    
    var old_amount = team_resources[team_id][resource_type]
    team_resources[team_id][resource_type] = amount
    
    # Emit change signal
    resource_changed.emit(team_id, resource_type, amount)

# Public API - Resource Generation/Consumption
func register_resource_generator(team_id: int, generator: Node) -> void:
    """Register a resource generator for a team"""
    
    if not team_id in resource_generators:
        resource_generators[team_id] = []
    
    if not generator in resource_generators[team_id]:
        resource_generators[team_id].append(generator)
        
        # Connect to generator signals if available
        if generator.has_signal("generation_changed"):
            generator.generation_changed.connect(_on_generation_changed.bind(team_id))
        
        print("ResourceManager: Registered generator for team %d" % team_id)

func unregister_resource_generator(team_id: int, generator: Node) -> void:
    """Unregister a resource generator for a team"""
    
    if team_id in resource_generators:
        resource_generators[team_id].erase(generator)
        
        # Disconnect signals
        if generator.has_signal("generation_changed"):
            if generator.generation_changed.is_connected(_on_generation_changed):
                generator.generation_changed.disconnect(_on_generation_changed)
        
        print("ResourceManager: Unregistered generator for team %d" % team_id)

func register_resource_consumer(team_id: int, consumer: Node) -> void:
    """Register a resource consumer for a team"""
    
    if not team_id in resource_consumers:
        resource_consumers[team_id] = []
    
    if not consumer in resource_consumers[team_id]:
        resource_consumers[team_id].append(consumer)
        
        # Connect to consumer signals if available
        if consumer.has_signal("consumption_changed"):
            consumer.consumption_changed.connect(_on_consumption_changed.bind(team_id))
        
        print("ResourceManager: Registered consumer for team %d" % team_id)

func unregister_resource_consumer(team_id: int, consumer: Node) -> void:
    """Unregister a resource consumer for a team"""
    
    if team_id in resource_consumers:
        resource_consumers[team_id].erase(consumer)
        
        # Disconnect signals
        if consumer.has_signal("consumption_changed"):
            if consumer.consumption_changed.is_connected(_on_consumption_changed):
                consumer.consumption_changed.disconnect(_on_consumption_changed)
        
        print("ResourceManager: Unregistered consumer for team %d" % team_id)

# Public API - Resource Rates and Statistics
func get_team_resource_rates(team_id: int) -> Dictionary:
    """Get current resource generation/consumption rates for a team"""
    
    return _calculate_net_resource_rates(team_id)

func get_team_resource_history(team_id: int) -> Array:
    """Get resource history for a team"""
    
    if team_id in resource_history:
        return resource_history[team_id].duplicate()
    return []

func get_team_generator_count(team_id: int) -> int:
    """Get number of active generators for a team"""
    
    if not team_id in resource_generators:
        return 0
    
    var count = 0
    for generator in resource_generators[team_id]:
        if is_instance_valid(generator) and generator.is_active():
            count += 1
    
    return count

func get_team_consumer_count(team_id: int) -> int:
    """Get number of active consumers for a team"""
    
    if not team_id in resource_consumers:
        return 0
    
    var count = 0
    for consumer in resource_consumers[team_id]:
        if is_instance_valid(consumer) and consumer.is_active():
            count += 1
    
    return count

func get_resource_efficiency(team_id: int, resource_type: ResourceType) -> float:
    """Get resource efficiency (generation / consumption) for a team"""
    
    var rates = _calculate_net_resource_rates(team_id)
    var net_rate = rates.get(resource_type, 0.0)
    
    # Calculate separate generation and consumption
    var generation = base_income_rates.get(resource_type, 0.0)
    var consumption = 0.0
    
    # Add generator contributions
    for generator in resource_generators[team_id]:
        if is_instance_valid(generator) and generator.is_active():
            var gen_rates = generator.get_generation_rates()
            generation += gen_rates.get(resource_type, 0.0)
    
    # Add consumer consumption
    for consumer in resource_consumers[team_id]:
        if is_instance_valid(consumer) and consumer.is_active():
            var cons_rates = consumer.get_consumption_rates()
            consumption += cons_rates.get(resource_type, 0.0)
    
    # Calculate efficiency
    if consumption > 0:
        return generation / consumption
    elif generation > 0:
        return float('inf')  # Infinite efficiency (no consumption)
    else:
        return 1.0  # Neutral efficiency

# Public API - System Management
func reset_team_resources(team_id: int) -> void:
    """Reset team resources to starting values"""
    
    if team_id in team_resources:
        team_resources[team_id] = {
            ResourceType.ENERGY: GameConstants.STARTING_ENERGY,
            ResourceType.MATERIALS: GameConstants.STARTING_MATERIALS,
            ResourceType.RESEARCH_POINTS: GameConstants.STARTING_RESEARCH
        }
        
        # Clear history
        resource_history[team_id].clear()
        _record_resource_snapshot(team_id)
        
        # Emit change signals
        for resource_type in team_resources[team_id]:
            resource_changed.emit(team_id, resource_type, team_resources[team_id][resource_type])

func get_system_statistics() -> Dictionary:
    """Get system-wide resource statistics"""
    
    var stats = {
        "total_teams": team_resources.size(),
        "total_generators": 0,
        "total_consumers": 0,
        "team_resources": team_resources.duplicate(),
        "resource_rates": {},
        "resource_efficiency": {}
    }
    
    # Calculate totals
    for team_id in resource_generators:
        stats.total_generators += get_team_generator_count(team_id)
    
    for team_id in resource_consumers:
        stats.total_consumers += get_team_consumer_count(team_id)
    
    # Calculate rates and efficiency for each team
    for team_id in team_resources:
        if team_id == 0:  # Skip neutral
            continue
        
        stats.resource_rates[team_id] = get_team_resource_rates(team_id)
        stats.resource_efficiency[team_id] = {}
        
        for resource_type in [ResourceType.ENERGY, ResourceType.MATERIALS, ResourceType.RESEARCH_POINTS]:
            stats.resource_efficiency[team_id][resource_type] = get_resource_efficiency(team_id, resource_type)
    
    return stats

func get_all_resource_data() -> Dictionary:
    """Get all resource data for UI/networking"""
    
    var data = {
        "team_resources": team_resources.duplicate(),
        "resource_rates": {},
        "resource_history": {},
        "storage_limits": storage_limits.duplicate(),
        "generator_counts": {},
        "consumer_counts": {}
    }
    
    for team_id in team_resources:
        if team_id == 0:  # Skip neutral
            continue
        
        data.resource_rates[team_id] = get_team_resource_rates(team_id)
        data.resource_history[team_id] = get_team_resource_history(team_id)
        data.generator_counts[team_id] = get_team_generator_count(team_id)
        data.consumer_counts[team_id] = get_team_consumer_count(team_id)
    
    return data

# Signal handlers
func _on_generation_changed(team_id: int, resource_type: ResourceType, new_rate: float) -> void:
    """Handle resource generation rate change"""
    
    resource_generation_changed.emit(team_id, resource_type, new_rate)

func _on_consumption_changed(team_id: int, resource_type: ResourceType, new_rate: float) -> void:
    """Handle resource consumption rate change"""
    
    resource_generation_changed.emit(team_id, resource_type, -new_rate)

# Utility functions
func get_resource_type_name(resource_type: ResourceType) -> String:
    """Get human-readable name for resource type"""
    
    match resource_type:
        ResourceType.ENERGY:
            return "Energy"
        ResourceType.MATERIALS:
            return "Materials"
        ResourceType.RESEARCH_POINTS:
            return "Research Points"
        _:
            return "Unknown"

func get_resource_type_icon(resource_type: ResourceType) -> String:
    """Get icon path for resource type"""
    
    match resource_type:
        ResourceType.ENERGY:
            return "res://assets/icons/energy.png"
        ResourceType.MATERIALS:
            return "res://assets/icons/materials.png"
        ResourceType.RESEARCH_POINTS:
            return "res://assets/icons/research.png"
        _:
            return "" 