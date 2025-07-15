# GameHUD.gd - Enhanced game HUD with resource display, control points, and team stats
class_name GameHUD
extends Control

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

# Dependencies
var logger = null
var resource_manager = null
var node_capture_system = null

# UI references - made optional to handle missing nodes gracefully
@onready var resource_panel = get_node_or_null("ResourcePanel")
@onready var control_points_panel = get_node_or_null("ControlPointsPanel")
@onready var team_stats_panel = get_node_or_null("TeamStatsPanel")
@onready var minimap_panel = get_node_or_null("MinimapPanel")
@onready var notification_panel = get_node_or_null("NotificationPanel")

# Resource display
@onready var energy_label = get_node_or_null("ResourcePanel/ResourceContainer/EnergyContainer/EnergyLabel")
@onready var energy_rate_label = get_node_or_null("ResourcePanel/ResourceContainer/EnergyContainer/EnergyRateLabel")
@onready var materials_label = get_node_or_null("ResourcePanel/ResourceContainer/MaterialsContainer/MaterialsLabel")
@onready var materials_rate_label = get_node_or_null("ResourcePanel/ResourceContainer/MaterialsContainer/MaterialsRateLabel")
@onready var research_label = get_node_or_null("ResourcePanel/ResourceContainer/ResearchContainer/ResearchLabel")
@onready var research_rate_label = get_node_or_null("ResourcePanel/ResourceContainer/ResearchContainer/ResearchRateLabel")

# Control points display
@onready var cp_team1_label = get_node_or_null("ControlPointsPanel/CPContainer/Team1Container/Team1CPLabel")
@onready var cp_team2_label = get_node_or_null("ControlPointsPanel/CPContainer/Team2Container/Team2CPLabel")
@onready var cp_victory_progress = get_node_or_null("ControlPointsPanel/CPContainer/VictoryProgress")

# Team stats display
@onready var team_generators_label = get_node_or_null("TeamStatsPanel/StatsContainer/GeneratorsLabel")
@onready var team_consumers_label = get_node_or_null("TeamStatsPanel/StatsContainer/ConsumersLabel")
@onready var team_efficiency_label = get_node_or_null("TeamStatsPanel/StatsContainer/EfficiencyLabel")

# Notification system
@onready var notification_container = get_node_or_null("NotificationPanel/NotificationContainer")
var active_notifications: Array = []
var max_notifications: int = 5
var notification_duration: float = GameConstants.NOTIFICATION_DURATION

# Game state tracking
var current_team_id: int = 1
var last_update_time: float = 0.0
var update_interval: float = 0.1  # Update HUD every 100ms

# Team colors
var team_colors: Dictionary = {
    1: Color(0.2, 0.4, 1.0, 1.0),  # Team 1 - Blue
    2: Color(1.0, 0.2, 0.2, 1.0),  # Team 2 - Red
    0: Color(0.5, 0.5, 0.5, 1.0)   # Neutral - Gray
}

# Signals
signal resource_notification(message: String, type: String)
signal control_point_notification(message: String, type: String)
signal victory_notification(message: String, team_id: int)

func setup(logger_instance, game_constants_instance) -> void:
    """Setup the GameHUD with dependencies"""
    logger = logger_instance
    # game_constants = game_constants_instance  # Can use this if needed
    
    # The resource_manager and node_capture_system are found via groups in _find_game_systems
    
    if logger:
        logger.info("GameHUD", "GameHUD setup completed")
    else:
        print("GameHUD setup completed")

func initialize() -> void:
    """Initialize the GameHUD system"""
    if logger:
        logger.info("GameHUD", "GameHUD initialized")
    else:
        print("GameHUD initialized")

func _ready() -> void:
    # Initialize UI
    _setup_ui()
    
    # Find game systems
    _find_game_systems()
    
    # Connect signals
    _connect_signals()
    
    # Start updating
    set_process(true)
    
    print("GameHUD: Initialized for team %d" % current_team_id)

