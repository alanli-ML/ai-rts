@tool
# BuildingManager.gd - Editor tool for placing and managing buildings and roads
class_name BuildingManager
extends Node3D

# Make this a tool script so it runs in the editor
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# =============================================================================
# INSPECTOR EDITABLE PROPERTIES
# =============================================================================

@export_group("Map Configuration")
@export var map_size: Vector2 = Vector2(100, 100)
@export var map_center: Vector3 = Vector3.ZERO
@export var building_scale: float = 1.0
@export var road_scale: float = 1.0

@export_group("Generation Controls") 
@export var auto_generate_on_ready: bool = false
@export var clear_existing_on_generate: bool = true
@export var generate_buildings: bool = true
@export var generate_roads: bool = true
@export var generate_navigation_obstacles: bool = true
@export var use_safe_mode: bool = true
@export var force_fallback_assets: bool = false

@export_group("Manual Building Tools")
@export var selected_building_asset: String = "building-a"
@export var building_rotation: float = 0.0
@export var manual_placement_mode: bool = false
@export var snap_to_grid: bool = true
@export var grid_size: float = 4.0

@export_group("District Settings")
@export var commercial_district_enabled: bool = true
@export var industrial_district_enabled: bool = true
@export var residential_district_enabled: bool = true
@export var commercial_building_density: float = 0.7
@export var industrial_building_density: float = 0.4
@export var residential_building_density: float = 0.6

@export_group("Road Network")
@export var main_road_width: float = 8.0
@export var secondary_road_width: float = 4.0
@export var local_street_width: float = 2.0
@export var road_spacing: float = 20.0
@export var create_ring_roads: bool = true
@export var create_cross_arteries: bool = true

@export_group("Performance & LOD")
@export var use_lod_system: bool = true
@export var lod_distance_medium: float = 50.0
@export var lod_distance_low: float = 100.0
@export var max_buildings_per_district: int = 25

@export_group("Navigation & Collision")
@export var building_collision_layer: int = 2
@export var navigation_obstacle_layer: int = 3
@export var obstacle_margin: float = 1.0
@export var update_navigation_mesh: bool = true

# =============================================================================
# EDITOR BUTTONS (Inspector callable methods)
# =============================================================================

@export_group("Editor Actions")
@export var _generate_full_map: bool = false : set = _on_generate_full_map
@export var _generate_buildings_only: bool = false : set = _on_generate_buildings_only  
@export var _generate_roads_only: bool = false : set = _on_generate_roads_only
@export var _clear_all_buildings: bool = false : set = _on_clear_all_buildings
@export var _clear_all_roads: bool = false : set = _on_clear_all_roads
@export var _update_navigation: bool = false : set = _on_update_navigation
@export var _save_layout_as_resource: bool = false : set = _on_save_layout_as_resource

# =============================================================================
# INTERNAL DATA STRUCTURES
# =============================================================================

enum DistrictType {
	COMMERCIAL,
	INDUSTRIAL, 
	RESIDENTIAL,
	STRATEGIC
}

enum BuildingSize {
	SMALL,
	MEDIUM,
	LARGE,
	SKYSCRAPER
}

class BuildingData:
	var asset_path: String
	var position: Vector3
	var rotation: float
	var district_type: DistrictType
	var building_size: BuildingSize
	var strategic_value: int
	var collision_size: Vector3
	var navigation_obstacle: bool = true
	
	func _init(asset: String, pos: Vector3, rot: float = 0.0):
		asset_path = asset
		position = pos
		rotation = rot
		collision_size = Vector3(4, 6, 4)  # Default size

class RoadData:
	var asset_path: String
	var position: Vector3
	var rotation: float
	var road_type: String
	var width: float
	
	func _init(asset: String, pos: Vector3, rot: float = 0.0):
		asset_path = asset
		position = pos
		rotation = rot
		road_type = "street"
		width = 2.0

# Asset catalogs - organized by category using actual Kenney GLB assets
var commercial_assets: Array[String] = []
var industrial_assets: Array[String] = []
var residential_assets: Array[String] = []
var road_assets: Array[String] = []

# Asset validation
var assets_initialized: bool = false

# Scene organization nodes
var buildings_container: Node3D
var roads_container: Node3D
var navigation_container: Node3D

