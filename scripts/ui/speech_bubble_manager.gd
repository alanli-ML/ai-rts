# SpeechBubbleManager.gd
class_name SpeechBubbleManager
extends Node

# Load shared constants
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Constants
const MAX_CONCURRENT_BUBBLES = 10
const BUBBLE_CLEANUP_INTERVAL = GameConstants.NOTIFICATION_DURATION + 2.0  # seconds

# Scene references
const SpeechBubbleScene = preload("res://scripts/ui/speech_bubble.gd")

# UI container
var speech_bubbles_container: Control
var active_bubbles: Dictionary = {}  # unit_id -> SpeechBubble
var bubble_queue: Array = []  # Queue for pending bubbles
var cleanup_timer: Timer

# Team colors for speech bubbles
var team_colors: Dictionary = {
    1: Color(0.2, 0.4, 0.8, 0.9),  # Blue team
    2: Color(0.8, 0.2, 0.2, 0.9),  # Red team
    0: Color(0.4, 0.4, 0.4, 0.9)   # Neutral/unknown
}

# AI integration
var ai_command_processor: Node = null
var logger: Node = null

func setup(logger_instance, _game_constants_instance) -> void:
    """Setup the SpeechBubbleManager with dependencies"""
    logger = logger_instance
    # game_constants = game_constants_instance  # Can use this if needed
    
    if logger:
        logger.info("SpeechBubbleManager", "SpeechBubbleManager setup completed")
    else:
        print("SpeechBubbleManager setup completed")

func initialize(_speech_bubble_manager_instance = null) -> void:
    """Initialize the SpeechBubbleManager system"""
    if logger:
        logger.info("SpeechBubbleManager", "SpeechBubbleManager initialized")
    else:
        print("SpeechBubbleManager initialized")

# Statistics
var stats: Dictionary = {
    "bubbles_created": 0,
    "bubbles_clicked": 0,
    "total_words_displayed": 0,
    "ai_generated_speeches": 0
}

# Signals
signal speech_bubble_created(unit_id: String, text: String)
signal speech_bubble_clicked(unit_id: String, text: String)
signal speech_bubble_finished(unit_id: String)

func _ready() -> void:
    # Add to speech_bubble_managers group for easy discovery
    add_to_group("speech_bubble_managers")
    
    # Create UI container
    _setup_ui_container()
    
    # Setup cleanup timer
    _setup_cleanup_timer()
    
    # Connect to AI system
    _connect_to_ai_system()
    
    # Connect to EventBus if available
    _connect_to_event_bus()
    
    print("SpeechBubbleManager: Speech bubble manager initialized")

func _setup_ui_container() -> void:
    """Set up the UI container for speech bubbles"""
    
    # Create container
    speech_bubbles_container = Control.new()
    speech_bubbles_container.name = "SpeechBubbles"
    speech_bubbles_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    speech_bubbles_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Add to scene tree
    # Try to find the main UI or game scene
    var main_scene = get_tree().current_scene
    if main_scene:
        main_scene.add_child(speech_bubbles_container)
    else:
        # Fallback: add to self
        add_child(speech_bubbles_container)
    
    print("SpeechBubbleManager: UI container created")

func _setup_cleanup_timer() -> void:
    """Set up timer for cleaning up old bubbles"""
    
    cleanup_timer = Timer.new()
    cleanup_timer.name = "CleanupTimer"
    cleanup_timer.wait_time = BUBBLE_CLEANUP_INTERVAL
    cleanup_timer.timeout.connect(_cleanup_old_bubbles)
    add_child(cleanup_timer)
    cleanup_timer.start()

func _connect_to_ai_system() -> void:
    """Connect to the AI command processor"""
    
    # Try to find AI command processor
    var ai_processors = get_tree().get_nodes_in_group("ai_processors")
    if ai_processors.size() > 0:
        ai_command_processor = ai_processors[0]
        print("SpeechBubbleManager: Connected to AI command processor")
    else:
        print("SpeechBubbleManager: No AI command processor found")
    
    # Try to find logger
    var loggers = get_tree().get_nodes_in_group("loggers")
    if loggers.size() > 0:
        logger = loggers[0]
    else:
        # Try to get from autoload
        if has_node("/root/DependencyContainer"):
            var container = get_node("/root/DependencyContainer")
            if container.has_method("get_logger"):
                logger = container.get_logger()

func _connect_to_event_bus() -> void:
    """Connect to EventBus signals"""
    
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        
        # Connect to unit command signals
        if event_bus.has_signal("unit_command_issued"):
            event_bus.unit_command_issued.connect(_on_unit_command_issued)
        
        # Connect to AI signals
        if event_bus.has_signal("ai_response_generated"):
            event_bus.ai_response_generated.connect(_on_ai_response_generated)
        
        print("SpeechBubbleManager: Connected to EventBus")

