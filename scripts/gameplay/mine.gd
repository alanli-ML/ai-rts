# mine.gd
class_name Mine
extends Area3D

@export var mine_id: String = ""
@export var team_id: int = 0
@export var damage: float = 150.0

func _ready():
    body_entered.connect(_on_body_entered)
    # Add a visual representation
    var mesh_instance = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    box_mesh.size = Vector3(0.5, 0.1, 0.5)
    mesh_instance.mesh = box_mesh
    add_child(mesh_instance)

func _on_body_entered(body: Node3D):
    if body is Unit and body.team_id != self.team_id:
        var entity_manager = get_node_or_null("/root/DependencyContainer/PlaceableEntityManager")
        if entity_manager:
            # Delegate detonation to the manager to handle effects and state
            entity_manager.detonate_mine(mine_id, body)
        else:
            # Fallback if manager isn't found (e.g., in a test scene)
            print("Mine %s exploded on unit %s (manager not found)." % [mine_id, body.unit_id])
            body.take_damage(damage)
            queue_free()