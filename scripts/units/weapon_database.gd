# WeaponDatabase.gd - Weapon archetype mapping and selection system
class_name WeaponDatabase
extends Node

# Weapon-to-archetype mapping with multiple variants per archetype
const WEAPON_ASSIGNMENTS = {
	"scout": {
		"primary": ["blaster-a", "blaster-c", "blaster-c"],  # Light, fast weapons
		"secondary": ["blaster-e"],                           # Backup weapons
		"attachments": ["scope_small", "clip_small"],
		"preferred_range": "short_medium",
		"combat_style": "hit_and_run"
	},
	"soldier": {
		"primary": ["blaster-b", "blaster-f", "blaster-l"],  # Balanced weapons  
		"secondary": ["blaster-g"],                           # Backup weapons
		"attachments": ["scope_small", "clip_large"],
		"preferred_range": "medium",
		"combat_style": "balanced"
	},
	"tank": {
		"primary": ["blaster-j", "blaster-k", "blaster-n"],  # Heavy weapons
		"secondary": ["blaster-o"],                           # Backup weapons  
		"attachments": ["scope_large_a", "clip_large"],
		"preferred_range": "short_medium",
		"combat_style": "close_combat"
	},
	"sniper": {
		"primary": ["blaster-e", "blaster-f", "blaster-g"],  # Precision weapons
		"secondary": ["blaster-q"],                           # Backup weapons
		"attachments": ["scope_large_a", "scope_large_b"],
		"preferred_range": "long",
		"combat_style": "precision"
	},
	"medic": {
		"primary": ["blaster-q", "blaster-r"],               # Support weapons
		"secondary": ["blaster-a"],                           # Backup weapons
		"attachments": ["scope_small", "clip_small"],
		"preferred_range": "short",
		"combat_style": "support"
	},
	"engineer": {
		"primary": ["blaster-e", "blaster-g", "blaster-o"],  # Utility weapons
		"secondary": ["blaster-c"],                           # Backup weapons
		"attachments": ["scope_small", "clip_large"],
		"preferred_range": "medium",
		"combat_style": "utility"
	},
	"turret": {
		"primary": ["blaster-o"],  # Top-mounted utility carbine
		"secondary": [],
		"attachments": [],
		"preferred_range": "medium",
		"combat_style": "defensive"
	}
	# Note: Turrets use custom top-mounting instead of hand attachment
}

