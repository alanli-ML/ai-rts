# NetworkManager.gd
extends Node

# Network configuration
const DEFAULT_PORT = 7777
const MAX_CLIENTS = 2
const TICK_RATE = 30

# Network state
enum NetworkState {
	OFFLINE,
	HOSTING,
	JOINING,
	CONNECTED,
	IN_MATCH
}

# Player data structure
class PlayerData:
	var peer_id: int
	var player_name: String
	var team_id: int
	var is_ready: bool = false
	var is_team_leader: bool = false
	var teammate_id: int = -1  # Peer ID of teammate, -1 if no teammate
	
	func _init(id: int, name: String, team: int):
		peer_id = id
		player_name = name
		team_id = team

# Team data structure for shared unit control
class TeamData:
	var team_id: int
	var team_name: String
	var player_ids: Array[int] = []
	var units: Array = []  # Shared units for this team
	var is_ready: bool = false  # Team is ready when all members are ready
	
	func _init(id: int, name: String = ""):
		team_id = id
		team_name = name if name != "" else "Team %d" % id
	
	func add_player(player_id: int) -> bool:
		if player_ids.size() >= 2:  # Max 2 players per team
			return false
		if player_id not in player_ids:
			player_ids.append(player_id)
		return true
	
	func remove_player(player_id: int) -> void:
		player_ids.erase(player_id)
	
	func is_full() -> bool:
		return player_ids.size() >= 2
	
	func get_teammate_id(player_id: int) -> int:
		for pid in player_ids:
			if pid != player_id:
				return pid
		return -1

# Network properties
var current_state: NetworkState = NetworkState.OFFLINE
var is_server: bool = false
var server_port: int = DEFAULT_PORT
var peer: ENetMultiplayerPeer
var connected_players: Dictionary = {}  # peer_id -> PlayerData
var teams: Dictionary = {}  # team_id -> TeamData
var local_player_id: int = 0

# Match state
var match_id: String = ""
var match_started: bool = false
var tick_number: int = 0
var input_buffer: Dictionary = {}  # tick -> {peer_id -> input_data}

# Signals
signal player_connected(player_data: PlayerData)
signal player_disconnected(peer_id: int)
signal player_ready_changed(peer_id: int, is_ready: bool)
signal match_started_signal()
signal match_ended_signal(winner_team: int)
signal network_error_signal(message: String)

func _ready() -> void:
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	Logger.info("NetworkManager", "NetworkManager initialized")

# Server hosting
func host_game(port: int = DEFAULT_PORT) -> bool:
	if current_state != NetworkState.OFFLINE:
		Logger.warning("NetworkManager", "Cannot host - already in network state: %s" % NetworkState.keys()[current_state])
		return false
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	
	if error != OK:
		Logger.error("NetworkManager", "Failed to create server on port %d: %s" % [port, error])
		network_error_signal.emit("Failed to create server on port %d" % port)
		return false
	
	multiplayer.multiplayer_peer = peer
	server_port = port
	is_server = true
	current_state = NetworkState.HOSTING
	local_player_id = 1  # Server is always peer ID 1
	
	# Add server as first player
	var server_player = PlayerData.new(local_player_id, "Host", 1)
	connected_players[local_player_id] = server_player
	
	Logger.info("NetworkManager", "Server started on port %d" % port)
	return true

# Client joining
func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if current_state != NetworkState.OFFLINE:
		Logger.warning("NetworkManager", "Cannot join - already in network state: %s" % NetworkState.keys()[current_state])
		return false
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		Logger.error("NetworkManager", "Failed to create client for %s:%d: %s" % [address, port, error])
		network_error_signal.emit("Failed to connect to %s:%d" % [address, port])
		return false
	
	multiplayer.multiplayer_peer = peer
	is_server = false
	current_state = NetworkState.JOINING
	
	Logger.info("NetworkManager", "Attempting to join server at %s:%d" % [address, port])
	return true

