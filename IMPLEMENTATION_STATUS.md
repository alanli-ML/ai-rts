# Implementation Status: Action & Trigger System Overhaul

## 1. Project Overview & Goals

This document outlines the refactoring of the game's action, trigger, and unit state management systems. The primary goal is to resolve bugs and architectural issues stemming from a "dual state machine" problem, where both the `PlanExecutor` and individual `Unit` scripts managed state, leading to conflicts and instability.

The new architecture centralizes all action execution and state management within the `Unit` class itself. The `Unit`'s internal state machine becomes the single source of truth for its behavior.

**Key Goals of the Overhaul:**

*   **Unified State Machine**: Eliminate the dual state machine by making `Unit.gd` the sole authority on a unit's current action and state.
*   **Decoupled Goal Setter**: The `PlanExecutor` is demoted from a micro-managing "controller" to a high-level "goal setter." It tells a unit *what* to do, not *how* to do it.
*   **Autonomous Triggers**: Trigger evaluation is moved directly into the `Unit`, allowing for immediate, autonomous reactions to environmental changes (e.g., enemy sighted, health low) without waiting for the `PlanExecutor`'s next tick.
*   **Improved Stability & Maintainability**: By centralizing logic, we reduce race conditions, simplify action interruption, and make the codebase easier to debug and extend.

## 2. High-Level Implementation Plan

The refactor is being implemented in the following phases:

### Phase 1: Centralize Action State in `Unit` (Completed)

*   **Goal**: The `Unit` class now owns its `current_action` and `action_complete` status. `PlanExecutor` uses a new `set_current_action()` method on the unit.
*   **`scripts/core/unit.gd`**:
    *   Added `current_action`, `action_complete`, `triggered_actions`, `trigger_last_states`, and `step_timer` properties.
    *   Added `set_current_action()` to receive commands and set the unit's internal state.
    *   Added `set_triggered_actions()` to receive conditional actions from a plan.
*   **`scripts/ai/plan_executor.gd`**:
    *   Refactored to be a simple sequencer. Its `_process` loop now checks `unit.action_complete` to advance the plan.
    *   The `execute_plan` method now calls `unit.set_triggered_actions()` and starts the plan sequence.

### Phase 2: Refactor the `Unit` State Machine (Completed)

*   **Goal**: The `Unit`'s `_physics_process` method is now fully responsible for executing its `current_action` and signaling completion.
*   **`scripts/core/unit.gd`**:
    *   The `_physics_process` method has been updated to check for action completion within each state (e.g., `navigation_agent.is_navigation_finished()` for `MOVING`).
    *   When an action is finished, `action_complete` is set to `true`.
    *   Added healing logic to the `HEALING` state.
*   **Specialized unit scripts** (`scout_unit.gd`, `sniper_unit.gd`, etc.):
    *   All specialized ability methods have been updated to correctly signal action completion.

### Phase 3: Integrate Triggers into the `Unit` (Completed)

*   **Goal**: All trigger evaluation logic has been moved from `PlanExecutor` into the `Unit` for immediate, state-aware reactions.
*   **`scripts/ai/plan_executor.gd`**:
    *   All trigger evaluation methods (`_evaluate_trigger`, etc.) have been removed.
    *   `interrupt_plan` method was updated to handle trigger-based interruptions without requesting a new plan prematurely.
*   **`scripts/core/unit.gd`**:
    *   A `_check_triggers()` method is called at the start of `_physics_process`.
    *   When a trigger fires, it interrupts the `PlanExecutor`'s plan and sets a new `current_action`.
    *   The unit now signals when it becomes idle after a triggered action, allowing `ServerGameState` to request a new plan.

### Phase 4: System-Wide Cleanup & Final Integration (Completed)

*   **Goal**: Ensure all specialized unit scripts conform to the new state-driven model and that the system is robust.
*   **Status**: The system is now fully integrated. `Unit.gd` is the single source of truth for its actions and trigger evaluations. `PlanExecutor.gd` is a lean sequencer. All specialized units correctly signal action completion.
*   **`scripts/ai/plan_executor.gd`**:
    *   The script is now a lean, clean plan sequencer.
*   **Specialized Unit Scripts** (`scout_unit.gd`, `tank_unit.gd`, etc.):
    *   All ability methods have been reviewed to ensure they correctly fail-fast and signal action completion, preventing units from getting stuck.
    *   This ensures the `PlanExecutor` can reliably advance to the next step in a plan.

## 3. Expected Improvements

*   **Reduced Bugs**: Eliminates race conditions caused by two systems trying to control unit state.
*   **More Responsive AI**: Units will react instantly to triggers (like taking damage) instead of waiting for the `PlanExecutor`'s next evaluation cycle.
*   **Cleaner Code**: Centralizing action logic in the `Unit` class makes the system more modular and easier to understand. `PlanExecutor` becomes a pure "plan sequencer."
*   **Easier to Extend**: Adding new actions or triggers will primarily involve modifying the `Unit` class and its subclasses, rather than multiple disconnected systems.