# Weapon specifications database
const WEAPON_SPECS = {
	"blaster-a": {
		"name": "Compact Blaster",
		"type": "pistol",
		"damage": 20.0,
		"range": 12.0,
		"fire_rate": 1.5,
		"accuracy": 0.9,
		"reload_time": 1.5,
		"max_ammo": 15,
		"weight": "light",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_light_01.wav"
	},
	"blaster-b": {
		"name": "Standard Rifle",
		"type": "rifle",
		"damage": 30.0,
		"range": 20.0,
		"fire_rate": 1.0,
		"accuracy": 0.85,
		"reload_time": 2.0,
		"max_ammo": 30,
		"weight": "medium",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_medium_01.wav"
	},
	"blaster-c": {
		"name": "Scout Pistol",
		"type": "pistol",
		"damage": 18.0,
		"range": 10.0,
		"fire_rate": 1.8,
		"accuracy": 0.88,
		"reload_time": 1.2,
		"max_ammo": 12,
		"weight": "light",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_light_02.wav"
	},
	"blaster-d": {
		"name": "Sniper Rifle",
		"type": "sniper",
		"damage": 45.0,
		"range": 35.0,
		"fire_rate": 0.5,
		"accuracy": 0.98,
		"reload_time": 3.0,
		"max_ammo": 8,
		"weight": "heavy",
		"rarity": "rare",
		"fire_sound": "res://assets/audio/sfx/blaster_heavy_01.wav"
	},
	"blaster-e": {
		"name": "Utility Carbine",
		"type": "carbine",
		"damage": 25.0,
		"range": 15.0,
		"fire_rate": 1.2,
		"accuracy": 0.82,
		"reload_time": 2.2,
		"max_ammo": 25,
		"weight": "medium",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_medium_02.wav"
	},
	"blaster-f": {
		"name": "Battle Rifle",
		"type": "rifle",
		"damage": 35.0,
		"range": 25.0,
		"fire_rate": 0.8,
		"accuracy": 0.87,
		"reload_time": 2.5,
		"max_ammo": 20,
		"weight": "medium",
		"rarity": "uncommon",
		"fire_sound": "res://assets/audio/sfx/blaster_medium_01.wav"
	},
	"blaster-g": {
		"name": "Submachine Gun",
		"type": "smg",
		"damage": 15.0,
		"range": 8.0,
		"fire_rate": 2.5,
		"accuracy": 0.75,
		"reload_time": 1.8,
		"max_ammo": 40,
		"weight": "light",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_rapid_01.wav"
	},
	"blaster-h": {
		"name": "Scout Carbine",
		"type": "carbine",
		"damage": 22.0,
		"range": 14.0,
		"fire_rate": 1.4,
		"accuracy": 0.85,
		"reload_time": 1.6,
		"max_ammo": 18,
		"weight": "light",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_medium_02.wav"
	},
	"blaster-i": {
		"name": "Marksman Rifle",
		"type": "marksman",
		"damage": 40.0,
		"range": 30.0,
		"fire_rate": 0.7,
		"accuracy": 0.95,
		"reload_time": 2.8,
		"max_ammo": 12,
		"weight": "heavy",
		"rarity": "uncommon",
		"fire_sound": "res://assets/audio/sfx/blaster_heavy_02.wav"
	},
	"blaster-j": {
		"name": "Heavy Blaster",
		"type": "heavy",
		"damage": 50.0,
		"range": 18.0,
		"fire_rate": 0.6,
		"accuracy": 0.78,
		"reload_time": 3.2,
		"max_ammo": 10,
		"weight": "heavy",
		"rarity": "rare",
		"fire_sound": "res://assets/audio/sfx/blaster_cannon_01.wav"
	},
	"blaster-k": {
		"name": "Assault Cannon",
		"type": "heavy",
		"damage": 55.0,
		"range": 20.0,
		"fire_rate": 0.5,
		"accuracy": 0.8,
		"reload_time": 3.5,
		"max_ammo": 8,
		"weight": "heavy",
		"rarity": "rare",
		"fire_sound": "res://assets/audio/sfx/blaster_cannon_01.wav"
	},
	"blaster-l": {
		"name": "Combat Rifle",
		"type": "rifle",
		"damage": 32.0,
		"range": 22.0,
		"fire_rate": 0.9,
		"accuracy": 0.86,
		"reload_time": 2.1,
		"max_ammo": 25,
		"weight": "medium",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_medium_01.wav"
	},
	"blaster-m": {
		"name": "Precision Rifle",
		"type": "sniper",
		"damage": 48.0,
		"range": 40.0,
		"fire_rate": 0.4,
		"accuracy": 0.99,
		"reload_time": 3.2,
		"max_ammo": 6,
		"weight": "heavy",
		"rarity": "epic",
		"fire_sound": "res://assets/audio/sfx/blaster_heavy_01.wav"
	},
	"blaster-n": {
		"name": "Destroyer",
		"type": "heavy",
		"damage": 60.0,
		"range": 15.0,
		"fire_rate": 0.4,
		"accuracy": 0.75,
		"reload_time": 4.0,
		"max_ammo": 6,
		"weight": "heavy",
		"rarity": "epic",
		"fire_sound": "res://assets/audio/sfx/blaster_cannon_02.wav"
	},
	"blaster-o": {
		"name": "Multi-Tool Gun",
		"type": "utility",
		"damage": 28.0,
		"range": 16.0,
		"fire_rate": 1.1,
		"accuracy": 0.83,
		"reload_time": 2.3,
		"max_ammo": 22,
		"weight": "medium",
		"rarity": "uncommon",
		"fire_sound": "res://assets/audio/sfx/blaster_utility_01.wav"
	},
	"blaster-p": {
		"name": "Medic Blaster",
		"type": "support",
		"damage": 12.0,
		"range": 10.0,
		"fire_rate": 2.2,
		"accuracy": 0.88,
		"reload_time": 1.5,
		"max_ammo": 30,
		"weight": "light",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_support_01.wav"
	},
	"blaster-q": {
		"name": "Hunter Rifle",
		"type": "marksman",
		"damage": 42.0,
		"range": 32.0,
		"fire_rate": 0.6,
		"accuracy": 0.96,
		"reload_time": 2.9,
		"max_ammo": 10,
		"weight": "heavy",
		"rarity": "uncommon",
		"fire_sound": "res://assets/audio/sfx/blaster_heavy_02.wav"
	},
	"blaster-r": {
		"name": "Support Carbine",
		"type": "support",
		"damage": 16.0,
		"range": 12.0,
		"fire_rate": 1.8,
		"accuracy": 0.85,
		"reload_time": 1.8,
		"max_ammo": 28,
		"weight": "light",
		"rarity": "common",
		"fire_sound": "res://assets/audio/sfx/blaster_support_01.wav"
	}
}

