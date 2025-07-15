# TestSpeechBubbles.gd
extends Node

# Test script for speech bubble system
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")
const SpeechBubbleManager = preload("res://scripts/ui/speech_bubble_manager.gd")

var speech_bubble_manager: SpeechBubbleManager = null
var test_units: Array = []

func _ready() -> void:
    # Create speech bubble manager
    speech_bubble_manager = SpeechBubbleManager.new()
    speech_bubble_manager.name = "SpeechBubbleManager"
    add_child(speech_bubble_manager)
    
    # Wait a bit for the scene to be ready
    await get_tree().process_frame
    
    # Find test units
    _find_test_units()
    
    print("TestSpeechBubbles: Test script initialized")

func _find_test_units() -> void:
    """Find units in the scene to test with"""
    test_units = get_tree().get_nodes_in_group("units")
    
    if test_units.size() > 0:
        print("TestSpeechBubbles: Found %d units for testing" % test_units.size())
    else:
        print("TestSpeechBubbles: No units found for testing")

func _input(event: InputEvent) -> void:
    """Handle input for testing"""
    
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_1:
                test_basic_speech_bubble()
            KEY_2:
                test_multiple_speech_bubbles()
            KEY_3:
                test_ai_generated_speech()
            KEY_4:
                test_long_speech_bubble()
            KEY_5:
                test_team_colors()
            KEY_6:
                test_speech_bubble_interactions()
            KEY_7:
                test_speech_bubble_cleanup()
            KEY_8:
                show_speech_bubble_stats()
            KEY_9:
                test_queued_speech_bubbles()
            KEY_0:
                hide_all_speech_bubbles()

