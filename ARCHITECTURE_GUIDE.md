 **Key Takeaway**: When adding or changing unit behaviors, the primary location for that logic is within `Unit.gd` or one of its archetype-specific subclasses (like `ScoutUnit.gd`).

## 4. Client-Server Architecture Best Practices

### 4.1 Behavior Logic Separation

**CRITICAL**: Only the server should execute behavior logic. Client units should only display server-calculated data.

```gdscript
# In Unit.gd - Proper server-only logic
func _evaluate_reactive_behavior() -> void:
    # CRITICAL: Only run behavior calculations on the server
    if not multiplayer.is_server():
        return
    # ... behavior calculation logic

func _execute_current_state(delta: float):
    # CRITICAL: Only execute behavior states on the server
    if not multiplayer.is_server():
        return
    # ... state execution logic
```

**Why**: Client units don't have access to complete game state (enemy positions, node systems, etc.) and attempting to run behavior logic causes script errors and performance issues.

### 4.2 Property Assignment Safety

Client units may not have all properties that server units have. Use safe assignment patterns:

```gdscript
# In ClientDisplayManager._update_unit()
# SAFE - Use set() method for dynamic property assignment
unit_instance.set("last_action_scores", unit_data.last_action_scores)
unit_instance.set("current_reactive_state", unit_data.current_reactive_state)

# UNSAFE - Direct property assignment may fail on client units
# unit_instance.last_action_scores = unit_data.last_action_scores  # May cause errors
```

### 4.3 Team ID Resolution Patterns

Clients may not have access to SessionManager. Implement fallback patterns:

```gdscript
func _get_player_team_id(peer_id: int) -> int:
    # Try SessionManager first (works on server)
    var session_manager = get_node_or_null("/root/DependencyContainer/SessionManager")
    if session_manager:
        # ... SessionManager logic
        return team_id
    
    # Fallback for clients - use UnifiedMain.client_team_id
    var unified_main = get_node_or_null("/root/UnifiedMain")
    if unified_main and "client_team_id" in unified_main:
        return unified_main.client_team_id
    
    return -1  # Failed to resolve
```

## 4.4 Data Synchronization Flow

The proper flow for synchronizing data from server to client:

1. **Server**: Calculate behavior activations in `Unit._evaluate_reactive_behavior()`
2. **Server**: Include data in `ServerGameState._gather_game_state()`
3. **Network**: Broadcast via `_on_game_state_update()` RPC
4. **Client**: Receive in `ClientDisplayManager._update_unit()`
5. **Client**: Display in UI components and status bars

## 5. How to Add a New Feature (Implementation Guide)

Follow these patterns to correctly integrate new features.

### Example 1: Adding a New Reactive Action (e.g., "take_evasive_maneuvers")

This example adds a new independent ability that a unit can choose to activate.

1.  **Define the Action**: In `scripts/ai/action_validator.gd`, add `"take_evasive_maneuvers"` to the `INDEPENDENT_REACTIVE_ACTIONS` array.
2.  **Inform the AI**: In `scripts/ai/ai_command_processor.gd`, update the `base_system_prompt_template` to include `"take_evasive_maneuvers"` in the list of "Independent Abilities".
3.  **Implement the Action Logic**: In `scripts/core/unit.gd` (or a subclass like `ScoutUnit.gd`), create the function that performs the action. This function will be called directly by the behavior engine.
    ```gdscript
    # In unit.gd or a subclass
    func take_evasive_maneuvers(params: Dictionary):
        # This is an instant action for this example. For actions that take time,
        # you would manage its state within _physics_process.
        # This action might, for example, apply a temporary speed boost and a zig-zag movement pattern.
        print("%s is taking evasive maneuvers." % unit_id)
    ```
4.  **No Hookup Needed**: The behavior engine in `Unit.gd` automatically discovers and calls this action if its activation level is high enough. You just need to ensure the function name matches the action name in `action_validator.gd`.

### Example 2: Adding a New State Variable (e.g., "ammo_percentage")

This example adds a new input that the unit's AI can use to make decisions.

