# TestResourceManagement.gd
extends Node

# Test script for resource management system
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const ResourceManager = preload("res://scripts/gameplay/resource_manager.gd")
const Building = preload("res://scripts/buildings/building.gd")

var resource_manager: ResourceManager = null
var test_buildings: Array = []

func _ready() -> void:
    # Create resource manager
    resource_manager = ResourceManager.new()
    resource_manager.name = "ResourceManager"
    add_child(resource_manager)
    
    # Wait a bit for the scene to be ready
    await get_tree().process_frame
    
    # Connect signals
    _connect_signals()
    
    print("TestResourceManagement: Test script initialized")

func _connect_signals() -> void:
    """Connect to resource manager signals"""
    
    resource_manager.resource_changed.connect(_on_resource_changed)
    resource_manager.resource_insufficient.connect(_on_resource_insufficient)
    resource_manager.resource_cap_reached.connect(_on_resource_cap_reached)
    resource_manager.resource_generation_changed.connect(_on_resource_generation_changed)
    
    print("TestResourceManagement: Signals connected")

func _input(event: InputEvent) -> void:
    """Handle input for testing"""
    
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1:
                test_initial_resources()
            KEY_2:
                test_resource_consumption()
            KEY_3:
                test_resource_generation()
            KEY_4:
                test_resource_limits()
            KEY_5:
                test_building_integration()
            KEY_6:
                test_construction_costs()
            KEY_7:
                test_resource_rates()
            KEY_8:
                test_resource_history()
            KEY_9:
                test_resource_efficiency()
            KEY_0:
                show_system_statistics()
            KEY_MINUS:
                test_resource_recovery()
            KEY_EQUAL:
                test_team_comparison()
            KEY_R:
                reset_test_scenario()
            KEY_H:
                print_help()

func test_initial_resources() -> void:
    """Test initial resource allocation"""
    
    print("TestResourceManagement: Initial Resources Test")
    
    for team_id in [1, 2]:
        var resources = resource_manager.get_team_resources(team_id)
        print("  Team %d resources:" % team_id)
        
        var ResourceType = resource_manager.ResourceType
        for resource_type in [ResourceType.ENERGY, ResourceType.MATERIALS, ResourceType.RESEARCH_POINTS]:
            var amount = resources.get(resource_type, 0)
            var type_name = resource_manager.get_resource_type_name(resource_type)
            print("    %s: %d" % [type_name, amount])
    
    print("TestResourceManagement: Initial resources test completed")

func test_resource_consumption() -> void:
    """Test resource consumption"""
    
    print("TestResourceManagement: Resource Consumption Test")
    
    var team_id = 1
    var ResourceType = resource_manager.ResourceType
    
    # Test affordable consumption
    var affordable_cost = {
        ResourceType.ENERGY: 100,
        ResourceType.MATERIALS: 50
    }
    
    var can_afford = resource_manager.has_sufficient_resources(team_id, affordable_cost)
    print("  Can afford cost %s: %s" % [affordable_cost, can_afford])
    
    if can_afford:
        var success = resource_manager.consume_resources(team_id, affordable_cost)
        print("  Consumption successful: %s" % success)
        
        # Show remaining resources
        var remaining = resource_manager.get_team_resources(team_id)
        print("  Remaining resources: %s" % remaining)
    
    # Test unaffordable consumption
    var expensive_cost = {
        ResourceType.ENERGY: 10000,
        ResourceType.MATERIALS: 5000
    }
    
    var can_afford_expensive = resource_manager.has_sufficient_resources(team_id, expensive_cost)
    print("  Can afford expensive cost %s: %s" % [expensive_cost, can_afford_expensive])
    
    if not can_afford_expensive:
        var success = resource_manager.consume_resources(team_id, expensive_cost)
        print("  Expensive consumption successful: %s" % success)
    
    print("TestResourceManagement: Resource consumption test completed")