# Placed building and road data
var placed_buildings: Array[BuildingData] = []
var placed_roads: Array[RoadData] = []

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	
	print("BuildingManager: Editor tool initialized")
	_initialize_assets()
	_setup_containers()
	
	if auto_generate_on_ready:
		call_deferred("_generate_full_map_safe")

func _initialize_assets() -> void:
	"""Initialize asset arrays with actual Kenney GLB assets"""
	print("BuildingManager: Initializing Kenney assets...")
	
	# Commercial buildings (high-detail buildings + skyscrapers + low-detail)
	commercial_assets = [
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-a.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-b.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-c.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-d.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-e.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-f.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-g.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-h.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-skyscraper-a.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-skyscraper-b.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/building-skyscraper-c.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-a.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-b.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-c.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-d.glb"
	]
	
	# Industrial buildings (factories + chimneys + tanks)
	industrial_assets = [
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-a.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-b.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-c.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-d.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-e.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-f.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-g.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/building-h.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/chimney-large.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/chimney-medium.glb",
		"res://assets/kenney/kenney_city-kit-industrial_1/Models/GLB format/detail-tank.glb"
	]
	
	# Residential buildings (low-detail buildings for neighborhoods)
	residential_assets = [
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-e.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-f.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-g.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-h.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-i.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-j.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-k.glb",
		"res://assets/kenney/kenney_city-kit-commercial_20/Models/GLB format/low-detail-building-l.glb"
	]
	
	# Road assets (basic road pieces)
	road_assets = [
		"res://assets/kenney/kenney_city-kit-roads/Models/GLB format/road-straight.glb",
		"res://assets/kenney/kenney_city-kit-roads/Models/GLB format/road-curve.glb",
		"res://assets/kenney/kenney_city-kit-roads/Models/GLB format/road-intersection.glb",
		"res://assets/kenney/kenney_city-kit-roads/Models/GLB format/road-crossroad.glb",
		"res://assets/kenney/kenney_city-kit-roads/Models/GLB format/road-roundabout.glb",
		"res://assets/kenney/kenney_city-kit-roads/Models/GLB format/road-end.glb",
		"res://assets/kenney/kenney_city-kit-roads/Models/GLB format/road-bend.glb"
	]
	
	assets_initialized = true
	print("BuildingManager: Loaded %d commercial, %d industrial, %d residential, %d road assets" % [
		commercial_assets.size(), industrial_assets.size(), residential_assets.size(), road_assets.size()
	])

func _setup_containers() -> void:
	"""Create organized container nodes for different map elements"""
	# Buildings container
	buildings_container = get_node_or_null("Buildings")
	if not buildings_container:
		buildings_container = Node3D.new()
		buildings_container.name = "Buildings"
		add_child(buildings_container)
		if Engine.is_editor_hint():
			buildings_container.set_owner(get_tree().edited_scene_root)
	
	# Roads container  
	roads_container = get_node_or_null("Roads")
	if not roads_container:
		roads_container = Node3D.new()
		roads_container.name = "Roads"
		add_child(roads_container)
		if Engine.is_editor_hint():
			roads_container.set_owner(get_tree().edited_scene_root)
	
	# Navigation container
	navigation_container = get_node_or_null("NavigationObstacles")
	if not navigation_container:
		navigation_container = Node3D.new()
		navigation_container.name = "NavigationObstacles"
		add_child(navigation_container)
		if Engine.is_editor_hint():
			navigation_container.set_owner(get_tree().edited_scene_root)

# =============================================================================
# INSPECTOR BUTTON CALLBACKS
# =============================================================================

func _on_generate_full_map(value: bool) -> void:
	if value and Engine.is_editor_hint():
		print("BuildingManager: Starting map generation...")
		# Reset the checkbox immediately to prevent multiple clicks
		_generate_full_map = false
		# Use call_deferred to avoid blocking the editor
		call_deferred("_generate_full_map_safe")

func _on_generate_buildings_only(value: bool) -> void:
	if value and Engine.is_editor_hint():
		_generate_buildings_only = false
		print("BuildingManager: Generating buildings only...")
		call_deferred("_generate_buildings_safe")

func _on_generate_roads_only(value: bool) -> void:
	if value and Engine.is_editor_hint():
		_generate_roads_only = false
		print("BuildingManager: Generating roads only...")
		call_deferred("_generate_roads_safe")

