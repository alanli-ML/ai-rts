# Building.gd - Base building class
class_name Building
extends StaticBody3D

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Building types enum (local)
enum BuildingType {
    POWER_SPIRE,
    DEFENSE_TOWER,
    RELAY_PAD
}

# Building identification
@export var building_id: String = ""
@export var building_type: BuildingType = BuildingType.POWER_SPIRE
@export var team_id: int = 1
@export var owner_player_id: String = ""

# Building stats
var max_health: float = 100.0
var current_health: float = 100.0
var construction_time: float = 5.0
var construction_cost: int = 100

# Construction state
var construction_progress: float = 0.0
var is_constructed: bool = false
var is_under_construction: bool = false
var construction_start_time: float = 0.0

# Building functionality
var power_generation: float = 0.0
var power_consumption: float = 0.0
var is_active: bool = true
var is_destroyed: bool = false

# Position and placement
var grid_position: Vector2i = Vector2i.ZERO
var placement_radius: float = GameConstants.BUILDING_PLACEMENT_RADIUS
var can_be_placed: bool = true

# Visual and audio
var construction_effect: Node3D = null
var building_mesh: MeshInstance3D = null
var health_bar: ProgressBar = null
var selection_indicator: MeshInstance3D = null

# Signals
signal building_constructed(building_id: String)
signal building_destroyed(building_id: String)
signal building_selected(building: Building)
signal building_deselected(building: Building)
signal building_health_changed(building_id: String, health: float)
signal building_activated(building_id: String)
signal building_deactivated(building_id: String)
signal power_generation_changed(building_id: String, power: float)

func _ready() -> void:
    # Generate unique ID if not set
    if building_id.is_empty():
        building_id = "building_" + str(randi())
    
    # Create child nodes
    _create_child_nodes()
    
    # Load building stats
    _load_building_stats()
    
    # Setup collision
    _setup_collision()
    
    # Setup visual
    _setup_visual()
    
    # Add to buildings group
    add_to_group("buildings")
    
    # Register with game systems
    _register_building()
    
    print("Building %s (%s) initialized for team %d" % [building_id, _get_building_type_string(building_type), team_id])

func _create_child_nodes() -> void:
    """Create child nodes for the building"""
    
    # Create building mesh
    building_mesh = MeshInstance3D.new()
    building_mesh.name = "BuildingMesh"
    add_child(building_mesh)
    
    # Create selection indicator
    selection_indicator = MeshInstance3D.new()
    selection_indicator.name = "SelectionIndicator"
    selection_indicator.mesh = SphereMesh.new()
    selection_indicator.mesh.radius = placement_radius * 1.2
    selection_indicator.mesh.height = 0.1
    selection_indicator.position.y = -0.5
    selection_indicator.visible = false
    var selection_material = StandardMaterial3D.new()
    selection_material.albedo_color = Color.GREEN
    selection_material.flags_transparent = true
    selection_material.albedo_color.a = 0.3
    selection_indicator.material_override = selection_material
    add_child(selection_indicator)

func _load_building_stats() -> void:
    """Load building stats from GameConstants"""
    
    var building_config = GameConstants.get_building_config(_get_building_type_string(building_type))
    if building_config.is_empty():
        print("No config found for building type: %s, using defaults" % _get_building_type_string(building_type))
        building_config = GameConstants.get_building_config("power_spire")  # Fallback
    
    if not building_config.is_empty():
        max_health = building_config.get("health", 100.0)
        current_health = max_health
        construction_time = building_config.get("construction_time", 5.0)
        construction_cost = building_config.get("cost", 100)
        power_generation = building_config.get("power_generation", 0.0)
        power_consumption = building_config.get("power_consumption", 0.0)

func _setup_collision() -> void:
    """Setup collision shape for the building"""
    
    var collision_shape = CollisionShape3D.new()
    collision_shape.name = "CollisionShape3D"
    
    # Create box collision based on building type
    var shape = BoxShape3D.new()
    match building_type:
        BuildingType.POWER_SPIRE:
            shape.size = Vector3(3, 4, 3)
        BuildingType.DEFENSE_TOWER:
            shape.size = Vector3(2, 5, 2)
        BuildingType.RELAY_PAD:
            shape.size = Vector3(4, 1, 4)
        _:
            shape.size = Vector3(2, 2, 2)
    
    collision_shape.shape = shape
    add_child(collision_shape)

