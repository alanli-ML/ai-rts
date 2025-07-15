# Two-Tier AI Control System Implementation Specification

## 📋 Overview

This document provides a comprehensive specification for implementing a sophisticated **Two-Tier AI Control System** with **Dynamic Action Triggers** for the AI-RTS game. The system automatically determines between strategic squad-level coordination (Tier 1) and tactical individual unit control (Tier 2) based on selection context and spatial analysis.

## 🎯 System Architecture

### Core Principles
- **Intelligent Command Routing**: Automatic tier selection based on unit distribution and count
- **Dynamic Formation Generation**: LLM-driven spatial positioning instead of hard-coded formations  
- **Emergent Tactical Intelligence**: Context-aware trigger responses tailored to individual circumstances
- **Scalable Performance**: Efficient trigger evaluation and plan execution

### Decision Matrix for Tier Selection
```gdscript
# Tier 1 (Squad Commander) Conditions:
- Multiple unit groups with distance > 25m between groups
- Mixed unit archetypes requiring coordination
- Strategic objectives involving multiple positions
- Unit count > 5 selected

# Tier 2 (Individual Specialists) Conditions:  
- Single cluster of units (distance < 15m)
- Uniform archetype selection
- Tactical micro-management scenarios
- Unit count ≤ 3 selected
```

## 🔧 Core Data Structures

### 1. Trigger Condition System

```gdscript
# TriggerCondition.gd
class_name TriggerCondition
extends RefCounted

enum ConditionType {
    HEALTH_PERCENTAGE,
    ENERGY_LEVEL,
    ENEMY_DISTANCE,
    ALLY_DISTANCE,
    ENEMY_COUNT,
    ALLY_COUNT,
    TIME_ELAPSED,
    AMMO_COUNT,
    UNDER_FIRE,
    IN_COVER,
    FLANKED,
    OUTNUMBERED,
    MORALE_LEVEL,
    ARCHETYPE_SPECIFIC
}

enum ComparisonOperator {
    LESS_THAN,
    GREATER_THAN,
    LESS_EQUAL,
    GREATER_EQUAL,
    EQUAL,
    NOT_EQUAL,
    BETWEEN,
    IN_LIST,
    CHANGED_BY
}

enum LogicalOperator {
    AND,
    OR,
    NOT
}

var condition_type: ConditionType
var operator: ComparisonOperator
var threshold_value: float
var secondary_threshold: float  # For BETWEEN operations
var string_value: String        # For string comparisons
var list_values: Array         # For IN_LIST operations

# Compound condition support
var logical_operator: LogicalOperator = LogicalOperator.AND
var child_conditions: Array[TriggerCondition] = []

func evaluate(unit: Unit, context: Dictionary) -> bool:
    match condition_type:
        ConditionType.HEALTH_PERCENTAGE:
            return _compare_value(unit.get_health_percentage() * 100, threshold_value)
        ConditionType.ENEMY_DISTANCE:
            var nearest_enemy_dist = _get_nearest_enemy_distance(unit)
            return _compare_value(nearest_enemy_dist, threshold_value)
        # ... additional condition evaluations
    
    return false

func _compare_value(value: float, threshold: float) -> bool:
    match operator:
        ComparisonOperator.LESS_THAN:
            return value < threshold
        ComparisonOperator.GREATER_THAN:
            return value > threshold
        # ... additional operators
    
    return false
```

### 2. Action Definition System

```gdscript
# UnitAction.gd
class_name UnitAction
extends RefCounted

enum ActionType {
    MOVEMENT,
    COMBAT,
    ABILITY,
    FORMATION,
    COORDINATION
}

enum ActionCategory {
    IMMEDIATE,      # Execute instantly
    DURATION_BASED, # Execute for specified time
    CONDITION_BASED # Execute until condition met
}

var action_name: String
var action_type: ActionType
var category: ActionCategory
var required_parameters: Array[String]
var optional_parameters: Dictionary
var energy_cost: float
var cooldown_duration: float
var execution_duration: float
var archetype_restrictions: Array[String]
var prerequisites: Array[TriggerCondition]

# Execution context
var execution_priority: int = 1
var can_interrupt: bool = true
var can_be_interrupted: bool = true
var parallel_execution: bool = false

func validate_parameters(params: Dictionary) -> Dictionary:
    var result = {"valid": true, "errors": []}
    
    # Check required parameters
    for required_param in required_parameters:
        if not params.has(required_param):
            result.valid = false
            result.errors.append("Missing required parameter: " + required_param)
    
    return result

func calculate_execution_time(params: Dictionary) -> float:
    match category:
        ActionCategory.IMMEDIATE:
            return 0.0
        ActionCategory.DURATION_BASED:
            return params.get("duration", execution_duration)
        ActionCategory.CONDITION_BASED:
            return -1.0  # Unknown duration
    
    return execution_duration
```

