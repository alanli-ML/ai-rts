# SpireEntity.gd - Power spires that can be hijacked
class_name SpireEntity
extends StaticBody3D

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Spire identification and ownership
@export var spire_id: String = ""
@export var team_id: int = 0  # 0 = neutral, 1 = team 1, 2 = team 2
@export var original_team: int = 0
@export var controlling_unit_id: String = ""

# Spire configuration
@export var spire_type: String = "power"  # power, communication, shield
@export var max_health: float = 500.0
@export var power_generation: float = 20.0
@export var hijack_time: float = 5.0
@export var hijack_range: float = 3.0
@export var defense_strength: float = 10.0

# Spire state
var current_health: float = 500.0
var is_active: bool = true
var is_being_hijacked: bool = false
var is_destroyed: bool = false
var hijack_progress: float = 0.0
var hijack_start_time: float = 0.0
var hijacker_unit: Unit = null

# Tile system integration
var tile_position: Vector2i = Vector2i.ZERO
var tile_system: Node = null
var strategic_value: int = 1

# Visual and collision components
var spire_base: MeshInstance3D
var spire_tower: MeshInstance3D
var power_crystal: MeshInstance3D
var team_banner: MeshInstance3D
var hijack_indicator: MeshInstance3D
var energy_field: MeshInstance3D

# Defense system
var defense_area: Area3D
var defense_collision: CollisionShape3D
var defense_cooldown: float = 0.0
var last_defense_time: float = 0.0

# Hijack detection
var hijack_area: Area3D
var hijack_collision: CollisionShape3D
var units_in_hijack_range: Array[Unit] = []

# Audio components
var activation_sound: AudioStreamPlayer3D
var hijack_sound: AudioStreamPlayer3D
var defense_sound: AudioStreamPlayer3D
var destroyed_sound: AudioStreamPlayer3D

# Dependencies
var logger
var asset_loader: Node
var map_generator: Node
var resource_manager: Node

# Signals
signal spire_activated(spire_id: String, team_id: int)
signal spire_deactivated(spire_id: String, reason: String)
signal spire_hijack_started(spire_id: String, hijacker: Unit)
signal spire_hijack_progress(spire_id: String, progress: float)
signal spire_hijack_completed(spire_id: String, new_team: int, hijacker: Unit)
signal spire_hijack_failed(spire_id: String, reason: String)
signal spire_defended(spire_id: String, defender_team: int)
signal spire_destroyed(spire_id: String, reason: String)
signal spire_health_changed(spire_id: String, health: float, max_health: float)

func _ready() -> void:
    # Set up collision layers
    collision_layer = 0b1000  # Spire layer
    collision_mask = 0b1      # Unit layer
    
    # Initialize spire
    current_health = max_health
    
    # Create visual components
    _create_visual_components()
    
    # Create collision detection
    _create_collision_detection()
    
    # Create hijack detection
    _create_hijack_detection()
    
    # Create defense system
    _create_defense_system()
    
    # Create audio components
    _create_audio_components()
    
    # Add to groups
    add_to_group("spires")
    add_to_group("buildings")
    add_to_group("entities")
    
    # Activate spire
    _activate_spire()
    
    if logger:
        logger.info("SpireEntity", "Spire %s created at %s (team %d)" % [spire_id, global_position, team_id])