func _setup_visual() -> void:
    """Setup visual representation of the building"""
    
    if building_mesh:
        # Create appropriate mesh based on building type
        match building_type:
            BuildingType.POWER_SPIRE:
                building_mesh.mesh = _create_power_spire_mesh()
            BuildingType.DEFENSE_TOWER:
                building_mesh.mesh = _create_defense_tower_mesh()
            BuildingType.RELAY_PAD:
                building_mesh.mesh = _create_relay_pad_mesh()
            _:
                building_mesh.mesh = BoxMesh.new()
        
        # Apply team color
        var material = StandardMaterial3D.new()
        material.albedo_color = Color.BLUE if team_id == 1 else Color.RED
        material.metallic = 0.3
        material.roughness = 0.7
        building_mesh.material_override = material

func _create_power_spire_mesh() -> Mesh:
    """Create mesh for power spire"""
    var mesh = CylinderMesh.new()
    mesh.top_radius = 0.5
    mesh.bottom_radius = 1.0
    mesh.height = 4.0
    mesh.rings = 3
    return mesh

func _create_defense_tower_mesh() -> Mesh:
    """Create mesh for defense tower"""
    var mesh = CylinderMesh.new()
    mesh.top_radius = 0.8
    mesh.bottom_radius = 1.2
    mesh.height = 5.0
    mesh.rings = 4
    return mesh

func _create_relay_pad_mesh() -> Mesh:
    """Create mesh for relay pad"""
    var mesh = CylinderMesh.new()
    mesh.top_radius = 2.0
    mesh.bottom_radius = 2.0
    mesh.height = 1.0
    mesh.rings = 1
    return mesh

func _register_building() -> void:
    """Register building with game systems"""
    
    # Register with EventBus if available
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        if event_bus.has_signal("building_spawned"):
            event_bus.building_spawned.emit(self)
    
    # Register with resource manager
    _register_with_resource_manager()

func _register_with_resource_manager() -> void:
    """Register building with resource manager based on type"""
    
    # Find resource manager
    var resource_manager = get_tree().get_first_node_in_group("resource_managers")
    if not resource_manager:
        return
    
    # Register as generator or consumer based on building type
    match building_type:
        BuildingType.POWER_SPIRE:
            resource_manager.register_resource_generator(team_id, self)
        BuildingType.DEFENSE_TOWER:
            resource_manager.register_resource_consumer(team_id, self)
        BuildingType.RELAY_PAD:
            resource_manager.register_resource_consumer(team_id, self)
    
    print("Building %s registered with resource manager" % building_id)

func start_construction() -> void:
    """Start building construction"""
    
    if is_under_construction or is_constructed:
        return
    
    is_under_construction = true
    construction_progress = 0.0
    construction_start_time = Time.get_ticks_msec() / 1000.0
    
    # Set initial construction visual state
    _update_construction_visual()
    
    print("Building %s construction started" % building_id)

func update_construction(delta: float) -> void:
    """Update construction progress"""
    
    if not is_under_construction or is_constructed:
        return
    
    # Update construction progress
    construction_progress += delta / construction_time
    
    # Update visual
    _update_construction_visual()
    
    # Check if construction is complete
    if construction_progress >= 1.0:
        _complete_construction()

func _complete_construction() -> void:
    """Complete building construction"""
    
    is_under_construction = false
    is_constructed = true
    construction_progress = 1.0
    
    # Activate building functionality
    _activate_building()
    
    # Update visual to final state
    _update_construction_visual()
    
    building_constructed.emit(building_id)
    print("Building %s construction completed" % building_id)

func _activate_building() -> void:
    """Activate building functionality"""
    
    is_active = true
    
    # Start power generation if applicable
    if power_generation > 0:
        _start_power_generation()
    
    # Start building-specific functionality
    _start_building_functionality()
    
    building_activated.emit(building_id)

func _start_power_generation() -> void:
    """Start power generation"""
    
    if power_generation > 0:
        power_generation_changed.emit(building_id, power_generation)
        print("Building %s generating %.1f power" % [building_id, power_generation])

func _start_building_functionality() -> void:
    """Start building-specific functionality (to be overridden by subclasses)"""
    
    match building_type:
        BuildingType.POWER_SPIRE:
            _start_power_spire_functionality()
        BuildingType.DEFENSE_TOWER:
            _start_defense_tower_functionality()
        BuildingType.RELAY_PAD:
            _start_relay_pad_functionality()

func _start_power_spire_functionality() -> void:
    """Start power spire functionality"""
    # Power spire mainly generates power (already handled in _start_power_generation)
    pass

func _start_defense_tower_functionality() -> void:
    """Start defense tower functionality"""
    # Defense towers will have targeting and attack systems
    pass

func _start_relay_pad_functionality() -> void:
    """Start relay pad functionality"""
    # Relay pads will have teleportation systems
    pass

