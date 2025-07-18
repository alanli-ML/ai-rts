# BuildingManager - Godot Editor Tool Guide

## Overview

The BuildingManager is a comprehensive Godot editor tool (@tool script) that enables easy creation and customization of urban battlefields using Kenney asset packs. It provides inspector-editable properties for manual adjustments and one-click generation of buildings, roads, and navigation systems.

## Features

### ✅ Editor Integration
- **Inspector-Editable Properties**: All settings accessible in Godot Inspector
- **One-Click Generation**: Generate entire maps or specific elements
- **Real-Time Preview**: See changes immediately in the editor
- **Manual Adjustments**: Fine-tune placement after generation
- **Save/Load Layouts**: Export and import layout configurations

### ✅ Building System
- **District-Based Generation**: Commercial, Industrial, Residential zones
- **Automatic Collision**: Buildings are untargetable but block movement
- **Navigation Integration**: Automatic NavigationObstacle3D setup
- **Asset Management**: Organized Kenney asset catalogs
- **Performance Optimization**: LOD system and spatial partitioning

### ✅ Road Network
- **Hierarchical System**: Main arteries, ring roads, local streets
- **Multiple Patterns**: Grid, radial, organic layouts
- **Intersection Handling**: Automatic crossroads and curves
- **Strategic Placement**: Connects districts and key points

## Quick Start Guide

### 1. Open the Test Map Scene
```
File → Open Scene → scenes/maps/test_map.tscn
```

### 2. Select BuildingManager Node
- In the Scene dock, click on `BuildingManager` node
- Inspector will show all editable properties

### 3. Configure Your Map
**Basic Settings** (Map Configuration group):
- `Map Size`: Dimensions of your battlefield (default: 100x100)
- `Building Scale`: Scale multiplier for all buildings
- `Road Scale`: Scale multiplier for all roads

### 4. Generate Your Map
**Option A - Full Generation**:
- Set `Auto Generate On Ready` to `true` 
- Save and reload scene

**Option B - Manual Generation**:
- In Inspector, scroll to "Editor Actions" group
- Click `Generate Full Map` checkbox
- Map generates instantly!

## Inspector Property Reference

### 📋 Map Configuration
| Property | Description | Default |
|----------|-------------|---------|
| `map_size` | Battlefield dimensions | (100, 100) |
| `map_center` | Center point of map | (0, 0, 0) |
| `building_scale` | Building size multiplier | 1.0 |
| `road_scale` | Road size multiplier | 1.0 |

### 🏗️ Generation Controls
| Property | Description | Default |
|----------|-------------|---------|
| `auto_generate_on_ready` | Generate map when scene loads | false |
| `clear_existing_on_generate` | Remove old buildings/roads | true |
| `generate_buildings` | Include buildings in generation | true |
| `generate_roads` | Include roads in generation | true |
| `generate_navigation_obstacles` | Add pathfinding obstacles | true |

### 🛠️ Manual Building Tools
| Property | Description | Default |
|----------|-------------|---------|
| `selected_building_asset` | Asset for manual placement | "building-a" |
| `building_rotation` | Rotation for manual placement | 0.0 |
| `snap_to_grid` | Align to grid when placing | true |
| `grid_size` | Grid cell size | 4.0 |

### 🏘️ District Settings
| Property | Description | Default |
|----------|-------------|---------|
| `commercial_district_enabled` | Generate commercial district | true |
| `industrial_district_enabled` | Generate industrial district | true |
| `residential_district_enabled` | Generate residential district | true |
| `commercial_building_density` | Building density (0.0-1.0) | 0.7 |
| `industrial_building_density` | Building density (0.0-1.0) | 0.4 |
| `residential_building_density` | Building density (0.0-1.0) | 0.6 |

### 🛣️ Road Network
| Property | Description | Default |
|----------|-------------|---------|
| `main_road_width` | Width of main arteries | 8.0 |
| `secondary_road_width` | Width of secondary roads | 4.0 |
| `local_street_width` | Width of local streets | 2.0 |
| `road_spacing` | Distance between parallel roads | 20.0 |
| `create_ring_roads` | Generate circular ring roads | true |
| `create_cross_arteries` | Generate N-S, E-W main roads | true |

### ⚡ Performance & LOD
| Property | Description | Default |
|----------|-------------|---------|
| `use_lod_system` | Enable level-of-detail system | true |
| `lod_distance_medium` | Distance for medium detail | 50.0 |
| `lod_distance_low` | Distance for low detail | 100.0 |
| `max_buildings_per_district` | Building limit per district | 25 |

### 🧭 Navigation & Collision
| Property | Description | Default |
|----------|-------------|---------|
| `building_collision_layer` | Physics layer for buildings | 2 |
| `navigation_obstacle_layer` | Layer for nav obstacles | 3 |
| `obstacle_margin` | Safety margin around buildings | 1.0 |
| `update_navigation_mesh` | Auto-update navigation | true |

## Editor Action Buttons

### 🎯 One-Click Actions
These checkboxes in the "Editor Actions" group trigger immediate actions:

| Button | Action |
|--------|--------|
| `Generate Full Map` | Create complete map with buildings and roads |
| `Generate Buildings Only` | Create only buildings (keep existing roads) |
| `Generate Roads Only` | Create only roads (keep existing buildings) |
| `Clear All Buildings` | Remove all generated buildings |
| `Clear All Roads` | Remove all generated roads |
| `Update Navigation` | Rebake navigation mesh |
| `Save Layout As Resource` | Export current layout to JSON |

