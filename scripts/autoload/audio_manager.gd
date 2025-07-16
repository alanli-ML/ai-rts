# AudioManager.gd
class_name AudioManager
extends Node

const POOL_SIZE_2D = 10
const POOL_SIZE_3D = 20

var sound_2d_pool: Array[AudioStreamPlayer]
var sound_3d_pool: Array[AudioStreamPlayer3D]
var current_2d_index = 0
var current_3d_index = 0

func _ready():
    _create_pools()
    add_to_group("audio_managers")
    print("AudioManager initialized.")

func _create_pools():
    var sound_2d_container = Node.new()
    sound_2d_container.name = "Sound2DPool"
    add_child(sound_2d_container)
    for i in range(POOL_SIZE_2D):
        var player = AudioStreamPlayer.new()
        player.name = "AudioStreamPlayer2D_%d" % i
        sound_2d_container.add_child(player)
        sound_2d_pool.append(player)
    
    var sound_3d_container = Node.new()
    sound_3d_container.name = "Sound3DPool"
    add_child(sound_3d_container)
    for i in range(POOL_SIZE_3D):
        var player = AudioStreamPlayer3D.new()
        player.name = "AudioStreamPlayer3D_%d" % i
        sound_3d_container.add_child(player)
        sound_3d_pool.append(player)

func play_sound_2d(sound_path: String, volume_db: float = 0.0):
    if sound_path.is_empty(): 
        return
    
    # Try to load the audio stream
    var stream = load(sound_path)
    if not stream:
        print("AudioManager: Could not load sound at path: %s - audio will be skipped" % sound_path)
        # Try to find a fallback sound (for development)
        stream = _try_fallback_sound_2d(sound_path)
        if not stream:
            return
    
    # Validate the stream is an AudioStream
    if not stream is AudioStream:
        print("AudioManager: Invalid audio stream at path: %s" % sound_path)
        return
        
    var player = sound_2d_pool[current_2d_index]
    if not player:
        print("AudioManager: Audio player not available in pool")
        return
        
    player.stream = stream
    player.volume_db = volume_db
    
    # Try to play with error handling
    if player.has_method("play"):
        player.play()
    else:
        print("AudioManager: Audio player cannot play sound")
    
    current_2d_index = (current_2d_index + 1) % POOL_SIZE_2D

func play_sound_3d(sound_path: String, position: Vector3, volume_db: float = 0.0):
    if sound_path.is_empty(): 
        return

    # Try to load the audio stream
    var stream = load(sound_path)
    if not stream:
        print("AudioManager: Could not load 3D sound at path: %s - audio will be skipped" % sound_path)
        # Try to find a fallback sound (for development)
        stream = _try_fallback_sound_3d(sound_path)
        if not stream:
            return
    
    # Validate the stream is an AudioStream
    if not stream is AudioStream:
        print("AudioManager: Invalid 3D audio stream at path: %s" % sound_path)
        return

    var player = sound_3d_pool[current_3d_index]
    if not player:
        print("AudioManager: 3D Audio player not available in pool")
        return
        
    player.global_position = position
    player.stream = stream
    player.volume_db = volume_db
    
    # Try to play with error handling
    if player.has_method("play"):
        player.play()
    else:
        print("AudioManager: 3D Audio player cannot play sound")
    
    current_3d_index = (current_3d_index + 1) % POOL_SIZE_3D

func _try_fallback_sound_2d(original_path: String) -> AudioStream:
    """Try to find a fallback sound for missing 2D audio"""
    # For development, we can return null - this prevents crashes
    # In the future, this could load a default "missing sound" audio file
    return null

func _try_fallback_sound_3d(original_path: String) -> AudioStream:
    """Try to find a fallback sound for missing 3D audio"""
    # For development, we can return null - this prevents crashes
    # In the future, this could load a default "missing sound" audio file
    return null