func _update_construction_visual() -> void:
    """Update construction visual state"""
    
    if building_mesh:
        # Fade building in as construction progresses
        var alpha = 0.3 + (construction_progress * 0.7)
        building_mesh.material_override.albedo_color.a = alpha
        
        # Scale building up as construction progresses
        var scale = 0.5 + (construction_progress * 0.5)
        building_mesh.scale = Vector3(scale, scale, scale)

func take_damage(damage: float) -> void:
    """Take damage and handle destruction"""
    
    if is_destroyed:
        return
    
    current_health -= damage
    current_health = max(0, current_health)
    
    building_health_changed.emit(building_id, current_health)
    
    if current_health <= 0:
        _destroy_building()

func _destroy_building() -> void:
    """Destroy the building"""
    
    is_destroyed = true
    is_active = false
    
    # Stop power generation
    if power_generation > 0:
        power_generation_changed.emit(building_id, 0.0)
    
    # Visual effects for destruction
    _show_destruction_effects()
    
    building_destroyed.emit(building_id)
    print("Building %s destroyed" % building_id)
    
    # Remove from scene after delay
    await get_tree().create_timer(2.0).timeout
    queue_free()

func _show_destruction_effects() -> void:
    """Show destruction visual effects"""
    
    if building_mesh:
        # Create destruction tween
        var tween = create_tween()
        tween.tween_property(building_mesh, "modulate", Color.RED, 0.5)
        tween.parallel().tween_property(building_mesh, "scale", Vector3(1.2, 1.2, 1.2), 0.5)
        tween.tween_property(building_mesh, "modulate", Color.TRANSPARENT, 1.0)
        tween.parallel().tween_property(building_mesh, "scale", Vector3.ZERO, 1.0)

func select() -> void:
    """Select this building"""
    
    if selection_indicator:
        selection_indicator.visible = true
    
    building_selected.emit(self)

func deselect() -> void:
    """Deselect this building"""
    
    if selection_indicator:
        selection_indicator.visible = false
    
    building_deselected.emit(self)

func can_place_at(position: Vector3) -> bool:
    """Check if building can be placed at position"""
    
    # Check for overlapping buildings
    var space_state = get_world_3d().direct_space_state
    var query = PhysicsShapeQueryParameters3D.new()
    query.shape = SphereShape3D.new()
    query.shape.radius = placement_radius
    query.transform.origin = position
    query.collision_mask = 0b10  # Buildings layer
    
    var result = space_state.intersect_shape(query)
    
    return result.is_empty()

# Getters
func get_building_id() -> String:
    return building_id

func get_building_type() -> BuildingType:
    return building_type

func get_team_id() -> int:
    return team_id

func get_health_percentage() -> float:
    return current_health / max_health if max_health > 0 else 0.0

func get_construction_progress() -> float:
    return construction_progress

func is_construction_complete() -> bool:
    return is_constructed

func is_building_active() -> bool:
    return is_active and not is_destroyed

func get_power_generation() -> float:
    return power_generation if is_active else 0.0

func get_power_consumption() -> float:
    return power_consumption if is_active else 0.0

func get_construction_cost() -> int:
    return construction_cost

func get_building_data() -> Dictionary:
    """Get building data for networking"""
    
    return {
        "id": building_id,
        "type": _get_building_type_string(building_type),
        "team_id": team_id,
        "position": [global_position.x, global_position.y, global_position.z],
        "rotation": rotation.y,
        "health": current_health,
        "max_health": max_health,
        "construction_progress": construction_progress,
        "is_constructed": is_constructed,
        "is_active": is_active,
        "power_generation": get_power_generation(),
        "power_consumption": get_power_consumption()
    }

func get_building_info() -> Dictionary:
    """Get building information for UI"""
    
    return {
        "id": building_id,
        "type": _get_building_type_string(building_type),
        "name": _get_building_name(),
        "description": _get_building_description(),
        "health": current_health,
        "max_health": max_health,
        "construction_progress": construction_progress,
        "is_constructed": is_constructed,
        "is_active": is_active,
        "power_generation": get_power_generation(),
        "power_consumption": get_power_consumption(),
        "construction_cost": construction_cost
    }

func _get_building_name() -> String:
    """Get display name for building"""
    
    match building_type:
        BuildingType.POWER_SPIRE:
            return "Power Spire"
        BuildingType.DEFENSE_TOWER:
            return "Defense Tower"
        BuildingType.RELAY_PAD:
            return "Relay Pad"
        _:
            return "Unknown Building"

func _get_building_description() -> String:
    """Get description for building"""
    
    match building_type:
        BuildingType.POWER_SPIRE:
            return "Generates energy for your team"
        BuildingType.DEFENSE_TOWER:
            return "Automatically attacks nearby enemies"
        BuildingType.RELAY_PAD:
            return "Allows units to teleport across the map"
        _:
            return "A building structure"