### 3. Action Trigger System

```gdscript
# ActionTrigger.gd
class_name ActionTrigger
extends RefCounted

var trigger_id: String
var trigger_condition: TriggerCondition
var response_action: UnitAction
var action_parameters: Dictionary
var trigger_priority: int
var speech_text: String
var prerequisite_conditions: Array[TriggerCondition]
var cooldown_remaining: float = 0.0
var max_retries: int = 3
var retry_count: int = 0

# Evaluation state
var last_evaluation_time: float = 0.0
var last_evaluation_result: bool = false
var evaluation_frequency: float = 0.1  # 10Hz

func evaluate_trigger(unit: Unit, context: Dictionary) -> bool:
    var current_time = Time.get_ticks_msec() / 1000.0
    
    # Throttle evaluation frequency
    if current_time - last_evaluation_time < evaluation_frequency:
        return last_evaluation_result
    
    # Check cooldown
    if cooldown_remaining > 0:
        return false
    
    # Check prerequisites
    for prerequisite in prerequisite_conditions:
        if not prerequisite.evaluate(unit, context):
            return false
    
    # Evaluate main condition
    last_evaluation_time = current_time
    last_evaluation_result = trigger_condition.evaluate(unit, context)
    
    return last_evaluation_result

func execute_trigger(unit: Unit, plan_executor: PlanExecutor) -> bool:
    if cooldown_remaining > 0:
        return false
    
    # Create plan step from trigger
    var step_data = {
        "action": response_action.action_name,
        "params": action_parameters,
        "speech": speech_text,
        "trigger": trigger_condition.to_string(),
        "priority": trigger_priority,
        "cooldown": response_action.cooldown_duration
    }
    
    # Execute through plan executor
    var success = plan_executor.execute_trigger_action(unit.unit_id, step_data)
    
    if success:
        cooldown_remaining = response_action.cooldown_duration
        retry_count = 0
    else:
        retry_count += 1
    
    return success
```

### 4. Tier Selection Logic

```gdscript
# TierSelector.gd
class_name TierSelector
extends RefCounted

enum ControlTier {
    SQUAD_COMMANDER,    # Tier 1: Strategic coordination
    INDIVIDUAL_SPECIALIST # Tier 2: Tactical micro-management
}

const CLUSTER_DISTANCE_THRESHOLD = 15.0
const GROUP_SEPARATION_THRESHOLD = 25.0
const LARGE_GROUP_THRESHOLD = 5

static func determine_control_tier(selected_units: Array[Unit]) -> ControlTier:
    if selected_units.size() <= 1:
        return ControlTier.INDIVIDUAL_SPECIALIST
    
    # Check for large groups
    if selected_units.size() > LARGE_GROUP_THRESHOLD:
        return ControlTier.SQUAD_COMMANDER
    
    # Analyze spatial distribution
    var unit_clusters = _analyze_unit_clustering(selected_units)
    
    # Multiple separated clusters = squad command
    if unit_clusters.size() > 1:
        var max_cluster_distance = _calculate_max_cluster_distance(unit_clusters)
        if max_cluster_distance > GROUP_SEPARATION_THRESHOLD:
            return ControlTier.SQUAD_COMMANDER
    
    # Check archetype diversity
    var archetypes = _get_unique_archetypes(selected_units)
    if archetypes.size() >= 3:
        return ControlTier.SQUAD_COMMANDER
    
    # Default to individual specialist control
    return ControlTier.INDIVIDUAL_SPECIALIST

static func _analyze_unit_clustering(units: Array[Unit]) -> Array[Array]:
    var clusters: Array[Array] = []
    var processed_units = {}
    
    for unit in units:
        if processed_units.has(unit.unit_id):
            continue
        
        var cluster = [unit]
        processed_units[unit.unit_id] = true
        
        # Find nearby units for this cluster
        for other_unit in units:
            if processed_units.has(other_unit.unit_id):
                continue
            
            var distance = unit.global_position.distance_to(other_unit.global_position)
            if distance <= CLUSTER_DISTANCE_THRESHOLD:
                cluster.append(other_unit)
                processed_units[other_unit.unit_id] = true
        
        clusters.append(cluster)
    
    return clusters
```