func _setup_ui() -> void:
    """Setup initial UI state"""
    
    # Set team colors
    _apply_team_colors()
    
    # Initialize resource display
    _initialize_resource_display()
    
    # Initialize control points display
    _initialize_control_points_display()
    
    # Initialize team stats display
    _initialize_team_stats_display()
    
    # Setup notification system
    _setup_notification_system()

func _apply_team_colors() -> void:
    """Apply team colors to UI elements"""
    
    var team_color = team_colors[current_team_id]
    
    # Apply to resource panel
    if resource_panel:
        var panel_style = resource_panel.get_theme_stylebox("panel")
        if panel_style:
            panel_style.border_color = team_color
    
    # Apply to control points panel
    if control_points_panel:
        var panel_style = control_points_panel.get_theme_stylebox("panel")
        if panel_style:
            panel_style.border_color = team_color

func _initialize_resource_display() -> void:
    """Initialize resource display"""
    
    if energy_label:
        energy_label.text = "Energy: 0"
    if energy_rate_label:
        energy_rate_label.text = "(+0.0/sec)"
    
    if materials_label:
        materials_label.text = "Materials: 0"
    if materials_rate_label:
        materials_rate_label.text = "(+0.0/sec)"
    
    if research_label:
        research_label.text = "Research: 0"
    if research_rate_label:
        research_rate_label.text = "(+0.0/sec)"

func _initialize_control_points_display() -> void:
    """Initialize control points display"""
    
    if cp_team1_label:
        cp_team1_label.text = "Team 1: 0/9"
        cp_team1_label.modulate = team_colors[1]
    
    if cp_team2_label:
        cp_team2_label.text = "Team 2: 0/9"
        cp_team2_label.modulate = team_colors[2]
    
    if cp_victory_progress:
        cp_victory_progress.value = 0
        cp_victory_progress.max_value = GameConstants.CONTROL_POINT_VICTORY_THRESHOLD

func _initialize_team_stats_display() -> void:
    """Initialize team stats display"""
    
    if team_generators_label:
        team_generators_label.text = "Generators: 0"
    
    if team_consumers_label:
        team_consumers_label.text = "Consumers: 0"
    
    if team_efficiency_label:
        team_efficiency_label.text = "Efficiency: 100%"

func _setup_notification_system() -> void:
    """Setup notification system"""
    
    if notification_container:
        # Clear any existing notifications
        for child in notification_container.get_children():
            child.queue_free()
        
        active_notifications.clear()

func _find_game_systems() -> void:
    """Find game systems to connect to"""
    
    # Find resource manager
    resource_manager = get_tree().get_first_node_in_group("resource_managers")
    if not resource_manager:
        print("GameHUD: Warning - Resource manager not found")
    
    # Find node capture system
    node_capture_system = get_tree().get_first_node_in_group("node_capture_systems")
    if not node_capture_system:
        print("GameHUD: Warning - Node capture system not found")

func _connect_signals() -> void:
    """Connect to game system signals"""
    
    # Connect resource manager signals
    if resource_manager:
        resource_manager.resource_changed.connect(_on_resource_changed)
        resource_manager.resource_insufficient.connect(_on_resource_insufficient)
        resource_manager.resource_cap_reached.connect(_on_resource_cap_reached)
        resource_manager.resource_generation_changed.connect(_on_resource_generation_changed)
    
    # Connect node capture system signals
    if node_capture_system:
        node_capture_system.control_point_captured.connect(_on_control_point_captured)
        node_capture_system.control_point_contested.connect(_on_control_point_contested)
        node_capture_system.control_point_neutralized.connect(_on_control_point_neutralized)
        node_capture_system.victory_condition_met.connect(_on_victory_condition_met)
    
    # Connect EventBus signals if available
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        if event_bus.has_signal("game_state_updated"):
            event_bus.game_state_updated.connect(_on_game_state_updated)

func _process(delta: float) -> void:
    """Process HUD updates"""
    
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - last_update_time >= update_interval:
        _update_hud()
        last_update_time = current_time
    
    # Update notifications
    _update_notifications(delta)

