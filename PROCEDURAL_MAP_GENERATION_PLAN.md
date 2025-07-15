# Server-Sided Procedural Map Generation Plan

## 📋 Overview

This plan outlines the implementation of a server-sided procedural generation system that transforms the current static 60x60 terrain with 9 control points into dynamic, tile-based urban environments using Kenney asset collections. The system will be fully server-authoritative and generate unique maps for each match.

## 🏗️ Architecture Overview

### Core Principle
> **Server-Authoritative Procedural Generation**: All map generation occurs on the server, clients receive final placement data for rendering

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                  Server-Side Generation                  │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ MapGenerator│  │  TileSystem  │  │DistrictGenerator│  │
│  │             │  │              │  │                │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ RoadNetwork │  │BuildingPlacer│  │  LODManager   │  │
│  │             │  │              │  │               │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
                            │
                   Generation Data
                            │
┌─────────────────────────────────────────────────────────┐
│                  Client Rendering                       │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Map Renderer│  │ Asset Loader │  │  3D Placement │  │
│  │             │  │              │  │               │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## 🎯 Technical Specifications

### Map Grid System
- **Base Grid**: 60x60 units (matches current terrain)
- **Tile Size**: 3x3 units (20x20 grid cells)
- **Control Point Districts**: 9 districts (3x3 arrangement)
- **District Size**: 18x18 units each with 2-unit borders

### Control Point Enhancement
- **Current**: Static yellow spheres at fixed positions
- **Enhanced**: Procedurally generated urban districts with:
  - Road networks using Kenney road assets
  - Mixed commercial/industrial buildings
  - Strategic positioning for gameplay balance
  - Unique visual identity per district

### Asset Integration
- **Roads**: 70+ road building blocks for street networks
- **Commercial**: 50+ business buildings for urban districts
- **Industrial**: 35+ factory buildings for production areas
- **Characters**: 18 character models for enhanced unit visuals

## 🔧 Implementation Details

### Phase 1: Core Generation System

#### 1.1 MapGenerator Class
```gdscript
# scripts/procedural/map_generator.gd
class_name MapGenerator
extends Node

var logger
var asset_loader: AssetLoader
var tile_system: TileSystem
var district_generator: DistrictGenerator
var road_network: RoadNetwork
var building_placer: BuildingPlacer

func generate_map(seed: int, control_points: Array) -> Dictionary:
    # Generate complete map data for server/client sync
    
func generate_district(control_point: ControlPoint, district_type: String) -> Dictionary:
    # Generate individual district around control point
```

#### 1.2 TileSystem Class
```gdscript
# scripts/procedural/tile_system.gd
class_name TileSystem
extends Node

const TILE_SIZE: float = 3.0
const GRID_WIDTH: int = 20
const GRID_HEIGHT: int = 20

var tile_grid: Array = []  # 2D array of tile data
var tile_types: Dictionary = {}  # Tile type definitions

func world_to_tile(world_pos: Vector3) -> Vector2i:
    # Convert world position to tile coordinates
    
func tile_to_world(tile_pos: Vector2i) -> Vector3:
    # Convert tile coordinates to world position
    
func set_tile(tile_pos: Vector2i, tile_type: String, asset_data: Dictionary):
    # Set tile type and associated 3D asset
```

#### 1.3 DistrictGenerator Class
```gdscript
# scripts/procedural/district_generator.gd
class_name DistrictGenerator
extends Node

enum DistrictType {
    COMMERCIAL,
    INDUSTRIAL,
    MIXED,
    RESIDENTIAL,
    MILITARY
}

func generate_district(center: Vector3, district_type: DistrictType, size: int) -> Dictionary:
    # Generate district layout around control point
    
func create_district_roads(district_area: Rect2i) -> Array:
    # Create internal road network for district
    
func place_district_buildings(district_area: Rect2i, roads: Array) -> Array:
    # Place buildings with proper road access
```

### Phase 2: Road Network System