func show_speech_bubble(unit_id: String, text: String, team_id: int = 0) -> bool:
    """Show a speech bubble for a unit"""
    
    # On the client, the "unit" is the visual representation node.
    # We find it via the ClientDisplayManager.
    var display_manager = get_node_or_null("/root/UnifiedMain/ClientDisplayManager")
    if not display_manager or not display_manager.displayed_units.has(unit_id):
        logger.warning("SpeechBubbleManager", "Could not find displayed unit for ID: %s" % unit_id)
        return false

    var unit = display_manager.displayed_units[unit_id]
    if not is_instance_valid(unit):
        logger.warning("SpeechBubbleManager", "Unit instance for ID %s is invalid." % unit_id)
        return false
    
    # Check if unit already has a bubble
    if unit_id in active_bubbles:
        # Update existing bubble
        var existing_bubble = active_bubbles[unit_id]
        existing_bubble.hide_immediately()
        existing_bubble.show_speech(text, unit, team_id)
        existing_bubble.set_bubble_color(team_colors.get(team_id, team_colors[0]))
        
        stats.bubbles_created += 1
        stats.total_words_displayed += text.split(" ").size()
        
        speech_bubble_created.emit(unit_id, text)
        return true
    
    # Check bubble limit
    if active_bubbles.size() >= MAX_CONCURRENT_BUBBLES:
        # Remove oldest bubble
        _remove_oldest_bubble()
    
    # Create new bubble
    var bubble = SpeechBubbleScene.new()
    bubble.name = "SpeechBubble_" + unit_id
    
    # Connect signals
    bubble.speech_bubble_finished.connect(_on_speech_bubble_finished)
    bubble.speech_bubble_clicked.connect(_on_speech_bubble_clicked)
    
    # Set team color
    bubble.set_bubble_color(team_colors.get(team_id, team_colors[0]))
    
    # Add to container
    speech_bubbles_container.add_child(bubble)
    
    # Show speech
    bubble.show_speech(text, unit, team_id)
    
    # Track bubble
    active_bubbles[unit_id] = bubble
    
    # Update stats
    stats.bubbles_created += 1
    stats.total_words_displayed += text.split(" ").size()
    
    speech_bubble_created.emit(unit_id, text)
    
    if logger:
        logger.info("SpeechBubbleManager", "Showing speech bubble for unit %s: %s" % [unit_id, text])
    
    return true

func hide_speech_bubble(unit_id: String) -> bool:
    """Hide a speech bubble for a unit"""
    
    if unit_id in active_bubbles:
        var bubble = active_bubbles[unit_id]
        bubble.hide_immediately()
        return true
    
    return false

func hide_all_speech_bubbles() -> void:
    """Hide all active speech bubbles"""
    
    for unit_id in active_bubbles:
        var bubble = active_bubbles[unit_id]
        bubble.hide_immediately()
    
    active_bubbles.clear()

func show_ai_generated_speech(unit_id: String, ai_response: String, team_id: int = 0) -> bool:
    """Show AI-generated speech with special handling"""
    
    # Process AI response for speech bubble
    var processed_text = _process_ai_response(ai_response)
    
    # Update stats
    stats.ai_generated_speeches += 1
    
    # Show with special AI styling
    var result = show_speech_bubble(unit_id, processed_text, team_id)
    
    if result and unit_id in active_bubbles:
        var bubble = active_bubbles[unit_id]
        # Add a subtle glow effect for AI-generated speech
        bubble.modulate = Color(1.1, 1.1, 1.1, 1.0)
    
    return result

func _process_ai_response(response: String) -> String:
    """Process AI response for speech bubble display"""
    
    # Remove common AI response prefixes
    var prefixes_to_remove = [
        "I will",
        "I'll",
        "Roger that",
        "Understood",
        "Affirmative",
        "Copy that"
    ]
    
    for prefix in prefixes_to_remove:
        if response.begins_with(prefix):
            response = response.substr(prefix.length()).strip_edges()
            break
    
    # Ensure it's not empty
    if response.is_empty():
        response = "Acknowledged"
    
    return response

func _find_unit_by_id(unit_id: String) -> Node3D:
    """Find a unit by its ID"""
    
    # Try to find in units group
    var units = get_tree().get_nodes_in_group("units")
    for unit in units:
        if unit.has_method("get_unit_id") and unit.get_unit_id() == unit_id:
            return unit
        elif unit.name == unit_id:
            return unit
    
    return null

func _remove_oldest_bubble() -> void:
    """Remove the oldest speech bubble"""
    
    if active_bubbles.is_empty():
        return
    
    # Find the oldest bubble (this is a simple approach)
    var oldest_unit_id = active_bubbles.keys()[0]
    var oldest_bubble = active_bubbles[oldest_unit_id]
    
    oldest_bubble.hide_immediately()

func _cleanup_old_bubbles() -> void:
    """Clean up old or invalid bubbles"""
    
    var bubbles_to_remove = []
    
    for unit_id in active_bubbles:
        var bubble = active_bubbles[unit_id]
        
        # Check if bubble is still valid
        if not is_instance_valid(bubble) or not bubble.target_unit:
            bubbles_to_remove.append(unit_id)
    
    # Remove invalid bubbles
    for unit_id in bubbles_to_remove:
        active_bubbles.erase(unit_id)
        print("SpeechBubbleManager: Cleaned up invalid bubble for unit %s" % unit_id)

