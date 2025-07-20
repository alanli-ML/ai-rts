class_name FogOfWarManager
extends Node3D

@onready var fog_plane: MeshInstance3D = $FogPlane

var shader_material: ShaderMaterial
var visibility_texture: ImageTexture
var visibility_image: Image
var camera: Camera3D

# Debug variables
var last_update_time: float = 0.0
var update_count: int = 0
var debug_enabled: bool = false

func _ready() -> void:
    # Add to group for easy discovery
    add_to_group("fog_managers")
    
    if not is_instance_valid(fog_plane):
        print("FogOfWarManager: ERROR - FogPlane node not found!")
        set_process(false)
        return
        
    shader_material = fog_plane.material_override
    if not shader_material:
        print("FogOfWarManager: ERROR - FogPlane has no shader material!")
        set_process(false)
        return

    # The visibility_texture uniform is now initialized with a placeholder
    # in the FogOfWar.tscn file, so we no longer need to create one here.

    # Defer camera search to ensure it's ready
    call_deferred("_find_camera")
    
    print("FogOfWarManager: Initialized with 3D fog plane approach at path: %s" % get_path())
    print("FogOfWarManager: Initial fog plane position: %s" % fog_plane.global_position)
    print("FogOfWarManager: Initial fog plane size: %s" % (fog_plane.mesh as QuadMesh).size)

func _process(_delta: float) -> void:
    # No need to update camera matrices manually since spatial shader handles it automatically
    if not is_instance_valid(camera) and Engine.get_frames_drawn() % 60 == 0:
        _find_camera()

func update_visibility_grid(grid_data: PackedByteArray, grid_meta: Dictionary) -> void:
    if not shader_material or not grid_meta.has("width"): 
        if debug_enabled:
            print("FogOfWarManager: Skipping visibility update - missing shader material or width")
        return

    var width = grid_meta.width
    var height = grid_meta.height
    update_count += 1
    
    if debug_enabled:
        print("FogOfWarManager: Update #%d - Visibility grid: %dx%d, data size: %d bytes" % [update_count, width, height, grid_data.size()])
        
        # Sample some data points to see if we're getting meaningful data
        if grid_data.size() > 0:
            var sample_indices = [0, grid_data.size() / 4, grid_data.size() / 2, grid_data.size() - 1]
            var sample_values = []
            for i in sample_indices:
                if i < grid_data.size():
                    sample_values.append(grid_data[i])
            print("FogOfWarManager: Sample visibility values: %s" % str(sample_values))
    
    # Check if we need to recreate the texture (e.g., first time, or if grid size changes)
    if not is_instance_valid(visibility_image) or visibility_image.get_width() != width or visibility_image.get_height() != height:
        visibility_image = Image.create(width, height, false, Image.FORMAT_R8)
        visibility_texture = ImageTexture.create_from_image(visibility_image)
        
        # CRITICAL: Set the texture parameter in the shader
        shader_material.set_shader_parameter("visibility_texture", visibility_texture)
        print("FogOfWarManager: Created new visibility texture %dx%d and set shader parameter" % [width, height])
        
        # Pass map dimensions to shader
        var map_world_size = Vector2(grid_meta.cell_size * width, grid_meta.cell_size * height)
        shader_material.set_shader_parameter("map_world_size", map_world_size)
        shader_material.set_shader_parameter("map_world_origin", grid_meta.origin)
        
        # Update fog plane size to match map
        var quad_mesh = fog_plane.mesh as QuadMesh
        if quad_mesh:
            quad_mesh.size = map_world_size
        
        print("FogOfWarManager: Updated fog plane size to %s, origin: %s" % [map_world_size, grid_meta.origin])

    # Update the image data with the new visibility grid
    visibility_image.set_data(width, height, false, Image.FORMAT_R8, grid_data)
    visibility_texture.update(visibility_image)
    
    # CRITICAL: Ensure the shader parameter is always up to date
    shader_material.set_shader_parameter("visibility_texture", visibility_texture)
    
    # Force material refresh to ensure shader picks up the new texture
    fog_plane.material_override = null
    fog_plane.material_override = shader_material
    
    last_update_time = Time.get_ticks_msec() / 1000.0
    
    if debug_enabled and update_count % 30 == 0:  # Every 30 updates (every ~2 seconds)
        print("FogOfWarManager: Fog updated successfully (update #%d) - texture set in shader" % update_count)
        
        # Verify the texture parameter was set correctly
        var current_texture = shader_material.get_shader_parameter("visibility_texture")
        if current_texture == visibility_texture:
            print("FogOfWarManager: ✓ Visibility texture parameter verified in shader")
        else:
            print("FogOfWarManager: ✗ WARNING - Visibility texture parameter mismatch!")