func _create_visual_components() -> void:
    """Create visual representation of the spire"""
    
    # Spire base
    spire_base = MeshInstance3D.new()
    spire_base.name = "SpireBase"
    
    var base_mesh = CylinderMesh.new()
    base_mesh.top_radius = 2.0
    base_mesh.bottom_radius = 2.5
    base_mesh.height = 2.0
    spire_base.mesh = base_mesh
    
    # Create base material
    var base_material = StandardMaterial3D.new()
    base_material.albedo_color = Color.GRAY
    base_material.metallic = 0.3
    base_material.roughness = 0.7
    spire_base.material_override = base_material
    
    add_child(spire_base)
    
    # Spire tower
    spire_tower = MeshInstance3D.new()
    spire_tower.name = "SpireTower"
    
    var tower_mesh = CylinderMesh.new()
    tower_mesh.top_radius = 0.8
    tower_mesh.bottom_radius = 1.5
    tower_mesh.height = 8.0
    spire_tower.mesh = tower_mesh
    
    spire_tower.position = Vector3(0, 5.0, 0)
    
    # Create tower material
    var tower_material = StandardMaterial3D.new()
    tower_material.albedo_color = Color.LIGHT_GRAY
    tower_material.metallic = 0.5
    tower_material.roughness = 0.3
    spire_tower.material_override = tower_material
    
    add_child(spire_tower)
    
    # Power crystal at top
    power_crystal = MeshInstance3D.new()
    power_crystal.name = "PowerCrystal"
    power_crystal.mesh = SphereMesh.new()
    power_crystal.mesh.radius = 1.0
    power_crystal.position = Vector3(0, 9.5, 0)
    
    # Create crystal material
    var crystal_material = StandardMaterial3D.new()
    crystal_material.albedo_color = _get_team_color()
    crystal_material.emission_enabled = true
    crystal_material.emission = _get_team_color() * 0.8
    crystal_material.flags_transparent = true
    crystal_material.albedo_color.a = 0.7
    power_crystal.material_override = crystal_material
    
    add_child(power_crystal)
    
    # Team banner
    team_banner = MeshInstance3D.new()
    team_banner.name = "TeamBanner"
    team_banner.mesh = BoxMesh.new()
    team_banner.mesh.size = Vector3(2.0, 1.0, 0.1)
    team_banner.position = Vector3(0, 7.0, 0)
    
    var banner_material = StandardMaterial3D.new()
    banner_material.albedo_color = _get_team_color()
    banner_material.emission_enabled = true
    banner_material.emission = _get_team_color() * 0.3
    team_banner.material_override = banner_material
    
    add_child(team_banner)
    
    # Hijack progress indicator
    hijack_indicator = MeshInstance3D.new()
    hijack_indicator.name = "HijackIndicator"
    hijack_indicator.mesh = CylinderMesh.new()
    hijack_indicator.mesh.top_radius = 2.2
    hijack_indicator.mesh.bottom_radius = 2.2
    hijack_indicator.mesh.height = 0.2
    hijack_indicator.position = Vector3(0, 0.2, 0)
    hijack_indicator.visible = false
    
    var hijack_material = StandardMaterial3D.new()
    hijack_material.albedo_color = Color.ORANGE
    hijack_material.emission_enabled = true
    hijack_material.emission = Color.ORANGE * 0.5
    hijack_material.flags_transparent = true
    hijack_material.albedo_color.a = 0.6
    hijack_indicator.material_override = hijack_material
    
    add_child(hijack_indicator)
    
    # Energy field
    energy_field = MeshInstance3D.new()
    energy_field.name = "EnergyField"
    energy_field.mesh = SphereMesh.new()
    energy_field.mesh.radius = 3.0
    energy_field.position = Vector3(0, 5.0, 0)
    energy_field.visible = false
    
    var field_material = StandardMaterial3D.new()
    field_material.albedo_color = _get_team_color()
    field_material.emission_enabled = true
    field_material.emission = _get_team_color() * 0.2
    field_material.flags_transparent = true
    field_material.albedo_color.a = 0.1
    energy_field.material_override = field_material
    
    add_child(energy_field)

func _create_collision_detection() -> void:
    """Create collision detection for the spire"""
    
    var collision_shape = CollisionShape3D.new()
    collision_shape.name = "SpireCollision"
    
    var cylinder_shape = CylinderShape3D.new()
    cylinder_shape.height = 10.0
    cylinder_shape.top_radius = 2.0
    cylinder_shape.bottom_radius = 2.5
    collision_shape.shape = cylinder_shape
    collision_shape.position = Vector3(0, 5.0, 0)
    
    add_child(collision_shape)

