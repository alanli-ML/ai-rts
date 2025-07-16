# AI Command Test - Debug script for testing AI command processing
# Run this from the editor or as a standalone scene to test AI integration
extends Node

func _ready():
    print("=== AI Command Test Started ===")
    
    # Wait a moment for systems to initialize
    await get_tree().process_frame
    await get_tree().process_frame
    
    test_api_configuration()
    await get_tree().create_timer(1.0).timeout
    test_structured_outputs()
    await get_tree().create_timer(1.0).timeout
    test_command_processing()

func test_api_configuration():
    print("\n=== Testing API Configuration ===")
    
    # Check environment variables
    var openai_key = OS.get_environment("OPENAI_API_KEY")
    var langsmith_key = OS.get_environment("LANGCHAIN_API_KEY")
    
    print("OpenAI API Key (env): %s" % ("✓ Set" if not openai_key.is_empty() else "✗ Missing"))
    print("LangSmith API Key (env): %s" % ("✓ Set" if not langsmith_key.is_empty() else "✗ Missing"))
    
    # Check .env file
    if FileAccess.file_exists("res://.env"):
        print(".env file: ✓ Exists")
        var file = FileAccess.open("res://.env", FileAccess.READ)
        var content = file.get_as_text()
        file.close()
        
        var has_openai = "OPENAI_API_KEY=" in content
        var has_langsmith = "LANGCHAIN_API_KEY=" in content or "LANGSMITH_API_KEY=" in content
        
        print("  - OpenAI key in .env: %s" % ("✓" if has_openai else "✗"))
        print("  - LangSmith key in .env: %s" % ("✓" if has_langsmith else "✗"))
    else:
        print(".env file: ✗ Missing")
        print("Create a .env file in project root with:")
        print("OPENAI_API_KEY=sk-your-key-here")
        print("LANGCHAIN_API_KEY=ls-your-key-here")
    
    # Check dependency container
    var container = get_node_or_null("/root/DependencyContainer")
    if container:
        print("DependencyContainer: ✓ Available")
        
        var openai_client = container.get_openai_client()
        var langsmith_client = container.get_langsmith_client()
        var ai_processor = container.get_ai_command_processor()
        
        print("  - OpenAI Client: %s" % ("✓" if openai_client else "✗"))
        print("  - LangSmith Client: %s" % ("✓" if langsmith_client else "✗"))
        print("  - AI Processor: %s" % ("✓" if ai_processor else "✗"))
        
        if openai_client:
            print("  - OpenAI API Key loaded: %s" % ("✓" if not openai_client.api_key.is_empty() else "✗"))
        
        if langsmith_client:
            print("  - LangSmith API Key loaded: %s" % ("✓" if not langsmith_client.api_key.is_empty() else "✗"))
            print("  - LangSmith tracing enabled: %s" % ("✓" if langsmith_client.enable_tracing else "✗"))
    else:
        print("DependencyContainer: ✗ Not found")

func test_structured_outputs():
    print("\n=== Testing Structured Outputs Migration ===")
    
    # Test the schema definitions
    const AIResponseSchemas = preload("res://scripts/ai/ai_response_schemas.gd")
    
    var group_schema = AIResponseSchemas.get_schema_for_command(true)
    var individual_schema = AIResponseSchemas.get_schema_for_command(false)
    
    print("Schema definitions: ✓ Loaded successfully")
    print("  - Group schema type: %s" % group_schema.get("type", "unknown"))
    print("  - Individual schema type: %s" % individual_schema.get("type", "unknown"))
    
    # Check that schemas have required fields
    var group_json_schema = group_schema.get("json_schema", {})
    var individual_json_schema = individual_schema.get("json_schema", {})
    
    if group_json_schema.has("strict") and group_json_schema.strict == true:
        print("  - Group schema strict mode: ✓ Enabled")
    else:
        print("  - Group schema strict mode: ✗ Missing or disabled")
    
    if individual_json_schema.has("strict") and individual_json_schema.strict == true:
        print("  - Individual schema strict mode: ✓ Enabled")
    else:
        print("  - Individual schema strict mode: ✗ Missing or disabled")
    
    # Test unit-specific schemas with enums
    var scout_schema = AIResponseSchemas.get_schema_for_command(false, ["scout"])
    var tank_schema = AIResponseSchemas.get_schema_for_command(false, ["tank"])
    var mixed_schema = AIResponseSchemas.get_schema_for_command(true, ["scout", "medic", "engineer"])
    
    # Verify that all fields are required (OpenAI requirement)
    var scout_schema_obj = scout_schema.get("json_schema", {}).get("schema", {})
    var plan_items = scout_schema_obj.get("properties", {}).get("plans", {}).get("items", {})
    var steps_items = plan_items.get("properties", {}).get("steps", {}).get("items", {})
    var steps_required = steps_items.get("required", [])
    
    if "speech" in steps_required:
        print("  - All fields marked as required: ✓ Compliant with OpenAI specs")
    else:
        print("  - All fields marked as required: ✗ Missing required fields")
    
    # Verify action enums are working
    var action_enum = steps_items.get("properties", {}).get("action", {}).get("enum", [])
    if "activate_stealth" in action_enum:
        print("  - Scout-specific actions in enum: ✓ Working")
    else:
        print("  - Scout-specific actions in enum: ✗ Missing")
    
    # Verify trigger structure
    var triggered_items = plan_items.get("properties", {}).get("triggered_actions", {}).get("items", {})
    var trigger_properties = triggered_items.get("properties", {})
    if trigger_properties.has("trigger_source") and trigger_properties.has("trigger_comparison") and trigger_properties.has("trigger_value"):
        print("  - New trigger structure: ✓ Implemented")
    else:
        print("  - New trigger structure: ✗ Missing")
    
    print("Structured outputs with enums: ✓ Ready for testing")

func test_command_processing():
    print("\n=== Testing Command Processing ===")
    
    var container = get_node_or_null("/root/DependencyContainer")
    if not container:
        print("Cannot test - DependencyContainer not available")
        return
    
    var ai_processor = container.get_ai_command_processor()
    if not ai_processor:
        print("Cannot test - AI Command Processor not available")
        return
    
    print("Attempting to process test command...")
    
    # Connect to signals to monitor progress
    if not ai_processor.processing_started.is_connected(_on_processing_started):
        ai_processor.processing_started.connect(_on_processing_started)
    if not ai_processor.plan_processed.is_connected(_on_plan_processed):
        ai_processor.plan_processed.connect(_on_plan_processed)
    if not ai_processor.command_failed.is_connected(_on_command_failed):
        ai_processor.command_failed.connect(_on_command_failed)
    
    # Send a test command
    ai_processor.process_command("Move to the center of the map", [], 1)

func _on_processing_started():
    print("✓ AI processing started")

func _on_plan_processed(plans: Array, message: String):
    print("✓ AI plan processed successfully!")
    print("  Plans: %d" % plans.size())
    print("  Message: %s" % message)

func _on_command_failed(error: String, unit_ids: Array):
    print("✗ AI command failed: %s" % error)
    print("\nTo fix this:")
    print("1. Check that API keys are properly configured")
    print("2. Check console output for detailed error messages")
    print("3. Ensure you're running in server mode (not client-only)")
    print("4. Verify internet connection for API calls") 