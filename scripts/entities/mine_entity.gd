# MineEntity.gd - Deployable mines with tile-based placement
class_name MineEntity
extends Area3D

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Mine identification and ownership
@export var mine_id: String = ""
@export var team_id: int = 1
@export var owner_unit_id: String = ""
@export var deployed_by: String = ""

# Mine configuration
@export var mine_type: String = "proximity"  # proximity, timed, remote
@export var damage: float = 50.0
@export var blast_radius: float = 8.0
@export var detection_radius: float = 3.0
@export var arm_time: float = 2.0
@export var lifetime: float = 60.0  # Auto-destruct after 60 seconds

# Mine state
var is_armed: bool = false
var is_triggered: bool = false
var is_destroyed: bool = false
var deployment_time: float = 0.0
var arm_timer: float = 0.0

# Tile system integration
var tile_position: Vector2i = Vector2i.ZERO
var tile_system: Node = null

# Visual and collision components
var mine_mesh: MeshInstance3D
var collision_shape: CollisionShape3D
var detection_area: Area3D
var arm_indicator: MeshInstance3D
var explosion_effect: Node3D

# Audio components
var arm_sound: AudioStreamPlayer3D
var explosion_sound: AudioStreamPlayer3D

# Targeting system
var detected_units: Array[Unit] = []
var trigger_target: Unit = null

# Dependencies
var logger
var asset_loader: Node
var map_generator: Node

# Signals
signal mine_deployed(mine_id: String, position: Vector3)
signal mine_armed(mine_id: String)
signal mine_triggered(mine_id: String, target_unit: Unit)
signal mine_exploded(mine_id: String, position: Vector3, damage: float)
signal mine_destroyed(mine_id: String, reason: String)
signal mine_detected_unit(mine_id: String, unit: Unit)

func _ready() -> void:
    # Set up as Area3D for detection
    collision_layer = 0b1000  # Mine layer
    collision_mask = 0b1      # Unit layer
    
    # Initialize mine
    deployment_time = Time.get_ticks_msec() / 1000.0
    arm_timer = arm_time
    
    # Create visual components
    _create_visual_components()
    
    # Create collision detection
    _create_collision_detection()
    
    # Create audio components
    _create_audio_components()
    
    # Connect signals
    body_entered.connect(_on_unit_entered_detection)
    body_exited.connect(_on_unit_exited_detection)
    
    # Add to mine group
    add_to_group("mines")
    add_to_group("entities")
    
    mine_deployed.emit(mine_id, global_position)
    
    if logger:
        logger.info("MineEntity", "Mine %s deployed at %s by %s" % [mine_id, global_position, owner_unit_id])

func _create_visual_components() -> void:
    """Create visual representation of the mine"""
    
    # Main mine mesh
    mine_mesh = MeshInstance3D.new()
    mine_mesh.name = "MineMesh"
    
    # Create mine visual based on type
    match mine_type:
        "proximity":
            var sphere_mesh = SphereMesh.new()
            sphere_mesh.radius = 0.3
            sphere_mesh.height = 0.6
            mine_mesh.mesh = sphere_mesh
        "timed":
            var cylinder_mesh = CylinderMesh.new()
            cylinder_mesh.top_radius = 0.4
            cylinder_mesh.bottom_radius = 0.4
            cylinder_mesh.height = 0.8
            mine_mesh.mesh = cylinder_mesh
        "remote":
            var box_mesh = BoxMesh.new()
            box_mesh.size = Vector3(0.6, 0.4, 0.6)
            mine_mesh.mesh = box_mesh
    
    # Create mine material
    var mine_material = StandardMaterial3D.new()
    mine_material.albedo_color = Color.RED if team_id == 2 else Color.BLUE
    mine_material.metallic = 0.7
    mine_material.roughness = 0.3
    mine_material.emission_enabled = true
    mine_material.emission = Color.RED * 0.3
    mine_mesh.material_override = mine_material
    
    # Position slightly above ground
    mine_mesh.position = Vector3(0, 0.2, 0)
    add_child(mine_mesh)
    
    # Create arming indicator
    arm_indicator = MeshInstance3D.new()
    arm_indicator.name = "ArmIndicator"
    arm_indicator.mesh = SphereMesh.new()
    arm_indicator.mesh.radius = 0.1
    arm_indicator.position = Vector3(0, 0.8, 0)
    arm_indicator.visible = false
    
    var indicator_material = StandardMaterial3D.new()
    indicator_material.albedo_color = Color.YELLOW
    indicator_material.emission_enabled = true
    indicator_material.emission = Color.YELLOW * 0.8
    arm_indicator.material_override = indicator_material
    
    add_child(arm_indicator)

