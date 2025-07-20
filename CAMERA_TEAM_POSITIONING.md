# Team-Based Camera Positioning System

## Overview

The AI-RTS game now features team-based camera positioning that automatically rotates and positions the camera to focus on each player's home base when the game starts. This provides players with an optimal tactical view of their base and the battlefield ahead, with a closer, more intimate view of the action.

## Camera Controls

### Movement Controls
- **WASD Keys**: Move camera around the battlefield
- **Mouse Wheel**: Zoom in/out for better tactical view (now supports much closer zoom - minimum 5.0 units)
- **Middle Mouse Drag**: Pan camera by dragging
- **Edge Scrolling**: Move camera by moving mouse to screen edges

### New Orbiting Camera Controls
- **Q Key**: Orbit camera counter-clockwise around the ground focus point
- **E Key**: Orbit camera clockwise around the ground focus point

The orbiting system calculates where the camera is currently looking at the ground (Y=0 plane) and orbits around that specific point, creating a smooth strafing effect that maintains focus on your area of interest.

## Implementation Details

### Core Components

#### 1. RTSCamera Enhancement

The `RTSCamera` class has been enhanced with several new methods:

- **`position_for_team_base(team_id: int, instant: bool = true)`**: Positions and rotates the camera to focus on the team's home base for optimal tactical view
- **`position_for_map_data(map_data: Dictionary, team_id: int = -1)`**: Updated to support team-based positioning when team ID is provided
- **`_orbit_around_ground_focus(rotation_degrees: float)`**: Orbits the camera around the ground intersection point
- **`_get_ground_intersection(ray_origin: Vector3, ray_direction: Vector3)`**: Calculates where the camera ray intersects with the ground plane

#### 2. Team-Specific Camera Positioning

**Team 1 (Northwest Base)**:
- Camera positioned at offset **(-12, 20, -12)** from base
- Zoom level: **15.0** units (close tactical view)
- Looks toward **(base + (8, 0, 8))** for battlefield awareness

**Team 2 (Southeast Base)**:
- Camera positioned at offset **(12, 20, 12)** from base  
- Zoom level: **15.0** units (close tactical view)
- Looks toward **(base + (-8, 0, -8))** for battlefield awareness

#### 3. Enhanced Zoom Settings

- **Minimum Zoom**: Reduced from 10.0 to **5.0** units (much closer view)
- **Default Zoom**: Reduced from 30.0 to **20.0** units (closer starting view)
- **Team-Based Zoom**: **15.0** units for intimate base view
- **Camera Angle**: Improved from -60° to **-55°** for better close-up visibility

#### 4. Orbiting System

The orbiting camera system works by:
1. **Ray Casting**: Determines where the camera is currently looking at the ground plane (Y=0)
2. **Focus Point Calculation**: Uses ray-plane intersection to find the exact ground point
3. **Orbital Movement**: Rotates the camera position around this focus point while maintaining the same distance
4. **Fallback Handling**: If no ground intersection is found (camera pointing up), uses current camera XZ position

### Integration Points

#### 1. UnifiedMain Integration
- **Team Assignment**: `client_team_id` is received from server during game start
- **Camera Positioning**: `_position_camera_for_team()` method calls the camera positioning after map load
- **Timing**: Camera positioning occurs after a frame delay to ensure map components are initialized

#### 2. ProceduralWorldRenderer Integration  
- **`initialize_procedural_world()`** method now accepts `team_id` parameter
- **`position_rts_camera_for_procedural_map()`** method passes team information to camera positioning

#### 3. Game Start Flow
1. Server sends `_on_game_started` RPC with player's team ID
2. Client stores team ID and loads map
3. Client positions camera based on team after map initialization  
4. Start message appears with updated control instructions including Q/E orbiting

## User Experience Improvements

### 1. **Closer Combat View**
- Players start much closer to their units and base
- Easier to see individual unit actions and animations
- Better sense of scale and immersion

### 2. **Team-Oriented Perspective**
- Each team gets a strategic view of their base and the battlefield ahead
- Natural orientation toward likely engagement areas
- Asymmetric but balanced starting viewpoints

### 3. **Intuitive Camera Controls**
- Q/E keys provide natural orbiting around points of interest
- No more awkward in-place rotation - camera orbits around what you're looking at
- Maintains focus on tactical areas while providing different viewing angles

### 4. **Enhanced Tutorial Information**
- Start message updated to include Q/E orbiting controls
- Players are informed about the new camera capabilities from the beginning

## Technical Notes

- Camera bounds are automatically adjusted based on procedural map size
- Team-based positioning takes precedence over generic map positioning
- Orbiting respects camera movement bounds to prevent going out of playable area
- Ground intersection calculation handles edge cases (camera pointing up, behind camera, etc.)

This system provides a much more engaging and tactically useful camera experience that adapts to each player's team while offering intuitive controls for battlefield observation. 