1.  **Define the State Variable**: In `scripts/ai/action_validator.gd`, add `"ammo_percentage"` to the `DEFINED_STATE_VARIABLES` array. This makes it a required input for the LLM's `behavior_matrix`.
2.  **Inform the AI**: In `scripts/ai/ai_command_processor.gd`, update the `base_system_prompt_template` to explain the new `ammo_percentage` state variable to the LLM.
3.  **Implement Data Gathering**: In `scripts/core/unit.gd`, inside the `_gather_state_variables` function, add the logic to calculate and normalize the new variable.
    ```gdscript
    # In _gather_state_variables() in unit.gd
    # ... after other state vars
    state["ammo_percentage"] = float(ammo) / max_ammo if max_ammo > 0 else 0.0
    ```
4.  **Done**: The new state variable is now automatically included in the dot product calculation for all action activations. The LLM can now be prompted to create personalities that, for example, make a unit more likely to `retreat` when its `ammo_percentage` is low.

### Example 3: Adding a New UI Element (e.g., Morale Bar)

This process remains largely the same, as it deals with broadcasting state from server to client.

1.  **Add Server-Side State**: In `scripts/core/unit.gd`, add the `morale` property: `var morale: float = 1.0`.
2.  **Broadcast the State**: In `scripts/server/server_game_state.gd`, inside the `_gather_game_state` function, add the new property to the `unit_data` dictionary:
    ```gdscript
    var unit_data = {
        # ... existing properties
        "morale": unit.morale
    }
    ```
3.  **Receive the State on Client**: In `scripts/client/client_display_manager.gd`, inside the `_update_unit` function, receive the new property and set it on the client-side unit node:
    ```gdscript
    # In _update_unit(unit_data: Dictionary, delta: float)
    if unit_data.has("morale"):
        unit_instance.set("morale", unit_data.morale)  # Use set() for safety
    ```
4.  **Create and Update the UI**: Create a UI scene (`MoraleBar.tscn`), instantiate it as a child of `AnimatedUnit.tscn`, and have its script read the `morale` property from its parent in `_process` to update its visual state.

## 6. Performance Optimization Guidelines

### 6.1 UI Update Frequency

**Avoid frequent UI rebuilds**: High-frequency UI updates cause severe performance issues.

```gdscript
# BAD - Updates 5 times per second without change detection, causes lag
const BEHAVIOR_REFRESH_INTERVAL: float = 0.2
# No caching or change detection - rebuilds UI every time

# GOOD - Updates 5 times per second WITH intelligent change detection
const BEHAVIOR_REFRESH_INTERVAL: float = 0.2
# With proper caching and change detection - only rebuilds when data changes

# CONSERVATIVE - Updates once per second, always smooth but less responsive
const BEHAVIOR_REFRESH_INTERVAL: float = 1.0
```

**Key Point**: The frequency itself isn't the problem—it's doing expensive work unnecessarily. With proper change detection, 0.2s intervals are perfectly acceptable.

### 6.2 Object Caching Patterns

**Cache expensive objects**: Creating new instances repeatedly is a major performance bottleneck.

```gdscript
# BAD - Creates new ActionValidator every time (expensive)
func _add_behavior_activations_display(unit: Node):
    var validator_script = preload("res://scripts/ai/action_validator.gd")
    var validator = validator_script.new()  # Expensive creation!

# GOOD - Cache the validator instance
var cached_action_validator = null

func _ready():
    var validator_script = preload("res://scripts/ai/action_validator.gd")
    cached_action_validator = validator_script.new()  # Create once

func _add_behavior_activations_display(unit: Node):
    var valid_actions = cached_action_validator.get_valid_actions_for_archetype(unit_archetype)
```

### 6.3 Intelligent Change Detection

**Only update when data changes**: Use caching to prevent unnecessary UI rebuilds.

```gdscript
# Implement change detection to avoid unnecessary UI updates
var last_behavior_data_cache: Dictionary = {}

func _refresh_behavior_matrix_display():
    var has_changes = false
    for unit in selected_units:
        var current_scores = unit.last_action_scores
        var cached_scores = last_behavior_data_cache.get(unit.unit_id, {})
        
        if not _dictionaries_equal(current_scores, cached_scores):
            has_changes = true
            last_behavior_data_cache[unit.unit_id] = current_scores.duplicate()
    
    # Only rebuild UI when data actually changed
    if has_changes:
        _update_selection_display(selected_units)
```

### 6.4 Debug Logging Performance

**Minimize frame-rate debug logging**: Excessive console output severely impacts performance.

