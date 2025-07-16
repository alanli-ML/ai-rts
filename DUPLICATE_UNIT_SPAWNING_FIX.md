# Duplicate Unit Spawning Fix - Critical Server-Side Bug

This document outlines the resolution of a critical bug causing multiple instances of units to spawn on the server side.

## 🚨 **Critical Issue Identified**

### ❌ **The Problem: Units Spawned Per Player Instead of Per Team**

**Location**: `scripts/server/session_manager.gd` in `_spawn_initial_units()` function

**Root Cause**: The unit spawning logic was iterating **per player** instead of **per team**, causing duplicate units when multiple players joined the same team.

**Problematic Code**:
```gdscript
# BROKEN: Spawns units for each player individually
for player_id in session.players.keys():  # ← Loops per PLAYER
    var player = session.players[player_id]
    var team_id = player.team_id
    
    # Spawn a mixed squad for each team
    var archetypes = ["scout", "tank", "sniper", "medic", "engineer"]
    for i in range(archetypes.size()):
        var unit_id = await game_state.spawn_unit(archetype, team_id, unit_position, player_id)
        # ↑ Spawns 5 units PER PLAYER, not per team!
```

## 💥 **Impact Analysis**

### **Example Scenario**:
- **Player 1** joins → Assigned to **Team 1**
- **Player 2** joins → Assigned to **Team 1** (load balancing)
- **Player 3** joins → Assigned to **Team 2**

### **Broken Behavior**:
- **Player 1** on Team 1 → Spawns 5 units at Team 1 base
- **Player 2** on Team 1 → Spawns **5 more units** at Team 1 base
- **Player 3** on Team 2 → Spawns 5 units at Team 2 base

### **Result**:
- **Team 1**: 10 units (duplicated!)
- **Team 2**: 5 units (correct)
- **Unbalanced gameplay** with random unit counts
- **Performance degradation** from unnecessary units
- **Confusing unit management** for players

### **Scaling Problem**:
- **2 players per team** → 10 units per team
- **3 players per team** → 15 units per team  
- **4 players per team** → 20 units per team
- The more players, the worse the duplication!

## ✅ **Complete Fix Implementation**

### **New Corrected Logic**:
```gdscript
# FIXED: Spawn units once per team, regardless of player count
var teams_with_players = {}

# First, identify which teams have players
for player_id in session.players.keys():
    var player = session.players[player_id]
    var team_id = player.team_id
    if not teams_with_players.has(team_id):
        teams_with_players[team_id] = []
    teams_with_players[team_id].append(player_id)

# Then spawn units once per team, regardless of how many players are on that team
for team_id in teams_with_players.keys():
    var team_players = teams_with_players[team_id]
    var representative_player = team_players[0]  # Use first player as representative
    
    logger.info("SessionManager", "Spawning initial units for team %d with %d players" % [team_id, team_players.size()])
    
    # Spawn a mixed squad for this team (ONCE only)
    var archetypes = ["scout", "tank", "sniper", "medic", "engineer"]
    for i in range(archetypes.size()):
        var unit_id = await game_state.spawn_unit(archetype, team_id, unit_position, representative_player)
        logger.info("SessionManager", "Spawned %s unit %s for team %d at %s" % [archetype, unit_id, team_id, unit_position])
```

### **Key Changes**:
1. **Two-phase approach**: First collect teams, then spawn units
2. **Team-based iteration**: Loop over teams instead of players  
3. **Representative player**: Use first player for unit ownership tracking
4. **Clear logging**: Shows team ID and player count for debugging
5. **Balanced spawning**: Each team gets exactly 5 units regardless of player count

## 🎯 **Benefits Achieved**

### **Gameplay Balance**:
- ✅ **Equal unit counts**: Each team gets exactly 5 initial units
- ✅ **Fair matches**: No team advantage from random player distribution
- ✅ **Predictable gameplay**: Consistent starting conditions
- ✅ **Scalable multiplayer**: Works with any number of players per team

### **Performance Improvements**:
- ✅ **Reduced server load**: No duplicate unit processing
- ✅ **Lower memory usage**: Fewer unit instances in memory
- ✅ **Better network efficiency**: Fewer units to synchronize
- ✅ **Faster game startup**: Less time spent spawning duplicates