# Disconnect from network
func disconnect_from_game() -> void:
	if current_state == NetworkState.OFFLINE:
		return
	
	if is_server:
		Logger.info("NetworkManager", "Shutting down server")
		# Notify all clients of shutdown
		_rpc_all_clients("_on_server_shutdown")
	else:
		Logger.info("NetworkManager", "Disconnecting from server")
	
	# Clean up
	if peer:
		peer.close()
		peer = null
	
	multiplayer.multiplayer_peer = null
	connected_players.clear()
	current_state = NetworkState.OFFLINE
	is_server = false
	match_started = false
	tick_number = 0
	input_buffer.clear()
	
	# Notify game systems
	EventBus.network_disconnected.emit()

# Player ready state
func set_player_ready(is_ready: bool) -> void:
	if current_state != NetworkState.CONNECTED:
		Logger.warning("NetworkManager", "Cannot set ready - not connected")
		return
	
	if local_player_id in connected_players:
		connected_players[local_player_id].is_ready = is_ready
		_rpc_all_clients("_on_player_ready_changed", [local_player_id, is_ready])
		player_ready_changed.emit(local_player_id, is_ready)

# Start match (server only)
func start_match() -> bool:
	if not is_server:
		Logger.warning("NetworkManager", "Only server can start match")
		return false
	
	if current_state != NetworkState.CONNECTED:
		Logger.warning("NetworkManager", "Cannot start match - not in connected state")
		return false
	
	# Check if all players are ready
	for player_data in connected_players.values():
		if not player_data.is_ready:
			Logger.warning("NetworkManager", "Cannot start match - player %s not ready" % player_data.player_name)
			return false
	
	# Generate match ID
	match_id = "match_" + str(Time.get_unix_time_from_system())
	match_started = true
	current_state = NetworkState.IN_MATCH
	tick_number = 0
	
	# Notify all clients
	_rpc_all_clients("_on_match_started", [match_id])
	match_started_signal.emit()
	
	Logger.info("NetworkManager", "Match started: %s" % match_id)
	return true

# Send input for lock-step synchronization
func send_input(input_data: Dictionary) -> void:
	if current_state != NetworkState.IN_MATCH:
		return
	
	var tick = tick_number
	if not input_buffer.has(tick):
		input_buffer[tick] = {}
	
	input_buffer[tick][local_player_id] = input_data
	
	# Send to server (or broadcast if we are server)
	if is_server:
		_rpc_all_clients("_on_input_received", [tick, local_player_id, input_data])
	else:
		_rpc_server("_on_input_received", [tick, local_player_id, input_data])

# Get player data
func get_player_data(peer_id: int) -> PlayerData:
	return connected_players.get(peer_id, null)

func get_local_player() -> PlayerData:
	return connected_players.get(local_player_id, null)

func get_all_players() -> Array:
	var players: Array = []
	for player_data in connected_players.values():
		players.append(player_data)
	return players

# Team management functions
func _assign_player_to_team(peer_id: int) -> int:
	"""Assign player to a team with available slots (max 2 per team)"""
	# Try to find a team with open slots
	for team_id in range(1, 3):  # Support 2 teams max
		if not teams.has(team_id):
			teams[team_id] = TeamData.new(team_id)
		
		var team_data = teams[team_id]
		if team_data.add_player(peer_id):
			Logger.info("NetworkManager", "Assigned player %d to team %d (%d/%d players)" % [peer_id, team_id, team_data.player_ids.size(), 2])
			return team_id
	
	return -1  # No available team slots

func _remove_player_from_team(peer_id: int) -> void:
	"""Remove player from their team"""
	if peer_id not in connected_players:
		return
	
	var player_data = connected_players[peer_id]
	var team_id = player_data.team_id
	
	if teams.has(team_id):
		var team_data = teams[team_id]
		team_data.remove_player(peer_id)
		
		# Update teammate information
		if player_data.teammate_id != -1 and player_data.teammate_id in connected_players:
			connected_players[player_data.teammate_id].teammate_id = -1
			_rpc_all_clients("_on_teammate_removed", [player_data.teammate_id])
		
		# Remove team if empty
		if team_data.player_ids.is_empty():
			teams.erase(team_id)
		
		Logger.info("NetworkManager", "Removed player %d from team %d" % [peer_id, team_id])

func get_team_data(team_id: int) -> TeamData:
	"""Get team data by ID"""
	return teams.get(team_id, null)

