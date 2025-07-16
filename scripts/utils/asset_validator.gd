# AssetValidator.gd - Utility to validate game asset integrity
class_name AssetValidator
extends Node

# Asset paths to validate
const WEAPON_BASE_PATH = "res://assets/kenney/kenney_blaster-kit-2/Models/GLB format/"
const CHARACTER_BASE_PATH = "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/"
const AUDIO_SFX_PATH = "res://assets/audio/sfx/"
const AUDIO_UI_PATH = "res://assets/audio/ui/"

# Required weapons (from weapon database)
const REQUIRED_WEAPONS = [
	"blaster-a", "blaster-b", "blaster-c", "blaster-d", "blaster-e",
	"blaster-f", "blaster-g", "blaster-h", "blaster-i", "blaster-j",
	"blaster-k", "blaster-l", "blaster-m", "blaster-n", "blaster-o",
	"blaster-p", "blaster-q", "blaster-r"
]

# Required character models (from animated unit)
const REQUIRED_CHARACTERS = [
	"character-a",  # scout
	"character-h",  # tank  
	"character-d",  # sniper
	"character-p",  # medic
	"character-o"   # engineer
]

# Required attachments
const REQUIRED_ATTACHMENTS = [
	"scope-large-a", "scope-large-b", "scope-small",
	"clip-large", "clip-small"
]

# Required audio files
const REQUIRED_AUDIO_SFX = [
	"blaster_light_01.wav", "blaster_light_02.wav",
	"blaster_medium_01.wav", "blaster_medium_02.wav", 
	"blaster_heavy_01.wav", "blaster_heavy_02.wav",
	"blaster_rapid_01.wav", "blaster_cannon_01.wav",
	"blaster_cannon_02.wav", "blaster_utility_01.wav",
	"blaster_support_01.wav", "unit_death_01.wav"
]

const REQUIRED_AUDIO_UI = [
	"command_submit_01.wav", "click_01.wav"
]

var logger
var validation_results: Dictionary = {}

func _ready() -> void:
	_setup_logger()

func _setup_logger() -> void:
	"""Setup logger reference"""
	if has_node("/root/DependencyContainer"):
		var dependency_container = get_node("/root/DependencyContainer")
		if dependency_container.has_method("get_logger"):
			logger = dependency_container.get_logger()

func validate_all_assets() -> Dictionary:
	"""Validate all game assets and return results"""
	validation_results.clear()
	
	_log_info("Starting asset validation...")
	
	# Validate weapons
	validation_results["weapons"] = _validate_weapons()
	
	# Validate characters  
	validation_results["characters"] = _validate_characters()
	
	# Validate attachments
	validation_results["attachments"] = _validate_attachments()
	
	# Validate audio
	validation_results["audio_sfx"] = _validate_audio_sfx()
	validation_results["audio_ui"] = _validate_audio_ui()
	
	# Calculate overall results
	var total_assets = 0
	var valid_assets = 0
	
	for category in validation_results:
		var category_result = validation_results[category]
		total_assets += category_result.total
		valid_assets += category_result.valid
	
	validation_results["overall"] = {
		"total": total_assets,
		"valid": valid_assets,
		"success_rate": float(valid_assets) / float(total_assets) if total_assets > 0 else 0.0
	}
	
	_log_info("Asset validation complete: %d/%d assets valid (%.1f%%)" % [
		valid_assets, total_assets, validation_results["overall"]["success_rate"] * 100.0
	])
	
	return validation_results

func _validate_weapons() -> Dictionary:
	"""Validate weapon model assets"""
	var result = {"valid": 0, "total": 0, "missing": [], "errors": []}
	
	for weapon in REQUIRED_WEAPONS:
		result.total += 1
		var weapon_path = WEAPON_BASE_PATH + weapon + ".glb"
		
		if _validate_asset_file(weapon_path):
			result.valid += 1
		else:
			result.missing.append(weapon)
			_log_warning("Missing weapon asset: %s" % weapon_path)
	
	return result

