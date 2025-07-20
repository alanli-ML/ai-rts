# AnimationController.gd - Advanced animation state machine for animated units
class_name AnimationController
extends Node

# Animation states
enum AnimationState {
	IDLE,
	WALK,
	RUN,
	ATTACK,
	RELOAD,
	DEATH,
	VICTORY,
	ATTACK_MOVING,
	TAKE_COVER,
	STUNNED,
	HEALING,
	CONSTRUCTING
}

# Animation transition events
enum AnimationEvent {
	START_MOVING,
	STOP_MOVING,
	SPEED_INCREASE,
	SPEED_DECREASE,
	START_ATTACK,
	FINISH_ATTACK,
	START_RELOAD,
	FINISH_RELOAD,
	TAKE_DAMAGE,
	DIE,
	WIN_COMBAT,
	ENTER_COVER,
	EXIT_COVER,
	GET_STUNNED,
	RECOVER_STUN,
	START_HEALING,
	FINISH_HEALING,
	START_CONSTRUCTING,
	FINISH_CONSTRUCTING
}

# Current state
var current_state: AnimationState = AnimationState.IDLE
var previous_state: AnimationState = AnimationState.IDLE

# Animation references
var animation_player: AnimationPlayer
var character_model: Node3D
var unit_reference: Node  # Reference to the parent unit

# Movement tracking
var current_speed: float = 0.0
var movement_direction: Vector3 = Vector3.ZERO
var is_moving: bool = false

# Combat tracking
var is_in_combat: bool = false
var is_attacking: bool = false
var is_reloading: bool = false
var health_percentage: float = 1.0

# Animation settings
const WALK_SPEED_THRESHOLD: float = 1.5
const RUN_SPEED_THRESHOLD: float = 3.0
const ANIMATION_BLEND_TIME: float = 0.3

# Available animations (with fallbacks)
var available_animations: Dictionary = {
	"idle": ["idle", "default", "rest"],
	"walk": ["walk", "move", "idle"],
	"run": ["run", "sprint", "walk", "move"],
	"attack": ["attack", "fire", "shoot", "idle"],
	"reload": ["reload", "rearm", "idle"],
	"death": ["death", "die", "fall", "idle"],
	"victory": ["victory", "celebrate", "cheer", "idle"],
	"take_cover": ["cover", "crouch", "duck", "idle"],
	"stunned": ["stunned", "dazed", "hurt", "idle"],
	"healing": ["interact-left", "interact-right", "emote-yes", "idle"],
	"constructing": ["interact-left", "interact-right", "emote-yes", "pick-up", "idle"]
}

# State transition table
var state_transitions: Dictionary = {}

var logger

signal animation_state_changed(old_state: AnimationState, new_state: AnimationState)
signal animation_event_triggered(event: AnimationEvent)
signal animation_loop_completed(animation_name: String)

func _ready() -> void:
	_setup_logger()
	_setup_state_transitions()
	name = "AnimationController"
	
	if logger:
		logger.info("AnimationController", "Animation controller initialized")
	else:
		print("AnimationController: Animation controller initialized")

func _setup_logger() -> void:
	"""Setup logger reference from dependency container"""
	if has_node("/root/DependencyContainer"):
		var dependency_container = get_node("/root/DependencyContainer")
		if dependency_container.has_method("get_logger"):
			logger = dependency_container.get_logger()

func _setup_state_transitions() -> void:
	"""Define valid state transitions"""
	state_transitions = {
		AnimationState.IDLE: [
			AnimationState.WALK, AnimationState.RUN, AnimationState.ATTACK,
			AnimationState.RELOAD, AnimationState.DEATH, AnimationState.TAKE_COVER,
			AnimationState.STUNNED, AnimationState.HEALING, AnimationState.CONSTRUCTING
		],
		AnimationState.WALK: [
			AnimationState.IDLE, AnimationState.RUN, AnimationState.ATTACK_MOVING,
			AnimationState.DEATH, AnimationState.STUNNED
		],
		AnimationState.RUN: [
			AnimationState.IDLE, AnimationState.WALK, AnimationState.ATTACK_MOVING,
			AnimationState.DEATH, AnimationState.STUNNED
		],
		AnimationState.ATTACK: [
			AnimationState.IDLE, AnimationState.RELOAD, AnimationState.VICTORY,
			AnimationState.DEATH, AnimationState.STUNNED
		],
		AnimationState.RELOAD: [
			AnimationState.IDLE, AnimationState.ATTACK, AnimationState.DEATH,
			AnimationState.STUNNED
		],
		AnimationState.ATTACK_MOVING: [
			AnimationState.WALK, AnimationState.RUN, AnimationState.IDLE,
			AnimationState.DEATH, AnimationState.STUNNED
		],
		AnimationState.TAKE_COVER: [
			AnimationState.IDLE, AnimationState.ATTACK, AnimationState.DEATH,
			AnimationState.STUNNED
		],
		AnimationState.VICTORY: [
			AnimationState.IDLE, AnimationState.DEATH
		],
		AnimationState.STUNNED: [
			AnimationState.IDLE, AnimationState.DEATH
		],
		AnimationState.HEALING: [
			AnimationState.IDLE, AnimationState.WALK, AnimationState.RUN,
			AnimationState.DEATH, AnimationState.STUNNED
		],
		AnimationState.CONSTRUCTING: [
			AnimationState.IDLE, AnimationState.WALK, AnimationState.RUN,
			AnimationState.DEATH, AnimationState.STUNNED
		],
		AnimationState.DEATH: []  # Death is terminal
	}

