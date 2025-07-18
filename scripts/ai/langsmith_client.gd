# LangSmithClient.gd
class_name LangSmithClient
extends Node

# LangSmith configuration
@export var api_key: String = ""
@export var base_url: String = "https://api.smith.langchain.com"
@export var project_name: String = "ai-rts-game"
@export var session_name: String = ""

# Tracing configuration
@export var enable_tracing: bool = true
@export var log_inputs: bool = true
@export var log_outputs: bool = true
@export var log_metadata: bool = true

# Internal variables
var http_request: HTTPRequest = null
var openai_client: OpenAIClient = null
var active_traces: Dictionary = {}
var trace_id_counter: int = 0

# Trace data structure
class TraceData:
	var trace_id: String
	var run_id: String
	var parent_run_id: String = ""
	var name: String
	var run_type: String = "llm"
	var start_time: float
	var end_time: float = 0.0
	var inputs: Dictionary = {}
	var outputs: Dictionary = {}
	var metadata: Dictionary = {}
	var error: String = ""
	var tags: Array = []
	
	func _init(id: String, trace_name: String):
		trace_id = id
		run_id = id
		name = trace_name
		start_time = Time.get_unix_time_from_system()

# Signals
signal trace_started(trace_id: String)
signal trace_completed(trace_id: String, success: bool)
signal trace_failed(trace_id: String, error: String)

func _ready() -> void:
	# Create HTTP request node for LangSmith API
	http_request = HTTPRequest.new()
	http_request.name = "LangSmithHTTPRequest"
	http_request.timeout = 60.0
	add_child(http_request)
	
	# Connect signals
	http_request.request_completed.connect(_on_langsmith_request_completed)
	
	# Load configuration
	_load_config()

func _load_config() -> void:
	"""Load LangSmith configuration from environment or config files"""
	
	# Try to load from environment variables first
	_load_from_environment()
	
	# Try to load from .env files
	var env_paths = [
		"res://.env",
		"user://.env"
	]
	
	for path in env_paths:
		if FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				_parse_env_file(file, path)
				file.close()
				break
	
	# Validate configuration
	if api_key.is_empty():
		print("LangSmith: API key not found - tracing disabled")
		enable_tracing = false
	else:
		print("LangSmith: Configured for project '%s' - tracing %s" % [project_name, "enabled" if enable_tracing else "disabled"])

func _load_from_environment() -> void:
	"""Load configuration from environment variables"""
	if OS.has_environment("LANGSMITH_API_KEY"):
		api_key = OS.get_environment("LANGSMITH_API_KEY")
	elif OS.has_environment("LANGCHAIN_API_KEY"):
		api_key = OS.get_environment("LANGCHAIN_API_KEY")
	
	if OS.has_environment("LANGSMITH_PROJECT"):
		project_name = OS.get_environment("LANGSMITH_PROJECT")
	elif OS.has_environment("LANGSMITH_PROJECT_NAME"):
		project_name = OS.get_environment("LANGSMITH_PROJECT_NAME")
	
	if OS.has_environment("LANGSMITH_SESSION_NAME"):
		session_name = OS.get_environment("LANGSMITH_SESSION_NAME")
	
	if OS.has_environment("LANGSMITH_TRACING"):
		var tracing_value = OS.get_environment("LANGSMITH_TRACING").to_lower()
		enable_tracing = tracing_value == "true" or tracing_value == "1"
	elif OS.has_environment("LANGSMITH_ENABLE_TRACING"):
		var tracing_value = OS.get_environment("LANGSMITH_ENABLE_TRACING").to_lower()
		enable_tracing = tracing_value == "true" or tracing_value == "1"
	
	if OS.has_environment("LANGSMITH_ENDPOINT"):
		base_url = OS.get_environment("LANGSMITH_ENDPOINT")
	elif OS.has_environment("LANGSMITH_BASE_URL"):
		base_url = OS.get_environment("LANGSMITH_BASE_URL")