# Attachment compatibility
const ATTACHMENT_COMPATIBILITY = {
	"scope_small": ["pistol", "carbine", "smg", "support"],
	"scope_large_a": ["rifle", "sniper", "marksman", "heavy"],
	"scope_large_b": ["sniper", "marksman", "heavy"],
	"clip_small": ["pistol", "carbine", "smg", "support"],
	"clip_large": ["rifle", "sniper", "marksman", "heavy", "utility"]
}

# Weapon rarity weights for random selection
const RARITY_WEIGHTS = {
	"common": 1.0,
	"uncommon": 0.7,
	"rare": 0.4,
	"epic": 0.2,
	"legendary": 0.1
}

# Cache for weapon selections
var weapon_cache: Dictionary = {}
var logger

func _ready() -> void:
	# Setup logger
	_setup_logger()
	
	if logger:
		logger.info("WeaponDatabase", "Weapon database initialized with %d weapons" % WEAPON_SPECS.size())
	else:
		print("WeaponDatabase: Weapon database initialized with %d weapons" % WEAPON_SPECS.size())

func _setup_logger() -> void:
	"""Setup logger reference from dependency container"""
	if has_node("/root/DependencyContainer"):
		var dependency_container = get_node("/root/DependencyContainer")
		if dependency_container.has_method("get_logger"):
			logger = dependency_container.get_logger()

func get_weapon_for_archetype(archetype: String, preference: String = "primary") -> String:
	"""Get a weapon for the specified archetype"""
	var archetype_data = WEAPON_ASSIGNMENTS.get(archetype, {})
	if archetype_data.is_empty():
		_log_warning("Unknown archetype: %s, using default weapon" % archetype)
		return "blaster-b"  # Default weapon
	
	var weapon_list = archetype_data.get(preference, [])
	if weapon_list.is_empty():
		_log_warning("No %s weapons for archetype %s" % [preference, archetype])
		# Fallback to primary weapons
		weapon_list = archetype_data.get("primary", ["blaster-b"])
	
	# Return random weapon from the list
	return weapon_list[randi() % weapon_list.size()]

func get_weapon_with_rarity_bias(archetype: String, preference: String = "primary") -> String:
	"""Get a weapon considering rarity weights"""
	var archetype_data = WEAPON_ASSIGNMENTS.get(archetype, {})
	if archetype_data.is_empty():
		return "blaster-b"
	
	var weapon_list = archetype_data.get(preference, archetype_data.get("primary", ["blaster-b"]))
	
	# Create weighted selection
	var weighted_weapons = []
	for weapon in weapon_list:
		var weapon_spec = WEAPON_SPECS.get(weapon, {})
		var rarity = weapon_spec.get("rarity", "common")
		var weight = RARITY_WEIGHTS.get(rarity, 1.0)
		
		# Add weapon multiple times based on weight
		var count = max(1, int(weight * 10))
		for i in range(count):
			weighted_weapons.append(weapon)
	
	return weighted_weapons[randi() % weighted_weapons.size()]