### 5. Enhanced Prompt Generation

```gdscript
# PromptGenerator.gd
class_name PromptGenerator
extends RefCounted

const TIER_1_PROMPT_TEMPLATE = """
You are a SQUAD COMMANDER coordinating multiple unit groups in tactical situations.

CURRENT SITUATION:
- Command Scope: {unit_count} units across {cluster_count} groups
- Unit Distribution: {unit_clusters}
- Available Archetypes: {archetypes}
- Tactical Context: {tactical_situation}

STRATEGIC OBJECTIVES:
- Coordinate multiple unit groups for maximum effectiveness
- Assign formations and positioning based on terrain and enemy positions
- Synchronize multi-group maneuvers and timing
- Adapt strategy based on battlefield developments

UNIT GROUPS:
{unit_group_details}

ENVIRONMENTAL CONTEXT:
{environmental_data}

Provide strategic coordination with formations and synchronized actions.
"""

const TIER_2_PROMPT_TEMPLATE = """
You are controlling {archetype} specialists in close tactical coordination.

UNIT CONTEXT:
{individual_unit_details}

TACTICAL ENVIRONMENT:
- Immediate Threats: {immediate_threats}
- Tactical Opportunities: {tactical_opportunities}
- Team Coordination: {nearby_allies}

ARCHETYPE CAPABILITIES:
{archetype_abilities}

CURRENT TRIGGERS:
Each unit should have 2 triggered actions based on battlefield analysis:
{suggested_triggers}

Provide individual unit control with precise triggers and responses.
"""

static func generate_prompt(tier: TierSelector.ControlTier, context: Dictionary) -> String:
    match tier:
        TierSelector.ControlTier.SQUAD_COMMANDER:
            return TIER_1_PROMPT_TEMPLATE.format(context)
        TierSelector.ControlTier.INDIVIDUAL_SPECIALIST:
            return TIER_2_PROMPT_TEMPLATE.format(context)
    
    return ""
```

## ⚙️ Processing Logic

### 1. Command Processing Pipeline

```gdscript
# Enhanced AICommandProcessor
func process_command_enhanced(command_text: String, selected_units: Array[Unit]) -> void:
    # Step 1: Analyze selection context
    var spatial_analysis = _analyze_unit_spatial_distribution(selected_units)
    var control_tier = TierSelector.determine_control_tier(selected_units)
    
    # Step 2: Generate contextual prompt
    var context = _build_enhanced_context(selected_units, spatial_analysis)
    var prompt = PromptGenerator.generate_prompt(control_tier, context)
    
    # Step 3: Process based on tier
    match control_tier:
        TierSelector.ControlTier.SQUAD_COMMANDER:
            await _process_squad_command(command_text, selected_units, prompt)
        TierSelector.ControlTier.INDIVIDUAL_SPECIALIST:
            await _process_individual_command(command_text, selected_units, prompt)

func _build_enhanced_context(units: Array[Unit], spatial_analysis: Dictionary) -> Dictionary:
    var context = {
        "unit_count": units.size(),
        "cluster_count": spatial_analysis.clusters.size(),
        "unit_clusters": spatial_analysis.cluster_info,
        "archetypes": _get_archetype_summary(units),
        "tactical_situation": _analyze_tactical_situation(units),
        "environmental_data": _get_environmental_context(units),
        "individual_unit_details": _get_individual_unit_context(units),
        "immediate_threats": _identify_immediate_threats(units),
        "tactical_opportunities": _identify_tactical_opportunities(units),
        "nearby_allies": _get_nearby_allies_context(units),
        "archetype_abilities": _get_archetype_abilities_summary(units),
        "suggested_triggers": _generate_suggested_triggers(units)
    }
    
    return context
```

### 2. Trigger Evaluation Engine