func _update_hud() -> void:
    """Update HUD displays"""
    
    _update_resource_display()
    _update_control_points_display()
    _update_team_stats_display()

func _update_resource_display() -> void:
    """Update resource display"""
    
    if not resource_manager:
        return
    
    # Get current team resources
    var resources = resource_manager.get_team_resources(current_team_id)
    var rates = resource_manager.get_team_resource_rates(current_team_id)
    
    # Update energy display
    if energy_label and resources.has(resource_manager.ResourceType.ENERGY):
        var energy_amount = resources[resource_manager.ResourceType.ENERGY]
        var energy_max = GameConstants.MAX_ENERGY_STORAGE
        energy_label.text = "Energy: %d/%d" % [energy_amount, energy_max]
        
        # Color based on percentage
        var energy_percentage = float(energy_amount) / float(energy_max)
        if energy_percentage < 0.2:
            energy_label.modulate = Color.RED
        elif energy_percentage < 0.5:
            energy_label.modulate = Color.YELLOW
        else:
            energy_label.modulate = Color.WHITE
    
    if energy_rate_label and rates.has(resource_manager.ResourceType.ENERGY):
        var energy_rate = rates[resource_manager.ResourceType.ENERGY]
        var rate_text = "(+%.1f/sec)" % energy_rate if energy_rate >= 0 else "(%.1f/sec)" % energy_rate
        energy_rate_label.text = rate_text
        energy_rate_label.modulate = Color.GREEN if energy_rate >= 0 else Color.RED
    
    # Update materials display
    if materials_label and resources.has(resource_manager.ResourceType.MATERIALS):
        var materials_amount = resources[resource_manager.ResourceType.MATERIALS]
        var materials_max = GameConstants.MAX_MATERIAL_STORAGE
        materials_label.text = "Materials: %d/%d" % [materials_amount, materials_max]
        
        # Color based on percentage
        var materials_percentage = float(materials_amount) / float(materials_max)
        if materials_percentage < 0.2:
            materials_label.modulate = Color.RED
        elif materials_percentage < 0.5:
            materials_label.modulate = Color.YELLOW
        else:
            materials_label.modulate = Color.WHITE
    
    if materials_rate_label and rates.has(resource_manager.ResourceType.MATERIALS):
        var materials_rate = rates[resource_manager.ResourceType.MATERIALS]
        var rate_text = "(+%.1f/sec)" % materials_rate if materials_rate >= 0 else "(%.1f/sec)" % materials_rate
        materials_rate_label.text = rate_text
        materials_rate_label.modulate = Color.GREEN if materials_rate >= 0 else Color.RED
    
    # Update research display
    if research_label and resources.has(resource_manager.ResourceType.RESEARCH_POINTS):
        var research_amount = resources[resource_manager.ResourceType.RESEARCH_POINTS]
        var research_max = GameConstants.MAX_RESEARCH_STORAGE
        research_label.text = "Research: %d/%d" % [research_amount, research_max]
        
        # Color based on percentage
        var research_percentage = float(research_amount) / float(research_max)
        if research_percentage < 0.2:
            research_label.modulate = Color.RED
        elif research_percentage < 0.5:
            research_label.modulate = Color.YELLOW
        else:
            research_label.modulate = Color.WHITE
    
    if research_rate_label and rates.has(resource_manager.ResourceType.RESEARCH_POINTS):
        var research_rate = rates[resource_manager.ResourceType.RESEARCH_POINTS]
        var rate_text = "(+%.1f/sec)" % research_rate if research_rate >= 0 else "(%.1f/sec)" % research_rate
        research_rate_label.text = rate_text
        research_rate_label.modulate = Color.GREEN if research_rate >= 0 else Color.RED