func _on_clear_all_buildings(value: bool) -> void:
	if value and Engine.is_editor_hint():
		_clear_all_buildings = false
		print("BuildingManager: Clearing buildings...")
		call_deferred("_clear_buildings_impl")

func _on_clear_all_roads(value: bool) -> void:
	if value and Engine.is_editor_hint():
		_clear_all_roads = false
		print("BuildingManager: Clearing roads...")
		call_deferred("_clear_roads_impl")

func _on_update_navigation(value: bool) -> void:
	if value and Engine.is_editor_hint():
		_update_navigation_impl()

func _on_save_layout_as_resource(value: bool) -> void:
	if value and Engine.is_editor_hint():
		_save_layout_impl()

# =============================================================================
# CORE GENERATION IMPLEMENTATIONS  
# =============================================================================

func _generate_full_map_safe() -> void:
	"""Safe version of map generation with error handling"""
	print("BuildingManager: Starting map generation...")
	
	# Validate assets first
	if not validate_assets():
		print("BuildingManager: ERROR - Asset validation failed!")
		return
	
	_setup_containers()
	
	if clear_existing_on_generate:
		_clear_buildings_impl()
		_clear_roads_impl()
	
	# Choose generation method based on safe mode setting
	if use_safe_mode:
		print("BuildingManager: Using safe mode (limited assets)")
		if generate_buildings:
			_generate_buildings_safe()
		if generate_roads:
			_generate_roads_safe()
	else:
		print("BuildingManager: Using full generation mode")
		if generate_buildings:
			_generate_buildings_impl()
		if generate_roads:
			_generate_roads_impl()
	
	if generate_navigation_obstacles:
		_update_navigation_impl()
	
	print("BuildingManager: Map generation complete!")

func _generate_full_map_impl() -> void:
	"""Generate the complete map with buildings and roads"""
	print("BuildingManager: Generating full map...")
	
	if clear_existing_on_generate:
		_clear_buildings_impl()
		_clear_roads_impl()
	
	_setup_containers()
	
	if generate_buildings:
		_generate_buildings_impl()
	
	if generate_roads:
		_generate_roads_impl()
	
	if generate_navigation_obstacles:
		_update_navigation_impl()
	
	print("BuildingManager: Map generation complete!")

func _generate_buildings_safe() -> void:
	"""Safe building generation with Kenney assets"""
	print("BuildingManager: Generating buildings safely...")
	
	# Generate a few buildings of different types
	_place_kenney_building(Vector3(-15, 0, -15), DistrictType.COMMERCIAL)
	_place_kenney_building(Vector3(15, 0, -15), DistrictType.INDUSTRIAL)
	_place_kenney_building(Vector3(-15, 0, 15), DistrictType.RESIDENTIAL)
	_place_kenney_building(Vector3(15, 0, 15), DistrictType.COMMERCIAL)
	_place_kenney_building(Vector3(0, 0, 25), DistrictType.INDUSTRIAL)
	
	print("BuildingManager: Safe building generation complete")

func _generate_roads_safe() -> void:
	"""Safe road generation with Kenney assets"""
	print("BuildingManager: Generating roads safely...")
	
	# Generate a simple cross pattern
	_place_kenney_road(Vector3(0, 0, 0), "crossroad")
	_place_kenney_road(Vector3(10, 0, 0), "straight")
	_place_kenney_road(Vector3(-10, 0, 0), "straight")
	_place_kenney_road(Vector3(0, 0, 10), "straight")
	_place_kenney_road(Vector3(0, 0, -10), "straight")
	
	print("BuildingManager: Safe road generation complete")

func _generate_buildings_impl() -> void:
	"""Generate buildings in districts"""
	print("BuildingManager: Generating buildings...")
	
	var half_size = map_size * 0.5
	
	# Define district bounds
	var districts = {}
	if commercial_district_enabled:
		districts[DistrictType.COMMERCIAL] = Rect2(
			Vector2(-half_size.x * 0.5, -half_size.y * 0.5),
			Vector2(half_size.x, half_size.y)
		)
	
	if industrial_district_enabled:
		districts[DistrictType.INDUSTRIAL] = Rect2(
			Vector2(-half_size.x, -half_size.y),  
			Vector2(half_size.x * 0.8, half_size.y * 0.8)
		)
	
	if residential_district_enabled:
		districts[DistrictType.RESIDENTIAL] = Rect2(
			Vector2(half_size.x * 0.2, half_size.y * 0.2),
			Vector2(half_size.x * 0.8, half_size.y * 0.8)
		)
	
	# Generate buildings for each district
	for district_type in districts:
		var bounds = districts[district_type]
		_generate_district_buildings(district_type, bounds)