func initialize(unit: Node, character: Node3D, anim_player: AnimationPlayer) -> void:
	"""Initialize the animation controller with references"""
	unit_reference = unit
	character_model = character
	animation_player = anim_player
	
	# Connect to animation player signals
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	
	# Set initial state
	current_state = AnimationState.IDLE
	_play_animation_for_state(current_state)
	
	if logger:
		logger.info("AnimationController", "Initialized with character model and animation player")

func handle_event(event: AnimationEvent, data: Dictionary = {}) -> void:
	"""Handle animation events and trigger state transitions"""
	animation_event_triggered.emit(event)
	
	var new_state = _determine_new_state(event, data)
	if new_state != current_state:
		_transition_to_state(new_state)

func _determine_new_state(event: AnimationEvent, data: Dictionary) -> AnimationState:
	"""Determine the new animation state based on event and current context"""
	
	# Handle terminal states first
	if event == AnimationEvent.DIE:
		return AnimationState.DEATH
	
	if current_state == AnimationState.DEATH:
		return AnimationState.DEATH  # Death is permanent
	
	# Handle stun states
	if event == AnimationEvent.GET_STUNNED:
		return AnimationState.STUNNED
	
	if event == AnimationEvent.RECOVER_STUN and current_state == AnimationState.STUNNED:
		return AnimationState.IDLE
	
	# Handle movement states
	if event == AnimationEvent.START_MOVING:
		var speed = data.get("speed", 0.0)
		current_speed = speed
		is_moving = true
		
		if is_attacking:
			return AnimationState.ATTACK_MOVING
		elif speed >= RUN_SPEED_THRESHOLD:
			return AnimationState.RUN
		elif speed >= WALK_SPEED_THRESHOLD:
			return AnimationState.WALK
		else:
			return AnimationState.IDLE
	
	if event == AnimationEvent.STOP_MOVING:
		is_moving = false
		current_speed = 0.0
		
		if is_attacking:
			return AnimationState.ATTACK
		elif is_reloading:
			return AnimationState.RELOAD
		else:
			return AnimationState.IDLE
	
	# Handle speed changes during movement
	if event == AnimationEvent.SPEED_INCREASE or event == AnimationEvent.SPEED_DECREASE:
		var speed = data.get("speed", current_speed)
		current_speed = speed
		
		if is_moving:
			if is_attacking:
				return AnimationState.ATTACK_MOVING
			elif speed >= RUN_SPEED_THRESHOLD:
				return AnimationState.RUN
			elif speed >= WALK_SPEED_THRESHOLD:
				return AnimationState.WALK
			else:
				return AnimationState.IDLE
	
	# Handle combat states
	if event == AnimationEvent.START_ATTACK:
		is_attacking = true
		is_in_combat = true
		
		if is_moving:
			return AnimationState.ATTACK_MOVING
		else:
			return AnimationState.ATTACK
	
	if event == AnimationEvent.FINISH_ATTACK:
		is_attacking = false
		
		if is_reloading:
			return AnimationState.RELOAD
		elif is_moving:
			return _get_movement_state()
		else:
			return AnimationState.IDLE
	
	if event == AnimationEvent.START_RELOAD:
		is_reloading = true
		return AnimationState.RELOAD
	
	if event == AnimationEvent.FINISH_RELOAD:
		is_reloading = false
		
		if is_attacking:
			return AnimationState.ATTACK if not is_moving else AnimationState.ATTACK_MOVING
		elif is_moving:
			return _get_movement_state()
		else:
			return AnimationState.IDLE
	
	# Handle cover states
	if event == AnimationEvent.ENTER_COVER:
		return AnimationState.TAKE_COVER
	
	if event == AnimationEvent.EXIT_COVER:
		if is_moving:
			return _get_movement_state()
		else:
			return AnimationState.IDLE
	
	# Handle victory state
	if event == AnimationEvent.WIN_COMBAT:
		is_in_combat = false
		return AnimationState.VICTORY
	
	# Handle healing states
	if event == AnimationEvent.START_HEALING:
		return AnimationState.HEALING
	
	if event == AnimationEvent.FINISH_HEALING:
		if is_moving:
			return _get_movement_state()
		else:
			return AnimationState.IDLE
	
	# Handle constructing states
	if event == AnimationEvent.START_CONSTRUCTING:
		return AnimationState.CONSTRUCTING
	
	if event == AnimationEvent.FINISH_CONSTRUCTING:
		if is_moving:
			return _get_movement_state()
		else:
			return AnimationState.IDLE
	
	# Default to current state if no transition needed
	return current_state