func test_resource_generation() -> void:
    """Test resource generation by adding generators"""
    
    print("TestResourceManagement: Resource Generation Test")
    
    var team_id = 1
    
    # Create test power spire
    var power_spire = Building.new()
    power_spire.name = "TestPowerSpire"
    power_spire.building_type = Building.BuildingType.POWER_SPIRE
    power_spire.team_id = team_id
    power_spire.is_constructed = true
    add_child(power_spire)
    
    # Register with resource manager
    resource_manager.register_resource_generator(team_id, power_spire)
    test_buildings.append(power_spire)
    
    # Show generation rates
    var rates = resource_manager.get_team_resource_rates(team_id)
    print("  Team %d generation rates: %s" % [team_id, rates])
    
    # Show generator count
    var generator_count = resource_manager.get_team_generator_count(team_id)
    print("  Team %d active generators: %d" % [team_id, generator_count])
    
    print("TestResourceManagement: Resource generation test completed")

func test_resource_limits() -> void:
    """Test resource storage limits"""
    
    print("TestResourceManagement: Resource Limits Test")
    
    var team_id = 1
    var ResourceType = resource_manager.ResourceType
    
    # Add massive amounts to test limits
    var massive_addition = {
        ResourceType.ENERGY: 10000,
        ResourceType.MATERIALS: 5000,
        ResourceType.RESEARCH_POINTS: 2000
    }
    
    var resources_before = resource_manager.get_team_resources(team_id)
    print("  Resources before addition: %s" % resources_before)
    
    resource_manager.add_resources(team_id, massive_addition)
    
    var resources_after = resource_manager.get_team_resources(team_id)
    print("  Resources after addition: %s" % resources_after)
    
    # Check if limits were applied
    if resources_after[ResourceType.ENERGY] == GameConstants.MAX_ENERGY_STORAGE:
        print("  Energy storage limit enforced correctly")
    
    if resources_after[ResourceType.MATERIALS] == GameConstants.MAX_MATERIAL_STORAGE:
        print("  Material storage limit enforced correctly")
    
    print("TestResourceManagement: Resource limits test completed")

func test_building_integration() -> void:
    """Test building integration with resource system"""
    
    print("TestResourceManagement: Building Integration Test")
    
    var team_id = 1
    var ResourceType = resource_manager.ResourceType
    
    # Create different building types
    var buildings_to_test = [
        {"type": Building.BuildingType.POWER_SPIRE, "name": "PowerSpire"},
        {"type": Building.BuildingType.DEFENSE_TOWER, "name": "DefenseTower"},
        {"type": Building.BuildingType.RELAY_PAD, "name": "RelayPad"}
    ]
    
    for building_data in buildings_to_test:
        var building = Building.new()
        building.name = "Test" + building_data.name
        building.building_type = building_data.type
        building.team_id = team_id
        building.is_constructed = true
        add_child(building)
        
        # Test resource methods
        var generation_rates = building.get_generation_rates()
        var consumption_rates = building.get_consumption_rates()
        var construction_cost = building.get_construction_cost()
        var can_afford = building.can_afford_construction(team_id)
        
        print("  %s:" % building_data.name)
        print("    Generation rates: %s" % generation_rates)
        print("    Consumption rates: %s" % consumption_rates)
        print("    Construction cost: %s" % construction_cost)
        print("    Can afford construction: %s" % can_afford)
        
        test_buildings.append(building)
    
    print("TestResourceManagement: Building integration test completed")

func test_construction_costs() -> void:
    """Test construction cost validation and consumption"""
    
    print("TestResourceManagement: Construction Costs Test")
    
    var team_id = 1
    
    # Test each building type
    var building_types = [
        Building.BuildingType.POWER_SPIRE,
        Building.BuildingType.DEFENSE_TOWER,
        Building.BuildingType.RELAY_PAD
    ]
    
    for building_type in building_types:
        var building = Building.new()
        building.building_type = building_type
        building.team_id = team_id
        
        var cost = building.get_construction_cost()
        var can_afford = building.can_afford_construction(team_id)
        
        print("  %s:" % building._get_building_type_string(building_type))
        print("    Cost: %s" % cost)
        print("    Can afford: %s" % can_afford)
        
        if can_afford:
            var resources_before = resource_manager.get_team_resources(team_id)
            var success = building.consume_construction_cost(team_id)
            var resources_after = resource_manager.get_team_resources(team_id)
            
            print("    Construction cost consumed: %s" % success)
            print("    Resources before: %s" % resources_before)
            print("    Resources after: %s" % resources_after)
        
        building.queue_free()
    
    print("TestResourceManagement: Construction costs test completed")

