# Animation and Material Fixes for Character Models

This document outlines the fixes applied to resolve animation and material issues with the Kenney blocky character models.

## Issues Addressed

### 1. Missing "Run" Animation Errors
**Problem**: The game was trying to play a "Run" animation that didn't exist in the Kenney character models, causing repeated warnings:
```
WARN: Animation 'Run' not found.
```

**Root Cause**: The Kenney blocky character models may have different animation names than expected, or the animations weren't being imported properly.

### 2. Material Null Errors
**Problem**: Material errors were occurring during rendering:
```
ERROR: Parameter "material" is null.
   at: material_casts_shadows (servers/rendering/renderer_rd/storage_rd/material_storage.cpp:2309)
```

**Root Cause**: Some model surfaces lacked proper materials after import.

## Fixes Applied

### 1. Enhanced Animation System (`scripts/units/animated_unit.gd`)

#### Improved Animation Fallback Logic
- **Comprehensive Fallback Chain**: Added multi-tier fallback system:
  1. Exact name match
  2. Case-insensitive match  
  3. Animation name variations (Run → Running, Walk, etc.)
  4. First available animation as last resort

#### Animation Name Mappings
```gdscript
var animation_mappings = {
    "Run": ["Running", "Walk", "walking", "run", "sprint", "jog", "move"],
    "Walk": ["walking", "run", "Running", "move", "step"],
    "Idle": ["idle", "T-Pose", "TPose", "Rest", "Stand", "Default", "Armature|Idle"],
    "Attack": ["attack", "Fire", "fire", "Shoot", "shoot", "Action"],
    "Death": ["death", "Die", "die", "Dead", "Fall", "fall"]
}
```

#### Debug Information
- Added debug output to show available animations for each character model
- Model structure inspection when AnimationPlayer isn't found
- Clear logging of fallback animation usage

### 2. Material Handling Improvements

#### Automatic Material Creation
- Added `_fix_model_materials()` function to handle missing materials
- Creates fallback StandardMaterial3D with light gray color for missing materials
- Recursively checks all MeshInstance3D nodes in loaded models

#### Material Validation
- Checks both surface override materials and mesh surface materials
- Provides fallback materials to prevent null material errors
- Logs material creation for debugging

### 3. Import Settings Updates

Updated GLB import settings for all character models to improve animation import:

```
animation/remove_immutable_tracks=false  # Was: true
animation/import_rest_as_RESET=true     # Was: false
```

**Why These Changes Help**:
- **remove_immutable_tracks=false**: Preserves all animation tracks, ensuring no animations are lost during import
- **import_rest_as_RESET=true**: Better handles rest pose and improves animation blending

#### Updated Files:
- `character-a.glb.import` (Scout)
- `character-h.glb.import` (Tank)  
- `character-d.glb.import` (Sniper)
- `character-p.glb.import` (Medic)
- `character-o.glb.import` (Engineer)

### 4. Debug Utilities

#### Enhanced Unit Debug Helper (`scripts/utils/unit_debug_helper.gd`)
- **Animation Inspection**: Functions to inspect available animations in character models
- **Material Analysis**: Detailed material inspection for troubleshooting
- **Fallback Testing**: Test animation fallback system for all archetypes

#### Debug Functions:
```gdscript
inspect_all_character_animations()     # List all animations per model
debug_animation_fallbacks()           # Test fallback system
debug_materials()                     # Inspect material setup
```

## Expected Results

### Before Fixes:
```
WARN: Animation 'Run' not found.
ERROR: Parameter "material" is null.
```

### After Fixes:
```
Available animations for scout: ["Idle", "Walk", "Attack", ...]
Using fallback animation 'Walk' for 'Run'
Creating fallback material for CharacterMesh surface 0
```

## Kenney Asset Information

According to the Kenney overview, each character model should have:
- **27 animations** per character
- **143 vertices** per model
- **5 groups** per model

The models are confirmed to be animated and should contain multiple animation tracks.

## Testing & Verification

To test the fixes:

1. **Run the Game**: Start the game and spawn units
2. **Check Console**: Look for animation debug output
3. **Verify Movement**: Units should animate when moving
4. **Check Materials**: Models should render properly without null material errors

### Debug Commands (if needed):
```gdscript
# In game console or debug script:
var debug_helper = UnitDebugHelper.new()
debug_helper.debug_all_animations()
debug_helper.debug_materials()
```

## Additional Notes

- **Performance**: The fallback system adds minimal overhead and only runs when exact matches fail
- **Extensibility**: Easy to add new animation mappings for future character models
- **Robustness**: System gracefully handles missing animations and materials
- **Debugging**: Comprehensive logging helps identify animation and material issues

## Future Improvements

1. **Animation Caching**: Cache animation mappings to avoid repeated lookups
2. **Custom Animation Sets**: Support for archetype-specific animation mappings
3. **Material Templates**: Pre-defined material templates for different character types
4. **Asset Validation**: Automated validation of character model imports

The implemented fixes ensure robust animation playback and material rendering while providing clear debugging information when issues occur. 