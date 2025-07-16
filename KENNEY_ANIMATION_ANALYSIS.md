# Kenney Blocky Characters Animation Analysis

This document provides a comprehensive analysis of available animations in the Kenney Blocky Characters pack.

## Key Findings

### ❌ **Missing Animations**
- **"Run"** - This animation does NOT exist in any Kenney character model
- **"Running"** - This is also not available
- This was causing all the `WARN: Animation 'Run' not found` errors

### ✅ **Available Movement Animations** 
All 18 character models (character-a.glb through character-r.glb) contain **identical animation sets**:

#### **Movement & Locomotion**
- `walk` (0.67s, 8 tracks) - Standard walking animation
- `sprint` (0.50s, 8 tracks) - Fast movement animation  
- `idle` (1.33s, 8 tracks) - Default standing animation
- `static` (0.10s, 8 tracks) - Motionless pose

#### **Combat Animations**
- `attack-kick-left` (0.58s) - Left leg kick attack
- `attack-kick-right` (0.58s) - Right leg kick attack  
- `attack-melee-left` (0.42s) - Left hand melee attack
- `attack-melee-right` (0.42s) - Right hand melee attack
- `die` (0.33s) - Death animation

#### **Weapon Handling**
- `holding-both` (0.17s) - Two-handed weapon pose
- `holding-both-shoot` (0.20s) - Two-handed shooting
- `holding-left` (0.17s) - Left-handed weapon pose
- `holding-left-shoot` (0.20s) - Left-handed shooting
- `holding-right` (0.17s) - Right-handed weapon pose
- `holding-right-shoot` (0.20s) - Right-handed shooting

#### **Interaction Animations**
- `interact-left` (0.67s) - Left hand interaction
- `interact-right` (0.67s) - Right hand interaction
- `pick-up` (0.33s) - Object pickup animation
- `emote-yes` (0.67s) - Nodding agreement
- `emote-no` (0.67s) - Shaking head disagreement

#### **Specialized Animations**
- `sit` (0.17s) - Sitting pose
- `drive` (0.17s) - Driving pose
- `wheelchair-sit` (0.17s) - Wheelchair sitting
- `wheelchair-move-forward/back/left/right` (0.50s each) - Wheelchair movement

## Animation Mapping Solution

### **Fixed Animation Fallback System**

The `play_animation()` function now uses a comprehensive mapping system:

```gdscript
var animation_mappings = {
    "Run": ["sprint", "walk"],        # Use sprint as primary, walk as fallback
    "Walk": ["walk", "sprint"],       # Use walk as primary, sprint as fallback  
    "Idle": ["idle", "static"],       # Use idle as primary, static as fallback
    "Attack": ["holding-both-shoot", "holding-left-shoot", "holding-right-shoot", "attack-melee-left", "attack-melee-right"],
    "Die": ["die"],                   # Direct mapping to die animation
    "Death": ["die"],                 # Map Death to die for compatibility
    "Sprint": ["sprint", "walk"],     # Use sprint as primary
    "Shoot": ["holding-both-shoot", "holding-left-shoot", "holding-right-shoot"]
}
```

### **Animation Priority Logic**

1. **Exact Match** - Try the requested animation name exactly
2. **Case-Insensitive Match** - Try case variations (e.g., "Idle" → "idle")  
3. **Mapped Fallbacks** - Use the mapping table above
4. **Final Fallback** - Play the first available animation if nothing else works

## Results

### ✅ **Fixes Applied**
- **No more "Run" animation errors** - Now falls back to "sprint" then "walk"
- **All units now animate properly** during movement
- **Death animations work correctly** using "die" animation
- **Weapon animations supported** for combat units
- **Comprehensive fallback system** prevents missing animation errors

### 🎯 **Recommended Animation Usage**

For best results in your RTS game:

- **Movement**: Use `"sprint"` for fast units, `"walk"` for normal movement
- **Idle State**: Use `"idle"` for default standing
- **Combat**: Use `"holding-both-shoot"` for ranged attacks, `"attack-melee-left/right"` for melee
- **Death**: Use `"die"` for unit destruction

## Character Model Assignments

Current unit archetype assignments:
- **Scout** → `character-a.glb`
- **Tank** → `character-h.glb`  
- **Sniper** → `character-d.glb`
- **Medic** → `character-p.glb`
- **Engineer** → `character-o.glb`

All models have identical animation sets, so any character can be assigned to any role without animation compatibility issues. 