#### 2.1 RoadNetwork Class
```gdscript
# scripts/procedural/road_network.gd
class_name RoadNetwork
extends Node

var road_graph: Dictionary = {}  # Node-based road connections
var road_segments: Array = []    # Individual road pieces

func generate_main_roads(control_points: Array) -> Array:
    # Generate primary roads connecting districts
    
func generate_district_roads(district_area: Rect2i) -> Array:
    # Generate internal district street network
    
func optimize_road_connections() -> void:
    # Optimize road network for gameplay and performance
```

#### 2.2 Road Asset Selection
- **Straight Roads**: `road-straight.glb`, `road-straight-half.glb`
- **Intersections**: `road-intersection.glb`, `road-crossroad.glb`
- **Curves**: `road-curve.glb`, `road-bend.glb`
- **Specialized**: `road-roundabout.glb`, `road-bridge.glb`

### Phase 3: Building Placement System

#### 3.1 BuildingPlacer Class
```gdscript
# scripts/procedural/building_placer.gd
class_name BuildingPlacer
extends Node

var placement_rules: Dictionary = {}
var building_density: float = 0.6

func place_buildings(district_area: Rect2i, roads: Array, district_type: String) -> Array:
    # Intelligent building placement with road access
    
func validate_building_placement(position: Vector3, building_size: Vector2) -> bool:
    # Validate building can be placed without conflicts
    
func select_building_asset(district_type: String, position: Vector3) -> PackedScene:
    # Select appropriate building asset based on context
```

#### 3.2 Building Selection Logic
- **Commercial Districts**: Mix of `building-a.glb` through `building-n.glb`
- **Industrial Districts**: Factory buildings `building-a.glb` through `building-t.glb`
- **Mixed Districts**: Combination of both with appropriate density
- **Special Buildings**: Skyscrapers for important locations

### Phase 4: Integration with Existing Systems

#### 4.1 Control Point Enhancement
```gdscript
# scripts/enhanced/enhanced_control_point.gd
class_name EnhancedControlPoint
extends ControlPoint

var district_data: Dictionary = {}
var generated_buildings: Array = []
var road_connections: Array = []

func initialize_district(district_type: String, generator: DistrictGenerator):
    # Replace static sphere with procedural district
    
func update_district_control(team_id: int):
    # Update district appearance based on controlling team
```

#### 4.2 Unit Spawning Integration
- **Building-Based Spawning**: Units spawn from appropriate buildings
- **Barracks**: Military units spawn from industrial buildings
- **Civilian Buildings**: Support units spawn from commercial buildings
- **Strategic Placement**: Spawn points integrated with district layout

### Phase 5: Performance Optimization

#### 5.1 LOD System
```gdscript
# scripts/procedural/lod_manager.gd
class_name LODManager
extends Node

enum LODLevel {
    HIGH,    # Full detail - close districts
    MEDIUM,  # Reduced detail - mid-distance
    LOW      # Minimal detail - far districts
}

func update_district_lod(district_id: String, camera_distance: float):
    # Dynamically adjust detail level based on distance
    
func create_lod_variants(building_asset: PackedScene) -> Dictionary:
    # Generate different detail levels for buildings
```

#### 5.2 Performance Targets
- **Generation Time**: < 3 seconds for complete map
- **Memory Usage**: < 150MB for all generated assets
- **FPS Impact**: < 10% performance loss during generation
- **Streaming**: Dynamic loading/unloading based on player location

### Phase 6: Map Synchronization

#### 6.1 Server-Client Synchronization
```gdscript
# scripts/procedural/map_synchronizer.gd
class_name MapSynchronizer
extends Node

func serialize_map_data(map_data: Dictionary) -> PackedByteArray:
    # Compress map data for network transmission
    
func deserialize_map_data(data: PackedByteArray) -> Dictionary:
    # Decompress map data on client
    
func sync_district_changes(district_id: String, changes: Dictionary):
    # Synchronize district updates (e.g., building destruction)
```

