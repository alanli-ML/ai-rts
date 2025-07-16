# GameHUD.gd - Refactored game HUD script
class_name GameHUD
extends Control

# UI References
@onready var energy_label = $TopBar/HBoxContainer/EnergyLabel
@onready var node_label = $TopBar/HBoxContainer/NodeLabel
@onready var selection_info_container = $TopBar/HBoxContainer/SelectionInfoContainer
@onready var command_input = $BottomBar/HBoxContainer/CommandInput
@onready var spawn_scout_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnScout
@onready var spawn_tank_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnTank
@onready var spawn_sniper_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnSniper
@onready var spawn_medic_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnMedic
@onready var spawn_engineer_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnEngineer
@onready var hover_tooltip = $HoverTooltip

# System References
var resource_manager
var node_capture_system
var team_unit_spawner
var selection_system
var audio_manager

func _ready() -> void:
    # Get system references from DependencyContainer
    var dc = get_node_or_null("/root/DependencyContainer")
    if dc:
        resource_manager = dc.get_resource_manager()
        node_capture_system = dc.get_node_capture_system()
        team_unit_spawner = dc.get_team_unit_spawner()
        audio_manager = dc.get_audio_manager()

    # Find the selection system - it might not be ready immediately
    call_deferred("_find_selection_system")

    # Connect signals with proper error checking
    if resource_manager:
        resource_manager.resource_changed.connect(_on_resource_changed)
    if node_capture_system:
        node_capture_system.team_node_count_changed.connect(_on_node_count_changed)
    if selection_system and selection_system.has_signal("selection_changed"):
        selection_system.selection_changed.connect(_on_selection_changed)
    else:
        print("GameHUD: Warning - Selection system not found or doesn't have selection_changed signal")
    
    command_input.text_submitted.connect(_on_command_submitted)
    spawn_scout_button.pressed.connect(func(): _on_spawn_pressed("scout"))
    spawn_tank_button.pressed.connect(func(): _on_spawn_pressed("tank"))
    spawn_sniper_button.pressed.connect(func(): _on_spawn_pressed("sniper"))
    spawn_medic_button.pressed.connect(func(): _on_spawn_pressed("medic"))
    spawn_engineer_button.pressed.connect(func(): _on_spawn_pressed("engineer"))
    
    # Make command input active by default and capture keyboard input
    _setup_command_input()
    
    # Initial UI update
    _update_energy_display(1000, 0.0)
    _update_node_display(0)
    _update_selection_display([])
    hover_tooltip.visible = false

func _setup_command_input():
    """Setup command input to be active by default and capture all keyboard input"""
    if command_input:
        # Ensure the LineEdit is properly configured for interaction
        command_input.editable = true
        command_input.mouse_filter = Control.MOUSE_FILTER_PASS
        command_input.focus_mode = Control.FOCUS_ALL
        
        # Make the command input grab focus immediately
        call_deferred("_grab_command_focus")
        
        # Connect focus signals to maintain focus
        command_input.focus_exited.connect(_on_command_input_focus_lost)
        
        print("GameHUD: Command input configured for automatic keyboard capture")

func _grab_command_focus():
    """Grab focus for command input with a frame delay"""
    if command_input and is_visible_in_tree():
        command_input.grab_focus()
        print("GameHUD: Command input focus grabbed")

func _on_command_input_focus_lost():
    """Automatically regrab focus when command input loses focus"""
    # Small delay to avoid conflicts with other UI interactions
    await get_tree().process_frame
    if command_input and is_visible_in_tree():
        command_input.grab_focus()

func _unhandled_input(event: InputEvent):
    """Capture keyboard input and route it to command input"""
    if not command_input or not is_visible_in_tree():
        return
        
    # Handle Enter key specifically for command submission
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
            if not command_input.has_focus():
                # If command input doesn't have focus but user pressed Enter, 
                # focus it and let them type
                command_input.grab_focus()
                get_viewport().set_input_as_handled()
                return
            # If it already has focus, the text_submitted signal will handle it
            return
        
        # For any other key, ensure command input has focus
        if not command_input.has_focus():
            command_input.grab_focus()
            # Let the input be processed by the LineEdit

func _physics_process(_delta):
    if hover_tooltip.visible:
        hover_tooltip.global_position = get_global_mouse_position() + Vector2(15, 15)

