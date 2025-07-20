# Implementation Plan: Dynamic Bias AI Overhaul

## 1. Project Overview & Goals

This document outlines the refactoring of the unit AI from an LLM-generated static `behavior_matrix` to a system where the LLM provides high-level strategic guidance. The primary goal is to elevate the LLM's role to a strategist, making unit AI more adaptive, reducing prompt complexity, and improving performance.

This overhaul refactors the AI's role to that of a high-level strategist. The LLM is now responsible for grouping units and assigning each group a strategic personality, defined by a prioritized order of primary states (`attack`, `defend`, `retreat`, `follow`). The game engine's `PlanExecutor` then performs a one-time, algorithmic adjustment of each unit's behavior matrix biases to match this personality. This allows units to react dynamically to changing battlefield conditions based on a fixed strategic guidance until a new command is issued.

**Key Goals of the Overhaul:**

*   **LLM as Strategist**: The LLM will now group units and assign them a `primary_state_priority_list` and a `control_point_attack_sequence`. It will no longer generate detailed weight matrices.
*   **Engine-Side Behavior Tuning**: The `PlanExecutor` will algorithmically adjust behavior matrix biases for units based on the LLM's strategic guidance. This happens once per command, allowing units to react dynamically to changing conditions until a new command is issued.
*   **Simplified AI Contract**: Drastically reduce the size and complexity of prompts and responses, leading to faster and more reliable AI interaction.
*   **Independent Abilities**: Non-primary abilities (e.g., `activate_shield`) will remain purely reactive, governed by pre-tuned weights, independent of the LLM's strategic input.

## 2. High-Level Implementation Plan

### Phase 1: Redefine the AI Contract (DONE)

*   **Goal**: Update the data structures and validation to support the new strategic plan model.
*   **`scripts/ai/ai_response_schemas.gd`**:
    *   **[DONE]** Rewrite `plan_schema` to represent a group assignment, including `unit_ids` (array).
    *   **[DONE]** Remove the `behavior_matrix` property and its complex schema.
    *   **[DONE]** Add `primary_state_priority_list`, an array of 4 unique primary state strings.
*   **`scripts/ai/ai_command_processor.gd`**:
    *   **[DONE]** Overhaul `base_system_prompt_template` to instruct the LLM on grouping units and providing a `primary_state_priority_list`.
    *   **[DONE]** Update the prompt to include high-level game context (node counts, unit statuses) for better strategic decisions.
*   **`scripts/ai/action_validator.gd`**:
    *   **[DONE]** Update `validate_plan` to validate the new group plan structure (`unit_ids`, `primary_state_priority_list`).
    *   **[DONE]** Remove the `_validate_behavior_matrix` function entirely.

### Phase 2: Implement the Behavior Tuning Engine (DONE)

*   **Goal**: Centralize the behavior tuning logic in the `PlanExecutor` and simplify the `Unit` to be a pure executor of the tuned plan.
*   **`scripts/ai/plan_executor.gd`**:
    *   **[DONE]** Refactor `execute_plan` to handle a group plan.
    *   **[DONE]** Implement a new private function `_generate_tuned_matrix` that takes a base behavior matrix and a `primary_state_priority_list`.
    *   **[DONE]** This function will algorithmically adjust the `bias` for the four primary states based on their order in the priority list (e.g., using values from 0.3 down to 0.0).
    *   **[DONE]** For each unit in the plan, it will generate this tuned matrix and pass it to the unit's `set_behavior_plan` method.
*   **`scripts/core/unit.gd`**:
    *   **[DONE]** Remove the `primary_state_priority_list` property and the `_adjust_primary_state_biases` function.
    *   **[DONE]** Revert `set_behavior_plan` to accept a full `behavior_matrix` and a `control_point_attack_sequence`. This function will now simply store the tuned matrix provided by the `PlanExecutor`.
    *   **[DONE]** Remove the real-time bias adjustment call from `_evaluate_reactive_behavior`.

