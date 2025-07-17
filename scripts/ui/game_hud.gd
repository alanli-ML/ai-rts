# GameHUD.gd - Refactored game HUD script
class_name GameHUD
extends Control

# UI References
@onready var energy_label = $TopBar/HBoxContainer/EnergyLabel
@onready var node_label = $TopBar/HBoxContainer/NodeLabel
@onready var action_queue_list = $UnitActionQueuePanel/MarginContainer/ScrollContainer/ActionQueueList
@onready var command_input = $BottomBar/HBoxContainer/CommandInput
@onready var spawn_scout_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnScout
@onready var spawn_tank_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnTank
@onready var spawn_sniper_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnSniper
@onready var spawn_medic_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnMedic
@onready var spawn_engineer_button = $BottomBar/HBoxContainer/SpawnButtons/SpawnEngineer
@onready var hover_tooltip = $HoverTooltip
@onready var command_status_label = $CommandStatusPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var command_summary_label = $CommandStatusPanel/MarginContainer/VBoxContainer/SummaryLabel

# System References
var resource_manager
var node_capture_system
var team_unit_spawner
var selection_system
var audio_manager
var ai_command_processor

func _ready() -> void:
    # Get system references from DependencyContainer
    var dc = get_node_or_null("/root/DependencyContainer")
    if dc:
        resource_manager = dc.get_resource_manager()
        node_capture_system = dc.get_node_capture_system()
        team_unit_spawner = dc.get_team_unit_spawner()
        audio_manager = dc.get_audio_manager()
        ai_command_processor = dc.get_node_or_null("AICommandProcessor")

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
    if ai_command_processor:
        ai_command_processor.processing_started.connect(_on_ai_processing_started)
        ai_command_processor.processing_finished.connect(_on_ai_processing_finished)
        ai_command_processor.plan_processed.connect(_on_ai_plan_processed)
        ai_command_processor.command_failed.connect(_on_ai_command_failed)
    
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
    var unit_ids: Array[String] = []
    
    if selected_units.is_empty():
        # No units selected - send as group command for entire team
        print("GameHUD: Submitting group command '%s' for entire team" % text)
    else:
        # Specific units selected
        for unit in selected_units:
            unit_ids.append(unit.unit_id)
        print("GameHUD: Submitting command '%s' to %d selected units" % [text, unit_ids.size()])
    
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
    for child in action_queue_list.get_children():
        child.queue_free()

    if selected_units.is_empty():
        var label = Label.new()
        label.text = "No units selected."
        action_queue_list.add_child(label)
    else:
        print("GameHUD: Updating selection display for %d units (server: %s)" % [selected_units.size(), multiplayer.is_server()])
        
        # Show detailed plan data for selected units
        for unit in selected_units:
            if not is_instance_valid(unit): continue
            
            print("GameHUD: Processing unit %s - strategic_goal: '%s'" % [unit.unit_id, unit.strategic_goal])
            
            var unit_short_id = unit.unit_id.right(4) if unit.unit_id.length() >= 4 else unit.unit_id
            var unit_header = "[font_size=20][b]%s (%s)[/b][/font_size]" % [unit.archetype.capitalize(), unit_short_id]
            
            # Add unit header
            var header_label = RichTextLabel.new()
            header_label.bbcode_enabled = true
            header_label.text = unit_header
            header_label.fit_content = true
            action_queue_list.add_child(header_label)
            
            # Show unit goal if available
            var unit_goal = ""
            if "strategic_goal" in unit and not unit.strategic_goal.is_empty():
                unit_goal = unit.strategic_goal
                print("GameHUD: Unit %s has goal: '%s'" % [unit.unit_id, unit_goal])
            else:
                unit_goal = "No specific goal assigned"
                print("GameHUD: Unit %s has no goal set (strategic_goal: '%s')" % [unit.unit_id, unit.strategic_goal])
            
            var goal_label = RichTextLabel.new()
            goal_label.bbcode_enabled = true
            goal_label.text = "[font_size=16][color=lightgreen][b]Goal:[/b] %s[/color][/font_size]" % unit_goal
            goal_label.fit_content = true
            action_queue_list.add_child(goal_label)
            
            # Add a small separator
            var separator_mini = RichTextLabel.new()
            separator_mini.bbcode_enabled = true
            separator_mini.text = " "
            separator_mini.fit_content = true
            action_queue_list.add_child(separator_mini)
            
            # Show detailed plan if available
            var full_plan = []
            if "full_plan" in unit and unit.full_plan is Array:
                full_plan = unit.full_plan
            
            if not full_plan.is_empty():
                var sequential_steps = full_plan.filter(func(s): return s.get("status") != "triggered")
                var triggered_steps = full_plan.filter(func(s): return s.get("status") == "triggered")

                if not sequential_steps.is_empty():
                    _add_detailed_plan_display(sequential_steps)
                else:
                    var no_plan_label = RichTextLabel.new()
                    no_plan_label.bbcode_enabled = true
                    no_plan_label.text = "[i]No sequential plan.[/i]"
                    no_plan_label.fit_content = true
                    action_queue_list.add_child(no_plan_label)

                if not triggered_steps.is_empty():
                    var separator = RichTextLabel.new()
                    separator.bbcode_enabled = true
                    separator.text = "\n[center][color=gray]Conditional Actions[/color][/center]"
                    separator.fit_content = true
                    action_queue_list.add_child(separator)
                    _add_detailed_plan_display(triggered_steps)
            else:
                _add_simple_status_display(unit)
            
            # Add separator between units if multiple selected
            if selected_units.size() > 1:
                var separator = Label.new()
                separator.text = "─────────────────"
                separator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                action_queue_list.add_child(separator)



