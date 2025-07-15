# TurretEntity.gd - Defensive turrets with tile-based placement
class_name TurretEntity
extends StaticBody3D

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Turret identification and ownership
@export var turret_id: String = ""
@export var team_id: int = 1
@export var owner_unit_id: String = ""
@export var built_by: String = ""

# Turret configuration
@export var turret_type: String = "basic"  # basic, heavy, anti_air, laser
@export var max_health: float = 200.0
@export var attack_damage: float = 30.0
@export var attack_range: float = 12.0
@export var attack_speed: float = 2.0  # Attacks per second
@export var construction_time: float = 8.0
@export var power_consumption: float = 5.0

# Turret state
var current_health: float = 200.0
var is_constructed: bool = false
var is_active: bool = false
var is_destroyed: bool = false
var construction_progress: float = 0.0
var construction_start_time: float = 0.0
var last_attack_time: float = 0.0

# Targeting system
var current_target: Unit = null
var visible_enemies: Array[Unit] = []
var target_priority_queue: Array[Unit] = []
var targeting_mode: String = "auto"  # auto, manual, hold_fire

# Tile system integration
var tile_position: Vector2i = Vector2i.ZERO
var tile_system: Node = null
var placement_valid: bool = true

# Visual and collision components
var turret_base: MeshInstance3D
var turret_barrel: MeshInstance3D
var construction_indicator: MeshInstance3D
var health_bar: ProgressBar
var range_indicator: MeshInstance3D
var muzzle_flash: MeshInstance3D

# Vision and detection
var vision_area: Area3D
var vision_collision: CollisionShape3D
var vision_angle: float = 360.0  # Full circle for turrets

# Audio components
var construction_sound: AudioStreamPlayer3D
var attack_sound: AudioStreamPlayer3D
var destroyed_sound: AudioStreamPlayer3D

# Dependencies
var logger
var asset_loader: Node
var map_generator: Node
var resource_manager: Node

# Signals
signal turret_constructed(turret_id: String, position: Vector3)
signal turret_activated(turret_id: String)
signal turret_deactivated(turret_id: String)
signal turret_destroyed(turret_id: String, reason: String)
signal turret_attacking(turret_id: String, target: Unit)
signal turret_target_acquired(turret_id: String, target: Unit)
signal turret_target_lost(turret_id: String, target: Unit)
signal turret_health_changed(turret_id: String, health: float, max_health: float)

func _ready() -> void:
    # Set up collision layers
    collision_layer = 0b100  # Building layer
    collision_mask = 0b1     # Unit layer
    
    # Initialize turret
    construction_start_time = Time.get_ticks_msec() / 1000.0
    current_health = max_health
    
    # Create visual components
    _create_visual_components()
    
    # Create collision detection
    _create_collision_detection()
    
    # Create vision system
    _create_vision_system()
    
    # Create audio components
    _create_audio_components()
    
    # Add to groups
    add_to_group("turrets")
    add_to_group("buildings")
    add_to_group("entities")
    
    if logger:
        logger.info("TurretEntity", "Turret %s created at %s by %s" % [turret_id, global_position, owner_unit_id])