### Phase 3: Update Supporting Systems (DONE)

*   **Goal**: Ensure constants and documentation reflect the new architecture.
*   **`scripts/shared/constants/game_constants.gd`**:
    *   **[DONE]** In `DEFAULT_BEHAVIOR_MATRICES`, set the `"bias"` for `attack`, `defend`, `retreat`, and `follow` to `0.0` to provide a neutral starting point for the dynamic adjustment algorithm.
    *   **[DONE]** Review biases for independent abilities (e.g., `activate_shield`) to ensure they are well-tuned for purely reactive use.
    *   **[DONE]** Add a helper function `get_default_behavior_matrix(archetype)` to easily retrieve base matrices.
*   **`README.md`**:
    *   **[DONE]** Update the "LLM Response Schema" section to show the new, simpler JSON structure with `primary_state_priority_list`.
    *   **[DONE]** Update the description to explain the new dynamic bias system instead of the static behavior matrix.

### Phase 4: Improve AI Context & Usability (DONE)

*   **Goal**: Make the AI's understanding of the map more intuitive and provide better strategic context.
*   **`scripts/core/map.gd`**:
    *   **[DONE]** Rename control points from `Node1`, `Node2`, etc., to intuitive geographical names: `Northwest`, `North`, `Northeast`, `West`, `Center`, `East`, `Southwest`, `South`, `Southeast`.
*   **`scripts/ai/ai_command_processor.gd`**:
    *   **[DONE]** Update the `base_system_prompt_template` to use the new node names and inform the LLM of team base locations (Team 1: Far Northwest, Team 2: Far Southeast).
*   **`scripts/ai/ai_response_schemas.gd`**:
    *   **[DONE]** Update the schema for `control_point_attack_sequence` to enforce the new node names using an `enum`.
*   **`scripts/ai/action_validator.gd`**:
    *   **[DONE]** Update the validation logic to check against the new list of valid node names.
*   **`README.md`**:
    *   **[DONE]** Update the example JSON in the LLM Response Schema section to use the new node names.

### Phase 5: AI Prompt & Context Refinement (DONE)

*   **Goal**: Clean up and simplify the prompt engineering to improve clarity and reliability.
*   **`scripts/ai/ai_command_processor.gd`**:
    *   **[DONE]** Refactor `_process_group_command` to simplify prompt construction.
    *   **[DONE]** Move all instructional text from the `user_prompt` into the `base_system_prompt_template`. The user prompt should only contain the player's command and the game context JSON.
    *   **[DONE]** Remove the obsolete `_get_archetype_specific_actions_info` function.
    *   **[DONE]** Remove the obsolete `_build_group_prompt` and `_build_individual_prompt` functions.

### Phase 7: Network Communication Refactor (IN PROGRESS)

*   **Goal**: Address client-side lag and missed events by optimizing data synchronization between the server and clients.
*   **`scripts/ai/plan_executor.gd`**:
    *   **[DONE]** Add reliable RPC call to `execute_plan` to broadcast static plan data (`behavior_matrix`, `control_point_attack_sequence`, `strategic_goal`) to clients once per plan.
*   **`scripts/unified_main.gd`**:
    *   **[DONE]** Implement `update_unit_behavior_plan_rpc` (reliable) to receive static plan data on clients and force immediate UI updates.
    *   **[DONE]** Implement `update_units_ui_data_rpc` (unreliable) to receive high-frequency UI data at a lower rate.
    *   **[DONE]** Implement `unit_died_rpc` and `unit_respawned_rpc` to reliably trigger client-side visual effects.
    *   **[DONE]** Implement generic `ability_visuals_rpc` for effects like shields and stealth.
