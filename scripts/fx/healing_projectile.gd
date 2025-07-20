# healing_projectile.gd
class_name HealingProjectile
extends Area3D

var speed: float = 30.0
var heal_amount: float = 25.0
var shooter_team_id: int
var direction: Vector3
var lifetime: float = 2.0 # seconds

func _ready():
    # On clients, this is a visual-only node. On server, it's a logical node.
    if multiplayer.is_server():
        # Server-side projectiles detect hits
        body_entered.connect(_on_body_entered)
        # Set collision mask to hit units (layer 1)
        set_collision_mask_value(1, true)
    else:
        # Client-side projectiles don't need collision
        monitoring = false
        monitorable = false

    # Destroy after lifetime
    await get_tree().create_timer(lifetime).timeout
    if is_instance_valid(self):
        queue_free()

func _physics_process(delta: float):
    global_position += direction * speed * delta

func _on_body_entered(body: Node3D):
    # This logic only runs on the server
    if not (body is Unit):
        return

    var hit_unit = body as Unit
    if hit_unit.team_id != shooter_team_id:
        return # Only heal allies

    # Check if unit needs healing
    if hit_unit.is_dead or hit_unit.get_health_percentage() >= 1.0:
        return # Can't heal dead units or full health units

    # Apply healing
    hit_unit.receive_healing(heal_amount)
    print("Healing projectile healed %s for %d HP" % [hit_unit.unit_id, heal_amount])

    # Trigger healing effect on clients
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node and root_node.has_method("spawn_healing_effect_rpc"):
        root_node.rpc("spawn_healing_effect_rpc", hit_unit.global_position + Vector3(0, 1.5, 0))

    # Destroy projectile after healing
    queue_free() 