func get_compatible_attachments(weapon_type: String) -> Array[String]:
	"""Get compatible attachments for a weapon type"""
	var weapon_spec = WEAPON_SPECS.get(weapon_type, {})
	var weapon_category = weapon_spec.get("type", "rifle")
	
	var compatible_attachments: Array[String] = []
	
	for attachment in ATTACHMENT_COMPATIBILITY:
		var compatible_types = ATTACHMENT_COMPATIBILITY[attachment]
		if weapon_category in compatible_types:
			compatible_attachments.append(attachment)
	
	return compatible_attachments

func get_recommended_attachments(archetype: String, weapon_type: String) -> Array[String]:
	"""Get recommended attachments for archetype and weapon combination"""
	var archetype_data = WEAPON_ASSIGNMENTS.get(archetype, {})
	var archetype_attachments = archetype_data.get("attachments", [])
	var compatible_attachments = get_compatible_attachments(weapon_type)
	
	# Return intersection of archetype preferences and weapon compatibility
	var recommended: Array[String] = []
	for attachment in archetype_attachments:
		if attachment in compatible_attachments:
			recommended.append(attachment)
	
	return recommended

func get_weapon_specs(weapon_type: String) -> Dictionary:
	"""Get detailed weapon specifications"""
	return WEAPON_SPECS.get(weapon_type, {})

func get_archetype_combat_style(archetype: String) -> String:
	"""Get combat style for archetype"""
	var archetype_data = WEAPON_ASSIGNMENTS.get(archetype, {})
	return archetype_data.get("combat_style", "balanced")

func get_archetype_preferred_range(archetype: String) -> String:
	"""Get preferred combat range for archetype"""
	var archetype_data = WEAPON_ASSIGNMENTS.get(archetype, {})
	return archetype_data.get("preferred_range", "medium")

func create_loadout(archetype: String, team_id: int = 1) -> Dictionary:
	"""Create a complete weapon loadout for an archetype"""
	var primary_weapon = get_weapon_with_rarity_bias(archetype, "primary")
	var secondary_weapon = get_weapon_for_archetype(archetype, "secondary")
	var recommended_attachments = get_recommended_attachments(archetype, primary_weapon)
	
	# Select 1-2 random attachments from recommended
	var selected_attachments: Array[String] = []
	if not recommended_attachments.is_empty():
		selected_attachments.append(recommended_attachments[randi() % recommended_attachments.size()])
		
		# 50% chance for second attachment
		if randf() < 0.5 and recommended_attachments.size() > 1:
			var second_attachment = recommended_attachments[randi() % recommended_attachments.size()]
			if second_attachment != selected_attachments[0]:
				selected_attachments.append(second_attachment)
	
	var loadout = {
		"archetype": archetype,
		"team_id": team_id,
		"primary_weapon": primary_weapon,
		"secondary_weapon": secondary_weapon,
		"attachments": selected_attachments,
		"primary_specs": get_weapon_specs(primary_weapon),
		"secondary_specs": get_weapon_specs(secondary_weapon),
		"combat_style": get_archetype_combat_style(archetype),
		"preferred_range": get_archetype_preferred_range(archetype)
	}
	
	return loadout

func validate_weapon_assignment(archetype: String, weapon_type: String) -> bool:
	"""Validate if a weapon is appropriate for an archetype"""
	var archetype_data = WEAPON_ASSIGNMENTS.get(archetype, {})
	if archetype_data.is_empty():
		return false
	
	var primary_weapons = archetype_data.get("primary", [])
	var secondary_weapons = archetype_data.get("secondary", [])
	
	return weapon_type in primary_weapons or weapon_type in secondary_weapons

