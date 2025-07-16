# Unit Range Visualization

## Overview
The range visualization system displays visual indicators for both vision range and attack range when units are selected. This helps players understand unit capabilities and positioning in tactical situations.

## Features

### Visual Indicators
- **Vision Range**: Larger, subtle circle showing how far the unit can see
- **Attack Range**: Smaller, more prominent circle showing effective combat range
- **Team Colors**: Different colors for each team while maintaining range distinction
- **Smooth Animations**: Fade-in effects when showing ranges

### Color Coding
- **Team 1 (Blue)**: Light blue vision, darker blue attack range
- **Team 2 (Red)**: Light red vision, darker red attack range  
- **Team 3 (Green)**: Light green vision, darker green attack range
- **Team 4 (Yellow)**: Light yellow vision, orange attack range

### Behavior
- **Auto-Show**: Ranges appear automatically when units are selected
- **Auto-Hide**: Ranges disappear when units are deselected
- **Distance Fading**: Ranges become more transparent at greater camera distances
- **Performance Optimized**: Efficient rendering with minimal performance impact

## Technical Implementation

### Components
1. **UnitRangeVisualization.tscn**: Scene file with mesh components
2. **unit_range_visualization.gd**: Script handling display logic
3. **Integration**: Built into base Unit class for all unit types

### Key Methods
- `show_ranges()`: Display range indicators
- `hide_ranges()`: Hide range indicators  
- `refresh_visualization()`: Update sizes when stats change
- `set_team_colors(team_id)`: Apply team-specific colors

### Automatic Integration
- Range visualization is automatically created for all units
- No manual setup required - works out of the box
- Scales based on unit stats (vision_range, attack_range)

## Usage

### For Players
1. **Select any unit** by clicking or box selection
2. **View ranges** - vision and attack ranges appear as colored circles
3. **Tactical planning** - use range indicators to position units effectively
4. **Multi-unit selection** - ranges show for all selected units

### For Developers
```gdscript
# Manual control (optional)
unit.set_range_visualization_visibility(true)   # Force show
unit.set_range_visualization_visibility(false)  # Force hide
unit.refresh_range_visualization()              # Update after stat changes

# Check if unit has range visualization
if unit.range_visualization:
    print("Range visualization available")
```

## Performance Considerations

- **Efficient Materials**: Uses unshaded, transparent materials
- **Distance Culling**: Reduces opacity at long distances
- **Minimal Geometry**: Simple cylinder meshes with optimized segment counts
- **Conditional Updates**: Only processes when visible and selected

## Visual Design

### Vision Range
- **Purpose**: Shows reconnaissance and detection capability
- **Appearance**: Large, very transparent circle
- **Color**: Light team color with low alpha
- **Priority**: Background information

### Attack Range  
- **Purpose**: Shows effective combat engagement distance
- **Appearance**: Smaller, more visible circle
- **Color**: Darker team color with higher alpha
- **Priority**: Primary tactical information

## Integration Points

The range visualization integrates with:
- **Selection System**: Shows/hides based on unit selection
- **Unit Stats**: Automatically scales with vision_range and attack_range
- **Team System**: Color-coded by team membership
- **Camera System**: Distance-based transparency

This system enhances tactical gameplay by providing clear visual feedback about unit capabilities without cluttering the interface. 