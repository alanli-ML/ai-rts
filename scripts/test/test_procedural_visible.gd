# test_procedural_visible.gd - Test that procedural generation creates visible objects
extends Node3D

func _ready() -> void:
    print("=== PROCEDURAL GENERATION VISIBILITY TEST ===")
    await get_tree().process_frame
    
    # Wait for the main scene to initialize
    await get_tree().create_timer(2.0).timeout
    
    # Get the main scene
    var main_scene = get_tree().current_scene
    if not main_scene:
        print("ERROR: Could not find main scene")
        return
    
    # Try to trigger procedural generation directly
    if main_scene.has_method("_initialize_procedural_world"):
        print("Triggering procedural generation...")
        await main_scene._initialize_procedural_world()
        print("Procedural generation complete!")
    else:
        print("Main scene does not have _initialize_procedural_world method")
    
    # Check if procedural objects were created
    _check_procedural_objects()

func _check_procedural_objects() -> void:
    """Check if procedural objects were created and are visible"""
    print("\n=== CHECKING PROCEDURAL OBJECTS ===")
    
    var main_scene = get_tree().current_scene
    if not main_scene:
        print("ERROR: Could not find main scene")
        return
    
    # Check for 3D scene
    var scene_3d = main_scene.get_node("GameUI/GameWorldContainer/GameWorld/3DView")
    if not scene_3d:
        print("ERROR: Could not find 3D scene")
        return
    
    print("3D scene found: %s" % scene_3d.name)
    
    # List all children in the 3D scene
    print("3D scene children:")
    for child in scene_3d.get_children():
        print("  - %s (%s)" % [child.name, child.get_class()])
        
        # Check for procedural containers
        if child.name == "ProceduralBuildings":
            print("    Found procedural buildings container with %d children" % child.get_child_count())
        elif child.name == "Roads":
            print("    Found roads container with %d children" % child.get_child_count())
        elif child.name == "ControlPoints":
            print("    Found control points container with %d children" % child.get_child_count())
            for cp in child.get_children():
                print("      - %s at %s" % [cp.name, cp.position])
    
    print("=== PROCEDURAL OBJECTS CHECK COMPLETE ===")

func _input(event: InputEvent) -> void:
    """Handle input to trigger test"""
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_SPACE:
            print("Manually triggering procedural generation check...")
            _check_procedural_objects() 