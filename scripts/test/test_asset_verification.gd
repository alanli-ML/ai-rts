extends Node

# Load components
const Logger = preload("res://scripts/shared/utils/logger.gd")

var logger
var asset_loader
var building_placer
var world_asset_manager

func _ready() -> void:
	print("Starting Kenny Asset Verification Test")
	
	# Initialize logger
	logger = Logger.new()
	logger.setup()
	
	# Initialize asset loader
	var AssetLoaderClass = preload("res://scripts/procedural/asset_loader.gd")
	asset_loader = AssetLoaderClass.new()
	asset_loader.setup(logger)
	
	# Initialize building placer
	var BuildingPlacerClass = preload("res://scripts/procedural/building_placer.gd")
	building_placer = BuildingPlacerClass.new()
	building_placer.setup(logger, null, asset_loader, null)
	
	# Initialize world asset manager
	var WorldAssetManagerClass = preload("res://scripts/core/world_asset_manager.gd")
	world_asset_manager = WorldAssetManagerClass.new()
	world_asset_manager.setup(logger, asset_loader)
	
	# Start verification
	await verify_kenny_assets()

func verify_kenny_assets() -> void:
	"""Verify all Kenny assets are loaded and accessible"""
	print("=== KENNY ASSET VERIFICATION TEST ===")
	
	# Load assets
	print("Loading Kenny assets...")
	asset_loader.load_kenney_assets()
	
	# Wait for loading to complete
	await get_tree().process_frame
	
	# Verify asset loading
	print("\n--- Asset Loading Status ---")
	var asset_counts = asset_loader.get_asset_counts()
	for category in asset_counts:
		print("%s: %s" % [category, asset_counts[category]])
	
	# Detailed asset info
	print("\n--- Detailed Asset Information ---")
	var detailed_info = asset_loader.get_detailed_asset_info()
	print("Loading Complete: %s" % detailed_info.loading_complete)
	print("Commercial Buildings: %d" % detailed_info.commercial.buildings_count)
	print("Commercial Skyscrapers: %d" % detailed_info.commercial.skyscrapers_count)
	print("Industrial Buildings: %d" % detailed_info.industrial.buildings_count)
	print("Characters: %d" % detailed_info.characters.count)
	
	# Sample asset paths
	if detailed_info.commercial.sample_building_paths.size() > 0:
		print("\nSample Commercial Building Paths:")
		for path in detailed_info.commercial.sample_building_paths:
			print("  - %s" % path)
	
	if detailed_info.industrial.sample_building_paths.size() > 0:
		print("\nSample Industrial Building Paths:")
		for path in detailed_info.industrial.sample_building_paths:
			print("  - %s" % path)
	
	# Verify asset verification
	print("\n--- Asset Verification ---")
	var verification_passed = asset_loader.verify_assets_loaded()
	print("Verification Passed: %s" % verification_passed)
	
	# Test building type generation
	print("\n--- Building Type Generation Test ---")
	await test_building_type_generation()
	
	# Test asset loading through WorldAssetManager
	print("\n--- WorldAssetManager Integration Test ---")
	test_world_asset_manager_integration()
	
	print("\n=== VERIFICATION COMPLETE ===")

func test_building_type_generation() -> void:
	"""Test that all building types can be generated"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	
	print("Testing building type generation for each district type...")
	
	# Test each district type
	for district_type in range(5):  # 0-4: Commercial, Industrial, Mixed, Residential, Military
		var district_name = ["Commercial", "Industrial", "Mixed", "Residential", "Military"][district_type]
		print("\n%s District (Type %d):" % [district_name, district_type])
		
		var building_types = building_placer._get_building_types_for_district(district_type)
		print("  Available building types: %d" % building_types.size())
		
		# Show first 10 building types
		var max_show = min(10, building_types.size())
		for i in range(max_show):
			print("    - %s" % building_types[i])
		
		if building_types.size() > 10:
			print("    ... and %d more" % (building_types.size() - 10))
		
		# Test asset selection
		print("  Sample asset selections:")
		for i in range(3):
			var asset_path = building_placer._select_building_asset(district_type, rng)
			print("    Sample %d: %s" % [i + 1, asset_path])
		
		await get_tree().process_frame

func test_world_asset_manager_integration() -> void:
	"""Test WorldAssetManager integration with new building types"""
	print("Testing WorldAssetManager building asset loading...")
	
	# Test various building type patterns
	var test_types = [
		"building-a", "building-n", "building-skyscraper-c",
		"low-detail-building-a", "industrial-building-f",
		"chimney-large", "detail-tank",
		"commercial", "industrial", "mixed_large"
	]
	
	for building_type in test_types:
		var asset = world_asset_manager.load_building_asset_by_type(building_type)
		var status = "SUCCESS" if asset else "FAILED"
		print("  %s: %s" % [building_type, status])
		
		if asset:
			print("    Resource path: %s" % asset.resource_path)

func _exit_tree() -> void:
	print("Kenny Asset Verification Test completed") 