func _update_control_points_display() -> void:
    """Update control points display"""
    
    if not node_capture_system:
        return
    
    # Get control counts
    var team1_count = node_capture_system.get_team_control_count(1)
    var team2_count = node_capture_system.get_team_control_count(2)
    var total_points = GameConstants.CONTROL_POINT_COUNT
    
    # Update team labels
    if cp_team1_label:
        cp_team1_label.text = "Team 1: %d/%d" % [team1_count, total_points]
    
    if cp_team2_label:
        cp_team2_label.text = "Team 2: %d/%d" % [team2_count, total_points]
    
    # Update victory progress
    if cp_victory_progress:
        var current_team_count = node_capture_system.get_team_control_count(current_team_id)
        cp_victory_progress.value = current_team_count
        
        # Change color based on progress
        var progress_percentage = float(current_team_count) / float(GameConstants.CONTROL_POINT_VICTORY_THRESHOLD)
        if progress_percentage >= 1.0:
            cp_victory_progress.modulate = Color.GREEN
        elif progress_percentage >= 0.7:
            cp_victory_progress.modulate = Color.YELLOW
        else:
            cp_victory_progress.modulate = Color.WHITE

func _update_team_stats_display() -> void:
    """Update team stats display"""
    
    if not resource_manager:
        return
    
    # Get team statistics
    var generator_count = resource_manager.get_team_generator_count(current_team_id)
    var consumer_count = resource_manager.get_team_consumer_count(current_team_id)
    
    # Update generator count
    if team_generators_label:
        team_generators_label.text = "Generators: %d" % generator_count
    
    # Update consumer count
    if team_consumers_label:
        team_consumers_label.text = "Consumers: %d" % consumer_count
    
    # Calculate and update efficiency
    if team_efficiency_label:
        var energy_efficiency = resource_manager.get_resource_efficiency(current_team_id, resource_manager.ResourceType.ENERGY)
        var efficiency_percentage = min(energy_efficiency * 100, 999)  # Cap at 999%
        team_efficiency_label.text = "Efficiency: %.0f%%" % efficiency_percentage
        
        # Color based on efficiency
        if energy_efficiency >= 1.0:
            team_efficiency_label.modulate = Color.GREEN
        elif energy_efficiency >= 0.5:
            team_efficiency_label.modulate = Color.YELLOW
        else:
            team_efficiency_label.modulate = Color.RED

func _update_notifications(delta: float) -> void:
    """Update notification system"""
    
    # Update existing notifications
    for i in range(active_notifications.size() - 1, -1, -1):
        var notification = active_notifications[i]
        notification.lifetime -= delta
        
        if notification.lifetime <= 0:
            # Remove expired notification
            if notification.ui_element and is_instance_valid(notification.ui_element):
                notification.ui_element.queue_free()
            active_notifications.remove_at(i)
        else:
            # Update fade based on remaining time
            var fade_time = 1.0
            if notification.lifetime <= fade_time and notification.ui_element:
                var alpha = notification.lifetime / fade_time
                notification.ui_element.modulate.a = alpha

func show_notification(message: String, type: String = "info", duration: float = 3.0) -> void:
    """Show a notification message"""
    
    # Remove oldest notification if at max capacity
    if active_notifications.size() >= max_notifications:
        var oldest = active_notifications[0]
        if oldest.ui_element and is_instance_valid(oldest.ui_element):
            oldest.ui_element.queue_free()
        active_notifications.remove_at(0)
    
    # Create notification UI element
    var notification_ui = _create_notification_ui(message, type)
    
    # Add to container
    if notification_container:
        notification_container.add_child(notification_ui)
    
    # Track notification
    var notification = {
        "message": message,
        "type": type,
        "lifetime": duration,
        "ui_element": notification_ui
    }
    
    active_notifications.append(notification)
    
    print("GameHUD: Notification - %s" % message)