func _parse_env_file(file: FileAccess, file_path: String) -> void:
	"""Parse .env file and extract LangSmith configuration"""
	var config_found = {}
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		
		# Skip empty lines and comments
		if line.is_empty() or line.begins_with("#"):
			continue
		
		# Parse key=value pairs
		if "=" in line:
			var parts = line.split("=", false, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges()
				var value = parts[1].strip_edges()
				
				# Remove quotes if present
				if (value.begins_with("\"") and value.ends_with("\"")) or (value.begins_with("'") and value.ends_with("'")):
					value = value.substr(1, value.length() - 2)
				
				# Load LangSmith-specific configuration
				match key:
					"LANGSMITH_API_KEY":
						if api_key.is_empty():  # Don't override environment variable
							api_key = value
							config_found["api_key"] = true
					"LANGCHAIN_API_KEY":
						if api_key.is_empty():  # Don't override environment variable
							api_key = value
							config_found["api_key"] = true
					"LANGSMITH_PROJECT":
						project_name = value
						config_found["project_name"] = true
					"LANGSMITH_PROJECT_NAME":
						project_name = value
						config_found["project_name"] = true
					"LANGSMITH_SESSION_NAME":
						session_name = value
						config_found["session_name"] = true
					"LANGSMITH_TRACING":
						var tracing_value = value.to_lower()
						enable_tracing = tracing_value == "true" or tracing_value == "1"
						config_found["enable_tracing"] = true
					"LANGSMITH_ENABLE_TRACING":
						var tracing_value = value.to_lower()
						enable_tracing = tracing_value == "true" or tracing_value == "1"
						config_found["enable_tracing"] = true
					"LANGSMITH_ENDPOINT":
						base_url = value
						config_found["base_url"] = true
					"LANGSMITH_BASE_URL":
						base_url = value
						config_found["base_url"] = true

func setup_openai_client(client: OpenAIClient) -> void:
	"""Setup the OpenAI client to wrap with LangSmith tracing"""
	openai_client = client

func traced_chat_completion(messages: Array, callback: Callable, error_callback: Callable = Callable(), metadata: Dictionary = {}, model: String = "", response_format: Dictionary = {}) -> String:
	"""
	Send a traced chat completion request
	
	Args:
		messages: Array of message dictionaries
		callback: Original callback function
		error_callback: Error callback function
		metadata: Additional metadata for tracing
		model: Optional model override (uses OpenAI client default if empty)
		
	Returns:
		String: Trace ID for this request
	"""
	var trace_id = _generate_trace_id()
	
	# Determine which model to use
	var model_to_use = model if not model.is_empty() else (openai_client.model if openai_client else "gpt-4o")
	
	# Check if HTTP request is busy or tracing is disabled
	if not enable_tracing or api_key.is_empty() or (http_request and http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED):
		# Fallback to direct OpenAI call without tracing
		if http_request and http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			print("LangSmith: HTTP request busy, bypassing tracing for this request")
		if openai_client:
			_send_with_model_override(messages, callback, model_to_use, response_format)
		return trace_id
	
	# Create trace data with enhanced title
	var trace_title = "chat_completion"
	if metadata.has("source"):
		trace_title = "chat_completion_%s" % metadata["source"]
	
	var trace = TraceData.new(trace_id, trace_title)
	trace.inputs = {
		"messages": messages,
		"model": model_to_use,
		"temperature": openai_client.temperature if openai_client else 0.7,
		"max_tokens": openai_client.max_tokens if openai_client else 500
	}
	trace.metadata = metadata.duplicate()
	trace.metadata["project"] = project_name
	trace.metadata["session"] = session_name
	trace.tags = ["ai-rts", "game-ai", "chat-completion"]
	
	active_traces[trace_id] = trace
	
	# Start the trace
	_start_trace(trace)
	
	# Create wrapped callback
	var wrapped_callback = func(response: Dictionary):
		_complete_trace(trace_id, response, "")
		callback.call(response)
	
	var wrapped_error_callback = func(error_type: OpenAIClient.APIError, error_message: String):
		_complete_trace(trace_id, {}, error_message)
		# Call original error handling if available
		if error_callback.is_valid():
			error_callback.call(error_type, error_message)
	
	# Send request with wrapped callbacks
	if openai_client:
		# Connect to OpenAI client signals for this request
		if not openai_client.request_failed.is_connected(wrapped_error_callback):
			openai_client.request_failed.connect(wrapped_error_callback, CONNECT_ONE_SHOT)
		
		_send_with_model_override(messages, wrapped_callback, model_to_use, response_format)
	
	trace_started.emit(trace_id)
	return trace_id

func _generate_uuid() -> String:
	"""Generate a proper UUID for LangSmith compatibility"""
	var uuid_template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	var result = ""
	for i in range(uuid_template.length()):
		var c = uuid_template[i]
		if c == "x":
			result += "%x" % (randi() % 16)
		elif c == "y":
			result += "%x" % ((randi() % 4) + 8)  # y must be 8, 9, A, or B
		else:
			result += c
	return result

func _generate_trace_id() -> String:
	"""Generate a unique trace ID for internal tracking"""
	trace_id_counter += 1
	var timestamp = Time.get_ticks_msec()
	return "trace_%d_%d" % [timestamp, trace_id_counter]

func _start_trace(trace: TraceData) -> void:
	"""Start a new trace in LangSmith"""
	if not enable_tracing or api_key.is_empty():
		return
	
	# Generate proper UUID for the run ID
	var uuid = _generate_uuid()
	trace.run_id = uuid
	
	var trace_data = {
		"id": uuid,
		"name": trace.name,
		"run_type": trace.run_type,
		"start_time": _format_timestamp(trace.start_time),
		"inputs": trace.inputs if log_inputs else {},
		"session_name": project_name,  # This is the correct field for project association
		"tags": trace.tags
	}
	
	# Add metadata as extra field if enabled
	if log_metadata and not trace.metadata.is_empty():
		trace_data["extra"] = trace.metadata
	
	_send_to_langsmith("/runs", trace_data, "POST")

func _complete_trace(trace_id: String, response: Dictionary, error: String = "") -> void:
	"""Complete a trace with response data"""
	if not active_traces.has(trace_id):
		return
	
	var trace = active_traces[trace_id] as TraceData
	trace.end_time = Time.get_unix_time_from_system()
	trace.error = error
	
	if error.is_empty():
		trace.outputs = response if log_outputs else {"success": true}
	else:
		trace.outputs = {"error": error}
	
	# Calculate metrics
	var duration = trace.end_time - trace.start_time
	trace.metadata["duration_seconds"] = duration
	trace.metadata["success"] = error.is_empty()
	
	# Extract token usage if available
	if response.has("usage"):
		trace.metadata["token_usage"] = response.usage
		trace.metadata["prompt_tokens"] = response.usage.get("prompt_tokens", 0)
		trace.metadata["completion_tokens"] = response.usage.get("completion_tokens", 0)
		trace.metadata["total_tokens"] = response.usage.get("total_tokens", 0)
	
	# Extract model response if available
	if response.has("choices") and response.choices.size() > 0:
		var choice = response.choices[0]
		if choice.has("message"):
			trace.outputs["response_message"] = choice.message
	
	# Send completion to LangSmith
	if enable_tracing and not api_key.is_empty():
		_update_trace_completion(trace)
	
	# Emit completion signal
	trace_completed.emit(trace_id, error.is_empty())
	
	# Clean up
	active_traces.erase(trace_id)

func _update_trace_completion(trace: TraceData) -> void:
	"""Update trace completion in LangSmith"""
	var update_data = {
		"end_time": _format_timestamp(trace.end_time),
		"outputs": trace.outputs,
		"error": trace.error
	}
	
	if log_metadata:
		update_data["extra"] = trace.metadata
	
	_send_to_langsmith("/runs/" + trace.run_id, update_data, "PATCH")

func _send_to_langsmith(endpoint: String, data: Dictionary, method: String = "POST") -> void:
	"""Send data to LangSmith API"""
	if not enable_tracing or api_key.is_empty():
		return
	
	# Check if HTTP request is already busy
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		print("LangSmith: HTTP request is busy, skipping trace upload")
		return
	
	# Prepare headers
	var headers = [
		"Content-Type: application/json",
		"x-api-key: " + api_key
	]
	
	# Convert data to JSON
	var json_data = JSON.stringify(data)
	
	# Send request
	var http_method = HTTPClient.METHOD_POST
	
	match method:
		"POST":
			http_method = HTTPClient.METHOD_POST
		"PATCH":
			http_method = HTTPClient.METHOD_PATCH
		"PUT":
			http_method = HTTPClient.METHOD_PUT
	
	var url = base_url + endpoint
	var error = http_request.request(url, headers, http_method, json_data)
	
	if error != OK:
		print("LangSmith: Failed to send request: %s" % str(error))

func _on_langsmith_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle LangSmith API responses"""
	var response_text = body.get_string_from_utf8()
	
	if response_code >= 200 and response_code < 300:
		# Success - no logging needed for normal operation
		pass
	else:
		print("LangSmith: API error %d: %s" % [response_code, response_text])

func _format_timestamp(timestamp: float) -> String:
	"""Format timestamp for LangSmith API"""
	var datetime = Time.get_datetime_dict_from_unix_time(int(timestamp))
	return "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second,
		int((timestamp - int(timestamp)) * 1000)
	]

# Utility functions for enhanced observability
func add_trace_metadata(trace_id: String, key: String, value) -> void:
	"""Add metadata to an active trace"""
	if active_traces.has(trace_id):
		var trace = active_traces[trace_id] as TraceData
		trace.metadata[key] = value

func add_trace_tag(trace_id: String, tag: String) -> void:
	"""Add a tag to an active trace"""
	if active_traces.has(trace_id):
		var trace = active_traces[trace_id] as TraceData
		if not trace.tags.has(tag):
			trace.tags.append(tag)

func get_trace_status(trace_id: String) -> Dictionary:
	"""Get the current status of a trace"""
	if not active_traces.has(trace_id):
		return {"exists": false}
	
	var trace = active_traces[trace_id] as TraceData
	return {
		"exists": true,
		"trace_id": trace.trace_id,
		"name": trace.name,
		"start_time": trace.start_time,
		"duration": (Time.get_ticks_msec() / 1000.0) - trace.start_time,
		"metadata": trace.metadata.duplicate()
	}

func set_session_name(session: String) -> void:
	"""Set the session name for grouping traces"""
	session_name = session

func _send_with_model_override(messages: Array, callback: Callable, model_override: String, response_format: Dictionary = {}) -> void:
	"""Send chat completion request with temporary model override"""
	if not openai_client:
		return
	
	# Store original model
	var original_model = openai_client.model
	
	# Set override model temporarily
	openai_client.model = model_override
	
	# Create a callback wrapper to restore original model
	var restore_callback = func(response: Dictionary):
		# Restore original model
		openai_client.model = original_model
		# Call original callback
		callback.call(response)
	
	# Send request with override model and response format
	openai_client.send_chat_completion(messages, restore_callback, response_format)

func flush_traces() -> void:
	"""Force completion of any pending traces (for cleanup)"""
	for trace_id in active_traces.keys():
		_complete_trace(trace_id, {}, "trace_flushed") 