func _get_building_type_string(type: BuildingType) -> String:
    """Convert BuildingType enum to string"""
    
    match type:
        BuildingType.POWER_SPIRE:
            return "power_spire"
        BuildingType.DEFENSE_TOWER:
            return "defense_tower"
        BuildingType.RELAY_PAD:
            return "relay_pad"
        _:
            return "unknown"

func server_update(delta: float) -> void:
    """Server-side update (called by game state)"""
    
    # Update construction if in progress
    if is_under_construction:
        update_construction(delta)
    
    # Update building-specific logic
    if is_active and is_constructed:
        _update_building_logic(delta)

func _update_building_logic(delta: float) -> void:
    """Update building-specific logic (to be overridden by subclasses)"""
    
    match building_type:
        BuildingType.DEFENSE_TOWER:
            _update_defense_tower_logic(delta)
        BuildingType.RELAY_PAD:
            _update_relay_pad_logic(delta)

func _update_defense_tower_logic(delta: float) -> void:
    """Update defense tower logic"""
    # Defense tower targeting and attack logic
    pass

func _update_relay_pad_logic(delta: float) -> void:
    """Update relay pad logic"""
    # Relay pad teleportation logic
    pass 

# Resource system integration
func is_active() -> bool:
    """Check if building is active for resource generation/consumption"""
    return is_constructed and not is_destroyed and is_active

func get_generation_rates() -> Dictionary:
    """Get resource generation rates for this building"""
    
    if not is_active():
        return {}
    
    var resource_manager = get_tree().get_first_node_in_group("resource_managers")
    if not resource_manager:
        return {}
    
    var ResourceType = resource_manager.ResourceType
    
    match building_type:
        BuildingType.POWER_SPIRE:
            return {
                ResourceType.ENERGY: 10.0,  # Energy per second
                ResourceType.MATERIALS: 2.0  # Materials per second
            }
        _:
            return {}

func get_consumption_rates() -> Dictionary:
    """Get resource consumption rates for this building"""
    
    if not is_active():
        return {}
    
    var resource_manager = get_tree().get_first_node_in_group("resource_managers")
    if not resource_manager:
        return {}
    
    var ResourceType = resource_manager.ResourceType
    
    match building_type:
        BuildingType.DEFENSE_TOWER:
            return {
                ResourceType.ENERGY: 3.0  # Energy per second
            }
        BuildingType.RELAY_PAD:
            return {
                ResourceType.ENERGY: 5.0,  # Energy per second
                ResourceType.MATERIALS: 1.0  # Materials per second
            }
        _:
            return {}

func get_construction_cost() -> Dictionary:
    """Get construction cost for this building"""
    
    var resource_manager = get_tree().get_first_node_in_group("resource_managers")
    if not resource_manager:
        return {}
    
    var ResourceType = resource_manager.ResourceType
    
    match building_type:
        BuildingType.POWER_SPIRE:
            return {
                ResourceType.ENERGY: 200,
                ResourceType.MATERIALS: 150
            }
        BuildingType.DEFENSE_TOWER:
            return {
                ResourceType.ENERGY: 300,
                ResourceType.MATERIALS: 200
            }
        BuildingType.RELAY_PAD:
            return {
                ResourceType.ENERGY: 500,
                ResourceType.MATERIALS: 300,
                ResourceType.RESEARCH_POINTS: 50
            }
        _:
            return {}

func can_afford_construction(team_id: int) -> bool:
    """Check if team can afford to build this building"""
    
    var resource_manager = get_tree().get_first_node_in_group("resource_managers")
    if not resource_manager:
        return false
    
    var cost = get_construction_cost()
    return resource_manager.has_sufficient_resources(team_id, cost)

func consume_construction_cost(team_id: int) -> bool:
    """Consume resources for building construction"""
    
    var resource_manager = get_tree().get_first_node_in_group("resource_managers")
    if not resource_manager:
        return false
    
    var cost = get_construction_cost()
    return resource_manager.consume_resources(team_id, cost)

func _exit_tree() -> void:
    """Clean up when building is removed"""
    
    # Unregister from resource manager
    var resource_manager = get_tree().get_first_node_in_group("resource_managers")
    if resource_manager:
        match building_type:
            BuildingType.POWER_SPIRE:
                resource_manager.unregister_resource_generator(team_id, self)
            BuildingType.DEFENSE_TOWER:
                resource_manager.unregister_resource_consumer(team_id, self)
            BuildingType.RELAY_PAD:
                resource_manager.unregister_resource_consumer(team_id, self)
    
    # Emit destruction signal
    if not is_destroyed:
        building_destroyed.emit(building_id)
    
    print("Building %s destroyed and cleaned up" % building_id) 