func _generate_district_buildings(district_type: DistrictType, bounds: Rect2) -> void:
	"""Generate buildings for a specific district"""
	var assets: Array[String]
	var density: float
	var building_spacing: float
	
	match district_type:
		DistrictType.COMMERCIAL:
			assets = commercial_assets
			density = commercial_building_density
			building_spacing = 12.0
		DistrictType.INDUSTRIAL:
			assets = industrial_assets  
			density = industrial_building_density
			building_spacing = 20.0
		DistrictType.RESIDENTIAL:
			assets = residential_assets
			density = residential_building_density
			building_spacing = 8.0
		_:
			return
	
	var building_count = int((bounds.size.x * bounds.size.y / (building_spacing * building_spacing)) * density)
	building_count = min(building_count, max_buildings_per_district)
	
	for i in range(building_count):
		var random_pos = Vector2(
			bounds.position.x + randf() * bounds.size.x,
			bounds.position.y + randf() * bounds.size.y
		)
		
		if snap_to_grid:
			random_pos = Vector2(
				round(random_pos.x / grid_size) * grid_size,
				round(random_pos.y / grid_size) * grid_size
			)
		
		var world_pos = Vector3(random_pos.x, 0, random_pos.y) + map_center
		var asset_path = assets[randi() % assets.size()]
		var rotation = randf() * TAU if district_type != DistrictType.COMMERCIAL else 0.0
		
		_place_building(asset_path, world_pos, rotation, district_type)

func _generate_roads_impl() -> void:
	"""Generate road network"""
	print("BuildingManager: Generating roads...")
	
	if create_cross_arteries:
		_create_main_arteries()
	
	if create_ring_roads:
		_create_ring_roads()
	
	_create_connecting_streets()

func _create_main_arteries() -> void:
	"""Create main N-S and E-W roads"""
	var half_size = map_size * 0.5
	
	# North-South main road
	var ns_segments = int(map_size.y / road_spacing)
	for i in range(ns_segments):
		var z_pos = -half_size.y + (i * road_spacing)
		_place_road("road-straight", Vector3(0, 0, z_pos), 0.0, "main_artery")
	
	# East-West main road  
	var ew_segments = int(map_size.x / road_spacing)
	for i in range(ew_segments):
		var x_pos = -half_size.x + (i * road_spacing)
		_place_road("road-straight", Vector3(x_pos, 0, 0), PI * 0.5, "main_artery")
	
	# Central intersection
	_place_road("road-crossroad", Vector3(0, 0, 0), 0.0, "intersection")

func _create_ring_roads() -> void:
	"""Create ring roads around districts"""
	var ring_radius = map_size.length() * 0.3
	var segments = 16
	
	for i in range(segments):
		var angle = (i / float(segments)) * TAU
		var pos = Vector3(
			cos(angle) * ring_radius,
			0,
			sin(angle) * ring_radius
		) + map_center
		
		var road_rotation = angle + PI * 0.5
		var asset = "road-curve" if i % 4 == 0 else "road-straight"
		_place_road(asset, pos, road_rotation, "ring_road")

func _create_connecting_streets() -> void:
	"""Create local connecting streets between main roads"""
	var half_size = map_size * 0.5
	var street_spacing = road_spacing * 0.5
	
	# Create grid of local streets
	var x_streets = int(map_size.x / street_spacing)
	var z_streets = int(map_size.y / street_spacing)
	
	for x in range(x_streets):
		for z in range(z_streets):
			if randf() > 0.3:  # Not every intersection gets a street
				continue
				
			var world_pos = Vector3(
				-half_size.x + (x * street_spacing),
				0,
				-half_size.y + (z * street_spacing)
			) + map_center
			
			# Randomly choose road type and orientation
			var road_type = ["road-straight", "road-curve"][randi() % 2]
			var rotation = [0.0, PI * 0.5, PI, PI * 1.5][randi() % 4]
			
			_place_road(road_type, world_pos, rotation, "local_street")

# =============================================================================
# BUILDING & ROAD PLACEMENT
# =============================================================================