## Manual Building Placement

### Method 1: Inspector Configuration
1. Set `selected_building_asset` to desired building
2. Adjust `building_rotation` if needed
3. Use script methods to place at specific coordinates

### Method 2: Script Integration
```gdscript
# Get reference to BuildingManager
var building_manager = get_node("BuildingManager")

# Place building at specific position
building_manager.place_building_at_position(Vector3(10, 0, 5), "building-skyscraper-a")

# Remove building near position
building_manager.remove_building_at_position(Vector3(10, 0, 5))
```

## Scene Structure

When you use BuildingManager, it creates organized scene structure:

```
TestMap
├── Environment/
├── BuildingManager/
│   ├── Buildings/           # All placed buildings
│   │   ├── Building_0       # Individual building instances
│   │   ├── Building_1       #   with collision and obstacles
│   │   └── ...
│   ├── Roads/              # All placed roads
│   │   ├── Road_0          # Individual road pieces
│   │   ├── Road_1
│   │   └── ...
│   └── NavigationObstacles/ # Navigation system components
├── Units/
└── RTSCamera/
```

## Asset Organization

The BuildingManager includes pre-configured asset catalogs:

### 🏢 Commercial Buildings (39 assets)
- High-detail buildings (building-a through building-n)
- Skyscrapers (building-skyscraper-a through building-skyscraper-e)
- Low-detail buildings (for performance)

### 🏭 Industrial Buildings (20 assets)
- Factories and warehouses
- Chimneys and storage tanks
- Industrial infrastructure

### 🏠 Residential Buildings (14 assets)
- Low-detail residential buildings
- Mixed residential structures
- Neighborhood buildings

### 🛣️ Road Assets (72+ pieces)
- Straight roads, curves, intersections
- Roundabouts, bridges, crossroads
- Highway pieces and barriers

## Navigation Integration

### Automatic Features
- **NavigationObstacle3D**: Each building blocks unit pathfinding
- **Collision Layers**: Buildings on layer 2, units on layer 1
- **Mesh Baking**: Automatic navigation mesh updates
- **Performance**: Optimized obstacle shapes

### Manual Navigation Control
```gdscript
# Force navigation update
building_manager._update_navigation_impl()

# Check if navigation is working
var nav_region = get_tree().get_first_node_in_group("navigation_regions")
if nav_region:
    nav_region.bake_navigation_mesh()
```

## Customization Tips

### 1. Adjust District Layouts
- Modify `bounds_center` and `bounds_size` in district configurations
- Change `building_density` for different tactical experiences
- Experiment with `road_spacing` for various gameplay scales

### 2. Performance Tuning
- Lower `max_buildings_per_district` for better performance
- Adjust LOD distances based on camera height
- Use `building_scale` to create more/less dense environments

### 3. Strategic Balance
- Place buildings to create natural chokepoints
- Use industrial districts for long-range tactical positions
- Residential areas provide close-quarters combat opportunities

## Troubleshooting

### Buildings Not Appearing
1. Check asset paths in `commercial_assets`, `industrial_assets`, `residential_assets`
2. Verify Kenney asset packs are properly imported
3. Ensure `generate_buildings` is enabled

### Navigation Not Working
1. Check that NavigationRegion3D exists in scene
2. Enable `update_navigation_mesh`
3. Verify `generate_navigation_obstacles` is enabled
4. Check collision layers (buildings on layer 2)

### Performance Issues
1. Reduce `max_buildings_per_district`
2. Enable `use_lod_system`
3. Lower building/road densities
4. Check for overlapping collision shapes

## Advanced Usage

### Custom Asset Integration
1. Add new building models to asset arrays
2. Create BuildingConfiguration resources for new assets
3. Define district layouts with DistrictLayout resources

### Layout Templates
- Save successful layouts using `Save Layout As Resource`
- Load templates from `maps/` directory
- Share layouts between projects

### Scripted Generation
```gdscript
# Create custom district
var custom_district = DistrictLayout.create_commercial_district(
    Vector2(20, 20),    # center
    Vector2(40, 40)     # size
)

# Generate buildings for specific district
building_manager._generate_district_buildings(
    BuildingManager.DistrictType.COMMERCIAL,
    custom_district.get_bounds_rect()
)
```

## File Locations

### Core Files
- `scripts/core/building_manager.gd` - Main tool script
- `scripts/resources/building_configuration.gd` - Building resource class
- `scripts/resources/district_layout.gd` - District resource class

### Configuration Files
- `maps/default_layout_config.json` - Example layout configuration
- `maps/saved_layout.json` - Auto-generated layouts (created by tool)

### Scene Integration
- `scenes/maps/test_map.tscn` - Example implementation

## Next Steps

1. **Try the Quick Start**: Generate your first map
2. **Experiment with Settings**: Adjust densities and scales
3. **Create Custom Layouts**: Design tactical scenarios
4. **Share Configurations**: Export and import layouts
5. **Extend the System**: Add new building types and districts

For advanced customization, see the resource classes in `scripts/resources/` and modify the generation algorithms in `building_manager.gd`.

---

*This tool transforms your basic flat terrain into rich urban battlefields perfect for tactical RTS gameplay!* 🏙️⚔️ 