func _create_visual_components() -> void:
    """Create visual representation of the turret"""
    
    # Turret base
    turret_base = MeshInstance3D.new()
    turret_base.name = "TurretBase"
    
    var base_mesh = CylinderMesh.new()
    base_mesh.top_radius = 1.0
    base_mesh.bottom_radius = 1.2
    base_mesh.height = 1.5
    turret_base.mesh = base_mesh
    
    # Create base material
    var base_material = StandardMaterial3D.new()
    base_material.albedo_color = Color.BLUE if team_id == 1 else Color.RED
    base_material.metallic = 0.8
    base_material.roughness = 0.2
    turret_base.material_override = base_material
    
    add_child(turret_base)
    
    # Turret barrel
    turret_barrel = MeshInstance3D.new()
    turret_barrel.name = "TurretBarrel"
    
    var barrel_mesh = CylinderMesh.new()
    barrel_mesh.top_radius = 0.2
    barrel_mesh.bottom_radius = 0.3
    barrel_mesh.height = 2.0
    turret_barrel.mesh = barrel_mesh
    
    # Position barrel on top of base
    turret_barrel.position = Vector3(0, 1.5, 0)
    turret_barrel.rotation_degrees = Vector3(0, 0, -90)  # Point horizontally
    
    # Create barrel material
    var barrel_material = StandardMaterial3D.new()
    barrel_material.albedo_color = Color.DARK_GRAY
    barrel_material.metallic = 0.9
    barrel_material.roughness = 0.1
    turret_barrel.material_override = barrel_material
    
    add_child(turret_barrel)
    
    # Construction indicator
    construction_indicator = MeshInstance3D.new()
    construction_indicator.name = "ConstructionIndicator"
    construction_indicator.mesh = SphereMesh.new()
    construction_indicator.mesh.radius = 0.3
    construction_indicator.position = Vector3(0, 2.5, 0)
    construction_indicator.visible = true
    
    var construction_material = StandardMaterial3D.new()
    construction_material.albedo_color = Color.YELLOW
    construction_material.emission_enabled = true
    construction_material.emission = Color.YELLOW * 0.5
    construction_indicator.material_override = construction_material
    
    add_child(construction_indicator)
    
    # Range indicator (initially hidden)
    range_indicator = MeshInstance3D.new()
    range_indicator.name = "RangeIndicator"
    range_indicator.mesh = SphereMesh.new()
    range_indicator.mesh.radius = attack_range
    range_indicator.position = Vector3(0, 0.1, 0)
    range_indicator.visible = false
    
    var range_material = StandardMaterial3D.new()
    range_material.albedo_color = Color.GREEN
    range_material.flags_transparent = true
    range_material.albedo_color.a = 0.1
    range_indicator.material_override = range_material
    
    add_child(range_indicator)
    
    # Muzzle flash
    muzzle_flash = MeshInstance3D.new()
    muzzle_flash.name = "MuzzleFlash"
    muzzle_flash.mesh = SphereMesh.new()
    muzzle_flash.mesh.radius = 0.5
    muzzle_flash.position = Vector3(0, 1.5, 1.0)  # At barrel tip
    muzzle_flash.visible = false
    
    var flash_material = StandardMaterial3D.new()
    flash_material.albedo_color = Color.ORANGE
    flash_material.emission_enabled = true
    flash_material.emission = Color.ORANGE * 3.0
    muzzle_flash.material_override = flash_material
    
    add_child(muzzle_flash)

func _create_collision_detection() -> void:
    """Create collision detection for the turret"""
    
    var collision_shape = CollisionShape3D.new()
    collision_shape.name = "TurretCollision"
    
    var cylinder_shape = CylinderShape3D.new()
    cylinder_shape.height = 2.0
    cylinder_shape.top_radius = 1.2
    cylinder_shape.bottom_radius = 1.2
    collision_shape.shape = cylinder_shape
    
    add_child(collision_shape)

func _create_vision_system() -> void:
    """Create vision system for target detection"""
    
    vision_area = Area3D.new()
    vision_area.name = "VisionArea"
    vision_area.collision_layer = 0b100000  # Vision layer
    vision_area.collision_mask = 0b1        # Unit layer
    
    vision_collision = CollisionShape3D.new()
    vision_collision.name = "VisionCollision"
    
    var vision_shape = SphereShape3D.new()
    vision_shape.radius = attack_range
    vision_collision.shape = vision_shape
    
    vision_area.add_child(vision_collision)
    add_child(vision_area)
    
    # Connect vision signals
    vision_area.body_entered.connect(_on_unit_entered_vision)
    vision_area.body_exited.connect(_on_unit_exited_vision)

func _create_audio_components() -> void:
    """Create audio components for turret sounds"""
    
    construction_sound = AudioStreamPlayer3D.new()
    construction_sound.name = "ConstructionSound"
    construction_sound.max_distance = 25.0
    construction_sound.unit_size = 8.0
    add_child(construction_sound)
    
    attack_sound = AudioStreamPlayer3D.new()
    attack_sound.name = "AttackSound"
    attack_sound.max_distance = 30.0
    attack_sound.unit_size = 10.0
    add_child(attack_sound)
    
    destroyed_sound = AudioStreamPlayer3D.new()
    destroyed_sound.name = "DestroyedSound"
    destroyed_sound.max_distance = 40.0
    destroyed_sound.unit_size = 15.0
    add_child(destroyed_sound)

