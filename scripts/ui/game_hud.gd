# GameHUD.gd - Refactored game HUD script
class_name GameHUD
extends Control

# Load shared constants
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# UI References
@onready var energy_label = $TopBar/HBoxContainer/EnergyLabel
@onready var node_label = $TopBar/HBoxContainer/NodeLabel
@onready var action_queue_list = $UnitActionQueuePanel/MarginContainer/ScrollContainer/ActionQueueList
@onready var command_input = $BottomBar/HBoxContainer/CommandInput
@onready var unit_status_panel = $BottomBar/HBoxContainer/UnitStatusPanel/MarginContainer/VBoxContainer/UnitList
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

# Player units tracking
var player_units: Dictionary = {}  # unit_id -> unit_data
var unit_bars: Dictionary = {}     # unit_id -> UI control
var is_refreshing_units: bool = false  # Prevent concurrent refreshes

# Auto-refresh for behavior matrix display
var behavior_refresh_timer: float = 0.0
const BEHAVIOR_REFRESH_INTERVAL: float = 1.0  # Reduced from 0.2 to 1.0 - Update once per second instead of 5 times per second

# Command input health check timer
var command_input_check_timer: float = 0.0
const COMMAND_INPUT_CHECK_INTERVAL: float = 2.0

# Cached validator to avoid expensive instantiation
var cached_action_validator = null

# Cache for behavior matrix data to avoid unnecessary UI rebuilds
var last_behavior_data_cache: Dictionary = {}  # unit_id -> last_known_action_scores

func _ready() -> void:
    # Add to group for easy discovery
    add_to_group("game_hud")
    
    # Initialize cached validator to avoid expensive creation during gameplay
    var validator_script = preload("res://scripts/ai/action_validator.gd")
    cached_action_validator = validator_script.new()
    
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
        # _on_ai_plan_processed is now ONLY for host's local AI processing, not other clients
        ai_command_processor.plan_processed.connect(_on_ai_plan_processed)
        ai_command_processor.command_failed.connect(_on_ai_command_failed) # This can still be used for local host feedback
    
    command_input.text_submitted.connect(_on_command_submitted)
    # Unit spawning is now handled via RPC commands, not direct buttons
    
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
    # Use call_deferred instead of await to avoid race conditions
    # This prevents issues where the node might become invalid during await
    call_deferred("_regrab_focus_safely")

func _regrab_focus_safely():
    """Safely regrab focus for command input"""
    if not command_input or not is_instance_valid(command_input):
        print("GameHUD: Command input is invalid, cannot regrab focus")
        return
        
    if not is_visible_in_tree():
        print("GameHUD: GameHUD not visible in tree, cannot regrab focus")
        return
        
    # Ensure command input is still editable and enabled
    if not command_input.editable:
        print("GameHUD: Command input not editable, re-enabling")
        command_input.editable = true
        
    # Re-grab focus
    command_input.grab_focus()
    print("GameHUD: Command input focus regrabbed safely")

func _unhandled_input(event: InputEvent):
    """Capture keyboard input and route it to command input - don't interfere with mouse selection"""
    if not command_input or not is_visible_in_tree():
        return
    
    # Only handle keyboard events, let selection system handle mouse events
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
        
        # For any other key, ensure command input has focus but don't handle the event
        if not command_input.has_focus():
            command_input.grab_focus()
            # Don't call set_input_as_handled() to let the LineEdit process the key

func _physics_process(delta):
    if hover_tooltip.visible:
        hover_tooltip.global_position = get_global_mouse_position() + Vector2(15, 15)
    
    # Auto-refresh behavior matrix display for selected units
    behavior_refresh_timer += delta
    if behavior_refresh_timer >= BEHAVIOR_REFRESH_INTERVAL:
        behavior_refresh_timer = 0.0
        _refresh_behavior_matrix_display()
    
    # Periodic check to ensure command input stays active (every 2 seconds)
    # This prevents any external interference from disabling the command input
    command_input_check_timer += delta
    if command_input_check_timer >= COMMAND_INPUT_CHECK_INTERVAL:
        command_input_check_timer = 0.0
        _check_command_input_health()

