# projectile.gd
class_name Projectile
extends Area3D

const IMPACT_EFFECT_SCENE = preload("res://scenes/fx/ImpactEffect.tscn")

var speed: float = 50.0
var damage: float = 10.0
var shooter_team_id: int
var direction: Vector3
var lifetime: float = 3.0 # seconds

func _ready():
    # Set collision mask to hit units (layer 1)
    set_collision_mask_value(1, true)
    
    body_entered.connect(_on_body_entered)
    await get_tree().create_timer(lifetime).timeout
    if is_instance_valid(self):
        queue_free()

func _physics_process(delta: float):
    global_position += direction * speed * delta

func _on_body_entered(body: Node3D):
    # Ensure we don't hit something that's not a unit or is on the same team
    if body is Unit and body.team_id != shooter_team_id:
        body.take_damage(damage)
        _create_impact_effect()
        queue_free()

func _create_impact_effect():
    if IMPACT_EFFECT_SCENE:
        var impact_effect = IMPACT_EFFECT_SCENE.instantiate()
        get_tree().root.add_child(impact_effect)
        impact_effect.global_position = global_position
        impact_effect.emitting = true