func _validate_characters() -> Dictionary:
	"""Validate character model assets"""
	var result = {"valid": 0, "total": 0, "missing": [], "errors": []}
	
	for character in REQUIRED_CHARACTERS:
		result.total += 1
		var character_path = CHARACTER_BASE_PATH + character + ".glb"
		
		if _validate_asset_file(character_path):
			result.valid += 1
		else:
			result.missing.append(character)
			_log_warning("Missing character asset: %s" % character_path)
	
	return result

func _validate_attachments() -> Dictionary:
	"""Validate attachment model assets"""
	var result = {"valid": 0, "total": 0, "missing": [], "errors": []}
	
	for attachment in REQUIRED_ATTACHMENTS:
		result.total += 1
		var attachment_path = WEAPON_BASE_PATH + attachment + ".glb"
		
		if _validate_asset_file(attachment_path):
			result.valid += 1
		else:
			result.missing.append(attachment)
			_log_warning("Missing attachment asset: %s" % attachment_path)
	
	return result

func _validate_audio_sfx() -> Dictionary:
	"""Validate SFX audio assets"""
	var result = {"valid": 0, "total": 0, "missing": [], "errors": []}
	
	for audio_file in REQUIRED_AUDIO_SFX:
		result.total += 1
		var audio_path = AUDIO_SFX_PATH + audio_file
		
		if _validate_asset_file(audio_path):
			result.valid += 1
		else:
			result.missing.append(audio_file)
			# Don't log warnings for audio files - they're expected to be missing initially
	
	return result

func _validate_audio_ui() -> Dictionary:
	"""Validate UI audio assets"""
	var result = {"valid": 0, "total": 0, "missing": [], "errors": []}
	
	for audio_file in REQUIRED_AUDIO_UI:
		result.total += 1
		var audio_path = AUDIO_UI_PATH + audio_file
		
		if _validate_asset_file(audio_path):
			result.valid += 1
		else:
			result.missing.append(audio_file)
			# Don't log warnings for audio files - they're expected to be missing initially
	
	return result

func _validate_asset_file(asset_path: String) -> bool:
	"""Validate a single asset file exists and can be loaded"""
	# Check if file exists
	if not ResourceLoader.exists(asset_path):
		return false
	
	# Try to load the resource
	var resource = load(asset_path)
	if not resource:
		return false
	
	return true

func print_validation_report() -> void:
	"""Print a detailed validation report"""
	if validation_results.is_empty():
		print("No validation results available. Run validate_all_assets() first.")
		return
	
	print("\n=== ASSET VALIDATION REPORT ===")
	
	var overall = validation_results.get("overall", {})
	print("Overall: %d/%d assets valid (%.1f%%)" % [
		overall.get("valid", 0),
		overall.get("total", 0), 
		overall.get("success_rate", 0.0) * 100.0
	])
	
	for category in ["weapons", "characters", "attachments", "audio_sfx", "audio_ui"]:
		if category in validation_results:
			var result = validation_results[category]
			print("\n%s: %d/%d valid" % [category.capitalize(), result.valid, result.total])
			
			if result.missing.size() > 0:
				print("  Missing: %s" % str(result.missing))
	
	print("\n==============================")

func get_missing_assets() -> Dictionary:
	"""Get a summary of all missing assets"""
	var missing = {}
	
	for category in validation_results:
		if category != "overall":
			var result = validation_results[category]
			if result.has("missing") and result.missing.size() > 0:
				missing[category] = result.missing
	
	return missing

func _log_info(message: String) -> void:
	"""Log info message"""
	if logger:
		logger.info("AssetValidator", message)
	else:
		print("AssetValidator: %s" % message)

func _log_warning(message: String) -> void:
	"""Log warning message"""
	if logger:
		logger.warning("AssetValidator", message)
	else:
		print("AssetValidator WARNING: %s" % message)

func _log_error(message: String) -> void:
	"""Log error message"""
	if logger:
		logger.error("AssetValidator", message)
	else:
		print("AssetValidator ERROR: %s" % message) 