func _check_command_input_health():
    """Periodically check and maintain command input health"""
    if not command_input or not is_visible_in_tree():
        return
    
    # Check if command input has lost its settings and restore them
    if not command_input.editable:
        print("GameHUD: Detected command input became non-editable, fixing...")
        command_input.editable = true
    
    if command_input.focus_mode != Control.FOCUS_ALL:
        print("GameHUD: Detected command input lost focus mode, fixing...")
        command_input.focus_mode = Control.FOCUS_ALL
    
    if command_input.mouse_filter != Control.MOUSE_FILTER_PASS:
        print("GameHUD: Detected command input lost mouse filter, fixing...")
        command_input.mouse_filter = Control.MOUSE_FILTER_PASS
    
    # If command input doesn't have focus and there's no modal dialog, give it focus
    if not command_input.has_focus() and not get_viewport().gui_is_dragging():
        # Only regrab focus if no other UI element should have priority
        var current_focus = get_viewport().gui_get_focus_owner()
        if not current_focus or current_focus == command_input:
            command_input.grab_focus()

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
    # Clear behavior cache when selection changes to ensure fresh comparisons
    last_behavior_data_cache.clear()
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
    if text.begins_with("/test"):
        get_node("/root/UnifiedMain").rpc("submit_test_command_rpc", text)
        command_input.clear()
        _ensure_command_input_active()
        return
        
    if text.is_empty():
        print("GameHUD: Empty command entered")
        _ensure_command_input_active()  # Keep focus for next command
        return
        
    if not selection_system:
        print("GameHUD: No selection system available")
        command_input.clear()
        _ensure_command_input_active()
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
    _ensure_command_input_active()  # Immediately ready for next command

func _ensure_command_input_active():
    """Ensure the command input is active and ready for input"""
    if not command_input:
        print("GameHUD: Warning - command_input is null")
        return
    
    # Ensure it's editable
    if not command_input.editable:
        print("GameHUD: Re-enabling command input editability")
        command_input.editable = true
    
    # Ensure proper focus mode
    if command_input.focus_mode != Control.FOCUS_ALL:
        command_input.focus_mode = Control.FOCUS_ALL
    
    # Ensure proper mouse filter
    if command_input.mouse_filter != Control.MOUSE_FILTER_PASS:
        command_input.mouse_filter = Control.MOUSE_FILTER_PASS
    
    # Grab focus
    command_input.grab_focus()
    print("GameHUD: Command input ensured active and focused")

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
        # Show detailed plan data for selected units
        for unit in selected_units:
            if not is_instance_valid(unit): continue
            
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
            # IMPORTANT: unit.strategic_goal is updated by ClientDisplayManager based on RPC from server.
            # This ensures the client-side UI reflects the latest goal.
            if "strategic_goal" in unit and not unit.strategic_goal.is_empty():
                unit_goal = unit.strategic_goal
            else:
                unit_goal = "No specific goal assigned" # Fallback if AI provides empty string or unit is idle
            
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
            
            # New: Show behavior matrix activations
            _add_behavior_activations_display(unit)

            # Add separator between units if multiple selected
            if selected_units.size() > 1:
                var separator = Label.new()
                separator.text = "─────────────────"
                separator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                action_queue_list.add_child(separator)

