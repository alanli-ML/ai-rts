# Logger.gd - Shared logging utility (autoload)
extends Node

enum LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR
}

var _log_file: FileAccess
var _log_level: LogLevel = LogLevel.DEBUG

func _ready():
    # Initialize logging
    if OS.is_debug_build():
        var log_path = "user://game_log_%s.txt" % Time.get_datetime_string_from_system().replace(":", "-")
        _log_file = FileAccess.open(log_path, FileAccess.WRITE)

func _log(level: LogLevel, category: String, message: String) -> void:
    var timestamp = Time.get_datetime_string_from_system()
    var level_str = _get_level_string(level)
    var formatted_message = "[%s] [%s] %s: %s" % [timestamp, level_str, category, message]
    
    # Print to console
    print(formatted_message)
    
    # Write to file if available
    if _log_file and _log_file.is_open():
        _log_file.store_line(formatted_message)
        _log_file.flush()

func _get_level_string(level: LogLevel) -> String:
    match level:
        LogLevel.DEBUG:
            return "DEBUG"
        LogLevel.INFO:
            return "INFO"
        LogLevel.WARNING:
            return "WARNING"
        LogLevel.ERROR:
            return "ERROR"
        _:
            return "UNKNOWN"

func debug(category: String, message: String) -> void:
    if _log_level <= LogLevel.DEBUG:
        _log(LogLevel.DEBUG, category, message)

func info(category: String, message: String) -> void:
    if _log_level <= LogLevel.INFO:
        _log(LogLevel.INFO, category, message)

func warning(category: String, message: String) -> void:
    if _log_level <= LogLevel.WARNING:
        _log(LogLevel.WARNING, category, message)

func error(category: String, message: String) -> void:
    if _log_level <= LogLevel.ERROR:
        _log(LogLevel.ERROR, category, message)

func set_log_level(level: LogLevel) -> void:
    _log_level = level

func _exit_tree() -> void:
    if _log_file and _log_file.is_open():
        _log_file.close() 