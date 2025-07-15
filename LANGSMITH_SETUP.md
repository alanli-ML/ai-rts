# LangSmith Integration Setup

This guide explains how to set up LangSmith for comprehensive LLM observability in the AI RTS game.

## What is LangSmith?

LangSmith is LangChain's platform for debugging, testing, evaluating, and monitoring LLM applications. It provides:

- **Tracing**: Track every LLM call with inputs, outputs, and metadata
- **Debugging**: Identify performance bottlenecks and errors
- **Monitoring**: Real-time observability of AI system behavior
- **Analytics**: Usage metrics, token costs, and performance analysis

## Setup Instructions

### 1. Get LangSmith API Key

1. Sign up at [LangSmith](https://smith.langchain.com/)
2. Create a new project (or use existing)
3. Get your API key from Settings

### 2. Configure API Key

Set your LangSmith API key using one of these methods:

#### Option A: Environment Variable (Recommended)
```bash
export LANGCHAIN_API_KEY="your-langsmith-api-key-here"
```

#### Option B: .env file in project root (Recommended)
Create a `.env` file in the `ai-rts/` directory with your configuration:

```bash
# AI RTS Game Configuration
OPENAI_API_KEY=sk-your-openai-api-key-here
LANGCHAIN_API_KEY=ls_your-langsmith-api-key-here
LANGSMITH_PROJECT_NAME=ai-rts-game
LANGSMITH_SESSION_NAME=
LANGSMITH_ENABLE_TRACING=true
LANGSMITH_BASE_URL=https://api.smith.langchain.com
```

#### Option C: User .env file
Create a `.env` file in your user directory (`~/.env` or `user://.env`) with the same format as above.

### 3. Available Configuration Options

All LangSmith settings can be configured via environment variables or .env files:

| Setting | Environment Variable | Default | Description |
|---------|---------------------|---------|-------------|
| API Key | `LANGCHAIN_API_KEY` | None | **Required** - Your LangSmith API key |
| Project Name | `LANGSMITH_PROJECT_NAME` | `"ai-rts-game"` | Project name in LangSmith dashboard |
| Session Name | `LANGSMITH_SESSION_NAME` | `""` | Optional session grouping for traces |
| Enable Tracing | `LANGSMITH_ENABLE_TRACING` | `true` | Enable/disable all tracing |
| Base URL | `LANGSMITH_BASE_URL` | LangSmith API URL | Custom LangSmith endpoint |

**Priority Order**: Environment Variables → .env file → Default values

### 4. Example .env Configuration

```bash
# Required - Get from https://smith.langchain.com/
LANGCHAIN_API_KEY=ls_abc123...

# Optional - Customize project organization
LANGSMITH_PROJECT_NAME=my-ai-rts-project
LANGSMITH_SESSION_NAME=multiplayer-session-1
LANGSMITH_ENABLE_TRACING=true

# Advanced - Custom endpoint (rarely needed)
# LANGSMITH_BASE_URL=https://api.smith.langchain.com
```

## What Gets Traced

The integration automatically traces:

### LLM Calls
- **Input Messages**: User commands and system prompts
- **Model Settings**: Temperature, max tokens, model name
- **Outputs**: AI responses and parsed commands
- **Timing**: Request duration and timestamps
- **Token Usage**: Prompt, completion, and total tokens

### Game Context
- **Command Text**: Original user command
- **Selected Units**: Count, types, and IDs
- **Game State**: Phase, resources, control points
- **Match Info**: Game time and current state

### Error Tracking
- **API Errors**: Network issues, rate limits, authentication
- **Parsing Errors**: JSON parsing failures
- **Execution Errors**: Command validation and execution failures

## LangSmith Dashboard

Once configured, you can view traces at:
- **Project URL**: `https://smith.langchain.com/projects/{your-project-name}`
- **Traces**: Real-time view of all LLM calls
- **Analytics**: Token usage, costs, and performance metrics
- **Sessions**: Grouped traces by game session

### Key Metrics to Monitor

1. **Latency**: How fast are LLM responses?
2. **Token Usage**: Cost optimization opportunities
3. **Error Rates**: Reliability issues
4. **Command Success**: How often AI commands work correctly
5. **Game Context**: Which scenarios trigger the most AI calls

## Usage Examples

### Setting Session Names
```gdscript
# Group traces by game session
var langsmith_client = dependency_container.get_langsmith_client()
langsmith_client.set_session_name("match_2024_01_15_1430")
```

### Adding Custom Metadata
```gdscript
# Add custom trace metadata during processing
langsmith_client.add_trace_metadata(trace_id, "player_skill_level", "expert")
langsmith_client.add_trace_tag(trace_id, "multiplayer")
```

## Quick Start

1. Create a `.env` file in your project root:
   ```bash
   LANGCHAIN_API_KEY=ls_your-actual-api-key-here
   LANGSMITH_PROJECT_NAME=my-project-name
   ```

2. Run your AI RTS game and check console output for:
   ```
   Loading LangSmith config from: res://.env
   LangSmith configuration loaded:
     Project: my-project-name
     Session: default
     Tracing: enabled
   ```

3. View your traces at `https://smith.langchain.com/projects/my-project-name`

## Troubleshooting

### Common Issues

1. **"LangSmith API key not found"**
   - Check your environment variable or .env file
   - Restart Godot after setting environment variables
   - Ensure .env file is in project root (not in scripts/ folder)

2. **"LangSmith: API error 401"**
   - Invalid API key
   - Check your LangSmith account status
   - Verify API key starts with `ls_`

3. **"LangSmith client not available"**
   - LangSmith client may not be initialized
   - Check dependency container setup
   - Ensure you're running in server mode

4. **"No LangSmith configuration found in .env"**
   - Check .env file format (KEY=value, no spaces around =)
   - Verify file encoding (should be UTF-8)
   - Check for typos in variable names

### Debug Mode

Enable debug logging by setting:
```gdscript
langsmith_client.enable_tracing = true
```

Check console output for LangSmith-related messages:
- `"LangSmith client initialized"`
- `"Started LLM call with trace ID"`
- `"Trace completed"`

## Performance Considerations

- **Minimal Overhead**: Tracing adds ~5-10ms per LLM call
- **Async Operation**: Traces are sent asynchronously
- **Graceful Degradation**: If LangSmith is unavailable, falls back to direct OpenAI calls
- **Optional**: Can be completely disabled by setting `enable_tracing = false`

## Privacy and Data

LangSmith traces include:
- User commands and AI responses
- Game state information
- Metadata about the game session

Ensure this aligns with your privacy requirements. You can disable specific data logging:
```gdscript
langsmith_client.log_inputs = false   # Don't log user inputs
langsmith_client.log_outputs = false  # Don't log AI outputs
langsmith_client.log_metadata = false # Don't log game metadata
```

## Integration Architecture

```
User Command → AI Command Processor
                ↓
            LangSmith Client (tracing wrapper)
                ↓
            OpenAI Client → OpenAI API
                ↓
            Response Processing
                ↓
            LangSmith Completion Trace
```

The LangSmith client acts as a transparent wrapper around OpenAI calls, providing observability without changing the core game logic. 