```gdscript
# TriggerEvaluationEngine.gd
class_name TriggerEvaluationEngine
extends Node

var active_triggers: Dictionary = {}  # unit_id -> Array[ActionTrigger]
var evaluation_timer: Timer
var evaluation_frequency: float = 0.1  # 10Hz

func _ready():
    evaluation_timer = Timer.new()
    evaluation_timer.wait_time = evaluation_frequency
    evaluation_timer.timeout.connect(_evaluate_all_triggers)
    evaluation_timer.autostart = true
    add_child(evaluation_timer)

func register_unit_triggers(unit_id: String, triggers: Array[ActionTrigger]):
    active_triggers[unit_id] = triggers
    print("TriggerEngine: Registered %d triggers for unit %s" % [triggers.size(), unit_id])

func _evaluate_all_triggers():
    for unit_id in active_triggers:
        var unit = _get_unit(unit_id)
        if not unit:
            continue
        
        var unit_triggers = active_triggers[unit_id]
        var context = _build_evaluation_context(unit)
        
        # Sort triggers by priority
        unit_triggers.sort_custom(func(a, b): return a.trigger_priority > b.trigger_priority)
        
        for trigger in unit_triggers:
            if trigger.evaluate_trigger(unit, context):
                var plan_executor = _get_plan_executor()
                if plan_executor:
                    trigger.execute_trigger(unit, plan_executor)
                    break  # Execute only highest priority trigger

func _build_evaluation_context(unit: Unit) -> Dictionary:
    return {
        "visible_enemies": unit.visible_enemies,
        "visible_allies": unit.visible_allies,
        "current_time": Time.get_ticks_msec() / 1000.0,
        "unit_state": unit.current_state,
        "team_id": unit.team_id,
        "position": unit.global_position
    }
```

### 3. Formation Generation Logic

```gdscript
# DynamicFormationGenerator.gd
class_name DynamicFormationGenerator
extends RefCounted

static func generate_formation_positions(units: Array[Unit], formation_intent: String, context: Dictionary) -> Dictionary:
    var formation_data = {
        "formation_type": "adaptive",
        "unit_positions": {},
        "formation_center": _calculate_formation_center(units),
        "reasoning": ""
    }
    
    # Analyze tactical context
    var enemy_positions = context.get("enemy_positions", [])
    var cover_positions = context.get("cover_positions", [])
    var terrain_data = context.get("terrain_data", {})
    
    # Generate positions based on intent and context
    match formation_intent:
        "defensive":
            formation_data.unit_positions = _generate_defensive_positions(units, enemy_positions, cover_positions)
            formation_data.reasoning = "Defensive positioning with cover utilization"
        
        "offensive":
            formation_data.unit_positions = _generate_offensive_positions(units, enemy_positions, terrain_data)
            formation_data.reasoning = "Aggressive positioning for coordinated assault"
        
        "flanking":
            formation_data.unit_positions = _generate_flanking_positions(units, enemy_positions)
            formation_data.reasoning = "Multi-directional approach for flanking maneuver"
        
        "retreat":
            formation_data.unit_positions = _generate_retreat_positions(units, enemy_positions)
            formation_data.reasoning = "Strategic withdrawal with covering fire"
        
        _:
            formation_data.unit_positions = _generate_adaptive_positions(units, context)
            formation_data.reasoning = "Adaptive positioning based on current situation"
    
    return formation_data

static func _generate_defensive_positions(units: Array[Unit], enemies: Array, cover: Array) -> Dictionary:
    var positions = {}
    var center_point = _calculate_average_position(units)
    
    # Prioritize cover positions
    var available_cover = cover.duplicate()
    
    for i in range(units.size()):
        var unit = units[i]
        var position = center_point
        
        # Assign cover positions to vulnerable units first
        if unit.archetype in ["medic", "sniper", "engineer"] and not available_cover.is_empty():
            position = available_cover.pop_front()
        else:
            # Generate defensive line positions
            var angle = (i * 2.0 * PI) / units.size()
            var radius = 8.0 + (i * 2.0)  # Staggered distances
            position = center_point + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
        
        positions[unit.unit_id] = position
    
    return positions
```

## 📋 Implementation Plan

### Phase 1: Core Infrastructure (Week 1-2)

#### 1.1 Data Structure Implementation
- [ ] **TriggerCondition Class**: Complete condition evaluation system
- [ ] **UnitAction Class**: Action definition and validation framework  
- [ ] **ActionTrigger Class**: Trigger-response binding system
- [ ] **TierSelector Class**: Intelligent tier selection logic

#### 1.2 Integration Points
- [ ] **Enhanced AICommandProcessor**: Integrate tier selection logic
- [ ] **PlanExecutor Enhancement**: Add trigger execution capabilities
- [ ] **Unit Class Extensions**: Add trigger registration and management
- [ ] **EventBus Extensions**: Add trigger evaluation events

### Phase 2: Trigger System (Week 3-4)

#### 2.1 Trigger Evaluation Engine
- [ ] **TriggerEvaluationEngine**: Real-time trigger monitoring
- [ ] **Performance Optimization**: Efficient 10Hz evaluation system
- [ ] **Priority Management**: Trigger conflict resolution
- [ ] **Memory Management**: Cleanup and garbage collection

