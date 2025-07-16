# Project Chimera Architecture Overview

This document describes the current networking and game logic architecture for Project Chimera, explains the differences between the client and host roles, and outlines what would be needed to move to a dedicated server model.

## Current Model: Client-Host (Listen Server)

The project currently uses a **Client-Host** model, often called a **"Listen Server"**. In this model, one of a player's machines acts as both the game server and a game client simultaneously.

### The Host's Role
When a player clicks "Host Game," their application instance takes on two jobs:

1.  **Server**: It becomes the **authoritative source of truth** for the game.
    *   **Game Logic**: It runs all core gameplay systems, including the `SessionManager`, `ServerGameState`, `AICommandProcessor`, and `PlanExecutor`. It is responsible for all game state changes, such as unit movement, combat calculations, resource updates, and node captures.
    *   **API Calls**: Because it runs the `AICommandProcessor`, the **host is the only instance that makes API calls to OpenAI**. When any player (including the host themself) enters a command, that command is sent to the host's server-side systems. The host then builds the context, sends the request to the LLM, and receives the plan.
    *   **State Synchronization**: After processing logic, the host broadcasts the updated game state to all connected clients.

2.  **Client**: It also runs a client instance so the host player can see the game and play.
    *   It renders the game world, handles the host player's input, and plays audio, just like any other client.
    *   Its connection to the server part is local, giving it a latency advantage (effectively 0 ping).

### The Client's Role
When a player clicks "Join Game," their application is purely a client.

*   **Game Logic**: Clients are non-authoritative. They **do not run critical game logic**. Their primary role is to receive game state updates from the host and render them.
*   **API Calls**: Clients **never** make API calls to OpenAI. They send their text commands and input to the host, which then handles the AI processing.
*   **Input**: The client captures player input (camera movement, unit selection, commands) and sends it to the host for processing.

### Summary of Differences

| Responsibility         | Host (Listen Server)                                | Client                                                 |
| ---------------------- | --------------------------------------------------- | ------------------------------------------------------ |
| **Game Logic**         | ✅ Runs all authoritative game logic                | ❌ Receives state from host, renders visuals           |
| **OpenAI API Calls**   | ✅ Makes all API calls via `AICommandProcessor`     | ❌ Sends text commands to host                         |
| **Dependencies**       | Loads both Server and Client dependencies           | Loads only Client dependencies                         |
| **Player Experience**  | Plays the game directly, has 0 latency              | Plays the game by connecting to the host               |

---

## Switching to a Dedicated Server Model

A **Dedicated Server** is a standalone, headless (no graphics) instance of the application that runs only the server logic. All players, including the person who might have started the server, connect to it as clients.

### Changes Needed to Switch

**Fortunately, the current architecture is already designed to support this with almost no code changes.**

The `unified_main.gd` script contains the following logic:

```gd
func _ready():
    # ...
    if OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
        _start_server_mode()
    else:
        _start_client_mode()
```

This code automatically detects if the game is being run in a headless environment (which is how dedicated servers are run).

*   **`_start_server_mode()`**: This function, called in headless mode, **only initializes the server dependencies** (`SessionManager`, `ServerGameState`, `AICommandProcessor`, etc.). It does not load any UI or client-side systems.
*   **`_start_client_mode()`**: This function initializes client dependencies and loads the lobby UI.

**To switch to a dedicated server model, the only change is in the deployment and launch process:**

1.  **Build the Project**: Export the game for the server's operating system (e.g., Linux).
2.  **Launch with Headless Flag**: Run the executable from the command line with the `--headless` flag.
    ```bash
    ./YourGameExecutable --headless
    ```
3.  **Client Connection**: All players would then use the "Join Game" option in their clients to connect to the IP address of the dedicated server.

The existing codebase will correctly handle this scenario, creating a pure server instance that can manage the game without a player acting as the host.