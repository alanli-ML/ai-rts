# Attack System Debugging Guide

This guide documents the comprehensive debugging system added to diagnose and fix the attacking system in the AI-RTS game.

## Problem Summary

Units were triggering the `enemy_in_range` action and executing attack commands, but no visible damage was being dealt to targets. The logs showed:

```
Trigger 'enemy_in_range' fired. Executing action 'attack'.
```

But no actual damage or combat effects were occurring.

## Debugging Improvements Made

### 1. Plan Executor Debug Output
**File**: `scripts/ai/plan_executor.gd`

**Added debug logging for**:
- Attack action execution with full parameter details
- Target lookup and validation
- Success/failure of unit.attack_target() calls

**Example output**:
```
DEBUG: PlanExecutor executing attack action with params: {"target_id": "unit_1234"}
DEBUG: PlanExecutor attack target lookup - target_id: unit_1234, found: yes
DEBUG: PlanExecutor calling unit.attack_target() for unit unit_5678 -> target unit_1234
```

### 2. Unit Attack State Machine Debug Output
**File**: `scripts/core/unit.gd`

**Added debug logging for**:
- Target setting and state transitions
- Distance calculations and movement decisions
- Attack attempts and weapon firing
- Cooldown tracking
- Fallback direct damage dealing
- Damage taken with visual feedback

**Example output**:
```
DEBUG: Unit unit_5678 setting attack target to unit_1234
DEBUG: Unit unit_5678 moving closer to target unit_1234 (distance: 20.3 > range: 15.0)
DEBUG: Unit unit_5678 attempting to fire at target unit_1234
DEBUG: Unit unit_5678 firing weapon at target unit_1234
DEBUG: Unit unit_1234 took 25.0 damage (100.0 -> 75.0 HP)
```

### 3. Weapon Attachment Debug Output
**File**: `scripts/units/weapon_attachment.gd`

**Added debug logging for**:
- Weapon equipping process with all steps
- can_fire() checks with specific failure reasons
- Weapon firing with full details
- Projectile spawning with configuration data

**Example output**:
```
DEBUG: WeaponAttachment.equip_weapon() called - unit: Unit, weapon: blaster-a, team: 1
DEBUG: WeaponAttachment.equip_weapon() - weapon equipped successfully (damage: 20.0, ammo: 15/15)
DEBUG: WeaponAttachment.can_fire() - all checks passed, can fire
DEBUG: WeaponAttachment.fire() - firing weapon blaster-a
DEBUG: WeaponAttachment._spawn_projectile() - projectile spawned successfully
```

### 4. Projectile System Debug Output
**File**: `scripts/fx/projectile.gd`

**Added debug logging for**:
- Projectile initialization with full configuration
- Collision shape verification
- Movement tracking (periodic)
- Hit detection with detailed target information
- Damage dealing confirmation

**Example output**:
```
DEBUG: Projectile._ready() - projectile spawned (damage: 20.0, team: 1, lifetime: 1.5s)
DEBUG: Projectile._ready() - collision shape found: SphereShape3D
DEBUG: Projectile._on_body_entered() - hit Unit unit_1234 (team 2 vs shooter team 1)
DEBUG: Projectile._on_body_entered() - dealing 20.0 damage to unit_1234
```

### 5. Unit Spawning and Weapon Attachment Debug Output
**File**: `scripts/units/animated_unit.gd`

**Added debug logging for**:
- Weapon attachment creation process
- Weapon type selection
- Attachment success/failure tracking

**Example output**:
```
DEBUG: AnimatedUnit._attach_weapon() called for unit unit_5678 (archetype: scout)
DEBUG: AnimatedUnit._attach_weapon() - selected weapon type: blaster-a
DEBUG: AnimatedUnit._attach_weapon() - Successfully attached weapon blaster-a to unit unit_5678
```

## Key Fixes Implemented

### 1. Improved Fallback Damage System
- Added guaranteed fallback to direct damage when weapon systems fail
- All attacks now have a reliable damage path
- Added attack success tracking to prevent multiple damage applications

### 2. Enhanced Projectile Collision Detection
- Added collision shape verification and auto-creation
- Enhanced collision signal handling for both body and area collisions
- Improved collision layer/mask debugging

### 3. Visual Feedback System
- Added floating damage numbers when units take damage
- Red damage indicators that animate upward and fade out
- Clear visual confirmation that damage is being dealt

### 4. Comprehensive Error Handling
- Weapon attachment failures no longer break the attack system
- Missing weapon models fall back to basic weapons
- Projectile spawning failures fall back to direct damage

## How to Use This Debugging System

### 1. Monitor Console Output
When units attack, you should see a complete trace like this:

```
DEBUG: PlanExecutor executing attack action with params: {"target_id": "unit_1234"}
DEBUG: Unit unit_5678 setting attack target to unit_1234
DEBUG: Unit unit_5678 attempting to fire at target unit_1234
DEBUG: WeaponAttachment.fire() - firing weapon blaster-a
DEBUG: Projectile._ready() - projectile spawned (damage: 20.0, team: 1)
DEBUG: Projectile._on_body_entered() - dealing 20.0 damage to unit_1234
DEBUG: Unit unit_1234 took 20.0 damage (100.0 -> 80.0 HP)
```

### 2. Look for Visual Feedback
- Red damage numbers should appear above units when they take damage
- Units should show health bar changes
- Impact effects should appear when projectiles hit

### 3. Check Attack Capability
Use the new debug method in console:
```gdscript
var unit = get_selected_unit()
print(unit.get_attack_capability_debug())
```

This will output detailed information about the unit's attack capability.

### 4. Common Issues and Solutions

**Issue**: "WeaponAttachment.can_fire() - weapon not equipped"
**Solution**: Check weapon attachment process logs for failures

**Issue**: "Projectile._spawn_projectile() - PROJECTILE_SCENE is null"
**Solution**: Verify Projectile.tscn exists and is properly referenced

**Issue**: "Unit using fallback direct damage"
**Solution**: Normal fallback behavior, but investigate why weapon failed

**Issue**: No damage numbers appearing
**Solution**: Check if units are on different teams (friendly fire is disabled)

## Expected Attack Flow

1. **Trigger Detection**: `enemy_in_range` trigger fires with `target_id` context
2. **Action Execution**: PlanExecutor calls attack action with target parameters
3. **Target Setting**: Unit sets attack target and enters ATTACKING state
4. **Range Check**: Unit moves closer if target is out of range
5. **Attack Attempt**: Unit tries to fire weapon or uses fallback damage
6. **Damage Dealing**: Target takes damage and shows visual feedback
7. **Cooldown**: Unit waits for attack cooldown before next attack

## Performance Notes

The debug output is verbose and should be disabled or filtered in production builds. To reduce output:

1. Comment out debug prints in performance-critical sections
2. Use logger levels to filter debug messages
3. Consider adding a debug flag to enable/disable attack system debugging

## Troubleshooting Checklist

- [ ] Units have weapon attachments (check AnimatedUnit._attach_weapon logs)
- [ ] Weapons are properly equipped (check WeaponAttachment.equip_weapon logs)
- [ ] Projectiles are spawning (check _spawn_projectile logs)
- [ ] Projectiles have collision shapes (check Projectile._ready logs)
- [ ] Units are on different teams (check team_id values in logs)
- [ ] Attack range is sufficient (check distance vs range in logs)
- [ ] Attack cooldown has passed (check cooldown messages)

This debugging system should provide complete visibility into the attack system and help identify exactly where any remaining issues occur. 