func _create_hijack_detection() -> void:
    """Create hijack detection area"""
    
    hijack_area = Area3D.new()
    hijack_area.name = "HijackArea"
    hijack_area.collision_layer = 0b100000  # Hijack layer
    hijack_area.collision_mask = 0b1        # Unit layer
    
    hijack_collision = CollisionShape3D.new()
    hijack_collision.name = "HijackCollision"
    
    var hijack_shape = CylinderShape3D.new()
    hijack_shape.height = 2.0
    hijack_shape.top_radius = hijack_range
    hijack_shape.bottom_radius = hijack_range
    hijack_collision.shape = hijack_shape
    hijack_collision.position = Vector3(0, 1.0, 0)
    
    hijack_area.add_child(hijack_collision)
    add_child(hijack_area)
    
    # Connect hijack signals
    hijack_area.body_entered.connect(_on_unit_entered_hijack_range)
    hijack_area.body_exited.connect(_on_unit_exited_hijack_range)

func _create_defense_system() -> void:
    """Create defense system for the spire"""
    
    defense_area = Area3D.new()
    defense_area.name = "DefenseArea"
    defense_area.collision_layer = 0b1000000  # Defense layer
    defense_area.collision_mask = 0b1          # Unit layer
    
    defense_collision = CollisionShape3D.new()
    defense_collision.name = "DefenseCollision"
    
    var defense_shape = SphereShape3D.new()
    defense_shape.radius = 8.0  # Defense range
    defense_collision.shape = defense_shape
    defense_collision.position = Vector3(0, 5.0, 0)
    
    defense_area.add_child(defense_collision)
    add_child(defense_area)
    
    # Connect defense signals
    defense_area.body_entered.connect(_on_unit_entered_defense_range)

func _create_audio_components() -> void:
    """Create audio components for spire sounds"""
    
    activation_sound = AudioStreamPlayer3D.new()
    activation_sound.name = "ActivationSound"
    activation_sound.max_distance = 30.0
    activation_sound.unit_size = 10.0
    add_child(activation_sound)
    
    hijack_sound = AudioStreamPlayer3D.new()
    hijack_sound.name = "HijackSound"
    hijack_sound.max_distance = 25.0
    hijack_sound.unit_size = 8.0
    add_child(hijack_sound)
    
    defense_sound = AudioStreamPlayer3D.new()
    defense_sound.name = "DefenseSound"
    defense_sound.max_distance = 35.0
    defense_sound.unit_size = 12.0
    add_child(defense_sound)
    
    destroyed_sound = AudioStreamPlayer3D.new()
    destroyed_sound.name = "DestroyedSound"
    destroyed_sound.max_distance = 50.0
    destroyed_sound.unit_size = 20.0
    add_child(destroyed_sound)

func setup(logger_ref, asset_loader_ref, map_generator_ref, resource_manager_ref) -> void:
    """Setup spire with dependencies"""
    logger = logger_ref
    asset_loader = asset_loader_ref
    map_generator = map_generator_ref
    resource_manager = resource_manager_ref
    
    # Get tile system reference
    if map_generator and map_generator.has_method("get_tile_system"):
        tile_system = map_generator.get_tile_system()
        if tile_system:
            tile_position = tile_system.world_to_tile(global_position)
    
    # Register with resource manager
    if resource_manager and resource_manager.has_method("register_resource_generator"):
        resource_manager.register_resource_generator(team_id, self)

func _physics_process(delta: float) -> void:
    """Update spire state"""
    
    if is_destroyed:
        return
    
    # Handle hijack progress
    if is_being_hijacked:
        _update_hijack_progress(delta)
    
    # Update defense cooldown
    if defense_cooldown > 0:
        defense_cooldown -= delta
    
    # Update visual effects
    _update_visual_effects()

