# projectile.gd
class_name Projectile
extends Area3D

var speed: float = 50.0
var damage: float = 10.0
var shooter_team_id: int
var direction: Vector3
var lifetime: float = 3.0 # seconds

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
    if hit_unit.team_id == shooter_team_id:
        return # Friendly fire ignored

    # Apply damage
    hit_unit.take_damage(damage)

    # Trigger impact effect on clients
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        root_node.rpc("spawn_impact_effect_rpc", global_position)

    # Destroy projectile after impact
    queue_free()