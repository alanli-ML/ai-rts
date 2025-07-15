# GameDisplayManager.gd - Handle dynamic game state display management  
class_name GameDisplayManager
extends Node

# Dependencies
var logger
var world_asset_manager
var scene_3d
var main_node

# Game state display
var displayed_units: Dictionary = {}
var displayed_buildings: Dictionary = {}
var displayed_control_points: Dictionary = {}
var selected_units: Array = []

# Signals
signal game_display_updated(state_data: Dictionary)

func _ready() -> void:
    # Initialize when added to scene tree
    pass

func setup(logger_instance, world_asset_manager_instance, scene_3d_instance, main_node_instance) -> void:
    """Setup the game display manager with dependencies"""
    logger = logger_instance
    world_asset_manager = world_asset_manager_instance
    scene_3d = scene_3d_instance
    main_node = main_node_instance
    
    logger.info("GameDisplayManager", "Game display manager setup complete")

func update_game_display(state_data: Dictionary) -> void:
    """Update the game display with new state"""
    # Update units
    var units_data = state_data.get("units", [])
    for unit_data in units_data:
        var unit_id = unit_data.get("id", "")
        if unit_id != "":
            update_unit_display(unit_id, unit_data)
    
    # Update buildings
    var buildings_data = state_data.get("buildings", [])
    for building_data in buildings_data:
        var building_id = building_data.get("id", "")
        if building_id != "":
            update_building_display(building_id, building_data)
    
    # Update resources display
    var resources_data = state_data.get("resources", {})
    if resources_data.size() > 0:
        update_resources_display(resources_data)
    
    # Update game time
    var game_time = state_data.get("game_time", 0.0)
    update_game_time_display(game_time)
    
    game_display_updated.emit(state_data)

func update_unit_display(unit_id: String, unit_data: Dictionary) -> void:
    """Update a unit's display"""
    var unit_display = displayed_units.get(unit_id)
    
    if not unit_display:
        # Create new unit display
        unit_display = create_unit_display(unit_data)
        displayed_units[unit_id] = unit_display
        
        # Add to the 3D scene
        if scene_3d:
            scene_3d.add_child(unit_display)
            
            # Set position after adding to scene tree
            var position_array = unit_data.get("position", [0, 0, 0])
            var new_position = Vector3(position_array[0], position_array[1], position_array[2])
            unit_display.global_position = new_position
            
            logger.info("GameDisplayManager", "Added unit %s to 3D scene at position %s" % [unit_id, unit_display.global_position])
        else:
            logger.error("GameDisplayManager", "Could not find 3D scene to add unit %s" % unit_id)
    else:
        # Update existing unit position
        var position_array = unit_data.get("position", [0, 0, 0])
        var new_position = Vector3(position_array[0], position_array[1], position_array[2])
        unit_display.global_position = new_position
        
        logger.info("GameDisplayManager", "Updated unit %s position to %s" % [unit_id, unit_display.global_position])

func update_building_display(building_id: String, building_data: Dictionary) -> void:
    """Update a building's display"""
    var building_display = displayed_buildings.get(building_id)
    
    if not building_display:
        # Create new building display
        building_display = create_building_display(building_data)
        displayed_buildings[building_id] = building_display
        
        # Add to the 3D scene
        if scene_3d:
            scene_3d.add_child(building_display)
            logger.info("GameDisplayManager", "Added building %s to 3D scene" % building_id)
        else:
            logger.warning("GameDisplayManager", "Could not find 3D scene to add building %s" % building_id)
    
    # Update position
    var position_array = building_data.get("position", [0, 0, 0])
    var position = Vector3(position_array[0], position_array[1], position_array[2])
    building_display.global_position = position
    
    # Update health
    var health = building_data.get("health", 100)
    var max_health = building_data.get("max_health", 100)
    
    if building_display.has_method("update_health"):
        building_display.update_health(health, max_health)