func _update_hijack_progress(delta: float) -> void:
    """Update hijack progress"""
    
    # Check if hijacker is still in range
    if not hijacker_unit or hijacker_unit.is_dead or hijacker_unit not in units_in_hijack_range:
        _cancel_hijack("hijacker_left")
        return
    
    # Update progress
    hijack_progress += delta / hijack_time
    
    # Update visual indicator
    if hijack_indicator:
        hijack_indicator.visible = true
        hijack_indicator.scale = Vector3(hijack_progress, 1.0, hijack_progress)
    
    spire_hijack_progress.emit(spire_id, hijack_progress)
    
    # Check if hijack is complete
    if hijack_progress >= 1.0:
        _complete_hijack()

func _complete_hijack() -> void:
    """Complete the hijack process"""
    
    var old_team = team_id
    var new_team = hijacker_unit.team_id
    
    # Change ownership
    team_id = new_team
    controlling_unit_id = hijacker_unit.unit_id
    
    # Reset hijack state
    is_being_hijacked = false
    hijack_progress = 0.0
    hijacker_unit = null
    
    # Update visuals
    _update_team_visuals()
    
    # Hide hijack indicator
    if hijack_indicator:
        hijack_indicator.visible = false
    
    # Play activation sound
    if activation_sound:
        activation_sound.play()
    
    # Register with new team's resource manager
    if resource_manager:
        resource_manager.unregister_resource_generator(old_team, self)
        resource_manager.register_resource_generator(new_team, self)
    
    spire_hijack_completed.emit(spire_id, new_team, hijacker_unit)
    
    if logger:
        logger.info("SpireEntity", "Spire %s hijacked by team %d (unit %s)" % [spire_id, new_team, hijacker_unit.unit_id])

func _cancel_hijack(reason: String) -> void:
    """Cancel the hijack process"""
    
    is_being_hijacked = false
    hijack_progress = 0.0
    hijacker_unit = null
    
    # Hide hijack indicator
    if hijack_indicator:
        hijack_indicator.visible = false
    
    spire_hijack_failed.emit(spire_id, reason)
    
    if logger:
        logger.info("SpireEntity", "Spire %s hijack cancelled: %s" % [spire_id, reason])

func _activate_spire() -> void:
    """Activate the spire"""
    
    is_active = true
    
    # Show energy field
    if energy_field:
        energy_field.visible = true
    
    # Play activation sound
    if activation_sound:
        activation_sound.play()
    
    spire_activated.emit(spire_id, team_id)

func _update_visual_effects() -> void:
    """Update visual effects"""
    
    # Animate crystal rotation
    if power_crystal:
        power_crystal.rotation.y += 0.02
    
    # Animate energy field
    if energy_field and energy_field.visible:
        energy_field.rotation.y += 0.01
        energy_field.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() / 1000.0) * 0.1)

func _update_team_visuals() -> void:
    """Update team-based visuals"""
    
    var team_color = _get_team_color()
    
    # Update crystal
    if power_crystal:
        var crystal_material = power_crystal.material_override as StandardMaterial3D
        if crystal_material:
            crystal_material.albedo_color = team_color
            crystal_material.emission = team_color * 0.8
    
    # Update banner
    if team_banner:
        var banner_material = team_banner.material_override as StandardMaterial3D
        if banner_material:
            banner_material.albedo_color = team_color
            banner_material.emission = team_color * 0.3
    
    # Update energy field
    if energy_field:
        var field_material = energy_field.material_override as StandardMaterial3D
        if field_material:
            field_material.albedo_color = team_color
            field_material.emission = team_color * 0.2

func _get_team_color() -> Color:
    """Get color for team"""
    
    match team_id:
        1:
            return Color.BLUE
        2:
            return Color.RED
        _:
            return Color.WHITE  # Neutral

func _on_unit_entered_hijack_range(body: Node3D) -> void:
    """Handle unit entering hijack range"""
    
    if body.is_in_group("units"):
        var unit = body as Unit
        if unit and not unit.is_dead:
            units_in_hijack_range.append(unit)
            
            # Start hijack if enemy engineer
            if unit.team_id != team_id and unit.archetype == "engineer" and not is_being_hijacked:
                _start_hijack(unit)

