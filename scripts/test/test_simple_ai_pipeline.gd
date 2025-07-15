# TestSimpleAIPipeline.gd
# Basic test for the AI control pipeline: User Input → OpenAI API → Command Processing
extends Node

# Test components
var openai_client = null
var test_results: Dictionary = {}

# Test scenarios
var test_scenarios: Array = [
	{
		"name": "Basic Movement Command",
		"user_prompt": "Move the selected units to the strategic position",
		"expected_keywords": ["move", "position", "units"]
	},
	{
		"name": "Attack Command", 
		"user_prompt": "Attack the enemy with selected scouts",
		"expected_keywords": ["attack", "enemy", "scouts"]
	},
	{
		"name": "Formation Command",
		"user_prompt": "Arrange units in defensive formation",
		"expected_keywords": ["formation", "defensive", "units"]
	}
]

func _ready() -> void:
	print("=== SIMPLE AI PIPELINE TEST INITIALIZING ===")
	
	# Wait for scene to be ready
	await get_tree().process_frame
	
	# Initialize OpenAI client
	await _initialize_openai_client()
	
	# Display test controls
	_print_test_controls()
	
	print("=== SIMPLE AI PIPELINE TEST READY ===")

func _initialize_openai_client() -> void:
	"""Initialize OpenAI client directly"""
	print("Initializing OpenAI client...")
	
	# Load OpenAI client class
	var OpenAIClientClass = preload("res://scripts/ai/openai_client.gd")
	openai_client = OpenAIClientClass.new()
	openai_client.name = "OpenAIClient"
	add_child(openai_client)
	
	# Connect signals
	openai_client.request_completed.connect(_on_openai_response)
	openai_client.request_failed.connect(_on_openai_error)
	
	print("OpenAI client initialized")

func _input(event: InputEvent) -> void:
	"""Handle input for testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				start_pipeline_test()
			KEY_1:
				test_individual_scenario(0)
			KEY_2:
				test_individual_scenario(1)
			KEY_3:
				test_individual_scenario(2)
			KEY_A:
				test_openai_api_directly()
			KEY_R:
				check_system_readiness()
			KEY_S:
				show_test_statistics()
			KEY_C:
				clear_test_results()
			KEY_H:
				_print_test_controls()

func start_pipeline_test() -> void:
	"""Start the complete pipeline test"""
	print("\n=== STARTING SIMPLE AI PIPELINE TEST ===")
	
	if not check_system_readiness():
		print("ERROR: System not ready for testing!")
		return
	
	test_results.clear()
	
	await _run_all_scenarios()
	
	_display_final_results()

func _run_all_scenarios() -> void:
	"""Run all test scenarios"""
	for i in range(test_scenarios.size()):
		var scenario = test_scenarios[i]
		print("\n--- Testing Scenario %d: %s ---" % [i + 1, scenario.name])
		
		var result = await _test_scenario(scenario)
		test_results[scenario.name] = result
		
		# Wait between tests
		await get_tree().create_timer(2.0).timeout

func test_individual_scenario(index: int) -> void:
	"""Test an individual scenario"""
	if index < 0 or index >= test_scenarios.size():
		print("Invalid scenario index: %d" % index)
		return
	
	var scenario = test_scenarios[index]
	print("\n--- Testing Individual Scenario: %s ---" % scenario.name)
	
	if not check_system_readiness():
		print("ERROR: System not ready for testing!")
		return
	
	var result = await _test_scenario(scenario)
	print("Individual test result: %s" % ("SUCCESS" if result.success else "FAILED"))

func _test_scenario(scenario: Dictionary) -> Dictionary:
	"""Test a single scenario through the AI pipeline"""
	var start_time = Time.get_ticks_msec()
	var result = {
		"success": false,
		"scenario": scenario.name,
		"user_prompt": scenario.user_prompt,
		"ai_response": null,
		"execution_time": 0,
		"errors": []
	}
	
	print("Testing: %s" % scenario.user_prompt)
	
	# Create a realistic RTS command prompt
	var system_prompt = """
You are an AI assistant for a Real-Time Strategy (RTS) game. 
Convert natural language commands into structured JSON responses.

