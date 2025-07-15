# StaticWorldInitializer.gd - Handle static world initialization as fallback
class_name StaticWorldInitializer
extends Node

# Dependencies
var logger
var scene_3d
var control_points_container
var buildings_container
var units_container

# Signals
signal static_world_initialized()

func _ready() -> void:
    # Initialize when added to scene tree
    pass

func setup(logger_instance, scene_3d_instance, control_points_container_instance, buildings_container_instance, units_container_instance) -> void:
    """Setup the static world initializer with dependencies"""
    logger = logger_instance
    scene_3d = scene_3d_instance
    control_points_container = control_points_container_instance
    buildings_container = buildings_container_instance
    units_container = units_container_instance
    
    logger.info("StaticWorldInitializer", "Static world initializer setup complete")

func initialize_static_world() -> void:
    """Initialize the game world with static control points (fallback)"""
    logger.info("StaticWorldInitializer", "Initializing static game world")
    
    # Initialize control points in the 3D world
    if control_points_container:
        initialize_control_points_3d()
    
    # Initialize building positions
    if buildings_container:
        initialize_buildings_3d()
    
    # Initialize unit containers
    if units_container:
        initialize_units_3d()
    
    static_world_initialized.emit()
    logger.info("StaticWorldInitializer", "Static world initialization complete")

func initialize_control_points_3d() -> void:
    """Initialize control points in the 3D world"""
    logger.info("StaticWorldInitializer", "Initializing control points in 3D world")
    
    # Control points are already positioned in the scene
    # Add visual representations if needed
    for i in range(1, 10):  # Control points 1-9
        var control_point = control_points_container.get_node("ControlPoint%d" % i)
        if control_point:
            # Add visual representation (sphere or other mesh) - MUCH more visible
            var mesh_instance = MeshInstance3D.new()
            var sphere_mesh = SphereMesh.new()
            sphere_mesh.radius = 3.0  # Larger radius
            sphere_mesh.height = 6.0  # Taller height
            mesh_instance.mesh = sphere_mesh
            
            # Position the sphere above the ground to avoid z-fighting
            mesh_instance.position = Vector3(0, 3.0, 0)  # 3 units above ground
            
            # Create VERY visible material
            var material = StandardMaterial3D.new()
            material.albedo_color = Color.YELLOW  # Bright yellow instead of gray
            material.emission_enabled = true
            material.emission = Color.YELLOW * 1.2  # Very bright emission
            material.emission_energy = 4.0  # High energy emission
            material.roughness = 0.0  # Shiny surface
            material.metallic = 0.3
            material.flags_unshaded = true  # Always bright
            mesh_instance.material_override = material
            
            control_point.call_deferred("add_child", mesh_instance)
            logger.info("StaticWorldInitializer", "Control point %d visual added at height 3.0" % i)

func initialize_buildings_3d() -> void:
    """Initialize building positions in the 3D world"""
    logger.info("StaticWorldInitializer", "Initializing buildings in 3D world")
    # Buildings will be spawned dynamically during gameplay

func initialize_units_3d() -> void:
    """Initialize unit containers in the 3D world"""
    logger.info("StaticWorldInitializer", "Initializing units in 3D world")
    # Units will be spawned dynamically during gameplay

func cleanup() -> void:
    """Cleanup static world initializer resources"""
    logger.info("StaticWorldInitializer", "Static world initializer cleanup complete") 