func _add_behavior_activations_display(unit: Node) -> void:
    """Add a display for the unit's real-time action activation scores."""
    var scores = unit.last_action_scores if "last_action_scores" in unit else {}
    if scores.is_empty():
        var no_data_label = RichTextLabel.new()
        no_data_label.bbcode_enabled = true
        no_data_label.text = "[i]No activation data available.[/i]"
        no_data_label.fit_content = true
        action_queue_list.add_child(no_data_label)
        return

    # Filter actions to only show those valid for the unit's archetype
    var unit_archetype = unit.archetype if "archetype" in unit else "general"
    var valid_actions = cached_action_validator.get_valid_actions_for_archetype(unit_archetype)

    # Add separator and header
    var separator = RichTextLabel.new()
    separator.bbcode_enabled = true
    separator.text = "\n[center][color=gray]─── Live Activations ───[/color][/center]"
    separator.fit_content = true
    action_queue_list.add_child(separator)

    var sorted_scores = []
    for action_name in scores:
        # Only include actions valid for this unit's archetype
        if action_name in valid_actions:
            sorted_scores.append({"name": action_name, "score": scores[action_name]})
    
    sorted_scores.sort_custom(func(a, b): return a.score > b.score)

    for item in sorted_scores:
        var action_name = item.name
        var score = item.score
        
        var action_display = action_name.capitalize().replace("_", " ")
        var action_color = _get_action_color_hud(action_name)

        var hbox = HBoxContainer.new()
        hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

        var name_label = Label.new()
        name_label.text = action_display
        name_label.custom_minimum_size.x = 100
        name_label.add_theme_color_override("font_color", action_color)
        hbox.add_child(name_label)
        
        var progress_bar = ProgressBar.new()
        progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        progress_bar.min_value = -1.0
        progress_bar.max_value = 1.0
        progress_bar.value = score
        progress_bar.show_percentage = false
        
        # Style the progress bar
        var fill_style = StyleBoxFlat.new()
        fill_style.bg_color = action_color
        progress_bar.add_theme_stylebox_override("fill", fill_style)
        
        hbox.add_child(progress_bar)
        
        var score_label = Label.new()
        score_label.text = "%.2f" % score
        score_label.custom_minimum_size.x = 40
        score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        hbox.add_child(score_label)
        
        action_queue_list.add_child(hbox)

func _format_trigger_name(trigger_name: String) -> String:
    """Format trigger name for display"""
    match trigger_name:
        "on_enemy_in_range":
            return "Enemy in Range"
        "on_enemy_sighted":
            return "Enemy Sighted"
        "on_under_attack":
            return "Under Attack"
        "on_health_low":
            return "Low Health"
        "on_health_critical":
            return "Critical Health"
        "on_ally_health_low":
            return "Ally Injured"
        _:
            return trigger_name.replace("_", " ").replace("on ", "").capitalize()

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
# This function is now primarily for the host's local AI processing feedback
func _on_ai_processing_started() -> void:
    """Handle AI processing started (local only)"""
    if command_status_label:
        command_status_label.text = "[color=yellow]🤖 Processing command...[/color]"
    if command_summary_label:
        command_summary_label.text = ""

func _on_ai_processing_finished() -> void:
    """Handle AI processing finished (local only)"""
    # This might be overridden by network feedback, but provides an immediate local update
    if command_status_label:
        command_status_label.text = "[color=gray]Ready for commands[/color]"

# This function is now ONLY for the host's local AI processing, not other clients
# Other clients will get updates via update_ai_command_feedback RPC.
func _on_ai_plan_processed(plans: Array, message: String, originating_peer_id: int = -1) -> void:
    """Handle successful AI plan processing (local host feedback)"""
    # If not a pure client, this runs for the host
    if multiplayer.is_server() and DisplayServer.get_name() != "headless":
        var summary_text = message
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
        
        update_ai_command_feedback(summary_text, "[color=green]✓ Command completed[/color]")
    
    # Auto-clear status after a few seconds
    await get_tree().create_timer(3.0).timeout
    if command_status_label:
        command_status_label.text = "[color=gray]Ready for commands[/color]"
    if command_summary_label:
        command_summary_label.text = ""

# This function can still be used for local host feedback on AI command failure
func _on_ai_command_failed(error: String, unit_ids: Array, originating_peer_id: int = -1) -> void:
    """Handle AI command failure (local host feedback)"""
    if multiplayer.is_server() and DisplayServer.get_name() != "headless":
        update_ai_command_feedback("[color=red]Error: %s[/color]" % error, "[color=red]✗ Command failed[/color]")
    
    # Auto-clear status after a few seconds
    await get_tree().create_timer(3.0).timeout
    if command_status_label:
        command_status_label.text = "[color=gray]Ready for commands[/color]"
    if command_summary_label:
        command_summary_label.text = ""