func _get_movement_state() -> AnimationState:
	"""Get the appropriate movement state based on current speed"""
	if current_speed >= RUN_SPEED_THRESHOLD:
		return AnimationState.RUN
	elif current_speed >= WALK_SPEED_THRESHOLD:
		return AnimationState.WALK
	else:
		return AnimationState.IDLE

func _transition_to_state(new_state: AnimationState) -> void:
	"""Transition to a new animation state"""
	
	# Check if transition is valid
	if not _is_valid_transition(current_state, new_state):
		if logger:
			logger.warning("AnimationController", "Invalid transition from %s to %s" % [
				AnimationState.keys()[current_state], 
				AnimationState.keys()[new_state]
			])
		return
	
	# Store previous state
	previous_state = current_state
	current_state = new_state
	
	# Play animation for new state
	_play_animation_for_state(new_state)
	
	# Emit state change signal
	animation_state_changed.emit(previous_state, current_state)
	
	if logger:
		logger.debug("AnimationController", "Transitioned from %s to %s" % [
			AnimationState.keys()[previous_state],
			AnimationState.keys()[current_state]
		])

func _is_valid_transition(from_state: AnimationState, to_state: AnimationState) -> bool:
	"""Check if a state transition is valid"""
	var valid_transitions = state_transitions.get(from_state, [])
	return to_state in valid_transitions

func _play_animation_for_state(state: AnimationState) -> void:
	"""Play the appropriate animation for the given state"""
	if not animation_player:
		return
	
	var animation_name = _get_animation_name_for_state(state)
	if animation_name.is_empty():
		if logger:
			logger.warning("AnimationController", "No animation found for state %s" % AnimationState.keys()[state])
		return
	
	# Play animation with blending if possible
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name, ANIMATION_BLEND_TIME)
		
		if logger:
			logger.debug("AnimationController", "Playing animation %s for state %s" % [
				animation_name, AnimationState.keys()[state]
			])
	else:
		if logger:
			logger.warning("AnimationController", "Animation %s not found in AnimationPlayer" % animation_name)

func _get_animation_name_for_state(state: AnimationState) -> String:
	"""Get the best available animation name for a state"""
	var state_key = ""
	
	match state:
		AnimationState.IDLE:
			state_key = "idle"
		AnimationState.WALK:
			state_key = "walk"
		AnimationState.RUN:
			state_key = "run"
		AnimationState.ATTACK, AnimationState.ATTACK_MOVING:
			state_key = "attack"
		AnimationState.RELOAD:
			state_key = "reload"
		AnimationState.DEATH:
			state_key = "death"
		AnimationState.VICTORY:
			state_key = "victory"
		AnimationState.TAKE_COVER:
			state_key = "take_cover"
		AnimationState.STUNNED:
			state_key = "stunned"
		AnimationState.HEALING:
			state_key = "healing"
		AnimationState.CONSTRUCTING:
			state_key = "constructing"
	
	if state_key.is_empty():
		return ""
	
	# Find the first available animation from the fallback list
	var animation_options = available_animations.get(state_key, [])
	for anim_name in animation_options:
		if animation_player and animation_player.has_animation(anim_name):
			return anim_name
	
	# If no animations found, return the first option for fallback
	return animation_options[0] if animation_options.size() > 0 else ""

