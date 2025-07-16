# Unit Goal Display System

## Overview
The unit goal display system shows each unit's strategic objective in both the HUD's bottom-right panel and above individual units in their status bars. This provides players with clear visibility into what each unit is trying to accomplish at a high level.

## Features

### Goal Sources
- **AI-Generated Goals**: When the AI processes commands, it assigns specific strategic goals to each unit
- **Default Goals**: Units without specific assignments show "Act autonomously based on my unit type"
- **Dynamic Updates**: Goals change in real-time as new commands are processed

### Display Locations

#### 1. HUD Panel (Bottom-Right)
- **Location**: Integrated into the existing Unit Action Queue panel
- **Format**: Bold green text with "Goal:" prefix
- **Visibility**: Shows for all selected units
- **Detail Level**: Full goal text with intelligent truncation for very long goals

#### 2. Unit Status Bars (Above Units)
- **Location**: Above each unit, integrated into existing status bar
- **Format**: Condensed green text above action status
- **Visibility**: Shows for all units when selected
- **Detail Level**: Abbreviated goal text optimized for quick scanning

### Smart Text Processing

#### HUD Display
- Shows complete goal text for comprehensive understanding
- Handles multi-unit selection by showing each unit's individual goal
- Clear labeling with unit identification

#### Status Bar Display
- **Intelligent Abbreviation**: Common phrases are shortened (e.g., "Capture" → "Cap", "Defend" → "Def")
- **Length Limiting**: Goals longer than 30 characters are truncated with "..."
- **Keyword Replacement**: Military terms are abbreviated for space efficiency
- **Auto-cleanup**: Removes common filler words ("the", "and" → "&")

## Implementation Details

### Goal Synchronization
1. **Server Side**: Goals are set on units when AI processes commands
2. **Network Sync**: Goals are included in unit state updates to clients
3. **Client Display**: Both HUD and status bars automatically update when goals change
4. **Real-time Updates**: Changes are reflected immediately across all display locations

### Display Examples

#### Common Goal Transformations
- "Capture the northern control point" → "Cap northern CP"
- "Defend position and attack enemies" → "Def pos & att E"
- "Move to objective and patrol area" → "Move to obj & pat area"
- "Act autonomously based on my unit type" → "Auto"

#### HUD Display Example
```
Scout (f3e2)
Goal: Secure the northern sector and provide overwatch
► Moving to position
○ Patrol area
```

#### Status Bar Display Example
```
Secure northern sector
► Moving
```

## Integration Points

### HUD Integration
- **Action Queue Panel**: Goals appear directly below unit headers
- **Multi-Selection**: Each selected unit shows its individual goal
- **Color Coding**: Light green text distinguishes goals from actions
- **Spacing**: Clean separation from action lists for readability

### Status Bar Integration  
- **Billboard Behavior**: Goals rotate to always face camera
- **Distance Fading**: Becomes more transparent at longer ranges
- **Hierarchical Display**: Goal shown above current action for priority
- **Team Colors**: Goal text adapts to maintain visibility on team-colored backgrounds

### Data Flow
1. **AI Command Processing**: Strategic goals assigned during plan creation
2. **Server State**: Goals stored on server-side unit instances
3. **Network Transmission**: Goals included in unit state broadcasts
4. **Client Synchronization**: `ClientDisplayManager` updates unit goals
5. **UI Updates**: Both HUD and status bars refresh automatically

## Visual Design

### Typography
- **HUD**: Bold 16pt font for emphasis and readability
- **Status Bar**: Bold 40pt font optimized for 3D world display
- **Color**: Light green (#90EE90) provides good contrast and positive association

### Layout
- **HUD**: Goals positioned immediately after unit identification
- **Status Bar**: Goals displayed above action status in hierarchical order
- **Spacing**: Adequate whitespace prevents visual crowding

### Performance Considerations
- **Text Processing**: Goal abbreviation done once per update, not per frame
- **Render Efficiency**: Status bar updates only when goal changes
- **Memory Usage**: Goals stored as strings, minimal memory impact

## User Experience

### For Players
1. **Quick Overview**: Glance at selected units to see their strategic objectives
2. **Tactical Planning**: Understanding unit goals helps coordinate overall strategy  
3. **Progress Tracking**: See how current actions relate to larger objectives
4. **Multi-Unit Coordination**: Quickly assess if units are working toward complementary goals

### For Commanders
1. **Strategic Clarity**: Clear visibility into AI's interpretation of commands
2. **Goal Verification**: Confirm units understood intended objectives
3. **Coordination**: Ensure units aren't working at cross-purposes
4. **Adaptation**: Issue new commands when goals need adjustment

## Future Enhancements

### Potential Improvements
- **Goal History**: Track how goals have evolved over time
- **Goal Completion**: Visual indicators when objectives are achieved
- **Priority Levels**: Color-coding for high/medium/low priority goals
- **Team Goals**: Display overarching team objectives alongside unit goals
- **Goal Conflicts**: Highlight when units have contradictory objectives

### Technical Extensions
- **Goal Templates**: Predefined goal types for consistency
- **Goal Validation**: AI validation that goals are achievable
- **Goal Metrics**: Track goal completion rates and times
- **Dynamic Goals**: Goals that adapt based on battlefield conditions

This system enhances situational awareness by providing clear insight into each unit's strategic purpose, making it easier to understand and coordinate complex AI-driven tactical operations. 