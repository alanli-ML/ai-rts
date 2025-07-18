# OpenAIClient.gd
class_name OpenAIClient
extends Node

# OpenAI API configuration
@export var api_key: String = ""
@export var base_url: String = "https://api.openai.com/v1"
@export var model: String = "gpt-4o-mini"
@export var max_tokens: int = 16384
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
	http_request.timeout = 60.0
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

func send_chat_completion(messages: Array, callback: Callable, response_format: Dictionary = {}) -> void:
	if api_key.is_empty():
		request_failed.emit(APIError.INVALID_API_KEY, "API key not configured")
		return
	
	if not _check_rate_limit():
		rate_limit_exceeded.emit()
		return
	
	var request_data = {
		"model": model,
		"messages": messages
		#"max_tokens": max_tokens,
		#"temperature": temperature
	}
	
	# Add structured outputs support
	if not response_format.is_empty():
		request_data["response_format"] = response_format
	
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
	var request_start_time = Time.get_ticks_msec() / 1000.0
	request_timestamps.append(request_start_time)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	var json_data = JSON.stringify(request_info.data)
	http_request.set_meta("callback", request_info.callback)
	http_request.set_meta("start_time", request_start_time)
	
	print("OpenAI: Sending HTTP request at %f" % request_start_time)
	var error = http_request.request(request_info.url, headers, HTTPClient.METHOD_POST, json_data)
	if error != OK:
		active_requests -= 1
		
		# Call the callback with error response to prevent timeout
		var callback = request_info.callback as Callable
		if callback.is_valid():
			var error_response = {
				"error": {
					"type": "network_error", 
					"message": "Failed to send HTTP request (error code: %d)" % error,
					"code": error
				}
			}
			callback.call(error_response)
		
		request_failed.emit(APIError.NETWORK_ERROR, "Failed to send request")
		_process_queue()

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var end_time = Time.get_ticks_msec() / 1000.0
	var start_time = http_request.get_meta("start_time", 0.0)
	var duration = end_time - start_time if start_time > 0 else 0.0
	
	print("=== OpenAI HTTP Response ===")
	print("Result code: %d" % result)
	print("Response code: %d" % response_code) 
	print("Duration: %.2f seconds" % duration)
	print("Headers: %s" % headers)
	
	active_requests -= 1
	var callback = http_request.get_meta("callback") as Callable
	
	var response_text = body.get_string_from_utf8()
	print("Response body length: %d" % response_text.length())
	if response_text.length() > 0:
		print("Response preview: %s..." % response_text.substr(0, min(200, response_text.length())))
	
	if result != HTTPRequest.RESULT_SUCCESS:
		print("ERROR: HTTP request failed with result: %d" % result)
		var error_type = APIError.NETWORK_ERROR
		var error_message = _get_error_message_from_result(result)
		
		# Call the callback with error response to prevent timeout
		if callback.is_valid():
			var error_response = {
				"error": {
					"type": "network_error",
					"message": error_message,
					"code": result
				}
			}
			callback.call(error_response)
		
		request_failed.emit(error_type, error_message)
		_process_queue()
		return
	
	if response_code < 200 or response_code >= 300:
		print("ERROR: HTTP response code indicates failure: %d" % response_code)
		var error_type = _get_error_type_from_code(response_code)
		var error_message = "HTTP error %d: %s" % [response_code, response_text]
		request_failed.emit(error_type, error_message)
		_process_queue()
		return
	
	if response_text.is_empty():
		print("ERROR: Empty response body")
		request_failed.emit(APIError.UNKNOWN_ERROR, "Empty response from API")
		_process_queue()
		return
	
	print("SUCCESS: Parsing JSON response...")
	var json = JSON.new()
	var parse_result = json.parse(response_text)
	if parse_result != OK:
		print("ERROR: JSON parsing failed: %s" % json.get_error_message())
		request_failed.emit(APIError.UNKNOWN_ERROR, "Invalid JSON response")
		_process_queue()
		return
	
	var response_data = json.data
	print("SUCCESS: JSON parsed, checking for refusal...")
	
	# Check for refusal in structured outputs
	if response_data.has("choices") and response_data.choices.size() > 0:
		var choice = response_data.choices[0]
		if choice.has("message") and choice.message.has("refusal") and choice.message.refusal != null:
			print("WARNING: Model refused to respond: %s" % choice.message.refusal)
			request_failed.emit(APIError.UNKNOWN_ERROR, "Model refusal: " + str(choice.message.refusal))
			_process_queue()
			return
	
	print("SUCCESS: No refusal, calling callback...")
	
	if callback.is_valid():
		print("Calling response callback...")
		callback.call(response_data)
		print("Callback completed")
	else:
		print("ERROR: Callback is not valid!")
	
	request_completed.emit(response_data)
	_process_queue()

func _get_error_type_from_code(code: int) -> APIError:
	match code:
		401: return APIError.INVALID_API_KEY
		429: return APIError.RATE_LIMITED  
		403: return APIError.QUOTA_EXCEEDED
		_: return APIError.UNKNOWN_ERROR

func _get_error_message_from_result(result_code: int) -> String:
	"""Convert HTTP result codes to user-friendly error messages"""
	match result_code:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "Network error: Data transfer incomplete"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Network error: Cannot connect to OpenAI API (check internet connection)"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Network error: Cannot resolve api.openai.com (DNS issue)"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Network error: Connection failed"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Network error: SSL/TLS handshake failed"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Network error: No response from OpenAI API"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Network error: Response too large"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "Network error: Failed to decompress response"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Network error: Request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "Network error: Cannot open download file"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Network error: Cannot write download file"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "Network error: Too many redirects"
		HTTPRequest.RESULT_TIMEOUT:
			return "Network error: Request timeout (API may be overloaded)"
		13: # ERR_UNAVAILABLE
			return "Network error: OpenAI API temporarily unavailable (check service status at status.openai.com)"
		_:
			return "Network error: HTTP request failed with code %d" % result_code