func _place_building(asset_path: String, position: Vector3, rotation: float, district_type: DistrictType) -> void:
	"""Place a single building at the specified position with lazy loading"""
	
	# Check if we should force fallback assets to avoid any loading issues
	if force_fallback_assets:
		print("BuildingManager: Using fallback assets (force_fallback_assets enabled)")
		_place_fallback_building(position, rotation, district_type)
		return
	
	print("BuildingManager: Loading building asset: ", asset_path)
	
	# Use ResourceLoader.load() for on-demand loading
	var building_scene = ResourceLoader.load(asset_path)
	if not building_scene:
		print("BuildingManager: Failed to load building asset: ", asset_path)
		# Create a fallback simple building
		_place_fallback_building(position, rotation, district_type)
		return
	
	var building_node = building_scene.instantiate()
	if not building_node:
		print("BuildingManager: Failed to instantiate building: ", asset_path)
		_place_fallback_building(position, rotation, district_type)
		return
	
	# Configure building transform
	building_node.global_position = position
	building_node.rotation.y = rotation
	building_node.scale *= building_scale
	
	# Set up building properties
	building_node.name = "Building_" + str(placed_buildings.size())
	
	# Add to scene
	buildings_container.add_child(building_node)
	if Engine.is_editor_hint():
		building_node.set_owner(get_tree().edited_scene_root)
	
	# Setup collision and navigation
	_setup_building_collision(building_node)
	_setup_building_navigation_obstacle(building_node)
	
	# Store building data
	var building_data = BuildingData.new(asset_path, position, rotation)
	building_data.district_type = district_type
	placed_buildings.append(building_data)
	
	print("BuildingManager: Successfully placed building at ", position)

func _place_fallback_building(position: Vector3, rotation: float, district_type: DistrictType) -> void:
	"""Place a simple fallback building when asset loading fails"""
	print("BuildingManager: Creating fallback building at ", position)
	
	# Create a simple geometric building
	var building_node = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	
	# Different sizes based on district type
	match district_type:
		DistrictType.COMMERCIAL:
			box_mesh.size = Vector3(6, 12, 6)
		DistrictType.INDUSTRIAL:
			box_mesh.size = Vector3(8, 8, 10)
		DistrictType.RESIDENTIAL:
			box_mesh.size = Vector3(4, 6, 4)
		_:
			box_mesh.size = Vector3(6, 8, 6)
	
	building_node.mesh = box_mesh
	
	# Create a simple material
	var material = StandardMaterial3D.new()
	match district_type:
		DistrictType.COMMERCIAL:
			material.albedo_color = Color.BLUE
		DistrictType.INDUSTRIAL:
			material.albedo_color = Color.ORANGE
		DistrictType.RESIDENTIAL:
			material.albedo_color = Color.GREEN
		_:
			material.albedo_color = Color.GRAY
	
	building_node.material_override = material
	
	# Configure transform
	building_node.global_position = position
	building_node.rotation.y = rotation
	building_node.scale *= building_scale
	building_node.name = "FallbackBuilding_" + str(placed_buildings.size())
	
	# Add to scene
	buildings_container.add_child(building_node)
	if Engine.is_editor_hint():
		building_node.set_owner(get_tree().edited_scene_root)
	
	# Setup collision and navigation
	_setup_building_collision(building_node)
	_setup_building_navigation_obstacle(building_node)
	
	# Store building data
	var building_data = BuildingData.new("fallback", position, rotation)
	building_data.district_type = district_type
	placed_buildings.append(building_data)

func _place_road(asset_name: String, position: Vector3, rotation: float, road_type: String) -> void:
	"""Place a single road piece with lazy loading"""
	var asset_path = "res://assets/kenney/kenney_city-kit-roads/Models/GLB format/" + asset_name + ".glb"
	
	# Check if we should force fallback assets to avoid any loading issues
	if force_fallback_assets:
		print("BuildingManager: Using fallback road assets (force_fallback_assets enabled)")
		_place_fallback_road(position, rotation, road_type)
		return
	
	print("BuildingManager: Loading road asset: ", asset_path)
	
	# Use ResourceLoader.load() for on-demand loading
	var road_scene = ResourceLoader.load(asset_path)
	if not road_scene:
		print("BuildingManager: Failed to load road asset: ", asset_path)
		_place_fallback_road(position, rotation, road_type)
		return
	
	var road_node = road_scene.instantiate()
	if not road_node:
		print("BuildingManager: Failed to instantiate road: ", asset_path)
		_place_fallback_road(position, rotation, road_type)
		return
	
	# Configure road transform
	road_node.global_position = position
	road_node.rotation.y = rotation
	road_node.scale *= road_scale
	
	# Set up road properties
	road_node.name = "Road_" + str(placed_roads.size())
	
	# Add to scene
	roads_container.add_child(road_node)
	if Engine.is_editor_hint():
		road_node.set_owner(get_tree().edited_scene_root)
	
	# Store road data
	var road_data = RoadData.new(asset_path, position, rotation)
	road_data.road_type = road_type
	placed_roads.append(road_data)
	
	print("BuildingManager: Successfully placed road at ", position)