func create_unit_display(unit_data: Dictionary) -> Node3D:
    """Create a unit display node"""
    var unit_id = unit_data.get("id", "unknown")
    var team_id = unit_data.get("team_id", 1)
    
    # Try to load Kenny character asset
    var character_scene = world_asset_manager.load_character_asset()
    
    if character_scene:
        # Use Kenny character asset
        var unit_display = character_scene.instantiate()
        unit_display.name = "Unit_" + unit_id
        
        # Scale characters appropriately for RTS view
        var scale_factor = randf_range(1.5, 2.0)
        unit_display.scale = Vector3(scale_factor, scale_factor, scale_factor)
        
        # Add some random rotation for variety
        unit_display.rotation_degrees.y = randf_range(0, 360)
        
        # Add team color overlay by finding the MeshInstance3D and modifying materials
        apply_team_color_to_character(unit_display, team_id)
        
        # Add collision for selection
        var collision_shape = CollisionShape3D.new()
        var box_shape = BoxShape3D.new()
        box_shape.size = Vector3(3, 6, 3)  # Approximate character size
        collision_shape.shape = box_shape
        unit_display.add_child(collision_shape)
        
        logger.info("GameDisplayManager", "Created Kenny character unit for team %d: %s" % [team_id, unit_id])
        
        return unit_display
    else:
        # Fallback to generic mesh if Kenny asset fails
        var unit_display = CharacterBody3D.new()
        unit_display.name = "Unit_" + unit_id + "_fallback"
        
        # Add visual representation - make units MUCH larger and more visible
        var mesh_instance = MeshInstance3D.new()
        var box_mesh = BoxMesh.new()
        box_mesh.size = Vector3(5, 8, 5)  # Much larger size
        mesh_instance.mesh = box_mesh
        unit_display.add_child(mesh_instance)
        
        # Add collision shape
        var collision_shape = CollisionShape3D.new()
        var box_shape = BoxShape3D.new()
        box_shape.size = Vector3(5, 8, 5)
        collision_shape.shape = box_shape
        unit_display.add_child(collision_shape)
        
        # Add team colors for better visibility
        var material = StandardMaterial3D.new()
        
        # Team color coding - make them VERY bright
        if team_id == 1:
            material.albedo_color = Color.CYAN  # Bright cyan instead of blue
        elif team_id == 2:
            material.albedo_color = Color.MAGENTA  # Bright magenta instead of red
        else:
            material.albedo_color = Color.YELLOW  # Bright yellow
        
        # Make material VERY visible
        material.emission_enabled = true
        material.emission = material.albedo_color * 0.8  # Very bright emission
        material.emission_energy = 3.0  # High energy
        material.roughness = 0.3
        material.metallic = 0.1
        material.flags_unshaded = true  # Make it always bright
        
        mesh_instance.material_override = material
        
        logger.info("GameDisplayManager", "Created fallback unit display for team %d with color %s" % [team_id, material.albedo_color])
        
        return unit_display

func apply_team_color_to_character(character_node: Node3D, team_id: int) -> void:
    """Apply team color tinting to a Kenny character"""
    var team_color: Color
    
    # Define team colors
    if team_id == 1:
        team_color = Color.CYAN
    elif team_id == 2:
        team_color = Color.MAGENTA
    else:
        team_color = Color.YELLOW
    
    # Find all MeshInstance3D nodes and apply team color modulation
    apply_team_color_recursive(character_node, team_color)

func apply_team_color_recursive(node: Node, team_color: Color) -> void:
    """Recursively apply team color to all MeshInstance3D nodes"""
    if node is MeshInstance3D:
        var mesh_instance = node as MeshInstance3D
        
        # Create a new material or modify existing one
        var material = mesh_instance.material_override
        if not material:
            material = StandardMaterial3D.new()
            # Copy from the original material if it exists
            if mesh_instance.get_surface_override_material(0):
                var original = mesh_instance.get_surface_override_material(0)
                material.albedo_color = original.albedo_color
                material.roughness = original.roughness
                material.metallic = original.metallic
        
        # Apply team color modulation
        material.albedo_color = material.albedo_color * team_color
        material.emission_enabled = true
        material.emission = team_color * 0.3
        material.emission_energy = 1.0
        
        mesh_instance.material_override = material
    
    # Recursively apply to children
    for child in node.get_children():
        apply_team_color_recursive(child, team_color)