func _create_notification_ui(message: String, type: String) -> Control:
    """Create UI element for notification"""
    
    var notification_panel = Panel.new()
    notification_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    notification_panel.custom_minimum_size = Vector2(300, 40)
    
    # Set panel color based on type
    var panel_color = Color.WHITE
    match type:
        "info":
            panel_color = Color(0.2, 0.4, 1.0, 0.8)
        "warning":
            panel_color = Color(1.0, 0.8, 0.2, 0.8)
        "error":
            panel_color = Color(1.0, 0.2, 0.2, 0.8)
        "success":
            panel_color = Color(0.2, 1.0, 0.2, 0.8)
    
    # Create styled panel
    var style_box = StyleBoxFlat.new()
    style_box.bg_color = panel_color
    style_box.corner_radius_top_left = 5
    style_box.corner_radius_top_right = 5
    style_box.corner_radius_bottom_left = 5
    style_box.corner_radius_bottom_right = 5
    notification_panel.add_theme_stylebox_override("panel", style_box)
    
    # Create message label
    var label = Label.new()
    label.text = message
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    label.add_theme_color_override("font_color", Color.WHITE)
    
    notification_panel.add_child(label)
    
    return notification_panel

# Public API
func set_team_id(team_id: int) -> void:
    """Set the team ID for this HUD"""
    current_team_id = team_id
    _apply_team_colors()

func get_team_id() -> int:
    """Get the current team ID"""
    return current_team_id

func force_update() -> void:
    """Force immediate HUD update"""
    _update_hud()

func show_resource_notification(message: String) -> void:
    """Show a resource-related notification"""
    show_notification(message, "warning")

func show_control_point_notification(message: String) -> void:
    """Show a control point-related notification"""
    show_notification(message, "info")

func show_victory_notification(message: String) -> void:
    """Show a victory-related notification"""
    show_notification(message, "success", 10.0)  # Longer duration for victory

# Signal handlers
func _on_resource_changed(team_id: int, resource_type: int, amount: int) -> void:
    """Handle resource changed signal"""
    if team_id == current_team_id:
        # Resource display will be updated in next HUD update
        pass

func _on_resource_insufficient(team_id: int, resource_type: int, required: int, available: int) -> void:
    """Handle resource insufficient signal"""
    if team_id == current_team_id:
        if resource_manager:
            var resource_name = resource_manager.get_resource_type_name(resource_type)
            var message = "Insufficient %s! Need %d, have %d" % [resource_name, required, available]
            show_resource_notification(message)

func _on_resource_cap_reached(team_id: int, resource_type: int, amount: int) -> void:
    """Handle resource cap reached signal"""
    if team_id == current_team_id:
        if resource_manager:
            var resource_name = resource_manager.get_resource_type_name(resource_type)
            var message = "%s storage full! (%d)" % [resource_name, amount]
            show_resource_notification(message)

func _on_resource_generation_changed(team_id: int, resource_type: int, new_rate: float) -> void:
    """Handle resource generation changed signal"""
    if team_id == current_team_id:
        # Rate display will be updated in next HUD update
        pass

func _on_control_point_captured(point_id: String, team_id: int) -> void:
    """Handle control point captured signal"""
    if node_capture_system:
        var point = node_capture_system.get_control_point(point_id)
        if point:
            var message = "%s captured by Team %d!" % [point.get_control_point_name(), team_id]
            show_control_point_notification(message)

func _on_control_point_contested(point_id: String, teams: Array) -> void:
    """Handle control point contested signal"""
    if node_capture_system:
        var point = node_capture_system.get_control_point(point_id)
        if point:
            var message = "%s contested by teams %s!" % [point.get_control_point_name(), teams]
            show_control_point_notification(message)

func _on_control_point_neutralized(point_id: String) -> void:
    """Handle control point neutralized signal"""
    if node_capture_system:
        var point = node_capture_system.get_control_point(point_id)
        if point:
            var message = "%s neutralized!" % point.get_control_point_name()
            show_control_point_notification(message)

func _on_victory_condition_met(team_id: int, condition_type: String) -> void:
    """Handle victory condition met signal"""
    var message = "Team %d achieved victory via %s!" % [team_id, condition_type]
    show_victory_notification(message)

func _on_game_state_updated(state_data: Dictionary) -> void:
    """Handle game state update from EventBus"""
    # Game state data can be used for additional updates
    pass 