func _create_collision_detection() -> void:
    """Create collision detection for mine triggering"""
    
    # Main collision shape for the mine body
    collision_shape = CollisionShape3D.new()
    collision_shape.name = "MineCollision"
    
    var sphere_shape = SphereShape3D.new()
    sphere_shape.radius = detection_radius
    collision_shape.shape = sphere_shape
    
    add_child(collision_shape)
    
    # Detection area for early warning
    detection_area = Area3D.new()
    detection_area.name = "DetectionArea"
    detection_area.collision_layer = 0b10000  # Detection layer
    detection_area.collision_mask = 0b1       # Unit layer
    
    var detection_collision = CollisionShape3D.new()
    detection_collision.name = "DetectionCollision"
    
    var detection_shape = SphereShape3D.new()
    detection_shape.radius = detection_radius * 1.5  # Slightly larger for early detection
    detection_collision.shape = detection_shape
    
    detection_area.add_child(detection_collision)
    add_child(detection_area)

func _create_audio_components() -> void:
    """Create audio components for mine sounds"""
    
    # Arming sound
    arm_sound = AudioStreamPlayer3D.new()
    arm_sound.name = "ArmSound"
    arm_sound.max_distance = 20.0
    arm_sound.unit_size = 5.0
    add_child(arm_sound)
    
    # Explosion sound
    explosion_sound = AudioStreamPlayer3D.new()
    explosion_sound.name = "ExplosionSound"
    explosion_sound.max_distance = 50.0
    explosion_sound.unit_size = 10.0
    add_child(explosion_sound)

func setup(logger_ref, asset_loader_ref, map_generator_ref) -> void:
    """Setup mine with dependencies"""
    logger = logger_ref
    asset_loader = asset_loader_ref
    map_generator = map_generator_ref
    
    # Get tile system reference
    if map_generator and map_generator.has_method("get_tile_system"):
        tile_system = map_generator.get_tile_system()
        if tile_system:
            tile_position = tile_system.world_to_tile(global_position)

func _physics_process(delta: float) -> void:
    """Update mine state"""
    
    if is_destroyed:
        return
    
    # Handle arming process
    if not is_armed:
        arm_timer -= delta
        if arm_timer <= 0:
            _arm_mine()
    
    # Handle lifetime
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - deployment_time >= lifetime:
        _destroy_mine("lifetime_expired")
    
    # Update visual indicators
    _update_visual_indicators()
    
    # Handle proximity detection
    if is_armed and mine_type == "proximity":
        _check_proximity_trigger()

func _arm_mine() -> void:
    """Arm the mine for triggering"""
    
    if is_armed:
        return
    
    is_armed = true
    arm_indicator.visible = true
    
    # Play arming sound
    if arm_sound:
        arm_sound.play()
    
    mine_armed.emit(mine_id)
    
    if logger:
        logger.info("MineEntity", "Mine %s armed at %s" % [mine_id, global_position])