func _on_speech_bubble_finished(unit_id: String) -> void:
    """Handle speech bubble finished signal"""
    
    if unit_id in active_bubbles:
        active_bubbles.erase(unit_id)
    
    speech_bubble_finished.emit(unit_id)

func _on_speech_bubble_clicked(unit_id: String, text: String) -> void:
    """Handle speech bubble clicked signal"""
    
    stats.bubbles_clicked += 1
    speech_bubble_clicked.emit(unit_id, text)
    
    if logger:
        logger.info("SpeechBubbleManager", "Speech bubble clicked for unit %s: %s" % [unit_id, text])

func _on_unit_command_issued(unit_id: String, command: String) -> void:
    """Handle unit command issued via EventBus"""
    
    # Check if command contains speech
    if command.begins_with("speech:"):
        var speech_text = command.substr(7)  # Remove "speech:" prefix
        var unit = _find_unit_by_id(unit_id)
        var team_id = unit.get_team_id() if unit and unit.has_method("get_team_id") else 0
        show_speech_bubble(unit_id, speech_text, team_id)

func _on_ai_response_generated(unit_id: String, response: String) -> void:
    """Handle AI response for a unit"""
    
    # Check if response contains speech
    var speech_text = response if response != "" else ""
    
    if speech_text != "":
        var unit = _find_unit_by_id(unit_id)
        var team_id = unit.get_team_id() if unit and unit.has_method("get_team_id") else 0
        show_ai_generated_speech(unit_id, speech_text, team_id)

# Public API
func get_active_bubble_count() -> int:
    """Get number of active speech bubbles"""
    return active_bubbles.size()

func get_bubble_for_unit(unit_id: String) -> SpeechBubble:
    """Get the speech bubble for a specific unit"""
    return active_bubbles.get(unit_id, null)

func is_unit_speaking(unit_id: String) -> bool:
    """Check if a unit is currently showing a speech bubble"""
    return unit_id in active_bubbles

func extend_bubble_time(unit_id: String, additional_seconds: float) -> bool:
    """Extend the display time of a speech bubble"""
    
    if unit_id in active_bubbles:
        var bubble = active_bubbles[unit_id]
        bubble.extend_display_time(additional_seconds)
        return true
    
    return false

func set_team_color(team_id: int, color: Color) -> void:
    """Set the color for a team's speech bubbles"""
    team_colors[team_id] = color
    
    # Update existing bubbles
    for unit_id in active_bubbles:
        var bubble = active_bubbles[unit_id]
        if bubble.team_id == team_id:
            bubble.set_bubble_color(color)

func get_statistics() -> Dictionary:
    """Get speech bubble statistics"""
    return stats.duplicate()

func reset_statistics() -> void:
    """Reset speech bubble statistics"""
    stats = {
        "bubbles_created": 0,
        "bubbles_clicked": 0,
        "total_words_displayed": 0,
        "ai_generated_speeches": 0
    }

func set_max_concurrent_bubbles(max_bubbles: int) -> void:
    """Set the maximum number of concurrent speech bubbles"""
    # Remove excess bubbles if needed
    while active_bubbles.size() > max_bubbles:
        _remove_oldest_bubble()

func get_all_active_speeches() -> Dictionary:
    """Get all currently active speeches"""
    var speeches = {}
    
    for unit_id in active_bubbles:
        var bubble = active_bubbles[unit_id]
        speeches[unit_id] = {
            "text": bubble.get_display_text(),
            "original_text": bubble.get_original_text(),
            "team_id": bubble.team_id
        }
    
    return speeches

func queue_speech_bubble(unit_id: String, text: String, team_id: int = 0, delay: float = 0.0) -> void:
    """Queue a speech bubble to be shown after a delay"""
    
    var bubble_data = {
        "unit_id": unit_id,
        "text": text,
        "team_id": team_id,
        "delay": delay,
        "queued_time": Time.get_ticks_msec() / 1000.0
    }
    
    bubble_queue.append(bubble_data)
    
    # Process queue if delay is 0
    if delay == 0.0:
        _process_bubble_queue()

func _process_bubble_queue() -> void:
    """Process queued speech bubbles"""
    
    var current_time = Time.get_ticks_msec() / 1000.0
    var bubbles_to_process = []
    
    for bubble_data in bubble_queue:
        var elapsed = current_time - bubble_data.queued_time
        if elapsed >= bubble_data.delay:
            bubbles_to_process.append(bubble_data)
    
    # Process ready bubbles
    for bubble_data in bubbles_to_process:
        show_speech_bubble(bubble_data.unit_id, bubble_data.text, bubble_data.team_id)
        bubble_queue.erase(bubble_data)

func _process(_delta: float) -> void:
    """Process queued speech bubbles"""
    
    if not bubble_queue.is_empty():
        _process_bubble_queue() 