func test_resource_rates() -> void:
    """Test resource generation and consumption rates"""
    
    print("TestResourceManagement: Resource Rates Test")
    
    for team_id in [1, 2]:
        var rates = resource_manager.get_team_resource_rates(team_id)
        var generator_count = resource_manager.get_team_generator_count(team_id)
        var consumer_count = resource_manager.get_team_consumer_count(team_id)
        
        print("  Team %d:" % team_id)
        print("    Resource rates: %s" % rates)
        print("    Generators: %d" % generator_count)
        print("    Consumers: %d" % consumer_count)
        
        # Test efficiency
        var ResourceType = resource_manager.ResourceType
        for resource_type in [ResourceType.ENERGY, ResourceType.MATERIALS, ResourceType.RESEARCH_POINTS]:
            var efficiency = resource_manager.get_resource_efficiency(team_id, resource_type)
            var type_name = resource_manager.get_resource_type_name(resource_type)
            print("    %s efficiency: %.2f" % [type_name, efficiency])
    
    print("TestResourceManagement: Resource rates test completed")

func test_resource_history() -> void:
    """Test resource history tracking"""
    
    print("TestResourceManagement: Resource History Test")
    
    for team_id in [1, 2]:
        var history = resource_manager.get_team_resource_history(team_id)
        print("  Team %d history length: %d" % [team_id, history.size()])
        
        if history.size() > 0:
            var latest = history[-1]
            print("    Latest snapshot: %s" % latest)
            
            if history.size() > 1:
                var previous = history[-2]
                print("    Previous snapshot: %s" % previous)
    
    print("TestResourceManagement: Resource history test completed")

func test_resource_efficiency() -> void:
    """Test resource efficiency calculations"""
    
    print("TestResourceManagement: Resource Efficiency Test")
    
    var team_id = 1
    var ResourceType = resource_manager.ResourceType
    
    # Test different scenarios
    var scenarios = [
        "Base (no buildings)",
        "With generators",
        "With consumers",
        "Mixed generators and consumers"
    ]
    
    for i in range(scenarios.size()):
        print("  Scenario %d: %s" % [i + 1, scenarios[i]])
        
        for resource_type in [ResourceType.ENERGY, ResourceType.MATERIALS, ResourceType.RESEARCH_POINTS]:
            var efficiency = resource_manager.get_resource_efficiency(team_id, resource_type)
            var type_name = resource_manager.get_resource_type_name(resource_type)
            print("    %s efficiency: %.2f" % [type_name, efficiency])
        
        # Add a building for the next scenario
        if i < scenarios.size() - 1:
            var building = Building.new()
            building.name = "TestBuilding%d" % i
            building.team_id = team_id
            building.is_constructed = true
            
            if i == 0:  # Add generator
                building.building_type = Building.BuildingType.POWER_SPIRE
                resource_manager.register_resource_generator(team_id, building)
            elif i == 1:  # Add consumer
                building.building_type = Building.BuildingType.DEFENSE_TOWER
                resource_manager.register_resource_consumer(team_id, building)
            
            add_child(building)
            test_buildings.append(building)
    
    print("TestResourceManagement: Resource efficiency test completed")

func test_resource_recovery() -> void:
    """Test resource recovery to starting values"""
    
    print("TestResourceManagement: Resource Recovery Test")
    
    var team_id = 1
    
    # Show current resources
    var current_resources = resource_manager.get_team_resources(team_id)
    print("  Current resources: %s" % current_resources)
    
    # Reset to starting values
    resource_manager.reset_team_resources(team_id)
    
    # Show resources after reset
    var reset_resources = resource_manager.get_team_resources(team_id)
    print("  Resources after reset: %s" % reset_resources)
    
    # Verify they match starting values
    var ResourceType = resource_manager.ResourceType
    var expected = {
        ResourceType.ENERGY: GameConstants.STARTING_ENERGY,
        ResourceType.MATERIALS: GameConstants.STARTING_MATERIALS,
        ResourceType.RESEARCH_POINTS: GameConstants.STARTING_RESEARCH
    }
    
    var matches = true
    for resource_type in expected:
        if reset_resources[resource_type] != expected[resource_type]:
            matches = false
            break
    
    print("  Resources match starting values: %s" % matches)
    
    print("TestResourceManagement: Resource recovery test completed")

