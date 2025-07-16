# building.gd
class_name BuildingEntity
extends StaticBody3D

@export var building_id: String = ""
@export var building_type: String = "power_spire"
@export var team_id: int = 0

var max_health: float = 500.0
var current_health: float = 0.0
var construction_progress: float = 0.0 # 0.0 to 1.0
var is_operational: bool = false
const CONSTRUCTION_RATE = 0.1 # 10% progress per second

func _ready():
    # Set initial health based on construction progress
    current_health = max_health * construction_progress
    
    # Add a visual representation
    var mesh_instance = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    box_mesh.size = Vector3(5, 5, 5)
    mesh_instance.mesh = box_mesh
    add_child(mesh_instance)
    
    var material = StandardMaterial3D.new()
    material.albedo_color = Color(0.5, 0.5, 0.5, 0.5) # Semi-transparent when under construction
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mesh_instance.material_override = material
    
    # Add collision
    var collision_shape = CollisionShape3D.new()
    collision_shape.shape = box_mesh.create_trimesh_shape()
    add_child(collision_shape)

func add_construction_progress(amount: float):
    if is_operational: return
    
    construction_progress = min(construction_progress + amount, 1.0)
    current_health = max_health * construction_progress
    
    # Update visual transparency based on progress
    var mesh_instance = find_child("MeshInstance3D", false)
    if mesh_instance and mesh_instance.material_override:
        mesh_instance.material_override.albedo_color.a = 0.5 + (construction_progress * 0.5)

    if construction_progress >= 1.0:
        _finish_construction()

func _finish_construction():
    is_operational = true
    print("Building %s is now operational." % building_id)
    
    var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
    if audio_manager:
        audio_manager.play_sound_3d("res://assets/audio/ui/command_submit_01.wav", global_position)
        
    # Update visual to be solid
    var mesh_instance = find_child("MeshInstance3D", false)
    if mesh_instance and mesh_instance.material_override:
        mesh_instance.material_override.albedo_color.a = 1.0
        # Change color based on team
        if team_id == 1:
            mesh_instance.material_override.albedo_color = Color.BLUE
        elif team_id == 2:
            mesh_instance.material_override.albedo_color = Color.RED
            
func take_damage(amount: float):
    if not is_operational: return
    current_health = max(0, current_health - amount)
    if current_health <= 0:
        die()

func die():
    print("Building %s has been destroyed." % building_id)
    queue_free()

func get_building_info() -> Dictionary:
    return {
        "id": building_id,
        "type": building_type,
        "team_id": team_id,
        "health_pct": (current_health / max_health) * 100.0 if max_health > 0 else 0,
        "progress": construction_progress,
        "is_operational": is_operational,
        "position": [global_position.x, global_position.y, global_position.z]
    }