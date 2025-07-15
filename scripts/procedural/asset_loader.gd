# AssetLoader.gd - Kenney Asset Integration System
class_name AssetLoader
extends Node

# Load shared components
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Asset Collections
var road_assets: Dictionary = {}
var commercial_assets: Dictionary = {}
var industrial_assets: Dictionary = {}
var character_assets: Dictionary = {}

# Asset Pools for Performance
var road_pool: Dictionary = {}
var building_pool: Dictionary = {}
var character_pool: Dictionary = {}

# Loading Status
var loading_complete: bool = false
var loading_progress: float = 0.0

# Asset Base Paths
const KENNEY_BASE_PATH = "res://assets/kenney/"
const ROADS_PATH = KENNEY_BASE_PATH + "kenney_city-kit-roads/Models/GLB format/"
const COMMERCIAL_PATH = KENNEY_BASE_PATH + "kenney_city-kit-commercial_20/Models/GLB format/"
const INDUSTRIAL_PATH = KENNEY_BASE_PATH + "kenney_city-kit-industrial_1/Models/GLB format/"
const CHARACTERS_PATH = KENNEY_BASE_PATH + "kenney_blocky-characters_20/Models/GLB format/"

# Dependencies
var logger = null

signal assets_loaded()
signal loading_progress_updated(progress: float)

func _ready() -> void:
	# Asset loading will be initiated by the dependency system
	pass

func setup(logger_instance) -> void:
	"""Setup the AssetLoader with dependencies"""
	logger = logger_instance
	if logger:
		logger.info("AssetLoader", "AssetLoader setup completed")

func load_kenney_assets() -> void:
	"""Load all Kenney asset collections"""
	if loading_complete:
		return
		
	if logger:
		logger.info("AssetLoader", "Starting Kenney asset loading")
	
	loading_progress = 0.0
	loading_progress_updated.emit(loading_progress)
	
	# Load each asset collection
	_load_road_assets()
	loading_progress = 0.25
	loading_progress_updated.emit(loading_progress)
	
	_load_commercial_assets()
	loading_progress = 0.5
	loading_progress_updated.emit(loading_progress)
	
	_load_industrial_assets()
	loading_progress = 0.75
	loading_progress_updated.emit(loading_progress)
	
	_load_character_assets()
	loading_progress = 1.0
	loading_progress_updated.emit(loading_progress)
	
	loading_complete = true
	assets_loaded.emit()
	
	if logger:
		logger.info("AssetLoader", "Kenney asset loading completed")

func _load_road_assets() -> void:
	"""Load road and infrastructure assets"""
	road_assets = {
		"straight": [
			"road-straight.glb",
			"road-straight-half.glb",
			"road-straight-barrier.glb"
		],
		"intersections": [
			"road-intersection.glb",
			"road-crossroad.glb",
			"road-curve-intersection.glb"
		],
		"curves": [
			"road-curve.glb",
			"road-bend.glb",
			"road-bend-square.glb"
		],
		"specialized": [
			"road-roundabout.glb",
			"road-bridge.glb",
			"road-end.glb"
		],
		"tiles": [
			"tile-low.glb",
			"tile-high.glb",
			"tile-slant.glb"
		]
	}
	
	# Pre-load critical road assets
	for category in road_assets.keys():
		for asset_name in road_assets[category]:
			var asset_path = ROADS_PATH + asset_name
			if FileAccess.file_exists(asset_path):
				var asset = load(asset_path)
				if asset:
					road_assets[category + "_loaded"] = road_assets.get(category + "_loaded", [])
					road_assets[category + "_loaded"].append(asset)
	
	if logger:
		logger.info("AssetLoader", "Road assets loaded: %d categories" % road_assets.size())