func create_building_display(building_data: Dictionary) -> Node3D:
    """Create a building display node"""
    var building_id = building_data.get("id", "unknown")
    var building_type = building_data.get("type", "commercial")
    var team_id = building_data.get("team_id", 0)
    
    # Try to load Kenny building asset
    var building_scene = world_asset_manager.load_building_asset_by_type(building_type)
    
    if building_scene:
        # Use Kenny building asset
        var building_display = building_scene.instantiate()
        building_display.name = "Building_" + building_id
        
        # Scale buildings appropriately
        var scale_factor = randf_range(0.8, 1.2)
        building_display.scale = Vector3(scale_factor, scale_factor, scale_factor)
        
        # Add some random rotation for variety
        building_display.rotation_degrees.y = randf_range(0, 360)
        
        # Apply team coloring if the building is owned by a team
        if team_id > 0:
            apply_team_color_to_building(building_display, team_id)
        
        logger.info("GameDisplayManager", "Created Kenny building display: %s (team %d)" % [building_id, team_id])
        
        return building_display
    else:
        # Fallback to generic mesh if Kenny asset fails
        var building_display = Node3D.new()
        building_display.name = "Building_" + building_id + "_fallback"
        
        # Add visual representation (simplified)
        var mesh_instance = MeshInstance3D.new()
        mesh_instance.mesh = BoxMesh.new()
        mesh_instance.mesh.size = Vector3(2, 2, 2)
        building_display.add_child(mesh_instance)
        
        # Add team coloring
        var material = StandardMaterial3D.new()
        material.albedo_color = Color.DARK_RED if team_id == 1 else Color.DARK_BLUE
        mesh_instance.material_override = material
        
        logger.info("GameDisplayManager", "Created fallback building display: %s (team %d)" % [building_id, team_id])
        
        return building_display

func apply_team_color_to_building(building_node: Node3D, team_id: int) -> void:
    """Apply team color tinting to a Kenny building"""
    var team_color: Color
    
    # Define team colors
    if team_id == 1:
        team_color = Color.CYAN * 0.7  # Slightly darker for buildings
    elif team_id == 2:
        team_color = Color.MAGENTA * 0.7
    else:
        team_color = Color.YELLOW * 0.7
    
    # Find all MeshInstance3D nodes and apply team color modulation
    apply_team_color_recursive(building_node, team_color)

func update_resources_display(resources_data: Dictionary) -> void:
    """Update the resources display"""
    var resources_text = "Resources: "
    for team_id in resources_data:
        var team_resources = resources_data[team_id]
        resources_text += "Team %d - Energy: %d, Minerals: %d  " % [team_id, team_resources.get("energy", 0), team_resources.get("minerals", 0)]
    
    if main_node and main_node.has_node("GameUI"):
        var resources_label = main_node.get_node("GameUI/GameOverlay/TopPanel/ResourcesLabel")
        if resources_label:
            resources_label.text = resources_text

func update_game_time_display(game_time: float) -> void:
    """Update the game time display"""
    var minutes = int(game_time / 60)
    var seconds = int(game_time) % 60
    var time_text = "%02d:%02d" % [minutes, seconds]
    
    if main_node and main_node.has_node("GameUI"):
        var time_label = main_node.get_node("GameUI/GameOverlay/TopPanel/GameTimeLabel")
        if time_label:
            time_label.text = "Time: " + time_text

func clear_game_display() -> void:
    """Clear the game display"""
    # Clear displayed units
    for unit_id in displayed_units:
        var unit_display = displayed_units[unit_id]
        if unit_display:
            unit_display.queue_free()
    displayed_units.clear()
    
    # Clear displayed buildings
    for building_id in displayed_buildings:
        var building_display = displayed_buildings[building_id]
        if building_display:
            building_display.queue_free()
    displayed_buildings.clear()
    
    # Clear selection
    selected_units.clear()
    
    logger.info("GameDisplayManager", "Game display cleared")

func cleanup() -> void:
    """Cleanup game display manager resources"""
    clear_game_display()
    logger.info("GameDisplayManager", "Game display manager cleanup complete") 