func setup(logger_ref, asset_loader_ref, map_generator_ref, resource_manager_ref) -> void:
    """Setup turret with dependencies"""
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
    if resource_manager and resource_manager.has_method("register_resource_consumer"):
        resource_manager.register_resource_consumer(team_id, self)

func _physics_process(delta: float) -> void:
    """Update turret state"""
    
    if is_destroyed:
        return
    
    # Handle construction
    if not is_constructed:
        _update_construction(delta)
        return
    
    # Handle targeting and combat
    if is_active:
        _update_targeting(delta)
        _update_combat(delta)
    
    # Update visual indicators
    _update_visual_indicators()

func _update_construction(delta: float) -> void:
    """Update construction progress"""
    
    construction_progress += delta / construction_time
    
    # Update construction visual
    if construction_indicator:
        construction_indicator.visible = true
        var blink_time = fmod(Time.get_ticks_msec() / 1000.0, 0.5)
        construction_indicator.scale = Vector3.ONE * (1.0 + sin(blink_time * 10) * 0.2)
    
    # Check if construction is complete
    if construction_progress >= 1.0:
        _complete_construction()

func _complete_construction() -> void:
    """Complete turret construction"""
    
    is_constructed = true
    is_active = true
    construction_progress = 1.0
    
    # Hide construction indicator
    if construction_indicator:
        construction_indicator.visible = false
    
    # Play construction complete sound
    if construction_sound:
        construction_sound.play()
    
    turret_constructed.emit(turret_id, global_position)
    turret_activated.emit(turret_id)
    
    if logger:
        logger.info("TurretEntity", "Turret %s construction completed at %s" % [turret_id, global_position])

func _update_targeting(delta: float) -> void:
    """Update targeting system"""
    
    # Remove dead or out-of-range targets
    visible_enemies = visible_enemies.filter(func(unit): 
        return unit and not unit.is_dead and global_position.distance_to(unit.global_position) <= attack_range
    )
    
    # Find best target if we don't have one
    if not current_target or current_target.is_dead or global_position.distance_to(current_target.global_position) > attack_range:
        current_target = _find_best_target()
        
        if current_target:
            turret_target_acquired.emit(turret_id, current_target)
    
    # Aim at current target
    if current_target:
        _aim_at_target(current_target)

func _find_best_target() -> Unit:
    """Find the best target based on priority"""
    
    if visible_enemies.is_empty():
        return null
    
    # Sort by priority (closest first for now)
    visible_enemies.sort_custom(func(a, b): 
        var dist_a = global_position.distance_to(a.global_position)
        var dist_b = global_position.distance_to(b.global_position)
        return dist_a < dist_b
    )
    
    return visible_enemies[0]

func _aim_at_target(target: Unit) -> void:
    """Aim turret barrel at target"""
    
    if not turret_barrel or not target:
        return
    
    var target_direction = (target.global_position - global_position).normalized()
    
    # Calculate rotation to face target
    var target_angle = atan2(target_direction.x, target_direction.z)
    
    # Smoothly rotate barrel
    var current_rotation = turret_barrel.rotation.y
    var angle_difference = target_angle - current_rotation
    
    # Normalize angle difference
    while angle_difference > PI:
        angle_difference -= 2 * PI
    while angle_difference < -PI:
        angle_difference += 2 * PI
    
    # Apply rotation
    turret_barrel.rotation.y = lerp_angle(current_rotation, target_angle, 0.1)

func _update_combat(delta: float) -> void:
    """Update combat system"""
    
    if not current_target or targeting_mode == "hold_fire":
        return
    
    # Check if target is in range and line of sight
    var distance = global_position.distance_to(current_target.global_position)
    if distance > attack_range:
        return
    
    # Check attack cooldown
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_attack_time < (1.0 / attack_speed):
        return
    
    # Check line of sight
    if not _has_line_of_sight(current_target):
        return
    
    # Attack target
    _attack_target(current_target)