#### 2.2 Default Trigger Sets
- [ ] **Scout Triggers**: Stealth, retreat, and reconnaissance triggers
- [ ] **Sniper Triggers**: Positioning, overwatch, and target acquisition
- [ ] **Medic Triggers**: Healing priorities and safety protocols
- [ ] **Engineer Triggers**: Construction, repair, and utility triggers
- [ ] **Tank Triggers**: Protection, aggression, and positioning

### Phase 3: Enhanced Prompt Generation (Week 5-6)

#### 3.1 Context Analysis Systems
- [ ] **Spatial Analysis Engine**: Unit clustering and distribution analysis
- [ ] **Tactical Situation Assessment**: Threat and opportunity identification
- [ ] **Environmental Context Builder**: Terrain and map feature analysis
- [ ] **Archetype Capability Database**: Dynamic ability reference system

#### 3.2 Tier-Specific Prompts
- [ ] **Squad Commander Prompts**: Multi-group coordination templates
- [ ] **Individual Specialist Prompts**: Archetype-specific tactical templates
- [ ] **Dynamic Context Injection**: Real-time battlefield data integration
- [ ] **Trigger Suggestion System**: AI-recommended trigger configurations

### Phase 4: Formation Generation (Week 7-8)

#### 4.1 Dynamic Formation System
- [ ] **DynamicFormationGenerator**: Adaptive positioning algorithms
- [ ] **Terrain Integration**: Cover and obstacle consideration
- [ ] **Enemy Analysis**: Counter-positioning strategies
- [ ] **Multi-Objective Optimization**: Balance between offense, defense, and mobility

#### 4.2 Formation Execution
- [ ] **Position Calculation**: Precise unit positioning algorithms
- [ ] **Movement Coordination**: Synchronized formation transitions
- [ ] **Collision Avoidance**: Unit pathfinding within formations
- [ ] **Formation Maintenance**: Dynamic position adjustment

### Phase 5: Testing & Optimization (Week 9-10)

#### 5.1 System Integration Testing
- [ ] **End-to-End Testing**: Complete command pipeline validation
- [ ] **Performance Testing**: Latency and memory usage optimization
- [ ] **Error Handling**: Graceful degradation and recovery
- [ ] **Concurrent Operation**: Multi-unit plan execution testing

#### 5.2 AI Quality Assurance
- [ ] **Trigger Response Quality**: Intelligent and contextual reactions
- [ ] **Formation Effectiveness**: Tactical positioning validation
- [ ] **Decision Making**: Tier selection accuracy testing
- [ ] **Player Experience**: Intuitive and responsive AI behavior

### Phase 6: Production Readiness (Week 11-12)

#### 6.1 Documentation & Configuration
- [ ] **System Documentation**: Complete technical documentation
- [ ] **Configuration System**: Tunable parameters for game balance
- [ ] **Debug Tools**: Trigger visualization and analysis tools
- [ ] **Performance Monitoring**: Real-time system health monitoring

#### 6.2 Deployment Preparation
- [ ] **Code Review**: Complete codebase review and optimization
- [ ] **Memory Optimization**: Final memory usage optimization
- [ ] **Network Integration**: Multiplayer synchronization
- [ ] **Final Testing**: Comprehensive system validation

## 🎯 Success Metrics

### Technical Metrics
- **Trigger Evaluation Latency**: < 10ms per unit per evaluation
- **Plan Execution Latency**: < 100ms for immediate actions
- **Memory Usage**: < 50MB for complete trigger system
- **Concurrent Plans**: Support for 20+ active plans simultaneously

### Gameplay Metrics
- **Response Intelligence**: Contextually appropriate trigger responses 95%+ of time
- **Formation Effectiveness**: Improved tactical positioning in 80%+ of situations
- **Player Satisfaction**: Intuitive and responsive AI behavior
- **Emergent Behavior**: Unpredictable but logical tactical adaptations

## 🚀 Advanced Features (Future Extensions)

### Machine Learning Integration
- **Trigger Pattern Learning**: AI learns optimal trigger configurations from gameplay
- **Formation Optimization**: ML-driven formation effectiveness analysis
- **Player Behavior Adaptation**: AI adapts to individual player tactics

### Dynamic Content Generation
- **Procedural Triggers**: Dynamically generated triggers based on map and situation
- **Adaptive Abilities**: Context-specific ability modifications
- **Emergent Tactics**: AI-discovered tactical combinations

This specification provides the complete framework for implementing a sophisticated, emergent AI control system that will revolutionize RTS gameplay through intelligent, context-aware unit behavior and strategic coordination. 