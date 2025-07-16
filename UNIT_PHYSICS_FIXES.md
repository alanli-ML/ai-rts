# Unit Physics Fixes - Flying Units Issue

This document outlines the critical fixes applied to resolve units flying into the air when walking.

## Issues Addressed

### 1. Units Flying When Walking ✅ FIXED
**Problem**: Units were floating/flying into the air instead of walking on the ground

**Root Cause**: Missing gravity implementation in CharacterBody3D movement system

### 2. Script Loading Errors 
**Problem**: 
```
SCRIPT ERROR: Parse Error: The member "weapon_attachment" already exists in parent class Unit.
SCRIPT ERROR: Could not resolve class "AnimatedUnit".
```

**Root Cause**: Duplicate member declaration and class loading cascade failures

## Critical Fixes Applied

### 1. Gravity Physics Implementation (`scripts/core/unit.gd`)

**Before (Broken)**:
```gdscript
velocity = direction * movement_speed
move_and_slide()
```

**After (Fixed)**:
```gdscript
# Apply gravity
if not is_on_floor():
    velocity.y += get_gravity().y * delta

if navigation_agent and not navigation_agent.is_navigation_finished():
    var next_pos = navigation_agent.get_next_path_position()
    var direction = global_position.direction_to(next_pos)
    # Only modify X and Z for horizontal movement, preserve Y for gravity
    velocity.x = direction.x * movement_speed
    velocity.z = direction.z * movement_speed
else:
    # Stop horizontal movement but preserve gravity
    velocity.x = 0
    velocity.z = 0

# Always call move_and_slide to apply physics
move_and_slide()
```

**Key Changes**:
- **Gravity Application**: Added proper gravity handling using `get_gravity().y * delta`
- **Velocity Separation**: Separated horizontal (X,Z) and vertical (Y) velocity components
- **Continuous Physics**: Always call `move_and_slide()` to apply physics properly
- **Floor Detection**: Use `is_on_floor()` to only apply gravity when needed

### 2. Fixed Class Loading Issues (`scripts/units/animated_unit.gd`)

**Problem**: Duplicate `weapon_attachment` declaration
```gdscript
var weapon_attachment: Node3D  # Already exists in parent Unit class!
```

**Solution**: Removed duplicate declaration and added safety check
```gdscript
func _attach_weapon():
    # Get weapon attachment from parent Unit class
    if not weapon_attachment:
        var WeaponAttachmentScene = preload("res://scenes/units/WeaponAttachment.tscn")
        weapon_attachment = WeaponAttachmentScene.instantiate()
        # ... rest of attachment logic
```

## Why Units Were Flying

### CharacterBody3D Physics in Godot 4
- **Manual Gravity**: Unlike RigidBody3D, CharacterBody3D requires manual gravity implementation
- **Velocity Management**: Must separate horizontal movement from gravity
- **Continuous Physics**: `move_and_slide()` must be called every frame

### Previous Broken Behavior
1. Units set `velocity = direction * movement_speed` (only horizontal)
2. No gravity applied to `velocity.y`
3. Units would maintain their Y position or float upward
4. Navigation would work horizontally but ignore vertical physics

### Fixed Behavior  
1. **Gravity Constantly Applied**: `velocity.y += gravity * delta` when not on floor
2. **Horizontal Movement Preserved**: Only X,Z components modified for navigation
3. **Physics Always Active**: `move_and_slide()` called every frame
4. **Ground Detection**: `is_on_floor()` prevents over-application of gravity

## Expected Results

### Before Fix:
- Units floating/flying when moving
- No ground collision physics
- Erratic vertical movement

### After Fix:
- Units walk naturally on the ground
- Proper gravity and collision physics
- Smooth ground-based movement
- Units can walk up/down slopes properly

## Technical Notes

### Godot 4 CharacterBody3D Requirements
- Must manually handle gravity via `velocity.y`
- Must call `move_and_slide()` for physics simulation
- Must use `is_on_floor()` for ground detection
- Must preserve existing velocity components when modifying movement

### Performance Considerations
- Gravity calculation is lightweight (`velocity.y += gravity * delta`)
- `move_and_slide()` handles collision detection efficiently
- Floor detection prevents unnecessary gravity application

### Multiplayer Compatibility
- Server-authoritative movement maintained
- Client prediction can use same physics
- Network-friendly velocity synchronization

## Testing Steps

1. **Start Game**: Launch and join a match
2. **Spawn Units**: Create units for both teams  
3. **Movement Test**: Units should walk naturally on ground
4. **Slope Test**: Units should handle elevation changes properly
5. **Combat Test**: Units should remain grounded during combat

## Future Improvements

1. **Jump Mechanics**: Add optional jump ability with gravity
2. **Slope Limits**: Configure maximum walkable slope angles
3. **Physics Materials**: Add different ground friction types
4. **Flying Units**: Special handling for air units (disable gravity)

The implemented fixes ensure all ground-based units now have proper physics and gravity, resolving the flying units issue completely. 