# OpenAIClient.gd
class_name OpenAIClient
extends Node

# OpenAI API configuration
@export var api_key: String = ""
@export var base_url: String = "https://api.openai.com/v1"
@export var model: String = "gpt-4o-mini"
@export var max_tokens: int = 500
@export var temperature: float = 0.7

# Rate limiting
@export var requests_per_minute: int = 60
@export var max_concurrent_requests: int = 5

# Internal variables
var http_request: HTTPRequest = null
var request_queue: Array = []
var active_requests: int = 0
var request_timestamps: Array = []

# Error handling
enum APIError {
	NONE,
	NETWORK_ERROR,
	RATE_LIMITED,
	INVALID_API_KEY,
	QUOTA_EXCEEDED,
	TIMEOUT,
	UNKNOWN_ERROR
}

# Signals
signal request_completed(response: Dictionary)
signal request_failed(error_type: APIError, message: String)
signal rate_limit_exceeded()

func _ready() -> void:
	http_request = HTTPRequest.new()
	http_request.name = "HTTPRequest"
	http_request.timeout = 30.0
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	_load_api_key()
	print("OpenAI client initialized")

func _load_api_key() -> void:
	api_key = OS.get_environment("OPENAI_API_KEY")
	if not api_key.is_empty():
		print("API key loaded from environment variable")
		return
		
	var env_path = "res://.env"
	if FileAccess.file_exists(env_path):
		var file = FileAccess.open(env_path, FileAccess.READ)
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.begins_with("OPENAI_API_KEY="):
				api_key = line.split("=", false, 1)[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
				print("API key loaded from .env file")
				file.close()
				return
		file.close()

	if api_key.is_empty():
		print("WARNING: OPENAI_API_KEY not found in environment or .env file.")

func send_chat_completion(messages: Array, callback: Callable) -> void:
	if api_key.is_empty():
		request_failed.emit(APIError.INVALID_API_KEY, "API key not configured")
		return
	
	if not _check_rate_limit():
		rate_limit_exceeded.emit()
		return
	
	var request_data = {
		"model": model,
		"messages": messages,
		"max_tokens": max_tokens,
		"temperature": temperature
	}
	
	var request_info = {
		"url": base_url + "/chat/completions",
		"data": request_data,
		"callback": callback,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	
	request_queue.append(request_info)
	_process_queue()

func _check_rate_limit() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	request_timestamps = request_timestamps.filter(func(timestamp): return current_time - timestamp < 60.0)
	if request_timestamps.size() >= requests_per_minute or active_requests >= max_concurrent_requests:
		return false
	return true

func _process_queue() -> void:
	if request_queue.is_empty() or active_requests >= max_concurrent_requests:
		return
	
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	
	var request_info = request_queue.pop_front()
	_send_request(request_info)

func _send_request(request_info: Dictionary) -> void:
	active_requests += 1
	request_timestamps.append(Time.get_ticks_msec() / 1000.0)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	var json_data = JSON.stringify(request_info.data)
	http_request.set_meta("callback", request_info.callback)
	
	var error = http_request.request(request_info.url, headers, HTTPClient.METHOD_POST, json_data)
	if error != OK:
		active_requests -= 1
		request_failed.emit(APIError.NETWORK_ERROR, "Failed to send request")

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	active_requests -= 1
	var callback = http_request.get_meta("callback") as Callable
	
	if response_code != HTTPClient.RESPONSE_OK:
		var error_message = "HTTP Error " + str(response_code)
		if body.size() > 0:
			var error_json = JSON.new()
			if error_json.parse(body.get_string_from_utf8()) == OK:
				var error_data = error_json.data
				if error_data.has("error") and error_data.error is Dictionary:
					error_message = error_data.error.get("message", error_message)
		request_failed.emit(_get_error_type(response_code), error_message)
		_process_queue()
		return
	
	var response_json = JSON.new()
	if response_json.parse(body.get_string_from_utf8()) != OK:
		request_failed.emit(APIError.UNKNOWN_ERROR, "Invalid JSON response")
		_process_queue()
		return
	
	var response_data = response_json.data
	if callback.is_valid():
		callback.call(response_data)
	request_completed.emit(response_data)
	_process_queue()
	if callback.is_valid():
		callback.call(response_data)
	
	_process_queue()

func _get_error_type(response_code: int) -> APIError:
	match response_code:
		401: return APIError.INVALID_API_KEY
		429: return APIError.RATE_LIMITED
		402: return APIError.QUOTA_EXCEEDED
		_: return APIError.NETWORK_ERROR