```gdscript
# BAD - Logs every frame, causes performance issues
print("DEBUG: ClientDisplayManager updating unit %s" % unit_id)

# GOOD - Comment out or use conditional logging
# print("DEBUG: ClientDisplayManager updating unit %s" % unit_id)

# BETTER - Use periodic logging
if int(Time.get_ticks_msec() / 1000.0) % 5 == 0:  # Every 5 seconds
    print("DEBUG: Periodic status update for %s" % unit_id)
```

## 7. UI Development Patterns

### 7.1 Player Unit Status Display

When implementing unit status displays (health bars, respawn timers):

1. **Team Filtering**: Filter units by player's team using fallback team ID resolution
2. **Dynamic Updates**: Update only when unit data changes to prevent lag
3. **State Transitions**: Handle alive → dead → respawning state transitions properly
4. **Data Flow**: Server calculates → ClientDisplayManager receives → UI displays

### 7.2 Action Activation Display

For displaying behavior matrix activations:

1. **Server-Authoritative**: Only server calculates activations
2. **Client Display**: Clients receive and display server-calculated data
3. **Archetype Filtering**: Only show actions valid for the unit's archetype
4. **Performance**: Use cached validators and change detection

### 7.3 Selection System Integration

When integrating with the selection system:

1. **Signal Connections**: Connect selection_changed signals in _ready() with proper error checking
2. **Team Validation**: Only allow selection of units from player's team
3. **Visual Feedback**: Implement select() and deselect() methods on units
4. **Performance**: Clear caches when selection changes to ensure fresh data

## 8. Scene & Asset Structure

-   **`UnifiedMain.tscn`**: The root scene of the application. It contains the `DependencyContainer` and is the parent for dynamically loaded scenes like the lobby, map, and HUD.
-   **`AnimatedUnit.tscn`**: This is the **client-side visual representation** of a unit. It contains the 3D model, `AnimationPlayer`, and slots for UI elements like health bars. Its script `AnimatedUnit.gd` handles animations and visual effects.
-   **`Unit.gd`**: This is the **server-side logic script**. While it is the base class for `AnimatedUnit.gd`, its primary role is to execute the game logic on the server. The server does not instantiate the `AnimatedUnit.tscn` scene; it instantiates the script and attaches it to a `CharacterBody3D` node.
-   **`game_hud.tscn`**: The main UI overlay for the game, displayed on the client.
-   **`test_map.tscn`**: A static map scene containing the environment, navigation mesh, and markers for spawn points and control points.

## 9. Common Pitfalls and Solutions

### 9.1 Client-Side Lag After Unit Selection

**Problem**: Client becomes extremely slow after selecting units.

**Causes**:
- High-frequency UI rebuilds (every 0.2s)
- Creating new ActionValidator instances repeatedly
- Rebuilding UI even when data hasn't changed

**Solutions**:
- Reduce update frequency to 1.0s or implement change detection
- Cache expensive objects like ActionValidator
- Use intelligent change detection before UI rebuilds

### 9.2 Script Errors on Client Units

**Problem**: "Nonexistent function" errors when clients try to execute behavior logic.

**Cause**: Client units attempting to execute server-only functions like `_execute_defend_state()`.

**Solution**: Add server checks to behavior execution functions:
```gdscript
func _execute_current_state(delta: float):
    if not multiplayer.is_server():
        return  # Client units should not execute behavior logic
```

### 9.3 Property Assignment Errors

**Problem**: "Invalid assignment" errors when setting properties on client units.

**Cause**: Client units (from scenes) may not have all properties that server units (script-only) have.

**Solution**: Use safe property assignment with `set()` method:
```gdscript
unit_instance.set("property_name", value)  # Safe
# unit_instance.property_name = value  # Unsafe - may fail
```

### 9.4 Team ID Resolution Failures

**Problem**: Unit status panels showing no units for clients.

**Cause**: Clients can't access SessionManager for team ID lookup.

**Solution**: Implement fallback team ID resolution using `UnifiedMain.client_team_id`.

### 9.5 Action Activation Data Not Showing

**Problem**: Behavior matrix activations not displaying in UI.

**Causes**:
- Client units running their own behavior calculations (conflicting with server)
- Behavior start delay preventing immediate activation calculation
- Missing data synchronization from server to client

**Solutions**:
- Disable client-side behavior execution
- Reduce behavior start delay to 0.1s for immediate UI feedback
- Ensure proper data flow: Server → ClientDisplayManager → UI