### **System Reliability**:
- ✅ **Predictable behavior**: No random unit counts based on join order
- ✅ **Easier debugging**: Clear team-based logging
- ✅ **Maintainable code**: Clean separation of team vs player logic
- ✅ **Future-proof**: Scales to any team configuration

## 📊 **Before vs After Comparison**

### **Scenario: 2 Players per Team**

| Aspect | Before (Broken) | After (Fixed) |
|--------|----------------|---------------|
| **Team 1 Units** | 10 (duplicated) | 5 (correct) |
| **Team 2 Units** | 10 (duplicated) | 5 (correct) |
| **Total Server Units** | 20 (100% overhead) | 10 (optimal) |
| **Game Balance** | ❌ Random/unfair | ✅ Equal/fair |
| **Performance** | ❌ Degraded | ✅ Optimal |

### **Scenario: 3 vs 1 Player Teams**

| Aspect | Before (Broken) | After (Fixed) |
|--------|----------------|---------------|
| **Team 1 Units** | 15 (3 players) | 5 (correct) |
| **Team 2 Units** | 5 (1 player) | 5 (correct) |
| **Balance Ratio** | 3:1 (unfair) | 1:1 (fair) |
| **Gameplay Impact** | ❌ Heavily skewed | ✅ Balanced |

## 🔧 **Technical Implementation Details**

### **Data Structure Used**:
```gdscript
teams_with_players = {
    1: ["player_1", "player_2"],  # Team 1 has 2 players
    2: ["player_3"]               # Team 2 has 1 player
}
```

### **Representative Player Selection**:
- Uses `team_players[0]` as unit owner for tracking purposes
- Maintains compatibility with existing unit ownership systems
- Ensures all team units have valid owner references

### **Logging Enhancements**:
```gdscript
logger.info("SessionManager", "Spawning initial units for team %d with %d players" % [team_id, team_players.size()])
logger.info("SessionManager", "Spawned %s unit %s for team %d at %s" % [archetype, unit_id, team_id, unit_position])
```

## 🧪 **Testing Validation**

### **Test Cases to Verify**:

1. **Single Player per Team**:
   - Team 1: 1 player → Should spawn 5 units
   - Team 2: 1 player → Should spawn 5 units

2. **Multiple Players per Team**:
   - Team 1: 3 players → Should spawn 5 units (not 15)
   - Team 2: 2 players → Should spawn 5 units (not 10)

3. **Uneven Team Distribution**:
   - Team 1: 4 players → Should spawn 5 units
   - Team 2: 1 player → Should spawn 5 units
   - Game should be balanced despite player count difference

4. **Console Output Verification**:
   - Should see "Spawning initial units for team X with Y players"
   - Should see exactly 5 spawn messages per team
   - No duplicate unit IDs should appear

## 🚀 **Deployment Impact**

### **Immediate Benefits**:
- **Existing matches**: Will have consistent unit counts going forward
- **New players**: Will experience balanced gameplay from first match
- **Server performance**: Immediate reduction in duplicate processing
- **Network traffic**: Lower synchronization overhead

### **Long-term Improvements**:
- **Scalable multiplayer**: Can support larger teams without exponential unit growth
- **Competitive balance**: Fair matches regardless of team composition
- **Easier game balancing**: Predictable starting conditions for balance tweaks
- **Better player experience**: No confusion from random starting unit counts

## 🔍 **Root Cause Analysis**

### **Why This Bug Existed**:
1. **Natural confusion**: "For each team" vs "for each player" is easily mixed up
2. **Limited testing**: Single-player testing wouldn't reveal the issue
3. **Team balancing**: Automatic team assignment made multiple players per team common
4. **Subtle symptoms**: Extra units might not be immediately obvious during development

### **Prevention for Future**:
1. **Clear naming**: Use team-focused variable names and comments
2. **Comprehensive testing**: Test with multiple players per team scenarios
3. **Explicit logging**: Log team vs player operations clearly
4. **Code reviews**: Specifically review unit spawning logic for per-team vs per-player patterns

This fix resolves a critical gameplay and performance issue, ensuring fair and balanced multiplayer matches with optimal server performance. 