func _find_selection_system():
    # The selection system is added to a group, which is a robust way to find it
    # without relying on specific scene tree paths.
    await get_tree().process_frame # Wait for nodes to be ready
    var nodes = get_tree().get_nodes_in_group("selection_systems")
    if not nodes.is_empty():
        selection_system = nodes[0]
        # Connect signals if not already connected
        if not selection_system.is_connected("selection_changed", _on_selection_changed):
             selection_system.selection_changed.connect(_on_selection_changed)
        if not selection_system.is_connected("unit_hovered", _on_unit_hovered):
             selection_system.unit_hovered.connect(_on_unit_hovered)
        print("GameHUD: Successfully connected to EnhancedSelectionSystem.")
    else:
        print("GameHUD: FATAL - Could not find EnhancedSelectionSystem via group.")


func _on_resource_changed(team_id: int, resource_type: int, new_amount: int):
    # Assuming client is team 1 for now
    if team_id == 1 and resource_type == resource_manager.ResourceType.ENERGY:
        var rate = 0.0
        if resource_manager and resource_manager.team_income_rates.has(team_id):
            rate = resource_manager.team_income_rates[team_id].get("energy", 0)
        _update_energy_display(new_amount, rate)

func _on_node_count_changed(team_id: int, new_count: int):
    # Assuming client is team 1
    if team_id == 1:
        _update_node_display(new_count)

func _on_selection_changed(selected_units: Array):
    _update_selection_display(selected_units)

func _on_unit_hovered(unit: Unit):
    if is_instance_valid(unit) and not unit.is_dead:
        var info_label = hover_tooltip.get_node("MarginContainer/InfoLabel")
        var health_color = "green"
        var health_pct = unit.get_health_percentage()
        if health_pct < 0.66: health_color = "yellow"
        if health_pct < 0.33: health_color = "red"
        
        info_label.text = "[b]%s[/b]\n[color=%s]Health: %d/%d[/color]" % [
            unit.archetype.capitalize(),
            health_color,
            int(unit.current_health),
            int(unit.max_health)
        ]
        hover_tooltip.visible = true
    else:
        hover_tooltip.visible = false

func _on_command_submitted(text: String):
    if text.is_empty():
        print("GameHUD: Empty command entered")
        command_input.grab_focus()  # Keep focus for next command
        return
        
    if not selection_system:
        print("GameHUD: No selection system available")
        command_input.clear()
        command_input.grab_focus()
        return
    
    var selected_units = selection_system.get_selected_units()
    if selected_units.is_empty():
        print("GameHUD: No units selected to command")
        command_input.clear()
        command_input.grab_focus()
        return

    var unit_ids = []
    for unit in selected_units:
        unit_ids.append(unit.unit_id)

    print("GameHUD: Submitting command '%s' to %d units" % [text, unit_ids.size()])
    
    if audio_manager:
        audio_manager.play_sound_2d("res://assets/audio/ui/command_submit_01.wav")
    
    # Send command to server via RPC
    get_node("/root/UnifiedMain").rpc("submit_command_rpc", text, unit_ids)
    
    command_input.clear()
    command_input.grab_focus()  # Immediately ready for next command

func _on_spawn_pressed(archetype: String):
    if audio_manager:
        audio_manager.play_sound_2d("res://assets/audio/ui/click_01.wav")

    if team_unit_spawner:
        # Assuming client is team 1 for now
        # In a real game, we'd get the client's actual team ID
        team_unit_spawner.request_spawn_unit(1, archetype)

func _update_energy_display(amount: int, rate: float):
    energy_label.text = "Energy: %d (+%.1f/s)" % [amount, rate]

func _update_node_display(count: int):
    node_label.text = "Nodes: %d/9" % count

func _update_selection_display(selected_units: Array):
    # Clear previous labels
    for child in selection_info_container.get_children():
        child.queue_free()

    if selected_units.is_empty():
        var label = Label.new()
        label.text = "Selected: 0"
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        selection_info_container.add_child(label)
    else:
        for unit in selected_units:
            if not is_instance_valid(unit): continue
            var plan_summary = unit.get("plan_summary", "Idle")
            var label_text = "%s (%s): %s" % [unit.archetype.capitalize(), unit.unit_id.right(4), plan_summary]
            var label = Label.new()
            label.text = label_text
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            selection_info_container.add_child(label)

func _find_selection_system_old():
    """Find the selection system using multiple approaches"""
    # The selection system is a child of the map, which is a child of UnifiedMain.
    # The HUD is also a child of UnifiedMain. The safest way is to get it from the parent.
    var map_node = get_parent().find_child("TestMap", false)
    if map_node:
        selection_system = map_node.find_child("EnhancedSelectionSystem", false)
        if selection_system:
            print("GameHUD: Found selection system in TestMap node.")
            return

    # Fallback if the above fails
    await get_tree().process_frame
    selection_system = get_tree().get_first_node_in_group("selection_systems")
    if selection_system:
        print("GameHUD: Found selection system by group after waiting a frame.")
        return

    print("GameHUD: Warning - Could not find selection system")