func _has_line_of_sight(target: Unit) -> bool:
    """Check if turret has line of sight to target"""
    
    var space_state = get_world_3d().direct_space_state
    var query = PhysicsRayQueryParameters3D.create(
        global_position + Vector3(0, 1, 0),  # From turret height
        target.global_position + Vector3(0, 1, 0)  # To target height
    )
    query.collision_mask = 0b110  # Buildings and terrain
    query.exclude = [self]
    
    var result = space_state.intersect_ray(query)
    return result.is_empty()  # True if no obstacles

func _attack_target(target: Unit) -> void:
    """Attack the target"""
    
    if not target or target.is_dead:
        return
    
    last_attack_time = Time.get_ticks_msec() / 1000.0
    
    # Show muzzle flash
    _show_muzzle_flash()
    
    # Play attack sound
    if attack_sound:
        attack_sound.play()
    
    # Deal damage
    target.take_damage(attack_damage)
    
    turret_attacking.emit(turret_id, target)
    
    if logger:
        logger.debug("TurretEntity", "Turret %s attacked unit %s for %.1f damage" % [turret_id, target.unit_id, attack_damage])

func _show_muzzle_flash() -> void:
    """Show muzzle flash effect"""
    
    if not muzzle_flash:
        return
    
    muzzle_flash.visible = true
    
    # Animate muzzle flash
    var tween = create_tween()
    tween.tween_property(muzzle_flash, "scale", Vector3(1.5, 1.5, 1.5), 0.1)
    tween.tween_property(muzzle_flash, "scale", Vector3.ONE, 0.1)
    tween.tween_callback(func(): muzzle_flash.visible = false)

func _update_visual_indicators() -> void:
    """Update visual indicators"""
    
    # Update health bar (if exists)
    if health_bar:
        health_bar.value = (current_health / max_health) * 100
    
    # Update range indicator visibility
    if range_indicator:
        range_indicator.visible = is_constructed and targeting_mode != "hold_fire"

func take_damage(damage: float) -> void:
    """Take damage and handle destruction"""
    
    if is_destroyed:
        return
    
    current_health -= damage
    current_health = max(0, current_health)
    
    turret_health_changed.emit(turret_id, current_health, max_health)
    
    if current_health <= 0:
        _destroy_turret("destroyed")

func _destroy_turret(reason: String) -> void:
    """Destroy the turret"""
    
    if is_destroyed:
        return
    
    is_destroyed = true
    is_active = false
    
    # Play destruction sound
    if destroyed_sound:
        destroyed_sound.play()
    
    # Create destruction effect
    _create_destruction_effect()
    
    turret_destroyed.emit(turret_id, reason)
    
    if logger:
        logger.info("TurretEntity", "Turret %s destroyed: %s" % [turret_id, reason])
    
    # Remove from groups
    remove_from_group("turrets")
    remove_from_group("buildings")
    remove_from_group("entities")
    
    # Unregister from resource manager
    if resource_manager and resource_manager.has_method("unregister_resource_consumer"):
        resource_manager.unregister_resource_consumer(team_id, self)
    
    # Remove after effect
    await get_tree().create_timer(1.0).timeout
    queue_free()

func _create_destruction_effect() -> void:
    """Create destruction visual effect"""
    
    # Create smoke/debris effect
    var destruction_effect = MeshInstance3D.new()
    destruction_effect.name = "DestructionEffect"
    destruction_effect.mesh = SphereMesh.new()
    destruction_effect.mesh.radius = 2.0
    destruction_effect.position = global_position
    
    var destruction_material = StandardMaterial3D.new()
    destruction_material.albedo_color = Color.BLACK
    destruction_material.emission_enabled = true
    destruction_material.emission = Color.ORANGE * 0.5
    destruction_material.flags_transparent = true
    destruction_effect.material_override = destruction_material
    
    get_parent().add_child(destruction_effect)
    
    # Animate destruction
    var tween = create_tween()
    tween.parallel().tween_property(destruction_effect, "scale", Vector3(2.0, 2.0, 2.0), 1.0)
    tween.parallel().tween_property(destruction_material, "albedo_color:a", 0.0, 1.0)
    tween.tween_callback(destruction_effect.queue_free)