func _check_proximity_trigger() -> void:
    """Check for proximity-based triggering"""
    
    if not is_armed or is_triggered:
        return
    
    # Check for enemy units in detection range
    for unit in detected_units:
        if unit and not unit.is_dead and unit.team_id != team_id:
            var distance = global_position.distance_to(unit.global_position)
            if distance <= detection_radius:
                _trigger_mine(unit)
                break

func _trigger_mine(target_unit: Unit = null) -> void:
    """Trigger the mine explosion"""
    
    if is_triggered or is_destroyed:
        return
    
    is_triggered = true
    trigger_target = target_unit
    
    mine_triggered.emit(mine_id, target_unit)
    
    # Start explosion sequence
    _explode_mine()

func _explode_mine() -> void:
    """Execute mine explosion with area damage"""
    
    if logger:
        logger.info("MineEntity", "Mine %s exploding at %s" % [mine_id, global_position])
    
    # Create explosion effect
    _create_explosion_effect()
    
    # Play explosion sound
    if explosion_sound:
        explosion_sound.play()
    
    # Deal area damage
    _deal_area_damage()
    
    # Emit explosion signal
    mine_exploded.emit(mine_id, global_position, damage)
    
    # Remove mine after explosion
    await get_tree().create_timer(0.5).timeout
    _destroy_mine("exploded")

func _create_explosion_effect() -> void:
    """Create visual explosion effect"""
    
    # Create explosion sphere
    explosion_effect = MeshInstance3D.new()
    explosion_effect.name = "ExplosionEffect"
    explosion_effect.mesh = SphereMesh.new()
    explosion_effect.mesh.radius = blast_radius
    explosion_effect.position = global_position
    
    # Create explosion material
    var explosion_material = StandardMaterial3D.new()
    explosion_material.albedo_color = Color.ORANGE
    explosion_material.emission_enabled = true
    explosion_material.emission = Color.ORANGE * 2.0
    explosion_material.flags_transparent = true
    explosion_material.albedo_color.a = 0.7
    explosion_effect.material_override = explosion_material
    
    # Add to scene
    get_parent().add_child(explosion_effect)
    
    # Animate explosion
    var tween = create_tween()
    tween.parallel().tween_property(explosion_effect, "scale", Vector3(1.5, 1.5, 1.5), 0.3)
    tween.parallel().tween_property(explosion_material, "albedo_color:a", 0.0, 0.3)
    tween.tween_callback(explosion_effect.queue_free)

func _deal_area_damage() -> void:
    """Deal damage to all units in blast radius"""
    
    var space_state = get_world_3d().direct_space_state
    var query = PhysicsShapeQueryParameters3D.new()
    query.shape = SphereShape3D.new()
    query.shape.radius = blast_radius
    query.transform.origin = global_position
    query.collision_mask = 0b1  # Unit layer
    
    var results = space_state.intersect_shape(query)
    
    for result in results:
        var collider = result.collider
        if collider.is_in_group("units") and collider != self:
            var unit = collider as Unit
            if unit and not unit.is_dead:
                # Calculate damage based on distance
                var distance = global_position.distance_to(unit.global_position)
                var damage_factor = 1.0 - (distance / blast_radius)
                damage_factor = max(0.2, damage_factor)  # Minimum 20% damage
                
                var actual_damage = damage * damage_factor
                unit.take_damage(actual_damage)
                
                if logger:
                    logger.info("MineEntity", "Mine %s damaged unit %s for %.1f damage" % [mine_id, unit.unit_id, actual_damage])

func _destroy_mine(reason: String) -> void:
    """Destroy the mine"""
    
    if is_destroyed:
        return
    
    is_destroyed = true
    
    mine_destroyed.emit(mine_id, reason)
    
    if logger:
        logger.info("MineEntity", "Mine %s destroyed: %s" % [mine_id, reason])
    
    # Remove from groups
    remove_from_group("mines")
    remove_from_group("entities")
    
    # Clean up and remove from scene
    queue_free()