func _find_camera() -> void:
    # Look for RTS cameras first (preferred)
    var rts_cameras = get_tree().get_nodes_in_group("rts_cameras")
    if rts_cameras.size() > 0:
        var rts_camera = rts_cameras[0]
        if rts_camera.has_method("get_camera_3d"):
            camera = rts_camera.get_camera_3d()
        elif rts_camera.has_node("Camera3D"):
            camera = rts_camera.get_node("Camera3D")
        else:
            camera = rts_camera if rts_camera is Camera3D else null
            
        if camera:
            print("FogOfWarManager: Found RTS camera: %s" % camera.name)
            return
    
    # Fallback to viewport camera
    camera = get_viewport().get_camera_3d()
    if camera:
        print("FogOfWarManager: Found viewport camera: %s" % camera.name)
    else:
        print("FogOfWarManager: Could not find any Camera3D. Retrying...")

func set_fog_height(height: float) -> void:
    """Set the height of the fog plane"""
    if shader_material:
        shader_material.set_shader_parameter("fog_height", height)
    
    fog_plane.position.y = height
    
    if debug_enabled:
        print("FogOfWarManager: Set fog height to %f" % height)

func set_fog_visibility(visible: bool) -> void:
    """Enable or disable fog of war visibility"""
    fog_plane.visible = visible
    
    if debug_enabled:
        print("FogOfWarManager: Set fog visibility to %s" % str(visible))

func toggle_debug() -> void:
    """Toggle debug output"""
    debug_enabled = !debug_enabled
    print("FogOfWarManager: Debug mode %s" % ("enabled" if debug_enabled else "disabled"))

func toggle_debug_visualization() -> void:
    """Toggle debug visualization mode in shader"""
    if shader_material:
        var current_debug = shader_material.get_shader_parameter("debug_mode")
        var new_debug = not current_debug
        shader_material.set_shader_parameter("debug_mode", new_debug)
        
        # Verify the parameter was set
        var actual_debug = shader_material.get_shader_parameter("debug_mode")
        print("FogOfWarManager: Debug visualization %s (was: %s, set to: %s, actual: %s)" % [
            "enabled" if new_debug else "disabled", 
            str(current_debug), 
            str(new_debug), 
            str(actual_debug)
        ])
        
        # Force a material update
        fog_plane.material_override = shader_material
        
        # Also try updating the visibility texture to trigger a shader refresh
        if is_instance_valid(visibility_texture):
            visibility_texture.update(visibility_image)
            print("FogOfWarManager: Forced texture and material update")
    else:
        print("FogOfWarManager: Error - no shader material available for debug toggle")

func force_shader_reload() -> void:
    """Force reload the shader material to apply parameter changes"""
    if shader_material and fog_plane:
        # Store current parameters
        var params = {}
        for param_name in ["fog_color", "map_world_size", "map_world_origin", "fog_height", "visibility_threshold", "edge_softness", "debug_mode", "visibility_texture"]:
            params[param_name] = shader_material.get_shader_parameter(param_name)
        
        # Recreate the material
        var new_material = shader_material.duplicate()
        
        # Restore parameters
        for param_name in params:
            new_material.set_shader_parameter(param_name, params[param_name])
        
        # Apply to fog plane
        fog_plane.material_override = new_material
        shader_material = new_material
        
        print("FogOfWarManager: Forced shader material reload")

func recreate_shader_from_scratch() -> void:
    """Completely recreate the shader material from the shader file"""
    if not fog_plane:
        print("FogOfWarManager: Error - no fog plane to apply shader to")
        return
    
    # Load the shader fresh from file
    var shader_path = "res://scripts/fx/fog_of_war.gdshader"
    var shader_resource = ResourceLoader.load(shader_path)
    
    if not shader_resource:
        print("FogOfWarManager: Error - could not load shader from %s" % shader_path)
        return
    
    # Create a completely new ShaderMaterial
    var new_material = ShaderMaterial.new()
    new_material.shader = shader_resource
    
    # Set all parameters to match what we expect
    new_material.set_shader_parameter("fog_color", Color(0.0, 0.0, 0.0, 0.7))
    new_material.set_shader_parameter("map_world_size", Vector2(120, 120))
    new_material.set_shader_parameter("map_world_origin", Vector2(-60, -60))
    new_material.set_shader_parameter("fog_height", 8.0)
    new_material.set_shader_parameter("visibility_threshold", 0.4)
    new_material.set_shader_parameter("edge_softness", 0.15)
    new_material.set_shader_parameter("debug_mode", false)
    
    # Set visibility texture if we have one
    if is_instance_valid(visibility_texture):
        new_material.set_shader_parameter("visibility_texture", visibility_texture)
    
    # Apply the new material
    fog_plane.material_override = new_material
    shader_material = new_material
    
    print("FogOfWarManager: Completely recreated shader material from scratch")
    print("FogOfWarManager: New material class: %s" % new_material.get_class())
    print("FogOfWarManager: Shader path: %s" % shader_resource.resource_path)

