# Implementation Status: Behavior Matrix Overhaul

## 1. Project Overview & Goals

This document outlines the refactoring of the unit command system from a high-latency, LLM-driven trigger system to a real-time, autonomous behavior system. The primary goal is to resolve latency issues and create more flexible, context-aware unit AI.

The new architecture centralizes real-time decision-making within the `Unit` class, which uses an LLM-generated **`behavior_matrix`** to score and select actions. The LLM's role shifts from a direct commander to a "personality tuner."

**Key Goals of the Overhaul:**

*   **Low-Latency AI**: Move tactical decision-making from the LLM to the game engine, allowing units to react instantly to battlefield conditions.
*   **Flexible Behaviors**: Replace the rigid `trigger -> action` system with a weighted scoring system (Utility AI) that can handle complex scenarios.
*   **Decoupled Goal Setter**: The `AICommandProcessor` and `PlanExecutor` now set a high-level behavior profile (`behavior_matrix`) and strategic sequence (`control_point_attack_sequence`), leaving the execution details to the unit.
*   **Enhanced Observability**: The UI will be updated to show real-time action "activation levels," providing clear insight into the AI's decision-making process.

## 2. High-Level Implementation Plan

The refactor is being implemented in the following phases:

### Phase 1: Redefine the AI Contract (COMPLETED)

*   **Goal**: Update the data structures and validation to support the new `behavior_matrix` model.
*   **`scripts/ai/action_validator.gd`**:
    *   **[COMPLETED]** Replaced old action/trigger constants with `DEFINED_STATE_VARIABLES`, `MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS`, and `INDEPENDENT_REACTIVE_ACTIONS`.
    *   **[COMPLETED]** Rewrote `validate_plan` to validate the new `behavior_matrix` and `control_point_attack_sequence` structure.
*   **`scripts/ai/ai_command_processor.gd`**:
    *   **[COMPLETED]** Overhauled the `base_system_prompt_template` to instruct the LLM on how to generate a `behavior_matrix`.
    *   **[COMPLETED]** Updated response parsing to handle the new JSON format.
*   **`scripts/ai/ai_response_schemas.gd`**:
    *   **[COMPLETED]** Rewrote the entire script to generate a JSON schema for the new `behavior_matrix` and `control_point_attack_sequence` structure.

### Phase 2: Implement the Real-time Behavior Engine (COMPLETED)

*   **Goal**: Make the `Unit` class an autonomous agent driven by its behavior matrix.
*   **`scripts/core/unit.gd`**:
    *   **[COMPLETED]** Removed all old trigger evaluation logic (`_check_triggers`, `triggered_actions`, etc.).
    *   **[COMPLETED]** Added new properties for the behavior engine (`behavior_matrix`, `control_point_attack_sequence`, `current_reactive_state`, etc.).
    *   **[COMPLETED]** Implemented the core behavior loop: `_evaluate_reactive_behavior` -> `_gather_state_variables` -> `_calculate_activation_levels` -> `_decide_and_execute_actions`.
    *   **[COMPLETED]** Implemented the logic for the new primary states: `attack`, `retreat`, `defend`, and `follow`.
*   **`scripts/ai/plan_executor.gd`**:
    *   **[COMPLETED]** Simplified `execute_plan` to pass the behavior data to the unit.
    *   **[COMPLETED]** Removed the obsolete step-advancement logic (`_process`, `_advance_plan`).

### Phase 3: Update Supporting Systems (COMPLETED)

*   **Goal**: Ensure all dependent systems can provide the necessary data for the new AI and display its status.
*   **`scripts/server/server_game_state.gd`**:
    *   **[COMPLETED]** Added `get_units_in_radius` for efficient spatial queries.
    *   **[COMPLETED]** Updated `get_context_for_ai` to gather the new `DEFINED_STATE_VARIABLES`.
    *   **[COMPLETED]** Updated `_gather_game_state` to broadcast the new behavior data (activations, matrix) to clients.
*   **`scripts/gameplay/node_capture_system.gd`**:
    *   **[COMPLETED]** Added helper to provide node control counts to `ServerGameState`.
*   **`scripts/client/client_display_manager.gd`**:
    *   **[COMPLETED]** Updated `_update_unit` to receive and store the new behavior data on client-side unit instances.
*   **`scripts/ui/game_hud.gd`**:
    *   **[COMPLETED]** Reworked `_update_selection_display` to visualize action activation levels.

## 3. Expected Improvements

*   **Vastly Reduced Latency**: Units will react instantly to threats.
*   **More Dynamic AI**: Unit behavior will change based on health, nearby allies/enemies, and other contextual factors.
*   **Cleaner Code**: Centralizing action logic in the `Unit` class simplifies the overall architecture.
*   **Better Debugging**: The new UI will make it easy to see *why* a unit is choosing a particular action.