func _on_animation_finished(anim_name: String) -> void:
	"""Handle animation completion"""
	animation_loop_completed.emit(anim_name)
	
	# Handle looping for continuous states
	if current_state in [AnimationState.IDLE, AnimationState.WALK, AnimationState.RUN]:
		_play_animation_for_state(current_state)
	
	# Handle state transitions after one-shot animations
	elif current_state == AnimationState.ATTACK:
		handle_event(AnimationEvent.FINISH_ATTACK)
	elif current_state == AnimationState.RELOAD:
		handle_event(AnimationEvent.FINISH_RELOAD)
	elif current_state == AnimationState.VICTORY:
		handle_event(AnimationEvent.STOP_MOVING)  # Return to idle/movement

# Public interface methods
func start_moving(speed: float, direction: Vector3 = Vector3.ZERO) -> void:
	"""Called when unit starts moving"""
	movement_direction = direction
	handle_event(AnimationEvent.START_MOVING, {"speed": speed})

func stop_moving() -> void:
	"""Called when unit stops moving"""
	handle_event(AnimationEvent.STOP_MOVING)

func update_speed(speed: float) -> void:
	"""Called when unit speed changes"""
	var event = AnimationEvent.SPEED_INCREASE if speed > current_speed else AnimationEvent.SPEED_DECREASE
	handle_event(event, {"speed": speed})

func start_attack() -> void:
	"""Called when unit starts attacking"""
	handle_event(AnimationEvent.START_ATTACK)

func finish_attack() -> void:
	"""Called when unit finishes attacking"""
	handle_event(AnimationEvent.FINISH_ATTACK)

func start_reload() -> void:
	"""Called when unit starts reloading"""
	handle_event(AnimationEvent.START_RELOAD)

func finish_reload() -> void:
	"""Called when unit finishes reloading"""
	handle_event(AnimationEvent.FINISH_RELOAD)

func take_damage(damage: float, new_health: float, max_health: float) -> void:
	"""Called when unit takes damage"""
	health_percentage = new_health / max_health
	handle_event(AnimationEvent.TAKE_DAMAGE, {"damage": damage, "health_percentage": health_percentage})

func die() -> void:
	"""Called when unit dies"""
	handle_event(AnimationEvent.DIE)

func win_combat() -> void:
	"""Called when unit wins combat"""
	handle_event(AnimationEvent.WIN_COMBAT)

func enter_cover() -> void:
	"""Called when unit enters cover"""
	handle_event(AnimationEvent.ENTER_COVER)

func exit_cover() -> void:
	"""Called when unit exits cover"""
	handle_event(AnimationEvent.EXIT_COVER)

func get_stunned() -> void:
	"""Called when unit gets stunned"""
	handle_event(AnimationEvent.GET_STUNNED)

func recover_from_stun() -> void:
	"""Called when unit recovers from stun"""
	handle_event(AnimationEvent.RECOVER_STUN)

func start_healing() -> void:
	"""Called when unit starts healing"""
	handle_event(AnimationEvent.START_HEALING)

func finish_healing() -> void:
	"""Called when unit finishes healing"""
	handle_event(AnimationEvent.FINISH_HEALING)

func start_constructing() -> void:
	"""Called when unit starts constructing"""
	handle_event(AnimationEvent.START_CONSTRUCTING)

func finish_constructing() -> void:
	"""Called when unit finishes constructing"""
	handle_event(AnimationEvent.FINISH_CONSTRUCTING)

# Debug and utility methods
func get_current_state_name() -> String:
	"""Get the current state as a readable string"""
	return AnimationState.keys()[current_state]

func get_available_animations_for_current_state() -> Array:
	"""Get available animations for the current state"""
	var state_key = ""
	match current_state:
		AnimationState.IDLE:
			state_key = "idle"
		AnimationState.WALK:
			state_key = "walk"
		AnimationState.RUN:
			state_key = "run"
		AnimationState.ATTACK, AnimationState.ATTACK_MOVING:
			state_key = "attack"
		AnimationState.RELOAD:
			state_key = "reload"
		AnimationState.DEATH:
			state_key = "death"
		AnimationState.VICTORY:
			state_key = "victory"
		AnimationState.TAKE_COVER:
			state_key = "take_cover"
		AnimationState.STUNNED:
			state_key = "stunned"
	
	return available_animations.get(state_key, [])

func debug_info() -> Dictionary:
	"""Get debug information about the animation controller"""
	return {
		"current_state": get_current_state_name(),
		"previous_state": AnimationState.keys()[previous_state],
		"current_speed": current_speed,
		"is_moving": is_moving,
		"is_attacking": is_attacking,
		"is_reloading": is_reloading,
		"is_in_combat": is_in_combat,
		"health_percentage": health_percentage,
		"available_animations": get_available_animations_for_current_state(),
		"movement_direction": movement_direction
	} 