func debug_coordinate_mapping(world_pos: Vector3) -> Dictionary:
    """Debug coordinate mapping from world position to texture UV"""
    if not shader_material:
        return {"error": "No shader material"}
    
    var map_world_size = shader_material.get_shader_parameter("map_world_size")
    var map_world_origin = shader_material.get_shader_parameter("map_world_origin")
    
    if not map_world_size or not map_world_origin:
        return {"error": "Missing shader parameters"}
    
    # Calculate UV coordinates (same as shader)
    var map_uv = Vector2(
        (world_pos.x - map_world_origin.x) / map_world_size.x,
        (world_pos.z - map_world_origin.y) / map_world_size.y
    )
    
    # Calculate texture pixel coordinates
    var texture_coords = Vector2.ZERO
    if is_instance_valid(visibility_image):
        texture_coords = Vector2(
            map_uv.x * visibility_image.get_width(),
            map_uv.y * visibility_image.get_height()
        )
    
    return {
        "world_pos": world_pos,
        "map_world_size": map_world_size,
        "map_world_origin": map_world_origin,
        "map_uv": map_uv,
        "texture_coords": texture_coords,
        "texture_size": Vector2(visibility_image.get_width(), visibility_image.get_height()) if is_instance_valid(visibility_image) else Vector2.ZERO
    }

func sample_visibility_at_world_pos(world_pos: Vector3) -> Dictionary:
    """Sample visibility value at a specific world position for debugging"""
    if not is_instance_valid(visibility_image):
        return {"error": "No visibility image"}
    
    var coord_info = debug_coordinate_mapping(world_pos)
    if coord_info.has("error"):
        return coord_info
    
    var texture_coords = coord_info.texture_coords
    var x = int(clamp(texture_coords.x, 0, visibility_image.get_width() - 1))
    var y = int(clamp(texture_coords.y, 0, visibility_image.get_height() - 1))
    
    var pixel_color = visibility_image.get_pixel(x, y)
    var visibility_value = pixel_color.r  # R8 format stores value in red channel
    
    coord_info["pixel_coords"] = Vector2(x, y)
    coord_info["visibility_value"] = visibility_value
    coord_info["is_visible"] = visibility_value > 0.5
    
    return coord_info

func test_fog_rendering() -> void:
    """Test function to verify fog rendering is working"""
    if not shader_material:
        print("FogOfWarManager: TEST FAILED - No shader material")
        return
    
    # Set fog to bright red for testing
    shader_material.set_shader_parameter("fog_color", Color(1.0, 0.0, 0.0, 1.0))
    shader_material.set_shader_parameter("debug_mode", true)
    
    # Create a test visibility texture if we don't have one
    if not is_instance_valid(visibility_texture):
        visibility_image = Image.create(32, 32, false, Image.FORMAT_R8)
        visibility_image.fill(Color(0, 0, 0))  # All fogged
        visibility_texture = ImageTexture.create_from_image(visibility_image)
        shader_material.set_shader_parameter("visibility_texture", visibility_texture)
    
    # Force material update
    fog_plane.material_override = null
    fog_plane.material_override = shader_material
    fog_plane.visible = true
    
    print("FogOfWarManager: TEST - Set fog to bright red, debug mode ON")
    print("FogOfWarManager: TEST - Fog plane visible: %s, position: %s" % [fog_plane.visible, fog_plane.global_position])
    print("FogOfWarManager: TEST - Fog plane scale: %s" % fog_plane.scale)
    
func get_debug_info() -> Dictionary:
    """Get debug information about fog of war state"""
    return {
        "update_count": update_count,
        "last_update_time": last_update_time,
        "has_camera": is_instance_valid(camera),
        "has_visibility_texture": is_instance_valid(visibility_texture),
        "fog_plane_visible": fog_plane.visible,
        "fog_plane_position": fog_plane.global_position,
        "visibility_image_size": Vector2(visibility_image.get_width(), visibility_image.get_height()) if is_instance_valid(visibility_image) else Vector2.ZERO,
        "shader_parameters": {
            "map_world_size": shader_material.get_shader_parameter("map_world_size") if shader_material else null,
            "map_world_origin": shader_material.get_shader_parameter("map_world_origin") if shader_material else null,
            "fog_color": shader_material.get_shader_parameter("fog_color") if shader_material else null,
            "visibility_threshold": shader_material.get_shader_parameter("visibility_threshold") if shader_material else null,
            "debug_mode": shader_material.get_shader_parameter("debug_mode") if shader_material else null
        }
    }