func _on_unit_exited_hijack_range(body: Node3D) -> void:
    """Handle unit exiting hijack range"""
    
    if body.is_in_group("units"):
        var unit = body as Unit
        if unit and unit in units_in_hijack_range:
            units_in_hijack_range.erase(unit)
            
            # Cancel hijack if this was the hijacker
            if unit == hijacker_unit:
                _cancel_hijack("hijacker_left")

func _on_unit_entered_defense_range(body: Node3D) -> void:
    """Handle unit entering defense range"""
    
    if body.is_in_group("units"):
        var unit = body as Unit
        if unit and not unit.is_dead and unit.team_id != team_id:
            _activate_defenses(unit)

func _start_hijack(unit: Unit) -> void:
    """Start hijack process"""
    
    if is_being_hijacked or unit.team_id == team_id:
        return
    
    is_being_hijacked = true
    hijack_progress = 0.0
    hijack_start_time = Time.get_ticks_msec() / 1000.0
    hijacker_unit = unit
    
    # Play hijack sound
    if hijack_sound:
        hijack_sound.play()
    
    spire_hijack_started.emit(spire_id, unit)
    
    if logger:
        logger.info("SpireEntity", "Spire %s hijack started by unit %s" % [spire_id, unit.unit_id])

func _activate_defenses(target: Unit) -> void:
    """Activate spire defenses against target"""
    
    if defense_cooldown > 0 or not is_active:
        return
    
    # Deal defensive damage
    target.take_damage(defense_strength)
    
    # Set defense cooldown
    defense_cooldown = 2.0
    last_defense_time = Time.get_ticks_msec() / 1000.0
    
    # Play defense sound
    if defense_sound:
        defense_sound.play()
    
    # Show defense effect
    _show_defense_effect(target)
    
    spire_defended.emit(spire_id, team_id)
    
    if logger:
        logger.info("SpireEntity", "Spire %s defended against unit %s" % [spire_id, target.unit_id])

func _show_defense_effect(target: Unit) -> void:
    """Show defense effect"""
    
    # Create lightning effect from spire to target
    var lightning = MeshInstance3D.new()
    lightning.name = "LightningEffect"
    lightning.mesh = CylinderMesh.new()
    lightning.mesh.top_radius = 0.1
    lightning.mesh.bottom_radius = 0.1
    
    var distance = global_position.distance_to(target.global_position)
    lightning.mesh.height = distance
    lightning.position = global_position + (target.global_position - global_position) * 0.5
    lightning.look_at(target.global_position, Vector3.UP)
    
    var lightning_material = StandardMaterial3D.new()
    lightning_material.albedo_color = Color.CYAN
    lightning_material.emission_enabled = true
    lightning_material.emission = Color.CYAN * 2.0
    lightning.material_override = lightning_material
    
    get_parent().add_child(lightning)
    
    # Animate lightning
    var tween = create_tween()
    tween.tween_property(lightning_material, "emission_energy", 0.0, 0.3)
    tween.tween_callback(lightning.queue_free)

func take_damage(damage: float) -> void:
    """Take damage and handle destruction"""
    
    if is_destroyed:
        return
    
    current_health -= damage
    current_health = max(0, current_health)
    
    spire_health_changed.emit(spire_id, current_health, max_health)
    
    if current_health <= 0:
        _destroy_spire("destroyed")

