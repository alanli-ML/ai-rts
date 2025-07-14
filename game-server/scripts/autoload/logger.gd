# Logger.gd
class_name Logger
extends RefCounted

enum LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR
}

static var _log_file: FileAccess
static var _log_level: LogLevel = LogLevel.DEBUG

static func _static_init() -> void:
    if OS.is_debug_build():
        var log_path = "user://game_log_%s.txt" % Time.get_datetime_string_from_system().replace(":", "-")
        _log_file = FileAccess.open(log_path, FileAccess.WRITE)

static func _log(level: LogLevel, category: String, message: String) -> void:
    if level < _log_level:
        return
    
    var timestamp = Time.get_time_string_from_system()
    var level_str = LogLevel.keys()[level]
    var log_entry = "[%s] [%s] [%s] %s" % [timestamp, level_str, category, message]
    
    print(log_entry)
    
    if _log_file:
        _log_file.store_line(log_entry)
        _log_file.flush()

static func debug(category: String, message: String) -> void:
    _log(LogLevel.DEBUG, category, message)

static func info(category: String, message: String) -> void:
    _log(LogLevel.INFO, category, message)

static func warning(category: String, message: String) -> void:
    _log(LogLevel.WARNING, category, message)
    push_warning(message)

static func error(category: String, message: String) -> void:
    _log(LogLevel.ERROR, category, message)
    push_error(message) 