func get_player_teammate(peer_id: int) -> PlayerData:
	"""Get teammate data for a player"""
	if peer_id not in connected_players:
		return null
	
	var player_data = connected_players[peer_id]
	if player_data.teammate_id == -1:
		return null
	
	return connected_players.get(player_data.teammate_id, null)

func is_team_ready(team_id: int) -> bool:
	"""Check if all players in a team are ready"""
	if not teams.has(team_id):
		return false
	
	var team_data = teams[team_id]
	for player_id in team_data.player_ids:
		if player_id in connected_players:
			if not connected_players[player_id].is_ready:
				return false
	
	return true

# Network event handlers
func _on_peer_connected(peer_id: int) -> void:
	Logger.info("NetworkManager", "Peer connected: %d" % peer_id)
	
	if is_server:
		# Assign player to team (supports 2 players per team)
		var assigned_team = _assign_player_to_team(peer_id)
		if assigned_team == -1:
			Logger.error("NetworkManager", "Failed to assign player %d to team - all teams full" % peer_id)
			return
		
		var player_data = PlayerData.new(peer_id, "Player_%d" % peer_id, assigned_team)
		connected_players[peer_id] = player_data
		
		# Set teammate information
		var team_data = teams[assigned_team]
		if team_data.player_ids.size() == 2:
			var teammate_id = team_data.get_teammate_id(peer_id)
			player_data.teammate_id = teammate_id
			
			# Update teammate's data
			if teammate_id in connected_players:
				connected_players[teammate_id].teammate_id = peer_id
				_rpc_all_clients("_on_teammate_assigned", [teammate_id, peer_id])
		
		# Set team leader for first player in team
		if team_data.player_ids.size() == 1:
			player_data.is_team_leader = true
		
		# Notify all clients about new player
		_rpc_all_clients("_on_player_joined", [peer_id, player_data.player_name, player_data.team_id, player_data.is_team_leader])
		player_connected.emit(player_data)
		
		# Send current player list and team data to new client
		_rpc_client(peer_id, "_on_player_list_update", [_serialize_player_list()])
		_rpc_client(peer_id, "_on_team_data_update", [_serialize_team_data()])

func _on_peer_disconnected(peer_id: int) -> void:
	Logger.info("NetworkManager", "Peer disconnected: %d" % peer_id)
	
	if peer_id in connected_players:
		if is_server:
			_remove_player_from_team(peer_id)
		
		connected_players.erase(peer_id)
		
		if is_server:
			# Notify remaining clients
			_rpc_all_clients("_on_player_left", [peer_id])
		
		player_disconnected.emit(peer_id)
		
		# If we're in a match and someone disconnects, end the match
		if match_started:
			_end_match_due_to_disconnect(peer_id)

func _on_connection_failed() -> void:
	Logger.error("NetworkManager", "Connection failed")
	current_state = NetworkState.OFFLINE
	network_error_signal.emit("Connection failed")

func _on_connected_to_server() -> void:
	Logger.info("NetworkManager", "Connected to server")
	current_state = NetworkState.CONNECTED
	local_player_id = multiplayer.get_unique_id()

func _on_server_disconnected() -> void:
	Logger.info("NetworkManager", "Server disconnected")
	disconnect_from_game()

# RPC functions
@rpc("any_peer", "call_local", "reliable")
func _on_player_joined(peer_id: int, player_name: String, team_id: int, is_team_leader: bool = false) -> void:
	if peer_id not in connected_players:
		var player_data = PlayerData.new(peer_id, player_name, team_id)
		player_data.is_team_leader = is_team_leader
		connected_players[peer_id] = player_data
		player_connected.emit(player_data)

@rpc("any_peer", "call_local", "reliable")
func _on_player_left(peer_id: int) -> void:
	if peer_id in connected_players:
		connected_players.erase(peer_id)
		player_disconnected.emit(peer_id)

@rpc("any_peer", "call_local", "reliable")
func _on_player_list_update(player_list: Array) -> void:
	# Deserialize player list
	connected_players.clear()
	for player_info in player_list:
		var player_data = PlayerData.new(player_info.peer_id, player_info.player_name, player_info.team_id)
		player_data.is_ready = player_info.is_ready
		connected_players[player_info.peer_id] = player_data