func _add_detailed_plan_display(full_plan: Array) -> void:
    """Add detailed plan display to the action queue panel"""
    for i in range(full_plan.size()):
        var step = full_plan[i]
        var action = step.get("action", "Unknown")
        var status = step.get("status", "pending")
        var trigger = step.get("trigger", "")
        if trigger == null:
            trigger = ""
        
        # Status indicator
        var status_icon = ""
        var status_color = "white"
        match status:
            "completed":
                status_icon = "✓"
                status_color = "green"
            "active":
                status_icon = "►"
                status_color = "yellow"
            "pending":
                status_icon = "○"
                status_color = "gray"
            "triggered":
                status_icon = "⚡" # Lightning bolt for trigger
                status_color = "orange"
        
        # Action color
        var action_color = _get_action_color_hud(action)
        
        # Build step text
        var step_text = "[font_size=16][color=%s]%s[/color] [color=%s]%s[/color]" % [status_color, status_icon, action_color, action]
        
        # Add trigger info if available and step is not completed
        if not trigger.is_empty() and status != "completed":
            var short_trigger = _shorten_trigger_hud(trigger)
            step_text += " [color=lightgray][font_size=14](%s)[/font_size][/color]" % short_trigger
        
        step_text += "[/font_size]"
        
        var step_label = RichTextLabel.new()
        step_label.bbcode_enabled = true
        step_label.text = step_text
        step_label.fit_content = true
        action_queue_list.add_child(step_label)

func _add_simple_status_display(unit: Node) -> void:
    """Add simple status display for units without full plan data"""
    var plan_summary = "Idle"
    if "plan_summary" in unit:
        plan_summary = unit.plan_summary
    
    var status_text = "[font_size=16][color=lightblue]%s[/color][/font_size]" % plan_summary
    
    var status_label = RichTextLabel.new()
    status_label.bbcode_enabled = true
    status_label.text = status_text
    status_label.fit_content = true
    action_queue_list.add_child(status_label)

func _get_action_color_hud(action: String) -> String:
    """Get color for action type in HUD display"""
    var action_lower = action.to_lower()
    
    if "move" in action_lower or "patrol" in action_lower:
        return "cyan"
    elif "attack" in action_lower or "charge" in action_lower:
        return "red"
    elif "heal" in action_lower:
        return "green"
    elif "construct" in action_lower or "repair" in action_lower:
        return "yellow"
    elif "retreat" in action_lower or "cover" in action_lower:
        return "orange"
    elif "stealth" in action_lower or "shield" in action_lower:
        return "purple"
    elif "follow" in action_lower:
        return "lightblue"
    else:
        return "white"

func _shorten_trigger_hud(trigger: String) -> String:
    """Shorten trigger text for HUD display"""
    if trigger.is_empty():
        return ""
    
    # Replace common trigger phrases with shorter versions
    var shortened = trigger
    shortened = shortened.replace("enemies_in_range", "enemy near")
    shortened = shortened.replace("health_pct", "HP")
    shortened = shortened.replace("ammo_pct", "ammo")
    shortened = shortened.replace("elapsed_ms", "time")
    shortened = shortened.replace("incoming_fire_count", "taking dmg")
    shortened = shortened.replace("target_health_pct", "target HP")
    shortened = shortened.replace("ally_health_pct", "ally HP")
    shortened = shortened.replace("nearby_enemies", "enemies near")
    shortened = shortened.replace("move_speed", "moving")
    
    # Limit length
    if shortened.length() > 25:
        shortened = shortened.substr(0, 22) + "..."
    
    return shortened

# AI Command Processing Signal Handlers
func _on_ai_processing_started() -> void:
    """Handle AI processing started"""
    if command_status_label:
        command_status_label.text = "[color=yellow]🤖 Processing command...[/color]"
    if command_summary_label:
        command_summary_label.text = ""

func _on_ai_processing_finished() -> void:
    """Handle AI processing finished"""
    if command_status_label:
        command_status_label.text = "[color=gray]Ready for commands[/color]"

func _on_ai_plan_processed(plans: Array, message: String) -> void:
    """Handle successful AI plan processing"""
    if command_status_label:
        command_status_label.text = "[color=green]✓ Command completed[/color]"
    
    # The message parameter now contains the summary (enhanced_message from AI processor)
    var summary_text = message
    
    # If no meaningful summary, generate a basic one from the plans
    if summary_text.is_empty() or summary_text == "Executing tactical plans":
        if not plans.is_empty():
            var unit_count = plans.size()
            var action_types = []
            for plan in plans:
                if plan.has("steps") and not plan.steps.is_empty():
                    var first_action = plan.steps[0].get("action", "")
                    if not action_types.has(first_action):
                        action_types.append(first_action)
            
            if not action_types.is_empty():
                summary_text = "Coordinating %d units: %s" % [unit_count, ", ".join(action_types)]
    
    if not summary_text.is_empty() and command_summary_label:
        command_summary_label.text = "[color=lightblue]%s[/color]" % summary_text
    
    # Auto-clear status after a few seconds
    await get_tree().create_timer(3.0).timeout
    if command_status_label:
        command_status_label.text = "[color=gray]Ready for commands[/color]"

func _on_ai_command_failed(error: String, unit_ids: Array) -> void:
    """Handle AI command failure"""
    if command_status_label:
        command_status_label.text = "[color=red]✗ Command failed[/color]"
    if command_summary_label:
        command_summary_label.text = "[color=red]Error: %s[/color]" % error
    
    # Auto-clear status after a few seconds
    await get_tree().create_timer(3.0).timeout
    if command_status_label:
        command_status_label.text = "[color=gray]Ready for commands[/color]"
    if command_summary_label:
        command_summary_label.text = ""

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