func update_ai_command_feedback(summary_text: String, status_text: String) -> void:
    """
    Updates the command status and summary labels.
    Called by UnifiedMain from server RPC or by local AI processing.
    """
    if command_status_label:
        command_status_label.text = status_text
    
    if command_summary_label:
        command_summary_label.text = summary_text
    
    # Crucially, force refresh selected unit display to show new strategic goals
    # and plan summaries that have been updated via the _on_game_state_update RPC.
    if selection_system and not selection_system.get_selected_units().is_empty():
        _update_selection_display(selection_system.get_selected_units())

    # Auto-clear status after a few seconds, if this is the final status update
    # Note: A separate timer might be needed if complex states are involved.
    # For now, it will clear after a few seconds regardless of how it was triggered.
    # We will remove the await and only set it on server side for client.
    # This function is now the end point, not starting a new timer here.
    pass

func _refresh_behavior_matrix_display() -> void:
    """Refresh only the behavior matrix display for currently selected units"""
    if not selection_system:
        return
    
    var selected_units = selection_system.get_selected_units()
    if selected_units.is_empty():
        last_behavior_data_cache.clear()  # Clear cache when no units selected
        return
    
    # Check if any selected unit has actually changed behavior matrix data
    var has_changes = false
    for unit in selected_units:
        if not is_instance_valid(unit):
            continue
        
        var unit_id = unit.unit_id if "unit_id" in unit else ""
        if unit_id.is_empty():
            continue
            
        var current_scores = unit.last_action_scores if "last_action_scores" in unit else {}
        var cached_scores = last_behavior_data_cache.get(unit_id, {})
        
        # Compare current scores with cached scores
        if not _dictionaries_equal(current_scores, cached_scores):
            has_changes = true
            last_behavior_data_cache[unit_id] = current_scores.duplicate() if current_scores else {}
    
    # Only do expensive UI rebuild if data actually changed
    if has_changes:
        _update_selection_display(selected_units)

func _dictionaries_equal(dict1: Dictionary, dict2: Dictionary) -> bool:
    """Compare two dictionaries for equality (including nested values)"""
    if dict1.size() != dict2.size():
        return false
    
    for key in dict1:
        if not dict2.has(key):
            return false
        # Use small epsilon for float comparison
        var val1 = dict1[key]
        var val2 = dict2[key]
        if typeof(val1) == TYPE_FLOAT and typeof(val2) == TYPE_FLOAT:
            if abs(val1 - val2) > 0.001:  # Small epsilon for float comparison
                return false
        elif val1 != val2:
            return false
    
    return true


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

# ========== Unit Status Panel Methods ==========

func update_player_units(units_data: Array, player_peer_id: int = -1) -> void:
    """Update the display of units controlled by this player"""
    # Clear previous data
    player_units.clear()
    
    # If no peer ID provided, try to get local player's peer ID  
    if player_peer_id == -1:
        player_peer_id = multiplayer.get_unique_id()
    
    # Find units that belong to this player's team
    var player_team_id = _get_player_team_id(player_peer_id)
    if player_team_id == -1:
        return
    
    # Filter units by team (units_data is now an Array of unit dictionaries)
    for unit_data in units_data:
        if unit_data.has("team_id") and unit_data.team_id == player_team_id:
            var unit_id = unit_data.get("id", "")
            if not unit_id.is_empty():
                player_units[unit_id] = unit_data
    
    # Update the UI (call async method safely)
    _refresh_unit_status_display()

func _get_player_team_id(peer_id: int) -> int:
    """Get the team ID for a given peer ID"""
    # Try to get session manager to find player's team
    var session_manager = get_node_or_null("/root/DependencyContainer/SessionManager")
    if not session_manager:
        return _get_team_id_from_unified_main()
        
    var session_id = session_manager.get_player_session(peer_id)
    if session_id.is_empty():
        return _get_team_id_from_unified_main()
        
    var session = session_manager.get_session(session_id)
    if not session:
        return _get_team_id_from_unified_main()
    
    # Find player in session
    for player_id in session.players:
        var player = session.players[player_id]
        if player.peer_id == peer_id:
            return player.team_id
    
    return _get_team_id_from_unified_main()

