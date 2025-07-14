# CooperativeSelectionUI.gd
extends Control

# UI elements
@onready var teammate_status_label: Label = $VBoxContainer/TeammateStatusLabel
@onready var current_commander_label: Label = $VBoxContainer/CurrentCommanderLabel
@onready var shared_units_label: Label = $VBoxContainer/SharedUnitsLabel
@onready var command_history_list: ItemList = $VBoxContainer/CommandHistoryList

# State tracking
var local_player_id: int = -1
var teammate_id: int = -1
var current_commanding_player: int = -1
var command_history: Array = []

func _ready() -> void:
	# Connect to team events
	EventBus.team_command_issued.connect(_on_team_command_issued)
	EventBus.teammate_assigned.connect(_on_teammate_assigned)
	EventBus.teammate_removed.connect(_on_teammate_removed)
	
	# Connect to network events
	NetworkManager.player_connected.connect(_on_player_connected)
	
	# Initialize UI
	_update_ui()
	
	Logger.info("CooperativeSelectionUI", "Cooperative selection UI initialized")

func _on_player_connected(player_data) -> void:
	"""Handle player connection"""
	if player_data.peer_id == NetworkManager.local_player_id:
		local_player_id = player_data.peer_id
		teammate_id = player_data.teammate_id
		_update_ui()

func _on_teammate_assigned(player_id: int, new_teammate_id: int) -> void:
	"""Handle teammate assignment"""
	if player_id == local_player_id:
		teammate_id = new_teammate_id
		_update_ui()

func _on_teammate_removed(player_id: int) -> void:
	"""Handle teammate removal"""
	if player_id == local_player_id:
		teammate_id = -1
		_update_ui()

func _on_team_command_issued(team_id: int, command: Dictionary, issuer_id: int) -> void:
	"""Handle team command issued by any team member"""
	var local_player = NetworkManager.get_player_data(local_player_id)
	if not local_player or local_player.team_id != team_id:
		return
	
	# Update current commanding player
	current_commanding_player = issuer_id
	
	# Add to command history
	var issuer_name = "Unknown"
	var issuer_data = NetworkManager.get_player_data(issuer_id)
	if issuer_data:
		issuer_name = issuer_data.player_name
	
	var command_text = "%s: %s" % [issuer_name, _format_command(command)]
	command_history.append(command_text)
	
	# Keep only last 10 commands
	if command_history.size() > 10:
		command_history.pop_front()
	
	_update_ui()

func _format_command(command: Dictionary) -> String:
	"""Format command for display"""
	var command_type = command.get("type", "unknown")
	var target = command.get("target", "")
	
	match command_type:
		"move":
			return "Move to %s" % target
		"attack":
			return "Attack %s" % target
		"ability":
			return "Use %s ability" % command.get("ability", "unknown")
		_:
			return "Unknown command"

func _update_ui() -> void:
	"""Update UI elements"""
	_update_teammate_status()
	_update_current_commander()
	_update_shared_units_info()
	_update_command_history()

func _update_teammate_status() -> void:
	"""Update teammate status display"""
	if not teammate_status_label:
		return
	
	if teammate_id == -1:
		teammate_status_label.text = "Status: Solo player (no teammate)"
		teammate_status_label.modulate = Color.YELLOW
	else:
		var teammate_data = NetworkManager.get_player_data(teammate_id)
		if teammate_data:
			var status = "Online" if teammate_data.peer_id in NetworkManager.connected_players else "Offline"
			teammate_status_label.text = "Teammate: %s (%s)" % [teammate_data.player_name, status]
			teammate_status_label.modulate = Color.GREEN if status == "Online" else Color.RED
		else:
			teammate_status_label.text = "Teammate: Disconnected"
			teammate_status_label.modulate = Color.RED

func _update_current_commander() -> void:
	"""Update current commander display"""
	if not current_commander_label:
		return
	
	if current_commanding_player == -1:
		current_commander_label.text = "Current Commander: None"
		current_commander_label.modulate = Color.GRAY
	else:
		var commander_data = NetworkManager.get_player_data(current_commanding_player)
		if commander_data:
			var is_self = current_commanding_player == local_player_id
			current_commander_label.text = "Current Commander: %s%s" % [commander_data.player_name, " (You)" if is_self else ""]
			current_commander_label.modulate = Color.BLUE if is_self else Color.GREEN
		else:
			current_commander_label.text = "Current Commander: Unknown"
			current_commander_label.modulate = Color.GRAY

func _update_shared_units_info() -> void:
	"""Update shared units information"""
	if not shared_units_label:
		return
	
	var local_player = NetworkManager.get_player_data(local_player_id)
	if not local_player:
		shared_units_label.text = "Shared Units: No team data"
		return
	
	var team_data = NetworkManager.get_team_data(local_player.team_id)
	if not team_data:
		shared_units_label.text = "Shared Units: No team data"
		return
	
	var alive_units = 0
	for unit in team_data.units:
		if unit and not unit.is_dead:
			alive_units += 1
	
	shared_units_label.text = "Shared Units: %d/%d alive" % [alive_units, team_data.units.size()]
	shared_units_label.modulate = Color.GREEN if alive_units > 0 else Color.RED

func _update_command_history() -> void:
	"""Update command history display"""
	if not command_history_list:
		return
	
	command_history_list.clear()
	for command_text in command_history:
		command_history_list.add_item(command_text)
	
	# Scroll to bottom
	if command_history_list.item_count > 0:
		command_history_list.ensure_current_is_visible()

func get_cooperative_control_info() -> Dictionary:
	"""Get information about cooperative control state"""
	var local_player = NetworkManager.get_player_data(local_player_id)
	if not local_player:
		return {}
	
	var teammate_data = NetworkManager.get_player_data(teammate_id) if teammate_id != -1 else null
	var team_data = NetworkManager.get_team_data(local_player.team_id)
	
	return {
		"has_teammate": teammate_id != -1,
		"teammate_name": teammate_data.player_name if teammate_data else "",
		"teammate_online": teammate_data != null and teammate_data.peer_id in NetworkManager.connected_players,
		"current_commander": current_commanding_player,
		"shared_units_count": team_data.units.size() if team_data else 0,
		"can_control_units": true  # Both teammates can always control units
	}

func show_command_feedback(command: Dictionary, success: bool) -> void:
	"""Show visual feedback for command execution"""
	var feedback_text = _format_command(command)
	if success:
		feedback_text += " ✓"
	else:
		feedback_text += " ✗"
	
	# Add to command history with status
	command_history.append(feedback_text)
	if command_history.size() > 10:
		command_history.pop_front()
	
	_update_command_history()

func clear_command_history() -> void:
	"""Clear command history"""
	command_history.clear()
	_update_command_history()

func set_visible_extended(visible: bool) -> void:
	"""Show/hide the cooperative UI"""
	self.visible = visible
	if visible:
		_update_ui() 