func _update_visual_indicators() -> void:
    """Update visual indicators based on mine state"""
    
    if not is_armed:
        # Blink during arming
        var blink_time = fmod(Time.get_ticks_msec() / 1000.0, 0.5)
        arm_indicator.visible = blink_time < 0.25
    elif is_armed and not is_triggered:
        # Steady glow when armed
        arm_indicator.visible = true
        
        # Increase glow intensity if enemies nearby
        var has_nearby_enemies = false
        for unit in detected_units:
            if unit and not unit.is_dead and unit.team_id != team_id:
                has_nearby_enemies = true
                break
        
        if has_nearby_enemies:
            var glow_material = arm_indicator.material_override as StandardMaterial3D
            if glow_material:
                glow_material.emission_energy = 1.5
        else:
            var glow_material = arm_indicator.material_override as StandardMaterial3D
            if glow_material:
                glow_material.emission_energy = 0.8

func _on_unit_entered_detection(body: Node3D) -> void:
    """Handle unit entering detection range"""
    
    if body.is_in_group("units"):
        var unit = body as Unit
        if unit and not unit.is_dead and unit not in detected_units:
            detected_units.append(unit)
            mine_detected_unit.emit(mine_id, unit)
            
            if logger:
                logger.debug("MineEntity", "Mine %s detected unit %s" % [mine_id, unit.unit_id])

func _on_unit_exited_detection(body: Node3D) -> void:
    """Handle unit exiting detection range"""
    
    if body.is_in_group("units"):
        var unit = body as Unit
        if unit and unit in detected_units:
            detected_units.erase(unit)

# Manual triggering for remote mines
func remote_trigger() -> void:
    """Manually trigger the mine (for remote mines)"""
    
    if mine_type == "remote" and is_armed and not is_triggered:
        _trigger_mine()

# Timed triggering for timed mines
func timed_trigger(delay: float) -> void:
    """Set up timed triggering"""
    
    if mine_type == "timed" and is_armed and not is_triggered:
        await get_tree().create_timer(delay).timeout
        if not is_triggered and not is_destroyed:
            _trigger_mine()

# Disarm mine (for engineer abilities)
func disarm() -> bool:
    """Disarm the mine safely"""
    
    if is_triggered or is_destroyed:
        return false
    
    _destroy_mine("disarmed")
    return true

# Get mine information
func get_mine_info() -> Dictionary:
    """Get mine information for UI/AI"""
    
    return {
        "mine_id": mine_id,
        "team_id": team_id,
        "owner_unit_id": owner_unit_id,
        "mine_type": mine_type,
        "position": global_position,
        "tile_position": tile_position,
        "is_armed": is_armed,
        "is_triggered": is_triggered,
        "damage": damage,
        "blast_radius": blast_radius,
        "detection_radius": detection_radius,
        "arm_time_remaining": max(0, arm_timer),
        "lifetime_remaining": max(0, lifetime - (Time.get_ticks_msec() / 1000.0 - deployment_time))
    }

# Static factory method for tile-based placement
static func create_mine_at_tile(tile_pos: Vector2i, mine_type: String, team_id: int, owner_unit_id: String, tile_system: Node) -> MineEntity:
    """Create a mine at a specific tile position"""
    
    var mine = MineEntity.new()
    mine.mine_id = "mine_%d_%d_%d" % [tile_pos.x, tile_pos.y, Time.get_ticks_msec()]
    mine.mine_type = mine_type
    mine.team_id = team_id
    mine.owner_unit_id = owner_unit_id
    mine.deployed_by = owner_unit_id
    mine.tile_position = tile_pos
    
    # Convert tile position to world position
    if tile_system and tile_system.has_method("tile_to_world"):
        mine.global_position = tile_system.tile_to_world(tile_pos)
    else:
        # Fallback calculation
        var tile_size = 3.0
        mine.global_position = Vector3(tile_pos.x * tile_size, 0, tile_pos.y * tile_size)
    
    return mine 