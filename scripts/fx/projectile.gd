# projectile.gd
class_name Projectile
extends Area3D

var speed: float = 50.0
var damage: float = 10.0
var shooter_team_id: int
var direction: Vector3
var lifetime: float = 3.0 # seconds

# Team colors for projectiles (matches weapon attachment colors)
var team_colors: Dictionary = {
	1: Color(0.2, 0.4, 1.0),    # Blue team
	2: Color(1.0, 0.3, 0.2),    # Red team
	3: Color(0.2, 1.0, 0.4),    # Green team
	4: Color(1.0, 0.8, 0.2)     # Yellow team
}

func _ready():
    # Create team-colored projectile mesh (50% larger than original)
    _create_team_colored_mesh()
    
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

func _create_team_colored_mesh():
    """Create a team-colored sphere mesh for the projectile"""
    var mesh_instance = get_node("MeshInstance3D")
    if not mesh_instance:
        return
    
    # Create sphere mesh with 50% larger size (0.1 -> 0.15 radius)
    var sphere_mesh = SphereMesh.new()
    sphere_mesh.radius = 0.15
    sphere_mesh.height = 0.3  # Height also increased proportionally
    mesh_instance.mesh = sphere_mesh
    
    # Create team-colored material
    var material = StandardMaterial3D.new()
    var team_color = team_colors.get(shooter_team_id, Color.WHITE)
    
    # Set material properties for visibility and team identification
    material.albedo_color = team_color
    material.emission_enabled = true
    material.emission = team_color * 2.0  # Bright emission for visibility
    material.emission_energy_multiplier = 3.0  # Extra brightness
    material.metallic = 0.0
    material.roughness = 0.1  # Slightly reflective
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color.a = 0.9  # Slightly transparent for visual appeal
    
    mesh_instance.material_override = material

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