func _get_team_id_from_unified_main() -> int:
    """Get team ID from UnifiedMain as backup when SessionManager fails"""
    var unified_main = get_node_or_null("/root/UnifiedMain")
    if not unified_main:
        return -1
    
    if "client_team_id" in unified_main:
        return unified_main.client_team_id
    
    return -1

func _refresh_unit_status_display() -> void:
    """Refresh the unit status panel with current player units"""
    if not unit_status_panel:
        return
    
    # Only refresh if not already refreshing
    if is_refreshing_units:
        return
    is_refreshing_units = true

    # Clear existing bars properly
    for bar_data in unit_bars.values():
        if bar_data.has("container") and is_instance_valid(bar_data["container"]):
            bar_data["container"].queue_free()
    unit_bars.clear()
    
    # Also clear all children directly from the panel to ensure immediate cleanup
    for child in unit_status_panel.get_children():
        child.queue_free()
    
    # Wait a frame to ensure cleanup is complete before creating new bars
    await get_tree().process_frame
    
    # Create bars for each player unit
    for unit_id in player_units:
        var unit_data = player_units[unit_id]
        _create_unit_bar(unit_id, unit_data)
    
    is_refreshing_units = false

func _create_unit_bar(unit_id: String, unit_data: Dictionary) -> void:
    """Create a health/respawn bar for a unit"""
    var bar_container = HBoxContainer.new()
    unit_status_panel.add_child(bar_container)
    
    # Unit ID label
    var id_label = Label.new()
    id_label.text = unit_id
    id_label.custom_minimum_size.x = 80
    id_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    bar_container.add_child(id_label)
    
    # Health/Respawn bar
    var progress_bar = ProgressBar.new()
    progress_bar.custom_minimum_size = Vector2(100, 20)
    progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    progress_bar.show_percentage = false
    bar_container.add_child(progress_bar)
    
    # Status label (health/respawn time)
    var status_label = Label.new()
    status_label.custom_minimum_size.x = 60
    status_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    bar_container.add_child(status_label)
    
    # Store references
    unit_bars[unit_id] = {
        "container": bar_container,
        "progress_bar": progress_bar,
        "status_label": status_label,
        "id_label": id_label
    }
    
    # Update the bar with current data
    _update_unit_bar(unit_id, unit_data)

func _update_unit_bar(unit_id: String, unit_data: Dictionary) -> void:
    """Update a specific unit's health/respawn bar"""
    if not unit_bars.has(unit_id):
        return
    
    var bar_elements = unit_bars[unit_id]
    var progress_bar = bar_elements.progress_bar
    var status_label = bar_elements.status_label
    
    var is_dead = unit_data.get("is_dead", false)
    var is_respawning = unit_data.get("is_respawning", false)
    var respawn_timer = unit_data.get("respawn_timer", 0.0)
    var current_health = unit_data.get("current_health", 100.0)
    var max_health = unit_data.get("max_health", 100.0)
    
    if is_dead and is_respawning:
        # Show respawn timer
        progress_bar.max_value = GameConstants.UNIT_RESPAWN_TIME
        progress_bar.value = GameConstants.UNIT_RESPAWN_TIME - respawn_timer
        progress_bar.modulate = Color.YELLOW
        status_label.text = "%ds" % int(respawn_timer)
    elif is_dead:
        # Dead but not respawning yet
        progress_bar.max_value = 1.0
        progress_bar.value = 0.0
        progress_bar.modulate = Color.RED
        status_label.text = "DEAD"
    else:
        # Show health
        progress_bar.max_value = max_health
        progress_bar.value = current_health
        var health_pct = current_health / max_health if max_health > 0 else 0.0
        
        # Color based on health percentage
        if health_pct > 0.7:
            progress_bar.modulate = Color.GREEN
        elif health_pct > 0.3:
            progress_bar.modulate = Color.YELLOW
        else:
            progress_bar.modulate = Color.RED
            
        status_label.text = "%d/%d" % [int(current_health), int(max_health)]

func update_unit_data(unit_id: String, unit_data: Dictionary) -> void:
    """Update data for a specific unit and refresh its bar"""
    if player_units.has(unit_id):
        player_units[unit_id] = unit_data
        _update_unit_bar(unit_id, unit_data)