func test_basic_speech_bubble() -> void:
    """Test basic speech bubble functionality"""
    
    if test_units.size() == 0:
        print("TestSpeechBubbles: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    speech_bubble_manager.show_speech_bubble(unit_id, "Hello, I'm a test unit!", 1)
    print("TestSpeechBubbles: Showing basic speech bubble for unit %s" % unit_id)

func test_multiple_speech_bubbles() -> void:
    """Test multiple speech bubbles at once"""
    
    if test_units.size() < 2:
        print("TestSpeechBubbles: Need at least 2 units for this test")
        return
    
    var messages = [
        "I'm ready for action!",
        "Standing by for orders.",
        "Unit operational and ready.",
        "Awaiting instructions.",
        "All systems green."
    ]
    
    for i in range(min(test_units.size(), messages.size())):
        var unit = test_units[i]
        var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
        var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
        
        speech_bubble_manager.show_speech_bubble(unit_id, messages[i], team_id)
    
    print("TestSpeechBubbles: Showing multiple speech bubbles")

func test_ai_generated_speech() -> void:
    """Test AI-generated speech bubbles"""
    
    if test_units.size() == 0:
        print("TestSpeechBubbles: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    var team_id = unit.get_team_id() if unit.has_method("get_team_id") else 1
    
    var ai_responses = [
        "I will move to the designated position immediately.",
        "Roger that, commander. Engaging target.",
        "Understood. Retreating to safe distance.",
        "Affirmative. Switching to defensive stance.",
        "Copy that. Initiating patrol route."
    ]
    
    var response = ai_responses[randi() % ai_responses.size()]
    speech_bubble_manager.show_ai_generated_speech(unit_id, response, team_id)
    
    print("TestSpeechBubbles: Showing AI-generated speech bubble")

func test_long_speech_bubble() -> void:
    """Test speech bubble with text longer than word limit"""
    
    if test_units.size() == 0:
        print("TestSpeechBubbles: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    var long_text = "This is a very long message that should be truncated to exactly twelve words maximum according to the speech bubble system requirements."
    speech_bubble_manager.show_speech_bubble(unit_id, long_text, 1)
    
    print("TestSpeechBubbles: Showing long speech bubble (should be truncated)")

func test_team_colors() -> void:
    """Test team-colored speech bubbles"""
    
    if test_units.size() < 2:
        print("TestSpeechBubbles: Need at least 2 units for team color test")
        return
    
    # Set custom team colors
    speech_bubble_manager.set_team_color(1, Color.BLUE)
    speech_bubble_manager.set_team_color(2, Color.RED)
    
    # Show bubbles for different teams
    for i in range(min(test_units.size(), 4)):
        var unit = test_units[i]
        var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
        var team_id = (i % 2) + 1  # Alternate between team 1 and 2
        
        var team_name = "Blue Team" if team_id == 1 else "Red Team"
        speech_bubble_manager.show_speech_bubble(unit_id, "I'm on %s!" % team_name, team_id)
    
    print("TestSpeechBubbles: Showing team-colored speech bubbles")

func test_speech_bubble_interactions() -> void:
    """Test speech bubble interactions and clicks"""
    
    if test_units.size() == 0:
        print("TestSpeechBubbles: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Connect to click signal
    if not speech_bubble_manager.speech_bubble_clicked.is_connected(_on_speech_bubble_clicked):
        speech_bubble_manager.speech_bubble_clicked.connect(_on_speech_bubble_clicked)
    
    speech_bubble_manager.show_speech_bubble(unit_id, "Click me to test interaction!", 1)
    
    print("TestSpeechBubbles: Showing clickable speech bubble")

func test_speech_bubble_cleanup() -> void:
    """Test speech bubble cleanup and management"""
    
    if test_units.size() == 0:
        print("TestSpeechBubbles: No units available for testing")
        return
    
    # Create many bubbles to test cleanup
    for i in range(15):  # More than MAX_CONCURRENT_BUBBLES
        var unit_index = i % test_units.size()
        var unit = test_units[unit_index]
        var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
        
        # Create unique unit ID for this test
        var test_unit_id = "%s_test_%d" % [unit_id, i]
        
        speech_bubble_manager.show_speech_bubble(test_unit_id, "Cleanup test %d" % i, 1)
    
    print("TestSpeechBubbles: Testing speech bubble cleanup (created 15 bubbles)")

func test_queued_speech_bubbles() -> void:
    """Test queued speech bubbles with delays"""
    
    if test_units.size() == 0:
        print("TestSpeechBubbles: No units available for testing")
        return
    
    var unit = test_units[0]
    var unit_id = unit.get_unit_id() if unit.has_method("get_unit_id") else unit.name
    
    # Queue multiple speech bubbles with delays
    speech_bubble_manager.queue_speech_bubble(unit_id, "First message", 1, 0.0)
    speech_bubble_manager.queue_speech_bubble(unit_id, "Second message", 1, 2.0)
    speech_bubble_manager.queue_speech_bubble(unit_id, "Third message", 1, 4.0)
    
    print("TestSpeechBubbles: Queued 3 speech bubbles with delays")

func show_speech_bubble_stats() -> void:
    """Show speech bubble statistics"""
    
    var stats = speech_bubble_manager.get_statistics()
    print("TestSpeechBubbles: Speech Bubble Statistics:")
    print("  Bubbles created: %d" % stats.bubbles_created)
    print("  Bubbles clicked: %d" % stats.bubbles_clicked)
    print("  Total words displayed: %d" % stats.total_words_displayed)
    print("  AI generated speeches: %d" % stats.ai_generated_speeches)
    print("  Active bubbles: %d" % speech_bubble_manager.get_active_bubble_count())

func hide_all_speech_bubbles() -> void:
    """Hide all speech bubbles"""
    
    speech_bubble_manager.hide_all_speech_bubbles()
    print("TestSpeechBubbles: All speech bubbles hidden")

func _on_speech_bubble_clicked(unit_id: String, text: String) -> void:
    """Handle speech bubble click event"""
    
    print("TestSpeechBubbles: Speech bubble clicked for unit %s: %s" % [unit_id, text])
    
    # Show a response bubble
    speech_bubble_manager.show_speech_bubble(unit_id, "You clicked me!", 1)

func print_help() -> void:
    """Print help information"""
    
    print("TestSpeechBubbles: Keyboard shortcuts:")
    print("  1 - Test basic speech bubble")
    print("  2 - Test multiple speech bubbles")
    print("  3 - Test AI-generated speech")
    print("  4 - Test long speech bubble")
    print("  5 - Test team colors")
    print("  6 - Test speech bubble interactions")
    print("  7 - Test speech bubble cleanup")
    print("  8 - Show speech bubble stats")
    print("  9 - Test queued speech bubbles")
    print("  0 - Hide all speech bubbles")

func _enter_tree() -> void:
    """Called when entering the tree"""
    
    # Wait a bit then print help
    await get_tree().create_timer(1.0).timeout
    print_help() 