func _on_unit_entered_vision(body: Node3D) -> void:
    """Handle unit entering vision range"""
    
    if body.is_in_group("units"):
        var unit = body as Unit
        if unit and not unit.is_dead and unit.team_id != team_id:
            if unit not in visible_enemies:
                visible_enemies.append(unit)
                
                if logger:
                    logger.debug("TurretEntity", "Turret %s detected enemy unit %s" % [turret_id, unit.unit_id])

func _on_unit_exited_vision(body: Node3D) -> void:
    """Handle unit exiting vision range"""
    
    if body.is_in_group("units"):
        var unit = body as Unit
        if unit and unit in visible_enemies:
            visible_enemies.erase(unit)
            
            if unit == current_target:
                current_target = null
                turret_target_lost.emit(turret_id, unit)

# Public methods for external control
func set_targeting_mode(mode: String) -> void:
    """Set targeting mode"""
    
    targeting_mode = mode
    
    match mode:
        "auto":
            is_active = true
        "hold_fire":
            is_active = false
            current_target = null
        "manual":
            is_active = true
            # Manual targeting would require external target assignment

func set_manual_target(target: Unit) -> void:
    """Set manual target"""
    
    if targeting_mode == "manual" and target and target.team_id != team_id:
        current_target = target
        turret_target_acquired.emit(turret_id, target)

func get_power_consumption() -> float:
    """Get current power consumption"""
    
    return power_consumption if is_active else 0.0

func get_turret_info() -> Dictionary:
    """Get turret information for UI/AI"""
    
    return {
        "turret_id": turret_id,
        "team_id": team_id,
        "owner_unit_id": owner_unit_id,
        "turret_type": turret_type,
        "position": global_position,
        "tile_position": tile_position,
        "is_constructed": is_constructed,
        "is_active": is_active,
        "current_health": current_health,
        "max_health": max_health,
        "construction_progress": construction_progress,
        "attack_damage": attack_damage,
        "attack_range": attack_range,
        "attack_speed": attack_speed,
        "current_target": current_target.unit_id if current_target else null,
        "visible_enemies": visible_enemies.size(),
        "targeting_mode": targeting_mode,
        "power_consumption": get_power_consumption()
    }

# Static factory method for tile-based placement
static func create_turret_at_tile(tile_pos: Vector2i, turret_type: String, team_id: int, owner_unit_id: String, tile_system: Node) -> TurretEntity:
    """Create a turret at a specific tile position"""
    
    var turret = TurretEntity.new()
    turret.turret_id = "turret_%d_%d_%d" % [tile_pos.x, tile_pos.y, Time.get_ticks_msec()]
    turret.turret_type = turret_type
    turret.team_id = team_id
    turret.owner_unit_id = owner_unit_id
    turret.built_by = owner_unit_id
    turret.tile_position = tile_pos
    
    # Convert tile position to world position
    if tile_system and tile_system.has_method("tile_to_world"):
        turret.global_position = tile_system.tile_to_world(tile_pos)
    else:
        # Fallback calculation
        var tile_size = 3.0
        turret.global_position = Vector3(tile_pos.x * tile_size, 0, tile_pos.y * tile_size)
    
    # Configure turret based on type
    match turret_type:
        "heavy":
            turret.max_health = 300.0
            turret.attack_damage = 50.0
            turret.attack_range = 15.0
            turret.attack_speed = 1.0
            turret.construction_time = 12.0
            turret.power_consumption = 8.0
        "anti_air":
            turret.max_health = 150.0
            turret.attack_damage = 25.0
            turret.attack_range = 20.0
            turret.attack_speed = 3.0
            turret.construction_time = 10.0
            turret.power_consumption = 6.0
        "laser":
            turret.max_health = 100.0
            turret.attack_damage = 15.0
            turret.attack_range = 18.0
            turret.attack_speed = 10.0
            turret.construction_time = 15.0
            turret.power_consumption = 12.0
        _: # basic
            turret.max_health = 200.0
            turret.attack_damage = 30.0
            turret.attack_range = 12.0
            turret.attack_speed = 2.0
            turret.construction_time = 8.0
            turret.power_consumption = 5.0
    
    turret.current_health = turret.max_health
    
    return turret 