*   **`scripts/server/server_game_state.gd`**:
    *   **[DONE]** Remove static plan data from `_gather_filtered_game_state_for_team` to reduce high-frequency packet size.
    *   **[DONE]** Remove high-frequency UI data (`last_action_scores`, etc.) from `_gather_filtered_game_state_for_team`.
    *   **[DONE]** Add a lower-frequency broadcast for UI data in `_physics_process`.
    *   **[REVERTED]** ~~Remove transform data (`position`, `velocity`, `basis`) from high-frequency packet.~~ (Re-added for manual interpolation).
    *   **[DONE]** Remove `is_stealthed` and `shield_active` from the high-frequency packet.
*   **`scripts/client/client_display_manager.gd`**:
    *   **[DONE]** Remove logic for updating static plan data from `_update_unit` as it's now handled by RPC.
    *   **[DONE]** Remove logic for updating high-frequency UI data from `_update_unit`.
    *   **[REVERTED]** ~~Remove manual transform interpolation, now handled by `MultiplayerSynchronizer`.~~ (Re-added manual interpolation).
    *   **[DONE]** Remove state-based visual effect logic for shields and stealth.
*   **`scripts/core/unit.gd`**:
    *   **[DONE]** Add RPC calls for death and respawn events in `die()` and `_handle_respawn()`.
*   **`scripts/units/*.gd` (Subclasses)**:
    *   **[DONE]** Add RPC calls for ability activations (shield, stealth).
*   **`scripts/units/animated_unit.gd`**:
    *   **[DONE]** Add `play_ability_effect()` method to handle visual effects from RPCs.
    *   **[REVERTED]** ~~Add client-side velocity calculation to drive animations from `MultiplayerSynchronizer` data.~~ (Now uses server-provided velocity).
*   **`scenes/units/AnimatedUnit.tscn`**:
    *   **[REVERTED]** ~~Add `MultiplayerSynchronizer` for efficient transform synchronization.~~ (Removed due to incompatibility with current network model).

### Phase 6: Final Code Cleanup (TO DO)

*   **Goal**: Remove obsolete code and functions that have been superseded by the new implementation.
*   **`scripts/ai/ai_command_processor.gd`**:
    *   **[TO DO]** Remove obsolete model configuration variables (`individual_command_model`, etc.) and simplify to a single `command_model`.
    *   **[TO DO]** Simplify `process_command` and `_build_source_info` to remove the group/individual command distinction.
    *   **[TO DO]** Fix bug in `_on_openai_response` where it incorrectly parsed `unit_id` instead of `unit_ids` from group plans.
    *   **[TO DO]** Remove call to the now-obsolete `set_initial_group_command_given` method.
*   **`scripts/server/server_game_state.gd`**:
    *   **[TO DO]** Remove all logic for autonomous unit actions (`ai_think_timer`, `_request_autonomous_plan_for_unit`, `units_waiting_for_ai`, etc.).
    *   **[TO DO]** Remove the obsolete `get_context_for_ai` method (superseded by `get_group_context_for_ai`).
*   **`scripts/core/unit.gd`**:
    *   **[TO DO]** Remove obsolete variables from the old plan execution system (`action_complete`, `step_timer`, etc.).
    *   **[TO DO]** Remove obsolete methods (`get_current_active_triggers`, `_set_default_triggered_actions`).
*   **`scripts/units/*.gd` (Subclasses)**:
    *   **[TO DO]** Remove all assignments to the obsolete `action_complete` variable.
*   **`scripts/shared/constants/game_constants.gd`**:
    *   **[TO DO]** Remove the deprecated `DEFAULT_TRIGGERED_ACTIONS` constant and its getter function.

## 3. Expected Improvements

*   **Vastly Reduced Latency & Cost**: Smaller prompts and responses make LLM calls faster and cheaper.
*   **More Dynamic & Strategic AI**: LLM focuses on strategy, while units adapt their tactics frame-by-frame.
*   **Cleaner Code**: Centralizing tactical logic in the `Unit` class simplifies the overall architecture.
*   **Better Debugging**: The existing UI that shows activation levels now also reflect the real-time bias adjustments, making the AI's "personality" visible.