# DistrictLayout.gd - Resource for configuring district layouts and boundaries
class_name DistrictLayout
extends Resource

@export_group("District Identification")
@export var district_name: String = ""
@export var district_type: String = "commercial"  # commercial, industrial, residential, mixed, strategic
@export var district_id: String = ""

@export_group("Boundaries")
@export var bounds_center: Vector2 = Vector2.ZERO
@export var bounds_size: Vector2 = Vector2(40, 40)
@export var bounds_rotation: float = 0.0

@export_group("Building Configuration")
@export var building_density: float = 0.5  # 0.0 to 1.0
@export var max_buildings: int = 20
@export var min_building_spacing: float = 8.0
@export var preferred_building_types: Array[String] = []
@export var snap_to_grid: bool = true
@export var grid_size: float = 4.0

@export_group("Road Configuration")
@export var has_main_road: bool = true
@export var road_pattern: String = "grid"  # grid, radial, organic, none
@export var road_density: float = 0.3
@export var connect_to_other_districts: bool = true

@export_group("Strategic Properties")
@export var strategic_value: int = 1
@export var defensive_advantage: float = 0.0  # -1.0 to 1.0
@export var resource_value: int = 0
@export var control_point_locations: Array[Vector2] = []

@export_group("Visual Theme")
@export var theme_color: Color = Color.WHITE
@export var building_scale_variance: float = 0.1  # 0.0 to 1.0
@export var rotation_variance: float = 15.0  # degrees
@export var height_preference: String = "mixed"  # low, medium, high, mixed, skyscraper

# Helper methods
func get_bounds_rect() -> Rect2:
	"""Get the district bounds as a Rect2"""
	return Rect2(
		bounds_center - bounds_size * 0.5,
		bounds_size
	)

func is_position_in_bounds(position: Vector2) -> bool:
	"""Check if a position is within district bounds"""
	var rect = get_bounds_rect()
	return rect.has_point(position)

func get_random_position_in_bounds() -> Vector2:
	"""Get a random position within district bounds"""
	var rect = get_bounds_rect()
	return Vector2(
		rect.position.x + randf() * rect.size.x,
		rect.position.y + randf() * rect.size.y
	)

func get_grid_aligned_position(position: Vector2) -> Vector2:
	"""Align position to grid if snap_to_grid is enabled"""
	if snap_to_grid and grid_size > 0:
		return Vector2(
			round(position.x / grid_size) * grid_size,
			round(position.y / grid_size) * grid_size
		)
	return position

func calculate_building_count() -> int:
	"""Calculate number of buildings based on density and bounds"""
	var area = bounds_size.x * bounds_size.y
	var theoretical_max = area / (min_building_spacing * min_building_spacing)
	var density_adjusted = int(theoretical_max * building_density)
	return min(density_adjusted, max_buildings)

func get_building_positions() -> Array[Vector2]:
	"""Generate building positions for this district"""
	var positions: Array[Vector2] = []
	var building_count = calculate_building_count()
	var attempts = 0
	var max_attempts = building_count * 10
	
	while positions.size() < building_count and attempts < max_attempts:
		var pos = get_random_position_in_bounds()
		pos = get_grid_aligned_position(pos)
		
		# Check minimum spacing from existing buildings
		var valid = true
		for existing_pos in positions:
			if pos.distance_to(existing_pos) < min_building_spacing:
				valid = false
				break
		
		if valid:
			positions.append(pos)
		
		attempts += 1
	
	return positions

func overlaps_with_district(other: DistrictLayout) -> bool:
	"""Check if this district overlaps with another district"""
	var rect1 = get_bounds_rect()
	var rect2 = other.get_bounds_rect()
	return rect1.intersects(rect2)

func validate() -> bool:
	"""Validate district configuration"""
	return not district_name.is_empty() and bounds_size.x > 0 and bounds_size.y > 0 and building_density >= 0.0 and building_density <= 1.0

# Static factory methods for common district types
static func create_commercial_district(center: Vector2, size: Vector2) -> DistrictLayout:
	var district = DistrictLayout.new()
	district.district_name = "Commercial District"
	district.district_type = "commercial"
	district.district_id = "commercial_" + str(Time.get_unix_time_from_system())
	district.bounds_center = center
	district.bounds_size = size
	district.building_density = 0.7
	district.max_buildings = 25
	district.min_building_spacing = 10.0
	district.preferred_building_types = ["commercial", "skyscraper"]
	district.has_main_road = true
	district.road_pattern = "grid"
	district.strategic_value = 3
	district.height_preference = "mixed"
	district.theme_color = Color.BLUE
	return district

static func create_industrial_district(center: Vector2, size: Vector2) -> DistrictLayout:
	var district = DistrictLayout.new()
	district.district_name = "Industrial District"
	district.district_type = "industrial"
	district.district_id = "industrial_" + str(Time.get_unix_time_from_system())
	district.bounds_center = center
	district.bounds_size = size
	district.building_density = 0.4
	district.max_buildings = 15
	district.min_building_spacing = 15.0
	district.preferred_building_types = ["industrial"]
	district.has_main_road = true
	district.road_pattern = "grid"
	district.strategic_value = 2
	district.height_preference = "high"
	district.theme_color = Color.ORANGE
	return district

static func create_residential_district(center: Vector2, size: Vector2) -> DistrictLayout:
	var district = DistrictLayout.new()
	district.district_name = "Residential District"
	district.district_type = "residential"
	district.district_id = "residential_" + str(Time.get_unix_time_from_system())
	district.bounds_center = center
	district.bounds_size = size
	district.building_density = 0.6
	district.max_buildings = 30
	district.min_building_spacing = 6.0
	district.preferred_building_types = ["residential"]
	district.has_main_road = false
	district.road_pattern = "organic"
	district.strategic_value = 1
	district.height_preference = "low"
	district.theme_color = Color.GREEN
	return district

static func create_strategic_district(center: Vector2, size: Vector2) -> DistrictLayout:
	var district = DistrictLayout.new()
	district.district_name = "Strategic District"
	district.district_type = "strategic"
	district.district_id = "strategic_" + str(Time.get_unix_time_from_system())
	district.bounds_center = center
	district.bounds_size = size
	district.building_density = 0.3
	district.max_buildings = 8
	district.min_building_spacing = 20.0
	district.preferred_building_types = ["commercial", "industrial"]
	district.has_main_road = true
	district.road_pattern = "radial"
	district.strategic_value = 5
	district.defensive_advantage = 0.5
	district.height_preference = "high"
	district.theme_color = Color.RED
	return district 