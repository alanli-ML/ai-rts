# scripts/ai/tier_selector.gd
class_name TierSelector
extends RefCounted

enum ControlTier { TIER_1_SQUAD, TIER_2_INDIVIDUAL }

const SQUAD_THRESHOLD = 4 # Number of units to be considered a squad
const ARCHETYPE_DIVERSITY_THRESHOLD = 2 # Number of different archetypes to trigger squad tier
const SPATIAL_CLUSTER_RADIUS = 25.0 # Max distance for units to be in the same cluster

func determine_control_tier(selected_units: Array) -> ControlTier:
    if selected_units.is_empty():
        return ControlTier.TIER_1_SQUAD # Default

    if selected_units.size() >= SQUAD_THRESHOLD:
        return ControlTier.TIER_1_SQUAD

    var archetypes = {}
    for unit in selected_units:
        if unit.has_method("get_archetype"):
            var archetype = unit.get_archetype()
            archetypes[archetype] = true
    
    if archetypes.size() >= ARCHETYPE_DIVERSITY_THRESHOLD:
        return ControlTier.TIER_1_SQUAD

    # Spatial clustering check could be added here
    # For now, if it's a small, homogenous group, it's Tier 2.
    return ControlTier.TIER_2_INDIVIDUAL