@rpc("any_peer", "call_local", "reliable")
func _on_player_ready_changed(peer_id: int, is_ready: bool) -> void:
	if peer_id in connected_players:
		connected_players[peer_id].is_ready = is_ready
		player_ready_changed.emit(peer_id, is_ready)

@rpc("any_peer", "call_local", "reliable")
func _on_teammate_assigned(player_id: int, teammate_id: int) -> void:
	if player_id in connected_players:
		connected_players[player_id].teammate_id = teammate_id
		Logger.info("NetworkManager", "Player %d assigned teammate %d" % [player_id, teammate_id])

@rpc("any_peer", "call_local", "reliable")
func _on_teammate_removed(player_id: int) -> void:
	if player_id in connected_players:
		connected_players[player_id].teammate_id = -1
		Logger.info("NetworkManager", "Player %d teammate removed" % player_id)

@rpc("any_peer", "call_local", "reliable")
func _on_team_data_update(team_data: Array) -> void:
	teams.clear()
	for team_info in team_data:
		var team = TeamData.new(team_info.team_id, team_info.team_name)
		team.player_ids = team_info.player_ids
		team.units = team_info.units
		team.is_ready = team_info.is_ready
		teams[team.team_id] = team
	Logger.info("NetworkManager", "Team data updated: %d teams" % teams.size())

@rpc("any_peer", "call_local", "reliable")
func _on_match_started(new_match_id: String) -> void:
	if not is_server:
		match_id = new_match_id
		match_started = true
		current_state = NetworkState.IN_MATCH
		tick_number = 0
		match_started_signal.emit()

@rpc("any_peer", "call_local", "reliable")
func _on_input_received(tick: int, peer_id: int, input_data: Dictionary) -> void:
	if not input_buffer.has(tick):
		input_buffer[tick] = {}
	
	input_buffer[tick][peer_id] = input_data
	
	# If we're the server, broadcast to all clients
	if is_server and peer_id != local_player_id:
		_rpc_all_clients("_on_input_received", [tick, peer_id, input_data])

@rpc("any_peer", "call_local", "reliable")
func _on_server_shutdown() -> void:
	Logger.info("NetworkManager", "Server is shutting down")
	disconnect_from_game()

# Helper functions
func _rpc_all_clients(method: String, args: Array = []) -> void:
	if args.is_empty():
		rpc(method)
	else:
		rpc(method, args[0], args[1] if args.size() > 1 else null, args[2] if args.size() > 2 else null)

func _rpc_client(peer_id: int, method: String, args: Array = []) -> void:
	if args.is_empty():
		rpc_id(peer_id, method)
	else:
		rpc_id(peer_id, method, args[0], args[1] if args.size() > 1 else null, args[2] if args.size() > 2 else null)

func _rpc_server(method: String, args: Array = []) -> void:
	if args.is_empty():
		rpc_id(1, method)
	else:
		rpc_id(1, method, args[0], args[1] if args.size() > 1 else null, args[2] if args.size() > 2 else null)

func _serialize_player_list() -> Array:
	var list = []
	for player_data in connected_players.values():
		list.append({
			"peer_id": player_data.peer_id,
			"player_name": player_data.player_name,
			"team_id": player_data.team_id,
			"is_ready": player_data.is_ready,
			"is_team_leader": player_data.is_team_leader,
			"teammate_id": player_data.teammate_id
		})
	return list

func _serialize_team_data() -> Array:
	var list = []
	for team_data in teams.values():
		list.append({
			"team_id": team_data.team_id,
			"team_name": team_data.team_name,
			"player_ids": team_data.player_ids,
			"units": team_data.units,
			"is_ready": team_data.is_ready
		})
	return list

func _end_match_due_to_disconnect(disconnected_peer_id: int) -> void:
	if not match_started:
		return
	
	var winner_team = 0
	if disconnected_peer_id in connected_players:
		var disconnected_player = connected_players[disconnected_peer_id]
		# Winner is the opposite team
		winner_team = 1 if disconnected_player.team_id == 2 else 2
	
	match_started = false
	current_state = NetworkState.CONNECTED
	match_ended_signal.emit(winner_team)
	
	Logger.info("NetworkManager", "Match ended due to disconnect. Winner: Team %d" % winner_team) 