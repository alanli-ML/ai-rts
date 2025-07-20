# Team-Based Camera Positioning System

## Overview

The AI-RTS game now features team-based camera positioning that automatically rotates and positions the camera to focus on each player's home base when the game starts. This provides players with an optimal tactical view of their base and the battlefield ahead, with a closer, more intimate view of the action.

## Implementation Details

### Core Components

#### 1. RTSCamera Enhancement

The `RTSCamera` class has been enhanced with two new methods:

- **`position_for_team_base(team_id: int, instant: bool = true)`**: Positions and rotates the camera to focus on the team's home base for optimal tactical view
- **`position_for_map_data(map_data: Dictionary, team_id: int = -1)`**: Updated to support team-based positioning when team ID is provided

#### 2. Enhanced Zoom Settings

The camera zoom system has been improved for closer tactical gameplay:

- **Minimum Zoom**: Reduced from 10.0 to **5.0** for much closer unit detail
- **Default Team Zoom**: Set to **15.0** for intimate base view at game start
- **Default Map Zoom**: Reduced from 30.0 to **20.0** for closer general view
- **Camera Angle**: Optimized to **-55 degrees** for better close-up visibility

#### 3. Team-Specific Camera Positioning

Each team gets positioned with a close tactical camera angle:

**Team 1 (Northwest Base)**:
- Camera positioned southwest of base (-12, 20, -12 offset) - much closer than before
- Looking northeast toward the immediate battlefield area
- Provides intimate view of home base and nearby tactical area

**Team 2 (Southeast Base)**:
- Camera positioned northeast of base (12, 20, 12 offset) - much closer than before
- Looking southwest toward the immediate battlefield area
- Provides intimate view of home base and nearby tactical area

### Integration Flow

#### 1. Server-Side Game Start
1. `SessionManager._start_game()` initiates game for session
2. Server sends `_on_game_started` RPC to each client with their team ID
3. Team ID is included in the game start data: `"player_team": player.team_id`

#### 2. Client-Side Initialization
1. Client receives `_on_game_started` RPC in `UnifiedMain`
2. Client stores `client_team_id = data.get("player_team", -1)`
3. Client loads game map and HUD
4. Client waits one frame for map initialization
5. Client calls `_position_camera_for_team(client_team_id)`

#### 3. Camera Positioning Execution
1. `_position_camera_for_team()` finds the RTS camera in the scene
2. Calls `rts_camera.position_for_team_base(team_id, true)` for instant positioning
3. Camera is positioned with close tactical view for the team at zoom level 15.0

### Technical Implementation

#### Home Base Integration

The system integrates with the existing `HomeBaseManager`:

```gdscript
var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
var team_base_pos = home_base_manager.get_home_base_position(team_id)
```

#### Camera Calculations

Close tactical positioning uses mathematical offsets optimized for intimate gameplay:

```gdscript
# Set closer zoom level for team-based positioning
var team_zoom_level = 15.0  # Closer than default 20.0
current_zoom = team_zoom_level
target_zoom = team_zoom_level

match team_id:
    1:
        camera_offset = Vector3(-12, 20, -12)  # Close and intimate
        look_target = team_base_pos + Vector3(8, 0, 8)  # Nearby battlefield
    2:
        camera_offset = Vector3(12, 20, 12)   # Close and intimate
        look_target = team_base_pos + Vector3(-8, 0, -8)  # Nearby battlefield
```

#### Improved Camera Angles

The camera angle has been optimized for closer views:

```gdscript
# Steeper angle for better close-up detail
camera_3d.position = Vector3(0, current_zoom * 0.7, current_zoom * 0.3)
var angle = deg_to_rad(-55)  # Optimized for close tactical view
```

### Camera Bounds and Constraints

- Camera positioning respects existing camera bounds (`use_bounds`)
- Position is clamped to configured min/max X and Z values
- Camera angle provides ~55-degree tactical overview optimized for close gameplay
- Height positioning provides clear unit detail and immediate area visibility

### Zoom Range Improvements

The zoom system has been enhanced across the board:

- **Minimum Zoom**: 5.0 (allows very close unit inspection)
- **Maximum Zoom**: 60.0 (maintains strategic overview capability)
- **Team Start Zoom**: 15.0 (intimate base view)
- **Map Default Zoom**: 20.0 (closer general map view)

### Fallback Handling

The system includes robust fallback mechanisms:

1. **Invalid Team ID**: Logs warning and uses closer default camera positioning (zoom 20.0)
2. **Missing RTS Camera**: Searches globally for any RTS camera before failing
3. **Missing Home Base**: Uses closer default positioning if home base not found

### Logging and Debug

Comprehensive logging tracks the positioning process with zoom information:

```gdscript
logger.info("RTSCamera", "Positioned camera for team %d at %s (zoom: %.1f), looking toward %s" % [team_id, camera_position, current_zoom, look_target])
```

## Benefits

### Strategic Advantages

1. **Immediate Orientation**: Players instantly know where their base is with intimate detail
2. **Tactical Awareness**: Close camera angle shows base details and immediate tactical area
3. **Unit Detail**: Closer zoom allows players to see individual unit actions clearly
4. **Reduced Confusion**: No need to manually find or zoom to home base at game start
5. **Enhanced Immersion**: Closer view creates more engaging tactical experience

### Technical Benefits

1. **Automatic**: No manual camera adjustment required for optimal view
2. **Consistent**: Same close experience for all players of a team
3. **Optimal**: Camera angle and zoom designed for intimate RTS gameplay
4. **Smooth**: Instant positioning without disorienting movement
5. **Scalable**: Zoom system works well from very close (5.0) to strategic overview (60.0)

## Future Enhancements

### Potential Improvements

1. **Smooth Transitions**: Add smooth camera movement instead of instant positioning
2. **Custom Zoom Levels**: Allow players to configure preferred starting zoom levels
3. **Dynamic Zoom**: Automatically adjust zoom based on unit density or action intensity
4. **Map-Specific Positioning**: Adjust close angles based on specific map layouts

### Configuration Options

The system could be extended with:

```gdscript
@export_group("Team Positioning")
@export var team_zoom_level: float = 15.0
@export var team_camera_offsets: Dictionary = {
    1: Vector3(-12, 20, -12),
    2: Vector3(12, 20, 12)
}
@export var team_look_offsets: Dictionary = {
    1: Vector3(8, 0, 8),
    2: Vector3(-8, 0, -8)
}
```

## Usage

The system works automatically with enhanced close-up views - no additional configuration required. When players join a game:

1. Server assigns teams in `SessionManager._assign_team()`
2. Game start triggers close team-based camera positioning at zoom 15.0
3. Each player sees intimate, detailed view of their team's area
4. Players can zoom out for strategic overview or zoom in even closer for unit detail
5. Players can immediately see unit details and begin tactical planning

## Troubleshooting

### Common Issues

**Camera too close or too far:**
- Adjust `team_zoom_level` in `position_for_team_base()` method
- Modify camera offset values for different distances
- Check zoom bounds (min_zoom: 5.0, max_zoom: 60.0)

**Camera not positioning correctly:**
- Verify `HomeBaseManager` is properly configured
- Check that team bases are positioned in scene
- Ensure RTS camera exists in map scene

**Team ID not being passed:**
- Verify `_on_game_started` RPC receives team data
- Check `client_team_id` is being set correctly
- Confirm session manager assigns teams properly

### Debug Information

Enable debug logging to track camera positioning:

```gdscript
logger.info("UnifiedMain", "Positioning camera for team %d" % team_id)
logger.info("RTSCamera", "Positioned camera for team %d at %s (zoom: %.1f), looking toward %s")
```

## Camera Control Tips

With the new close positioning system:

- **Mouse wheel**: Zoom from very close (5.0) to strategic overview (60.0)
- **WASD/Arrow keys**: Pan around the battlefield while maintaining zoom level
- **Middle mouse drag**: Smooth camera movement for precise positioning
- **Edge scrolling**: Move camera by placing mouse at screen edges (if enabled) 