func _place_fallback_road(position: Vector3, rotation: float, road_type: String) -> void:
	"""Place a simple fallback road when asset loading fails"""
	print("BuildingManager: Creating fallback road at ", position)
	
	# Create a simple geometric road
	var road_node = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(8, 0.2, 8)
	road_node.mesh = box_mesh
	
	# Create a simple gray material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.GRAY
	road_node.material_override = material
	
	# Configure transform
	road_node.global_position = position
	road_node.rotation.y = rotation
	road_node.scale *= road_scale
	road_node.name = "FallbackRoad_" + str(placed_roads.size())
	
	# Add to scene
	roads_container.add_child(road_node)
	if Engine.is_editor_hint():
		road_node.set_owner(get_tree().edited_scene_root)
	
	# Store road data
	var road_data = RoadData.new("fallback", position, rotation)
	road_data.road_type = road_type
	placed_roads.append(road_data)

func _setup_building_collision(building_node: Node3D) -> void:
	"""Setup collision for building (non-traversable but untargetable)"""
	var static_body = StaticBody3D.new()
	static_body.name = "BuildingCollision"
	
	# Configure collision layers
	static_body.set_collision_layer_value(building_collision_layer, true)
	static_body.set_collision_mask_value(1, false)  # Don't collide with units
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(6, 8, 6) * building_scale
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, 4 * building_scale, 0)
	
	static_body.add_child(collision_shape)
	building_node.add_child(static_body)
	
	if Engine.is_editor_hint():
		static_body.set_owner(get_tree().edited_scene_root)
		collision_shape.set_owner(get_tree().edited_scene_root)

func _setup_building_navigation_obstacle(building_node: Node3D) -> void:
	"""Setup NavigationObstacle3D for pathfinding"""
	if not generate_navigation_obstacles:
		return
	
	var nav_obstacle = NavigationObstacle3D.new()
	nav_obstacle.name = "NavigationObstacle"
	
	# Configure obstacle properties
	nav_obstacle.radius = (3.0 + obstacle_margin) * building_scale
	nav_obstacle.height = 8.0 * building_scale
	nav_obstacle.avoidance_enabled = true
	
	building_node.add_child(nav_obstacle)
	
	if Engine.is_editor_hint():
		nav_obstacle.set_owner(get_tree().edited_scene_root)

# =============================================================================
# CLEANUP METHODS
# =============================================================================

func _clear_buildings_impl() -> void:
	"""Clear all placed buildings"""
	print("BuildingManager: Clearing all buildings...")
	
	if buildings_container:
		for child in buildings_container.get_children():
			child.queue_free()
	
	placed_buildings.clear()

func _clear_roads_impl() -> void:
	"""Clear all placed roads"""
	print("BuildingManager: Clearing all roads...")
	
	if roads_container:
		for child in roads_container.get_children():
			child.queue_free()
	
	placed_roads.clear()

# =============================================================================
# NAVIGATION & UTILITY METHODS
# =============================================================================

func _update_navigation_impl() -> void:
	"""Update navigation mesh to account for new buildings"""
	print("BuildingManager: Updating navigation mesh...")
	
	if not update_navigation_mesh:
		return
	
	# Find NavigationRegion3D in the scene
	var nav_region = get_tree().get_first_node_in_group("navigation_regions")
	if not nav_region:
		# Try to find it in the parent scene
		var scene_root = get_tree().edited_scene_root
		if scene_root:
			nav_region = scene_root.find_child("NavigationRegion3D", true, false)
	
	if nav_region and nav_region is NavigationRegion3D:
		# Trigger navigation mesh baking
		nav_region.bake_navigation_mesh()
		print("BuildingManager: Navigation mesh updated")
	else:
		print("BuildingManager: No NavigationRegion3D found")