func get_weapon_effectiveness(weapon_type: String, range: float) -> float:
	"""Calculate weapon effectiveness at given range"""
	var weapon_spec = WEAPON_SPECS.get(weapon_type, {})
	var optimal_range = weapon_spec.get("range", 15.0)
	var weapon_accuracy = weapon_spec.get("accuracy", 0.85)
	
	# Calculate range effectiveness
	var range_effectiveness = 1.0
	if range > optimal_range:
		range_effectiveness = optimal_range / range
	
	# Combine with base accuracy
	return weapon_accuracy * range_effectiveness

func get_all_weapons_for_archetype(archetype: String) -> Array[String]:
	"""Get all weapons (primary and secondary) for an archetype"""
	var archetype_data = WEAPON_ASSIGNMENTS.get(archetype, {})
	var all_weapons: Array[String] = []
	
	all_weapons.append_array(archetype_data.get("primary", []))
	all_weapons.append_array(archetype_data.get("secondary", []))
	
	return all_weapons

func get_weapon_count_by_type() -> Dictionary:
	"""Get count of weapons by type"""
	var type_counts: Dictionary = {}
	
	for weapon_type in WEAPON_SPECS:
		var weapon_spec = WEAPON_SPECS[weapon_type]
		var category = weapon_spec.get("type", "unknown")
		
		if not type_counts.has(category):
			type_counts[category] = 0
		type_counts[category] += 1
	
	return type_counts

func get_archetype_statistics() -> Dictionary:
	"""Get statistics about archetype weapon assignments"""
	var stats = {}
	
	for archetype in WEAPON_ASSIGNMENTS:
		var archetype_data = WEAPON_ASSIGNMENTS[archetype]
		var primary_count = archetype_data.get("primary", []).size()
		var secondary_count = archetype_data.get("secondary", []).size()
		var attachment_count = archetype_data.get("attachments", []).size()
		
		stats[archetype] = {
			"primary_weapons": primary_count,
			"secondary_weapons": secondary_count,
			"attachments": attachment_count,
			"total_weapons": primary_count + secondary_count,
			"combat_style": archetype_data.get("combat_style", "unknown"),
			"preferred_range": archetype_data.get("preferred_range", "unknown")
		}
	
	return stats

func _log_warning(message: String) -> void:
	"""Log warning message"""
	if logger:
		logger.warning("WeaponDatabase", message)
	else:
		print("WeaponDatabase WARNING: %s" % message)

# Debug functions
func debug_weapon_info(weapon_type: String) -> Dictionary:
	"""Get debug information about a weapon"""
	var weapon_spec = WEAPON_SPECS.get(weapon_type, {})
	var compatible_attachments = get_compatible_attachments(weapon_type)
	
	return {
		"weapon_type": weapon_type,
		"exists": not weapon_spec.is_empty(),
		"specifications": weapon_spec,
		"compatible_attachments": compatible_attachments,
		"effectiveness_at_10m": get_weapon_effectiveness(weapon_type, 10.0),
		"effectiveness_at_20m": get_weapon_effectiveness(weapon_type, 20.0),
		"effectiveness_at_30m": get_weapon_effectiveness(weapon_type, 30.0)
	}

func debug_archetype_info(archetype: String) -> Dictionary:
	"""Get debug information about an archetype"""
	var archetype_data = WEAPON_ASSIGNMENTS.get(archetype, {})
	var all_weapons = get_all_weapons_for_archetype(archetype)
	
	return {
		"archetype": archetype,
		"exists": not archetype_data.is_empty(),
		"archetype_data": archetype_data,
		"all_weapons": all_weapons,
		"weapon_count": all_weapons.size(),
		"sample_loadout": create_loadout(archetype) if not archetype_data.is_empty() else {}
	}

func debug_database_summary() -> Dictionary:
	"""Get summary of the entire weapon database"""
	return {
		"total_weapons": WEAPON_SPECS.size(),
		"total_archetypes": WEAPON_ASSIGNMENTS.size(),
		"weapons_by_type": get_weapon_count_by_type(),
		"archetype_statistics": get_archetype_statistics(),
		"total_attachments": ATTACHMENT_COMPATIBILITY.size()
	} 