func _destroy_spire(reason: String) -> void:
    """Destroy the spire"""
    
    if is_destroyed:
        return
    
    is_destroyed = true
    is_active = false
    
    # Cancel any ongoing hijack
    if is_being_hijacked:
        _cancel_hijack("spire_destroyed")
    
    # Play destruction sound
    if destroyed_sound:
        destroyed_sound.play()
    
    # Create destruction effect
    _create_destruction_effect()
    
    spire_destroyed.emit(spire_id, reason)
    
    if logger:
        logger.info("SpireEntity", "Spire %s destroyed: %s" % [spire_id, reason])
    
    # Remove from groups
    remove_from_group("spires")
    remove_from_group("buildings")
    remove_from_group("entities")
    
    # Unregister from resource manager
    if resource_manager:
        resource_manager.unregister_resource_generator(team_id, self)
    
    # Remove after effect
    await get_tree().create_timer(2.0).timeout
    queue_free()

func _create_destruction_effect() -> void:
    """Create destruction visual effect"""
    
    # Create explosion effect
    var explosion = MeshInstance3D.new()
    explosion.name = "Explosion"
    explosion.mesh = SphereMesh.new()
    explosion.mesh.radius = 5.0
    explosion.position = global_position + Vector3(0, 5, 0)
    
    var explosion_material = StandardMaterial3D.new()
    explosion_material.albedo_color = Color.ORANGE
    explosion_material.emission_enabled = true
    explosion_material.emission = Color.ORANGE * 2.0
    explosion_material.flags_transparent = true
    explosion.material_override = explosion_material
    
    get_parent().add_child(explosion)
    
    # Animate explosion
    var tween = create_tween()
    tween.parallel().tween_property(explosion, "scale", Vector3(2.0, 2.0, 2.0), 2.0)
    tween.parallel().tween_property(explosion_material, "albedo_color:a", 0.0, 2.0)
    tween.tween_callback(explosion.queue_free)

# Public methods
func get_power_generation() -> float:
    """Get current power generation"""
    
    return power_generation if is_active else 0.0

func get_spire_info() -> Dictionary:
    """Get spire information for UI/AI"""
    
    return {
        "spire_id": spire_id,
        "team_id": team_id,
        "original_team": original_team,
        "controlling_unit_id": controlling_unit_id,
        "spire_type": spire_type,
        "position": global_position,
        "tile_position": tile_position,
        "is_active": is_active,
        "is_being_hijacked": is_being_hijacked,
        "hijack_progress": hijack_progress,
        "hijacker_unit": hijacker_unit.unit_id if hijacker_unit else null,
        "current_health": current_health,
        "max_health": max_health,
        "power_generation": get_power_generation(),
        "strategic_value": strategic_value,
        "units_in_hijack_range": units_in_hijack_range.size(),
        "hijack_time": hijack_time,
        "hijack_range": hijack_range,
        "defense_strength": defense_strength
    }

# Static factory method for tile-based placement
static func create_spire_at_tile(tile_pos: Vector2i, spire_type: String, team_id: int, tile_system: Node) -> SpireEntity:
    """Create a spire at a specific tile position"""
    
    var spire = SpireEntity.new()
    spire.spire_id = "spire_%d_%d_%d" % [tile_pos.x, tile_pos.y, Time.get_ticks_msec()]
    spire.spire_type = spire_type
    spire.team_id = team_id
    spire.original_team = team_id
    spire.tile_position = tile_pos
    
    # Convert tile position to world position
    if tile_system and tile_system.has_method("tile_to_world"):
        spire.global_position = tile_system.tile_to_world(tile_pos)
    else:
        # Fallback calculation
        var tile_size = 3.0
        spire.global_position = Vector3(tile_pos.x * tile_size, 0, tile_pos.y * tile_size)
    
    # Configure spire based on type
    match spire_type:
        "communication":
            spire.max_health = 300.0
            spire.power_generation = 15.0
            spire.hijack_time = 8.0
            spire.defense_strength = 5.0
        "shield":
            spire.max_health = 800.0
            spire.power_generation = 10.0
            spire.hijack_time = 10.0
            spire.defense_strength = 20.0
        _: # power
            spire.max_health = 500.0
            spire.power_generation = 20.0
            spire.hijack_time = 5.0
            spire.defense_strength = 10.0
    
    spire.current_health = spire.max_health
    
    return spire 