func _save_layout_impl() -> void:
	"""Save current layout as a resource for reuse"""
	print("BuildingManager: Saving layout as resource...")
	
	var layout_data = {
		"buildings": [],
		"roads": [],
		"map_size": map_size,
		"map_center": map_center
	}
	
	for building in placed_buildings:
		layout_data.buildings.append({
			"asset_path": building.asset_path,
			"position": [building.position.x, building.position.y, building.position.z],
			"rotation": building.rotation,
			"district_type": building.district_type
		})
	
	for road in placed_roads:
		layout_data.roads.append({
			"asset_path": road.asset_path,
			"position": [road.position.x, road.position.y, road.position.z],
			"rotation": road.rotation,
			"road_type": road.road_type
		})
	
	var file = FileAccess.open("res://maps/saved_layout.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(layout_data))
		file.close()
		print("BuildingManager: Layout saved to res://maps/saved_layout.json")
	else:
		print("BuildingManager: Failed to save layout")

# =============================================================================
# MANUAL PLACEMENT TOOLS (for future enhancement)
# =============================================================================

func place_building_at_position(position: Vector3, asset_name: String = "") -> void:
	"""Manual building placement - can be called from other tools"""
	var asset_path = asset_name if not asset_name.is_empty() else selected_building_asset
	_place_building(asset_path, position, building_rotation, DistrictType.COMMERCIAL)

func get_building_at_position(position: Vector3, tolerance: float = 2.0) -> Node3D:
	"""Get building near the specified position"""
	for child in buildings_container.get_children():
		if child.global_position.distance_to(position) <= tolerance:
			return child
	return null

func remove_building_at_position(position: Vector3, tolerance: float = 2.0) -> bool:
	"""Remove building near the specified position"""
	var building = get_building_at_position(position, tolerance)
	if building:
		building.queue_free()
		return true
	return false

# =============================================================================
# VALIDATION & DEBUGGING
# =============================================================================

func validate_assets() -> bool:
	"""Validate that Kenney assets are available"""
	if not assets_initialized:
		print("BuildingManager: Assets not initialized")
		return false
	
	if commercial_assets.is_empty() or road_assets.is_empty():
		print("BuildingManager: Asset arrays are empty")
		return false
	
	# Quick validation without actually loading assets (to avoid freezing)
	print("BuildingManager: Asset validation passed (%d commercial, %d industrial, %d residential, %d road)" % [
		commercial_assets.size(), industrial_assets.size(), residential_assets.size(), road_assets.size()
	])
	return true

func get_building_count_by_district() -> Dictionary:
	"""Get building counts organized by district"""
	var counts = {}
	for building in placed_buildings:
		var district = building.district_type
		counts[district] = counts.get(district, 0) + 1
	return counts

func get_layout_statistics() -> Dictionary:
	"""Get statistics about the current layout"""
	return {
		"total_buildings": placed_buildings.size(),
		"total_roads": placed_roads.size(),
		"district_counts": get_building_count_by_district(),
		"map_coverage": (placed_buildings.size() * 16.0) / (map_size.x * map_size.y) * 100.0
	}

func _place_kenney_building(position: Vector3, district_type: DistrictType) -> void:
	"""Place a Kenney building asset"""
	var assets: Array[String]
	match district_type:
		DistrictType.COMMERCIAL:
			assets = commercial_assets
		DistrictType.INDUSTRIAL:
			assets = industrial_assets
		DistrictType.RESIDENTIAL:
			assets = residential_assets
		_:
			assets = commercial_assets
	
	if assets.is_empty():
		print("BuildingManager: No assets available for district type")
		return
	
	var asset_path = assets[randi() % assets.size()]
	_place_building(asset_path, position, randf() * TAU, district_type)

func _place_kenney_road(position: Vector3, road_type: String = "straight") -> void:
	"""Place a Kenney road asset"""
	if road_assets.is_empty():
		print("BuildingManager: No road assets available")
		return
	
	var asset_name: String
	match road_type:
		"straight":
			asset_name = "road-straight"
		"curve":
			asset_name = "road-curve"
		"intersection":
			asset_name = "road-intersection"
		"crossroad":
			asset_name = "road-crossroad"
		_:
			asset_name = "road-straight"
	
	_place_road(asset_name, position, 0.0, road_type) 