Respond with a JSON object containing:
- "type": "command" 
- "action": the main action (move, attack, formation, etc.)
- "units": type of units involved
- "parameters": relevant parameters
- "message": confirmation message

Example:
{"type": "command", "action": "move", "units": "selected", "parameters": {"position": "strategic"}, "message": "Moving units to strategic position"}
"""
	
	# Send command to OpenAI
	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": scenario.user_prompt}
	]
	
	var ai_response = await _send_openai_request(messages)
	
	if not ai_response:
		result.errors.append("AI command processing failed")
		return result
	
	result.ai_response = ai_response
	
	# Validate response
	if _validate_ai_response(ai_response, scenario):
		result.success = true
		result.execution_time = Time.get_ticks_msec() - start_time
		print("Scenario completed successfully in %d ms" % result.execution_time)
	else:
		result.errors.append("AI response validation failed")
	
	return result

func _send_openai_request(messages: Array) -> Dictionary:
	"""Send request to OpenAI and wait for response"""
	var response_data = null
	var response_received = false
	var error_occurred = false
	
	# Setup response handler
	var response_handler = func(response: Dictionary):
		response_data = response
		response_received = true
	
	var error_handler = func(error_type, error_message: String):
		print("OpenAI API Error: %s" % error_message)
		error_occurred = true
		response_received = true
	
	# Connect signals temporarily
	if not openai_client.request_completed.is_connected(response_handler):
		openai_client.request_completed.connect(response_handler, CONNECT_ONE_SHOT)
	if not openai_client.request_failed.is_connected(error_handler):
		openai_client.request_failed.connect(error_handler, CONNECT_ONE_SHOT)
	
	# Send request
	openai_client.send_chat_completion(messages, func(response, error_type, error_message): pass)
	
	# Wait for response with timeout
	var timeout = 30.0
	var elapsed = 0.0
	var check_interval = 0.1
	
	while not response_received and elapsed < timeout:
		await get_tree().create_timer(check_interval).timeout
		elapsed += check_interval
	
	if error_occurred or not response_received:
		return {}
	
	return response_data

func _validate_ai_response(response: Dictionary, scenario: Dictionary) -> bool:
	"""Validate the AI response"""
	if response.is_empty():
		print("Empty response from AI")
		return false
	
	# Extract content from OpenAI response
	var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
	
	if content.is_empty():
		print("No content in AI response")
		return false
	
	print("AI Response Content: %s" % content)
	
	# Try to parse as JSON
	var json = JSON.new()
	var parse_result = json.parse(content)
	
	if parse_result != OK:
		print("Response is not valid JSON, checking for keywords...")
		# Fallback: check for expected keywords
		return _check_keywords_in_response(content, scenario.expected_keywords)
	
	var ai_data = json.data
	
	# Validate JSON structure
	if not ai_data.has("type") or not ai_data.has("action"):
		print("Missing required fields in AI response")
		return false
	
	# Check if response matches expected action
	var action = ai_data.get("action", "").to_lower()
	var expected_keywords = scenario.get("expected_keywords", [])
	
	for keyword in expected_keywords:
		if keyword.to_lower() in action or keyword.to_lower() in content.to_lower():
			print("Found expected keyword: %s" % keyword)
			return true
	
	print("No expected keywords found in response")
	return false

func _check_keywords_in_response(content: String, expected_keywords: Array) -> bool:
	"""Check if expected keywords are present in response"""
	var content_lower = content.to_lower()
	var found_keywords = []
	
	for keyword in expected_keywords:
		if keyword.to_lower() in content_lower:
			found_keywords.append(keyword)
	
	print("Found keywords: %s" % str(found_keywords))
	return found_keywords.size() > 0

func test_openai_api_directly() -> void:
	"""Test OpenAI API directly"""
	print("\n=== TESTING OPENAI API DIRECTLY ===")
	
	if not openai_client:
		print("ERROR: OpenAI client not available")
		return
	
	# Simple connectivity test
	var test_messages = [
		{
			"role": "system", 
			"content": "You are a helpful assistant. Respond with exactly 'API test successful' if you receive this message."
		},
		{
			"role": "user",
			"content": "Please confirm API connectivity"
		}
	]
	
	var response = await _send_openai_request(test_messages)
	
	if not response.is_empty():
		var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
		print("OpenAI API Response: %s" % content)
		
		if "API test successful" in content or "successful" in content.to_lower():
			print("✓ OpenAI API connectivity test PASSED")
		else:
			print("✓ OpenAI API responding (content: %s)" % content)
	else:
		print("✗ OpenAI API test FAILED")

func check_system_readiness() -> bool:
	"""Check if system is ready for testing"""
	print("\n=== SYSTEM READINESS CHECK ===")
	
	var ready = true
	var checks = []
	
	# Check OpenAI client
	checks.append({"name": "OpenAI Client", "ready": openai_client != null})
	
	# Check API key
	var api_key_set = false
	if openai_client:
		api_key_set = openai_client.api_key != "" and openai_client.api_key != "sk-test-key-for-development"
	checks.append({"name": "OpenAI API Key", "ready": api_key_set})
	
	# Display results
	for check in checks:
		var status = "✓" if check.ready else "✗"
		print("  %s %s" % [status, check.name])
		if not check.ready:
			ready = false
	
	print("\nOverall system status: %s" % ("READY" if ready else "NOT READY"))
	
	if not ready:
		print("\nTo fix:")
		if not api_key_set:
			print("  - Set OPENAI_API_KEY environment variable")
			print("  - Example: export OPENAI_API_KEY='your-key-here'")
	
	return ready

func _display_final_results() -> void:
	"""Display final test results"""
	print("\n=== SIMPLE AI PIPELINE TEST RESULTS ===")
	
	var total_tests = test_results.size()
	var successful_tests = 0
	
	for scenario_name in test_results:
		var result = test_results[scenario_name]
		var status = "SUCCESS" if result.success else "FAILED"
		print("  %s: %s" % [scenario_name, status])
		
		if result.success:
			successful_tests += 1
			print("    Execution time: %d ms" % result.execution_time)
		else:
			print("    Errors: %s" % str(result.errors))
	
	var success_rate = float(successful_tests) / float(total_tests) * 100.0 if total_tests > 0 else 0.0
	print("\nOverall Success Rate: %.1f%% (%d/%d)" % [success_rate, successful_tests, total_tests])
	
	if success_rate >= 80.0:
		print("🎉 AI PIPELINE TEST PASSED!")
	elif success_rate >= 50.0:
		print("⚠️  AI PIPELINE PARTIALLY WORKING")
	else:
		print("❌ AI PIPELINE NEEDS IMPROVEMENT")

func show_test_statistics() -> void:
	"""Show test statistics"""
	print("\n=== AI PIPELINE TEST STATISTICS ===")
	
	if test_results.is_empty():
		print("No test results available. Run tests first.")
		return
	
	var total_execution_time = 0
	var error_count = 0
	
	for scenario_name in test_results:
		var result = test_results[scenario_name]
		total_execution_time += result.execution_time
		error_count += result.errors.size()
	
	print("Total tests: %d" % test_results.size())
	print("Total execution time: %d ms" % total_execution_time)
	print("Average execution time: %.1f ms" % (total_execution_time / float(test_results.size())))
	print("Total errors: %d" % error_count)

func clear_test_results() -> void:
	"""Clear all test results"""
	test_results.clear()
	print("Test results cleared")

func _print_test_controls() -> void:
	"""Print available test controls"""
	print("\n=== SIMPLE AI PIPELINE TEST CONTROLS ===")
	print("  SPACE - Run complete pipeline test")
	print("  1-3   - Test individual scenarios")
	print("  A     - Test OpenAI API directly")
	print("  R     - Check system readiness")
	print("  S     - Show test statistics")
	print("  C     - Clear test results")
	print("  H     - Show this help")
	print("\nTest Scenarios:")
	for i in range(test_scenarios.size()):
		print("  %d. %s" % [i + 1, test_scenarios[i].name])
	print("\nIMPORTANT: Set OPENAI_API_KEY environment variable before testing!")

# Signal handlers
func _on_openai_response(response: Dictionary) -> void:
	print("  → OpenAI response received")

func _on_openai_error(error_type, error_message: String) -> void:
	print("  ✗ OpenAI error: %s" % error_message) 