func test_team_comparison() -> void:
    """Test resource comparison between teams"""
    
    print("TestResourceManagement: Team Comparison Test")
    
    for team_id in [1, 2]:
        var resources = resource_manager.get_team_resources(team_id)
        var rates = resource_manager.get_team_resource_rates(team_id)
        var generators = resource_manager.get_team_generator_count(team_id)
        var consumers = resource_manager.get_team_consumer_count(team_id)
        
        print("  Team %d:" % team_id)
        print("    Resources: %s" % resources)
        print("    Rates: %s" % rates)
        print("    Generators: %d, Consumers: %d" % [generators, consumers])
        
        # Calculate total resource value
        var total_value = 0
        for resource_type in resources:
            total_value += resources[resource_type]
        print("    Total resource value: %d" % total_value)
    
    print("TestResourceManagement: Team comparison test completed")

func show_system_statistics() -> void:
    """Show comprehensive system statistics"""
    
    var stats = resource_manager.get_system_statistics()
    print("TestResourceManagement: System Statistics")
    print("  Total teams: %d" % stats.total_teams)
    print("  Total generators: %d" % stats.total_generators)
    print("  Total consumers: %d" % stats.total_consumers)
    
    print("  Team resources:")
    for team_id in stats.team_resources:
        if team_id == 0:  # Skip neutral
            continue
        print("    Team %d: %s" % [team_id, stats.team_resources[team_id]])
    
    print("  Resource rates:")
    for team_id in stats.resource_rates:
        print("    Team %d: %s" % [team_id, stats.resource_rates[team_id]])
    
    print("  Resource efficiency:")
    for team_id in stats.resource_efficiency:
        print("    Team %d: %s" % [team_id, stats.resource_efficiency[team_id]])

func reset_test_scenario() -> void:
    """Reset to clean test scenario"""
    
    print("TestResourceManagement: Resetting test scenario")
    
    # Clean up test buildings
    for building in test_buildings:
        if is_instance_valid(building):
            building.queue_free()
    test_buildings.clear()
    
    # Reset all team resources
    for team_id in [1, 2]:
        resource_manager.reset_team_resources(team_id)
    
    print("  Test scenario reset completed")

# Signal handlers
func _on_resource_changed(team_id: int, resource_type: int, amount: int) -> void:
    """Handle resource changed signal"""
    var type_name = resource_manager.get_resource_type_name(resource_type)
    print("TestResourceManagement: Team %d %s changed to %d" % [team_id, type_name, amount])

func _on_resource_insufficient(team_id: int, resource_type: int, required: int, available: int) -> void:
    """Handle resource insufficient signal"""
    var type_name = resource_manager.get_resource_type_name(resource_type)
    print("TestResourceManagement: Team %d insufficient %s (required: %d, available: %d)" % [team_id, type_name, required, available])

func _on_resource_cap_reached(team_id: int, resource_type: int, amount: int) -> void:
    """Handle resource cap reached signal"""
    var type_name = resource_manager.get_resource_type_name(resource_type)
    print("TestResourceManagement: Team %d %s storage cap reached (%d)" % [team_id, type_name, amount])

func _on_resource_generation_changed(team_id: int, resource_type: int, new_rate: float) -> void:
    """Handle resource generation changed signal"""
    var type_name = resource_manager.get_resource_type_name(resource_type)
    print("TestResourceManagement: Team %d %s generation rate changed to %.2f" % [team_id, type_name, new_rate])

func print_help() -> void:
    """Print help information"""
    
    print("TestResourceManagement: Number key shortcuts:")
    print("  1 - Test initial resources")
    print("  2 - Test resource consumption")
    print("  3 - Test resource generation")
    print("  4 - Test resource limits")
    print("  5 - Test building integration")
    print("  6 - Test construction costs")
    print("  7 - Test resource rates")
    print("  8 - Test resource history")
    print("  9 - Test resource efficiency")
    print("  0 - Show system statistics")
    print("  - - Test resource recovery")
    print("  = - Test team comparison")
    print("  R - Reset test scenario")
    print("  H - Show this help")

func _enter_tree() -> void:
    """Called when entering the tree"""
    
    # Wait a bit then print help
    await get_tree().create_timer(1.0).timeout
    print_help() 