# BuildingConfiguration.gd - Resource for configuring building types and properties
class_name BuildingConfiguration
extends Resource

@export_group("Asset Configuration")
@export var building_name: String = ""
@export var asset_path: String = ""
@export var building_type: String = "commercial"  # commercial, industrial, residential, strategic

@export_group("Placement Properties")
@export var collision_size: Vector3 = Vector3(6, 8, 6)
@export var placement_offset: Vector3 = Vector3.ZERO
@export var allowed_rotations: Array[float] = [0.0, 90.0, 180.0, 270.0]
@export var can_be_rotated: bool = true

@export_group("Gameplay Properties")
@export var strategic_value: int = 1
@export var cover_rating: float = 0.5  # 0.0 = no cover, 1.0 = full cover
@export var sight_blocking: bool = true
@export var blocks_movement: bool = true

@export_group("District Settings")
@export var preferred_district_types: Array[String] = ["commercial"]
@export var placement_density_weight: float = 1.0
@export var minimum_spacing: float = 8.0
@export var maximum_per_district: int = 10

@export_group("Visual Settings")
@export var scale_multiplier: float = 1.0
@export var height_category: String = "medium"  # low, medium, high, skyscraper
@export var lod_distance_medium: float = 50.0
@export var lod_distance_low: float = 100.0

@export_group("Navigation")
@export var creates_navigation_obstacle: bool = true
@export var obstacle_radius: float = 4.0
@export var obstacle_height: float = 8.0
@export var avoidance_margin: float = 1.0

# Validation
func is_valid() -> bool:
	return not building_name.is_empty() and not asset_path.is_empty() and ResourceLoader.exists(asset_path)

func get_rotation_degrees() -> Array[float]:
	if can_be_rotated:
		return allowed_rotations
	else:
		return [0.0]

func get_scaled_collision_size() -> Vector3:
	return collision_size * scale_multiplier

func get_scaled_obstacle_radius() -> float:
	return (obstacle_radius + avoidance_margin) * scale_multiplier

func fits_in_district(district_type: String) -> bool:
	return district_type in preferred_district_types

# Create default configurations for common building types
static func create_commercial_config(asset_path: String, name: String) -> BuildingConfiguration:
	var config = BuildingConfiguration.new()
	config.building_name = name
	config.asset_path = asset_path
	config.building_type = "commercial"
	config.collision_size = Vector3(6, 8, 6)
	config.strategic_value = 2
	config.cover_rating = 0.7
	config.preferred_district_types = ["commercial"]
	config.height_category = "medium"
	return config

static func create_industrial_config(asset_path: String, name: String) -> BuildingConfiguration:
	var config = BuildingConfiguration.new()
	config.building_name = name
	config.asset_path = asset_path
	config.building_type = "industrial"
	config.collision_size = Vector3(8, 10, 8)
	config.strategic_value = 3
	config.cover_rating = 0.8
	config.preferred_district_types = ["industrial"]
	config.minimum_spacing = 12.0
	config.height_category = "high"
	return config

static func create_residential_config(asset_path: String, name: String) -> BuildingConfiguration:
	var config = BuildingConfiguration.new()
	config.building_name = name
	config.asset_path = asset_path
	config.building_type = "residential"
	config.collision_size = Vector3(4, 6, 4)
	config.strategic_value = 1
	config.cover_rating = 0.4
	config.preferred_district_types = ["residential"]
	config.minimum_spacing = 6.0
	config.height_category = "low"
	config.maximum_per_district = 15
	return config

static func create_skyscraper_config(asset_path: String, name: String) -> BuildingConfiguration:
	var config = BuildingConfiguration.new()
	config.building_name = name
	config.asset_path = asset_path
	config.building_type = "commercial"
	config.collision_size = Vector3(8, 20, 8)
	config.strategic_value = 5
	config.cover_rating = 0.9
	config.sight_blocking = true
	config.preferred_district_types = ["commercial"]
	config.minimum_spacing = 15.0
	config.height_category = "skyscraper"
	config.maximum_per_district = 3
	config.can_be_rotated = false  # Skyscrapers typically face specific directions
	return config 