#### 6.2 Network Message Structure
```gdscript
# Addition to scripts/shared/types/network_messages.gd
class_name MapGenerationMessage:
    var seed: int
    var control_points: Array
    var districts: Dictionary
    var road_network: Dictionary
    var building_placements: Array
```

## 🎮 Gameplay Integration

### Strategic Enhancements
1. **Dynamic Control Points**: Each district provides unique strategic value
2. **Resource Generation**: Buildings generate resources based on type
3. **Tactical Positioning**: Road networks affect unit movement and strategy
4. **Visual Variety**: No two matches look identical

### Balance Considerations
1. **Fair District Distribution**: Ensure balanced resource generation
2. **Strategic Positioning**: Control points maintain tactical importance
3. **Access Routes**: All districts remain accessible via road network
4. **Defensive Positions**: Buildings provide strategic cover options

## 🔄 Implementation Roadmap

### Week 1: Foundation Systems
- [ ] Create MapGenerator core class
- [ ] Implement TileSystem for grid management
- [ ] Set up basic DistrictGenerator
- [ ] Test basic generation without assets

### Week 2: Asset Integration
- [ ] Integrate with existing AssetLoader system
- [ ] Implement RoadNetwork generation
- [ ] Create BuildingPlacer system
- [ ] Test with Kenney assets

### Week 3: Advanced Features
- [ ] Implement LOD system
- [ ] Add enhanced terrain generation
- [ ] Create map synchronization system
- [ ] Performance optimization

### Week 4: Integration & Polish
- [ ] Integrate with existing control point system
- [ ] Update UnifiedMain initialization
- [ ] Add to dependency container
- [ ] Comprehensive testing and balancing

## 📊 File Structure

```
scripts/
├── procedural/
│   ├── map_generator.gd              # Core generation system
│   ├── tile_system.gd                # Grid-based map management
│   ├── district_generator.gd         # Control point urban areas
│   ├── road_network.gd               # Road system generation
│   ├── building_placer.gd            # Intelligent building placement
│   ├── lod_manager.gd                # Performance optimization
│   ├── map_synchronizer.gd           # Server-client sync
│   └── biome_system.gd               # District type management
├── enhanced/
│   ├── enhanced_control_point.gd     # Enhanced control point class
│   ├── procedural_spawn_system.gd    # Building-based unit spawning
│   └── district_resource_generator.gd # Resource generation per district
```

## 🧪 Testing Strategy

### Unit Testing
- Individual component testing for each generation system
- Asset loading and placement validation
- Performance benchmarking for each phase

### Integration Testing
- Full map generation with all systems
- Server-client synchronization validation
- Gameplay balance testing with procedural maps

### Performance Testing
- Memory usage monitoring during generation
- FPS impact measurement
- Network bandwidth usage for map sync

## 🔐 Security Considerations

### Server Authority
- All generation occurs server-side
- Clients receive only final placement data
- No client-side generation validation needed

### Deterministic Generation
- Seed-based generation for reproducible results
- Server validates all procedural decisions
- Prevents client-side manipulation

## 🎯 Success Metrics

### Technical Metrics
- Generation time: < 3 seconds
- Memory usage: < 150MB
- Network sync: < 5MB per map
- FPS impact: < 10% during generation

### Gameplay Metrics
- Map variety: Unique layout each match
- Balance: Fair resource distribution
- Strategic depth: Multiple tactical options
- Visual appeal: Immersive urban environments

## 🚀 Future Enhancements

### Phase 2 Features
- Weather and time-of-day systems
- Dynamic building destruction/construction
- Procedural unit customization
- Advanced AI behavior based on map layout

### Phase 3 Features
- Player-influenced generation
- Persistent base building
- Large-scale city generation
- Seasonal map variations

---

This plan provides a comprehensive framework for implementing server-sided procedural generation of tile-based game maps using Kenney assets, transforming the current static terrain into dynamic, strategic urban environments while maintaining the game's core multiplayer RTS mechanics. 