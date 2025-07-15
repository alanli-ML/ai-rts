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
var last_request_time: float = 0.0

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
signal request_failed(error: APIError, message: String)
signal rate_limit_exceeded()

func _ready() -> void:
	# Create HTTP request node
	http_request = HTTPRequest.new()
	http_request.name = "HTTPRequest"
	http_request.timeout = 30.0
	add_child(http_request)
	
	# Connect signals
	http_request.request_completed.connect(_on_request_completed)
	
	# Load API key from environment or config
	_load_api_key()
	
	print("OpenAI client initialized")

func _load_api_key() -> void:
	# Try to load from environment variable first
	if OS.has_environment("OPENAI_API_KEY"):
		api_key = OS.get_environment("OPENAI_API_KEY")
		print("API key loaded from environment")
		return
	
	# Try to load from .env file
	var env_file_path = "res://.env"
	if FileAccess.file_exists(env_file_path):
		var file = FileAccess.open(env_file_path, FileAccess.READ)
		if file:
			while not file.eof_reached():
				var line = file.get_line().strip_edges()
				if line.begins_with("OPENAI_API_KEY="):
					api_key = line.split("=", false, 1)[1].strip_edges()
					# Remove quotes if present
					if api_key.begins_with('"') and api_key.ends_with('"'):
						api_key = api_key.substr(1, api_key.length() - 2)
					elif api_key.begins_with("'") and api_key.ends_with("'"):
						api_key = api_key.substr(1, api_key.length() - 2)
					print("API key loaded from .env file")
					file.close()
					return
			file.close()
	
	# Also try user://env file for user-specific settings
	var user_env_path = "user://.env"
	if FileAccess.file_exists(user_env_path):
		var file = FileAccess.open(user_env_path, FileAccess.READ)
		if file:
			while not file.eof_reached():
				var line = file.get_line().strip_edges()
				if line.begins_with("OPENAI_API_KEY="):
					api_key = line.split("=", false, 1)[1].strip_edges()
					# Remove quotes if present
					if api_key.begins_with('"') and api_key.ends_with('"'):
						api_key = api_key.substr(1, api_key.length() - 2)
					elif api_key.begins_with("'") and api_key.ends_with("'"):
						api_key = api_key.substr(1, api_key.length() - 2)
					print("API key loaded from user://.env file")
					file.close()
					return
			file.close()
	
	print("No API key found. Checked environment variable, .env file, and user://.env file")
	print("Please set OPENAI_API_KEY in one of these locations:")
	print("  1. Environment variable: export OPENAI_API_KEY='your-key'")
	print("  2. .env file in project root: OPENAI_API_KEY=your-key")
	print("  3. user://.env file: OPENAI_API_KEY=your-key")
	
	# For testing purposes, use a placeholder key
	api_key = "sk-test-key-for-development"
	print("Using placeholder API key for testing")

func send_chat_completion(messages: Array, callback: Callable) -> void:
	"""
	Send a chat completion request to OpenAI API
	
	Args:
		messages: Array of message dictionaries with 'role' and 'content'
		callback: Function to call when request completes
	"""
	if api_key.is_empty():
		print("API key not configured")
		request_failed.emit(APIError.INVALID_API_KEY, "API key not configured")
		return
	
	if not _check_rate_limit():
		print("Rate limit exceeded")
		rate_limit_exceeded.emit()
		return
	
	# Create request data
	var request_data = {
		"model": model,
		"messages": messages,
		"max_tokens": max_tokens,
		"temperature": temperature
	}
	
	# Queue the request
	var request_info = {
		"url": base_url + "/chat/completions",
		"data": request_data,
		"callback": callback,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	
	request_queue.append(request_info)
	_process_queue()

func _check_rate_limit() -> bool:
	"""Check if we're within rate limits"""
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Remove old timestamps (older than 1 minute)
	request_timestamps = request_timestamps.filter(func(timestamp): return current_time - timestamp < 60.0)
	
	# Check requests per minute
	if request_timestamps.size() >= requests_per_minute:
		return false
	
	# Check concurrent requests
	if active_requests >= max_concurrent_requests:
		return false
	
	return true

func _process_queue() -> void:
	"""Process queued requests"""
	if request_queue.is_empty() or active_requests >= max_concurrent_requests:
		return
	
	# Check if HTTP request is currently busy
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return  # Wait for current request to complete
	
	var request_info = request_queue.pop_front()
	_send_request(request_info)

func _send_request(request_info: Dictionary) -> void:
	"""Send an HTTP request to OpenAI API"""
	active_requests += 1
	request_timestamps.append(Time.get_ticks_msec() / 1000.0)
	
	# Prepare headers
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	# Convert data to JSON
	var json_data = JSON.stringify(request_info.data)
	
	# Store callback for response handling
	http_request.set_meta("callback", request_info.callback)
	http_request.set_meta("request_time", request_info.timestamp)
	
	# Send request
	var error = http_request.request(request_info.url, headers, HTTPClient.METHOD_POST, json_data)
	
	if error != OK:
		print("Failed to send request: " + str(error))
		active_requests -= 1
		request_failed.emit(APIError.NETWORK_ERROR, "Failed to send request")
		return
	
	print("Request sent to OpenAI API")

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle completed HTTP request"""
	active_requests -= 1
	
	# Get callback from metadata
	var callback = http_request.get_meta("callback") as Callable
	var request_time = http_request.get_meta("request_time") as float
	
	# Calculate response time
	var response_time = (Time.get_ticks_msec() / 1000.0) - request_time
	print("Request completed in " + str(response_time) + "s")
	
	# Handle HTTP errors
	if response_code != 200:
		var error_type = _get_error_type(response_code)
		var error_message = "HTTP " + str(response_code)
		
		if body.size() > 0:
			var json = JSON.new()
			var parse_result = json.parse(body.get_string_from_utf8())
			if parse_result == OK:
				var error_data = json.data
				if error_data.has("error"):
					error_message = error_data.error.get("message", error_message)
		
		print("Request failed: " + error_message)
		request_failed.emit(error_type, error_message)
		
		# Don't call callback on error - let signal handle it
		_process_queue()
		return
	
	# Parse response
	if body.size() == 0:
		print("Empty response body")
		request_failed.emit(APIError.UNKNOWN_ERROR, "Empty response")
		# Don't call callback on error - let signal handle it
		_process_queue()
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		print("Failed to parse JSON response")
		request_failed.emit(APIError.UNKNOWN_ERROR, "Invalid JSON response")
		# Don't call callback on error - let signal handle it
		_process_queue()
		return
	
	var response_data = json.data
	print("Request successful")
	
	# Emit success signal
	request_completed.emit(response_data)
	
	# Call callback with only response data (matching expected signature)
	if callback.is_valid():
		callback.call(response_data)
	
	# Process next request in queue
	_process_queue()

func _get_error_type(response_code: int) -> APIError:
	"""Convert HTTP response code to API error type"""
	match response_code:
		401:
			return APIError.INVALID_API_KEY
		429:
			return APIError.RATE_LIMITED
		402:
			return APIError.QUOTA_EXCEEDED
		_:
			return APIError.NETWORK_ERROR

func get_usage_info() -> Dictionary:
	"""Get current usage statistics"""
	return {
		"active_requests": active_requests,
		"queued_requests": request_queue.size(),
		"requests_last_minute": request_timestamps.size(),
		"rate_limit": requests_per_minute
	}

func clear_queue() -> void:
	"""Clear all queued requests"""
	request_queue.clear()
	print("Request queue cleared") 