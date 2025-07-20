# VictoryScreen.gd - Victory/Defeat screen display
class_name VictoryScreen
extends Control

# UI node references
@onready var title_label: Label = $CenterContainer/VictoryPanel/VBoxContainer/Title
@onready var team_label: Label = $CenterContainer/VictoryPanel/VBoxContainer/TeamLabel  
@onready var victory_message: Label = $CenterContainer/VictoryPanel/VBoxContainer/VictoryMessage
@onready var match_duration: Label = $CenterContainer/VictoryPanel/VBoxContainer/Statistics/MatchDuration
@onready var nodes_controlled: Label = $CenterContainer/VictoryPanel/VBoxContainer/Statistics/NodesControlled
@onready var play_again_button: Button = $CenterContainer/VictoryPanel/VBoxContainer/ButtonContainer/PlayAgainButton
@onready var main_menu_button: Button = $CenterContainer/VictoryPanel/VBoxContainer/ButtonContainer/MainMenuButton

# Team colors
var team_colors: Dictionary = {
    1: Color(0.4, 0.7, 1.0, 1.0),  # Team 1 - Blue
    2: Color(1.0, 0.4, 0.4, 1.0)   # Team 2 - Red
}

# Signals
signal play_again_requested()
signal main_menu_requested()

func _ready() -> void:
    # Connect button signals
    play_again_button.pressed.connect(_on_play_again_pressed)
    main_menu_button.pressed.connect(_on_main_menu_pressed)
    
    # Ensure victory screen appears above all other UI
    z_index = 100
    
    # Hide by default
    visible = false

func show_victory_screen(winning_team: int, client_team: int, match_data: Dictionary = {}) -> void:
    """Display the victory screen with appropriate messaging based on teams"""
    
    # Ensure we're on top of all other UI
    move_to_front()
    
    # Determine if client won or lost
    var client_won = (winning_team == client_team)
    
    # Set title and colors based on result
    if client_won:
        title_label.text = "VICTORY!"
        title_label.modulate = Color(0.2, 1.0, 0.2, 1.0)  # Green
    else:
        title_label.text = "DEFEAT"
        title_label.modulate = Color(1.0, 0.3, 0.3, 1.0)  # Red
    
    # Set team label with appropriate color
    team_label.text = "Team %d Wins!" % winning_team
    team_label.modulate = team_colors.get(winning_team, Color.WHITE)
    
    # Set victory message
    victory_message.text = "All 9 control nodes captured!"
    
    # Update statistics if provided
    if match_data.has("duration"):
        var duration_seconds = match_data.duration
        var minutes = int(duration_seconds) / 60
        var seconds = int(duration_seconds) % 60
        match_duration.text = "Match Duration: %d:%02d" % [minutes, seconds]
    else:
        match_duration.text = "Match Duration: --:--"
    
    if match_data.has("team_control_counts"):
        var counts = match_data.team_control_counts
        var team1_nodes = counts.get(1, 0)
        var team2_nodes = counts.get(2, 0)
        nodes_controlled.text = "Final Control: %d vs %d" % [team1_nodes, team2_nodes]
    else:
        nodes_controlled.text = "Final Control: 9 vs 0"
    
    # Show the screen with fade-in animation
    visible = true
    modulate.a = 0.0
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, 0.5)
    
    # Play victory/defeat sound
    _play_victory_sound(client_won)
    
    print("VictoryScreen: Displayed %s screen for Team %d (client team: %d)" % 
          ["VICTORY" if client_won else "DEFEAT", winning_team, client_team])

func hide_victory_screen() -> void:
    """Hide the victory screen"""
    visible = false

func _play_victory_sound(client_won: bool) -> void:
    """Play appropriate sound effect"""
    var audio_manager = get_node_or_null("/root/DependencyContainer/AudioManager")
    if audio_manager:
        if client_won:
            # Play victory sound - use multiple sounds for more impact
            audio_manager.play_sound_2d("res://assets/audio/ui/command_submit_01.wav")
            # Delay second sound slightly
            await get_tree().create_timer(0.2).timeout
            audio_manager.play_sound_2d("res://assets/audio/ui/command_submit_01.wav")
        else:
            # Play defeat sound (more subdued)
            audio_manager.play_sound_2d("res://assets/audio/ui/click_01.wav")

func _on_play_again_pressed() -> void:
    """Handle play again button press"""
    print("VictoryScreen: Play again requested")
    play_again_requested.emit()

func _on_main_menu_pressed() -> void:
    """Handle main menu button press"""
    print("VictoryScreen: Main menu requested")
    main_menu_requested.emit()

func _input(event: InputEvent) -> void:
    """Handle input while victory screen is visible"""
    if not visible:
        return
        
    # Allow ESC key to close screen (go to main menu)
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            _on_main_menu_pressed()
            get_viewport().set_input_as_handled() 