func _load_commercial_assets() -> void:
	"""Load commercial building assets"""
	commercial_assets = {
		"buildings": [],
		"skyscrapers": [],
		"low_detail": [],
		"details": []
	}
	
	# Load standard buildings (a through n)
	var building_letters = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n"]
	for letter in building_letters:
		var building_name = "building-%s.glb" % letter
		var asset_path = COMMERCIAL_PATH + building_name
		if FileAccess.file_exists(asset_path):
			var asset = load(asset_path)
			if asset:
				commercial_assets["buildings"].append(asset)
	
	# Load skyscrapers (a through e)
	var skyscraper_letters = ["a", "b", "c", "d", "e"]
	for letter in skyscraper_letters:
		var skyscraper_name = "building-skyscraper-%s.glb" % letter
		var asset_path = COMMERCIAL_PATH + skyscraper_name
		if FileAccess.file_exists(asset_path):
			var asset = load(asset_path)
			if asset:
				commercial_assets["skyscrapers"].append(asset)
	
	# Load low detail buildings
	var low_detail_buildings = [
		"low-detail-building-a.glb", "low-detail-building-b.glb",
		"low-detail-building-c.glb", "low-detail-building-d.glb",
		"low-detail-building-wide-a.glb", "low-detail-building-wide-b.glb"
	]
	for building_name in low_detail_buildings:
		var asset_path = COMMERCIAL_PATH + building_name
		if FileAccess.file_exists(asset_path):
			var asset = load(asset_path)
			if asset:
				commercial_assets["low_detail"].append(asset)
	
	if logger:
		logger.info("AssetLoader", "Commercial assets loaded: %d buildings, %d skyscrapers" % [
			commercial_assets["buildings"].size(), 
			commercial_assets["skyscrapers"].size()
		])

func _load_industrial_assets() -> void:
	"""Load industrial building assets"""
	industrial_assets = {
		"buildings": [],
		"chimneys": [],
		"details": []
	}
	
	# Load industrial buildings (a through t)
	var building_letters = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t"]
	for letter in building_letters:
		var building_name = "building-%s.glb" % letter
		var asset_path = INDUSTRIAL_PATH + building_name
		if FileAccess.file_exists(asset_path):
			var asset = load(asset_path)
			if asset:
				industrial_assets["buildings"].append(asset)
	
	# Load chimneys
	var chimney_types = [
		"chimney-basic.glb", "chimney-large.glb",
		"chimney-medium.glb", "chimney-small.glb"
	]
	for chimney_name in chimney_types:
		var asset_path = INDUSTRIAL_PATH + chimney_name
		if FileAccess.file_exists(asset_path):
			var asset = load(asset_path)
			if asset:
				industrial_assets["chimneys"].append(asset)
	
	# Load details
	var detail_path = INDUSTRIAL_PATH + "detail-tank.glb"
	if FileAccess.file_exists(detail_path):
		var asset = load(detail_path)
		if asset:
			industrial_assets["details"].append(asset)
	
	if logger:
		logger.info("AssetLoader", "Industrial assets loaded: %d buildings, %d chimneys" % [
			industrial_assets["buildings"].size(), 
			industrial_assets["chimneys"].size()
		])

func _load_character_assets() -> void:
	"""Load character model assets"""
	character_assets = {
		"characters": []
	}
	
	# Load character models (a through r)
	var character_letters = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r"]
	for letter in character_letters:
		var character_name = "character-%s.glb" % letter
		var asset_path = CHARACTERS_PATH + character_name
		if FileAccess.file_exists(asset_path):
			var asset = load(asset_path)
			if asset:
				character_assets["characters"].append(asset)
	
	if logger:
		logger.info("AssetLoader", "Character assets loaded: %d characters" % character_assets["characters"].size())

func get_random_road_asset(category: String):
	"""Get a random road asset from the specified category"""
	var loaded_category = category + "_loaded"
	if road_assets.has(loaded_category) and road_assets[loaded_category].size() > 0:
		return road_assets[loaded_category][randi() % road_assets[loaded_category].size()]
	return null

func get_random_commercial_building():
	"""Get a random commercial building asset"""
	if commercial_assets["buildings"].size() > 0:
		return commercial_assets["buildings"][randi() % commercial_assets["buildings"].size()]
	return null

func get_random_industrial_building():
	"""Get a random industrial building asset"""
	if industrial_assets["buildings"].size() > 0:
		return industrial_assets["buildings"][randi() % industrial_assets["buildings"].size()]
	return null

func get_random_character():
	"""Get a random character asset"""
	if character_assets["characters"].size() > 0:
		return character_assets["characters"][randi() % character_assets["characters"].size()]
	return null

func get_skyscraper():
	"""Get a random skyscraper asset"""
	if commercial_assets["skyscrapers"].size() > 0:
		return commercial_assets["skyscrapers"][randi() % commercial_assets["skyscrapers"].size()]
	return null

func is_loading_complete() -> bool:
	"""Check if asset loading is complete"""
	return loading_complete

func get_loading_progress() -> float:
	"""Get current loading progress (0.0 to 1.0)"""
	return loading_progress

func get_asset_counts() -> Dictionary:
	"""Get counts of loaded assets for debugging"""
	return {
		"roads": road_assets.size(),
		"commercial": commercial_assets["buildings"].size(),
		"industrial": industrial_assets["buildings"].size(),
		"characters": character_assets["characters"].size()
	} 