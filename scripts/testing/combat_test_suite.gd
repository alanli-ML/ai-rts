# scripts/testing/combat_test_suite.gd
class_name CombatTestSuite
extends Node

# Load shared enums
const GameEnums = preload("res://scripts/shared/types/game_enums.gd")

var dc
var team_unit_spawner
var game_state
var plan_executor
var ai_command_processor
var action_validator
var logger

func setup(dependency_container):
    dc = dependency_container
    team_unit_spawner = dc.get_team_unit_spawner()
    game_state = dc.get_game_state()
    plan_executor = dc.get_node_or_null("PlanExecutor")
    ai_command_processor = dc.get_ai_command_processor()
    action_validator = dc.get_node_or_null("ActionValidator")
    logger = dc.get_logger()
    logger.info("CombatTestSuite", "Test suite setup complete.")

func execute_command(command: String):
    var parts = command.split(" ", false)
    if parts.is_empty(): return

    var test_name = parts[0]
    var args = parts.slice(1)

    logger.info("CombatTestSuite", "Executing test command: %s with args %s" % [test_name, str(args)])

    match test_name:
        "/test_duel":
            if args.size() == 2:
                _test_duel(args[0], args[1])
            else:
                logger.warning("CombatTestSuite", "Usage: /test_duel <archetype1> <archetype2>")
        "/test_abilities":
            if args.size() == 1:
                _test_abilities(args[0])
            else:
                _test_all_abilities()
        "/test_death":
            if args.size() == 1:
                _test_death_mechanics(args[0])
            else:
                _test_all_death_mechanics()
        "/test_team_fight":
            _test_team_fight()
        "/test_respawn":
            if args.size() == 1:
                _test_respawn_mechanics(args[0])
            else:
                _test_respawn_mechanics("scout")  # Default to scout
        "/test_quick_respawn":
            _test_quick_respawn_mechanics()
        "/test_super_quick_respawn":
            _test_super_quick_respawn()
        "/test_help":
            _show_help()
        _:
            logger.warning("CombatTestSuite", "Unknown test command: %s" % test_name)
            _show_help()

func _show_help():
    var help_text = """
    [b]Combat Test Suite Commands:[/b]
    [color=cyan]/test_duel <arch1> <arch2>[/color] - Spawns two units to fight each other.
    [color=cyan]/test_abilities <archetype>[/color] - Tests all abilities for a given archetype.
    [color=cyan]/test_abilities[/color] - Tests all abilities for all archetypes.
    [color=cyan]/test_death <archetype>[/color] - Tests death mechanics for a given archetype.
    [color=cyan]/test_death[/color] - Tests death mechanics for all archetypes.
    [color=cyan]/test_team_fight[/color] - Spawns two full teams and makes them fight.
    [color=cyan]/test_respawn <archetype>[/color] - Tests respawn mechanics (30 sec wait).
    [color=cyan]/test_quick_respawn[/color] - Tests respawn mechanics (5 sec wait).
    [color=cyan]/test_super_quick_respawn[/color] - Tests respawn mechanics (2 sec wait).
    [color=cyan]/test_help[/color] - Shows this help message.
    """
    logger.info("CombatTestSuite", "Displaying help.")
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        root_node.rpc("_on_ai_command_feedback_rpc", help_text, "[color=lightblue]Test Help[/color]")

func _test_duel(archetype1: String, archetype2: String):
    logger.info("CombatTestSuite", "Starting duel: %s vs %s" % [archetype1, archetype2])
    var pos1 = Vector3(-10, 1, 0)
    var pos2 = Vector3(10, 1, 0)
    
    var unit1 = await _spawn_unit_for_test(archetype1, 1, pos1)
    var unit2 = await _spawn_unit_for_test(archetype2, 2, pos2)
    
    if not is_instance_valid(unit1) or not is_instance_valid(unit2):
        logger.error("CombatTestSuite", "Failed to spawn units for duel.")
        return

    await get_tree().create_timer(1.0).timeout
    
    logger.info("CombatTestSuite", "Making units %s and %s fight." % [unit1.unit_id, unit2.unit_id])
    _make_units_attack(unit1, unit2)
    _make_units_attack(unit2, unit1)

func _test_all_abilities():
    var archetypes = ["scout", "tank", "sniper", "medic", "engineer"]
    for arch in archetypes:
        await _test_abilities(arch)
        await get_tree().create_timer(5.0).timeout

func _test_abilities(archetype: String):
    logger.info("CombatTestSuite", "Testing abilities for %s" % archetype)
    
    var unit = await _spawn_unit_for_test(archetype, 1, Vector3(0, 1, 0))
    if not is_instance_valid(unit): return

    match archetype:
        "scout":
            _execute_action(unit, "activate_stealth", {})
        "tank":
            _execute_action(unit, "activate_shield", {})
        "sniper":
            var dummy = await _spawn_unit_for_test("tank", 2, Vector3(20, 1, 0))
            if is_instance_valid(dummy):
                logger.info("CombatTestSuite", "Testing enhanced charge_shot implementation")
                
                # Test the charge_shot action
                _execute_action(unit, "charge_shot", {"target_id": dummy.unit_id})
                
                # Wait for charging phase and verify visual effects
                var charge_start_time = Time.get_ticks_msec() / 1000.0
                logger.info("CombatTestSuite", "Charge shot started at time %.2f" % charge_start_time)
                
                # Check that unit is in charging state
                await get_tree().create_timer(0.5).timeout
                if unit.current_state == GameEnums.UnitState.CHARGING_SHOT:
                    logger.info("CombatTestSuite", "✓ Unit correctly entered CHARGING_SHOT state")
                    
                    # Check for charge effects
                    if unit.has_method("get_charge_progress"):
                        var progress = unit.get_charge_progress()
                        logger.info("CombatTestSuite", "✓ Charge progress: %.2f" % progress)
                    
                    # Check for visual charge effect
                    var charge_effect = unit.get_node_or_null("ChargeEffect")
                    if charge_effect:
                        logger.info("CombatTestSuite", "✓ Charge visual effect created")
                    else:
                        logger.warning("CombatTestSuite", "⚠ Charge visual effect not found")
                else:
                    logger.error("CombatTestSuite", "✗ Unit failed to enter CHARGING_SHOT state")
                
                # Wait for shot to complete
                await get_tree().create_timer(2.5).timeout
                
                # Check that charging is complete
                if unit.current_state == GameEnums.UnitState.IDLE:
                    logger.info("CombatTestSuite", "✓ Charge shot completed, unit returned to IDLE")
                    
                    # Check target took damage
                    if dummy.current_health < dummy.max_health:
                        var damage_dealt = dummy.max_health - dummy.current_health
                        logger.info("CombatTestSuite", "✓ Target took %.1f damage from charged shot" % damage_dealt)
                        
                        # Verify enhanced damage (should be 2.5x normal)
                        if damage_dealt > 50: # Assuming base damage ~25, enhanced should be ~62.5
                            logger.info("CombatTestSuite", "✓ Enhanced damage confirmed (%.1f damage)" % damage_dealt)
                        else:
                            logger.warning("CombatTestSuite", "⚠ Damage may not be enhanced (%.1f damage)" % damage_dealt)
                    else:
                        logger.error("CombatTestSuite", "✗ Target took no damage from charged shot")
                        
                    # Check that charge effect was cleaned up
                    var charge_effect_after = unit.get_node_or_null("ChargeEffect")
                    if not charge_effect_after:
                        logger.info("CombatTestSuite", "✓ Charge effect properly cleaned up")
                    else:
                        logger.warning("CombatTestSuite", "⚠ Charge effect still present after shot")
                else:
                    logger.error("CombatTestSuite", "✗ Unit did not complete charge shot properly")
        "medic":
            var injured_ally = await _spawn_unit_for_test("scout", 1, Vector3(5, 1, 0))
            if is_instance_valid(injured_ally):
                injured_ally.take_damage(50)
                await get_tree().create_timer(0.5).timeout
                _execute_action(unit, "heal_ally", {"target_id": injured_ally.unit_id})
        "engineer":
            _execute_action(unit, "lay_mines", {})
            await get_tree().create_timer(6.0).timeout
            _execute_action(unit, "construct", {"position": [5, 0, 5]})

func _test_all_death_mechanics():
    var archetypes = ["scout", "tank", "sniper", "medic", "engineer"]
    for arch in archetypes:
        await _test_death_mechanics(arch)
        await get_tree().create_timer(2.0).timeout

func _test_death_mechanics(archetype: String):
    logger.info("CombatTestSuite", "Testing death mechanics for %s" % archetype)
    var unit = await _spawn_unit_for_test(archetype, 1, Vector3(0, 1, 0))
    if not is_instance_valid(unit): return
    
    # Give time to see the unit alive
    await get_tree().create_timer(1.0).timeout
    
    logger.info("CombatTestSuite", "Killing unit %s (current health: %f)" % [unit.unit_id, unit.current_health])
    
    # If it's an AnimatedUnit, check if it has the death animation available
    if unit.has_method("play_animation") and unit.get("animation_player"):
        var anim_player = unit.get("animation_player")
        if anim_player:
            var available_anims = anim_player.get_animation_list()
            logger.info("CombatTestSuite", "Available animations for %s: %s" % [archetype, available_anims])
            if "die" in available_anims:
                logger.info("CombatTestSuite", "✓ Death animation 'die' available for %s" % archetype)
            else:
                logger.warning("CombatTestSuite", "⚠ Death animation 'die' NOT available for %s" % archetype)
    
    # Kill the unit and watch for death animation
    unit.take_damage(unit.max_health * 2)
    
    # Wait to see death animation play
    await get_tree().create_timer(3.0).timeout
    logger.info("CombatTestSuite", "Death animation test completed for %s" % archetype)

func _test_respawn_mechanics(archetype: String):
    logger.info("CombatTestSuite", "Testing respawn mechanics for %s" % archetype)
    var unit = await _spawn_unit_for_test(archetype, 1, Vector3(0, 1, 0))
    if not is_instance_valid(unit): return
    
    # Store original position and health
    var original_position = unit.global_position
    var original_health = unit.current_health
    
    logger.info("CombatTestSuite", "Unit %s alive at %s with %d health" % [unit.unit_id, original_position, original_health])
    
    # Connect to respawn signal
    var respawn_received = false
    unit.unit_respawned.connect(func(unit_id): 
        respawn_received = true
        logger.info("CombatTestSuite", "✓ Received respawn signal for unit %s" % unit_id)
    )
    
    # Kill the unit
    logger.info("CombatTestSuite", "Killing unit %s..." % unit.unit_id)
    unit.take_damage(unit.max_health * 2)
    
    # Verify unit is dead
    if unit.is_dead:
        logger.info("CombatTestSuite", "✓ Unit is confirmed dead")
    else:
        logger.error("CombatTestSuite", "✗ Unit should be dead but is_dead=false")
        return
    
    # Check if respawn timer started
    if unit.is_respawning:
        logger.info("CombatTestSuite", "✓ Respawn timer started - %.1f seconds remaining" % unit.get_respawn_time_remaining())
    else:
        logger.error("CombatTestSuite", "✗ Respawn timer did not start")
        return
    
    # Wait for respawn (30 seconds + buffer)
    logger.info("CombatTestSuite", "Waiting for respawn in 30 seconds...")
    var wait_time = 32.0  # 30 second respawn + 2 second buffer
    var start_time = Time.get_ticks_msec()
    
    while Time.get_ticks_msec() - start_time < wait_time * 1000:
        await get_tree().process_frame
        
        # Check if unit respawned early
        if not unit.is_dead and respawn_received:
            break
    
    # Verify respawn occurred
    if unit.is_dead:
        logger.error("CombatTestSuite", "✗ Unit did not respawn after %d seconds" % wait_time)
        return
    
    if not respawn_received:
        logger.error("CombatTestSuite", "✗ Respawn signal was not received")
        return
    
    # Verify unit state after respawn
    logger.info("CombatTestSuite", "✓ Unit %s respawned successfully!" % unit.unit_id)
    logger.info("CombatTestSuite", "  - Health: %d/%d" % [unit.current_health, unit.max_health])
    logger.info("CombatTestSuite", "  - Position: %s" % unit.global_position)
    logger.info("CombatTestSuite", "  - Invulnerable: %s" % unit.invulnerable)
    
    # Verify health was restored
    if unit.current_health == unit.max_health:
        logger.info("CombatTestSuite", "✓ Health fully restored")
    else:
        logger.warning("CombatTestSuite", "⚠ Health not fully restored: %d/%d" % [unit.current_health, unit.max_health])
    
    # Test invulnerability period
    if unit.invulnerable:
        logger.info("CombatTestSuite", "✓ Unit has invulnerability after respawn")
        var damage_before = unit.current_health
        unit.take_damage(50)  # Try to damage
        if unit.current_health == damage_before:
            logger.info("CombatTestSuite", "✓ Invulnerability prevents damage")
        else:
            logger.error("CombatTestSuite", "✗ Invulnerability failed - took damage during invulnerability period")
    else:
        logger.warning("CombatTestSuite", "⚠ Unit does not have invulnerability after respawn")
    
    logger.info("CombatTestSuite", "Respawn mechanics test completed for %s" % archetype)

func _test_quick_respawn_mechanics():
    """Test respawn mechanics with reduced timer for quick testing"""
    logger.info("CombatTestSuite", "Starting quick respawn test (5 second timer)")
    
    var unit = await _spawn_unit_for_test("scout", 1, Vector3(0, 1, 0))
    if not is_instance_valid(unit): return
    
    # Connect to respawn signal
    var respawn_received = false
    unit.unit_respawned.connect(func(unit_id): 
        respawn_received = true
        logger.info("CombatTestSuite", "✓ Received respawn signal for unit %s" % unit_id)
    )
    
    # Kill the unit and manually set shorter respawn time
    unit.take_damage(unit.max_health * 2)
    unit.respawn_timer = 5.0  # Override to 5 seconds for quick testing
    
    logger.info("CombatTestSuite", "Unit killed, waiting 5 seconds for respawn...")
    
    # Wait for quick respawn
    await get_tree().create_timer(6.0).timeout
    
    # Verify respawn occurred
    if unit.is_dead:
        logger.error("CombatTestSuite", "✗ Unit did not respawn after 5 seconds")
    elif respawn_received:
        logger.info("CombatTestSuite", "✓ Quick respawn test passed!")
        logger.info("CombatTestSuite", "  - Unit %s health: %d/%d" % [unit.unit_id, unit.current_health, unit.max_health])
        logger.info("CombatTestSuite", "  - Invulnerable: %s" % unit.invulnerable)
    else:
        logger.error("CombatTestSuite", "✗ Unit respawned but signal not received")
    
    logger.info("CombatTestSuite", "Quick respawn test completed")

func _test_super_quick_respawn():
    """Test respawn with 2-second timer for immediate verification"""
    logger.info("CombatTestSuite", "Starting super quick respawn test (2 second timer)")
    
    var unit = await _spawn_unit_for_test("scout", 1, Vector3(0, 1, 0))
    if not is_instance_valid(unit): return
    
    logger.info("CombatTestSuite", "Unit %s spawned at position %s" % [unit.unit_id, unit.global_position])
    
    # Connect to respawn signal
    var respawn_received = false
    unit.unit_respawned.connect(func(unit_id): 
        respawn_received = true
        logger.info("CombatTestSuite", "✓ RESPAWN SIGNAL received for unit %s" % unit_id)
    )
    
    # Kill the unit and override respawn timer immediately
    logger.info("CombatTestSuite", "Killing unit and setting 2-second respawn timer...")
    unit.take_damage(unit.max_health * 2)
    
    # Verify death
    if unit.is_dead:
        logger.info("CombatTestSuite", "✓ Unit is confirmed dead")
        
        # Override respawn timer to 2 seconds
        unit.respawn_timer = 2.0
        logger.info("CombatTestSuite", "✓ Respawn timer overridden to 2 seconds")
        logger.info("CombatTestSuite", "✓ is_respawning: %s" % unit.is_respawning)
        logger.info("CombatTestSuite", "✓ physics_process enabled: %s" % unit.is_physics_processing())
    else:
        logger.error("CombatTestSuite", "✗ Unit is not dead after taking damage")
        return
    
    # Wait 3 seconds for respawn
    logger.info("CombatTestSuite", "Waiting 3 seconds for respawn...")
    await get_tree().create_timer(3.0).timeout
    
    # Check results
    if unit.is_dead:
        logger.error("CombatTestSuite", "✗ Unit still dead after 3 seconds")
        logger.error("CombatTestSuite", "  - is_respawning: %s" % unit.is_respawning)
        logger.error("CombatTestSuite", "  - respawn_timer: %.2f" % unit.get_respawn_time_remaining())
        logger.error("CombatTestSuite", "  - physics_process: %s" % unit.is_physics_processing())
    else:
        logger.info("CombatTestSuite", "✓ Unit successfully respawned!")
        logger.info("CombatTestSuite", "  - Health: %d/%d" % [unit.current_health, unit.max_health])
        logger.info("CombatTestSuite", "  - Position: %s" % unit.global_position)
        logger.info("CombatTestSuite", "  - Signal received: %s" % respawn_received)
        
        if respawn_received:
            logger.info("CombatTestSuite", "✓ COMPLETE SUCCESS - Respawn system working!")
        else:
            logger.warning("CombatTestSuite", "⚠ Respawn worked but signal not received")

func _test_team_fight():
    logger.info("CombatTestSuite", "Starting team fight.")
    var archetypes = ["scout", "tank", "sniper", "medic", "engineer"]
    var team1_units = []
    var team2_units = []

    for i in range(archetypes.size()):
        var arch = archetypes[i]
        var unit1 = await _spawn_unit_for_test(arch, 1, Vector3(-15 + i*6, 1, -5))
        var unit2 = await _spawn_unit_for_test(arch, 2, Vector3(-15 + i*6, 1, 5))
        if is_instance_valid(unit1): team1_units.append(unit1)
        if is_instance_valid(unit2): team2_units.append(unit2)

    await get_tree().create_timer(1.0).timeout

    var team1_ids = team1_units.map(func(u): return u.unit_id)
    var team2_ids = team2_units.map(func(u): return u.unit_id)
    
    ai_command_processor.process_command("Attack the enemy team", team1_ids, -1)
    ai_command_processor.process_command("Attack the enemy team", team2_ids, -1)
    
# --- Helper Functions ---

func _spawn_unit_for_test(archetype: String, team_id: int, position: Vector3) -> Node:
    if not team_unit_spawner:
        logger.error("CombatTestSuite", "TeamUnitSpawner not available.")
        return null
    
    var unit = await team_unit_spawner.spawn_unit(team_id, position, archetype)
    if not is_instance_valid(unit):
        logger.error("CombatTestSuite", "Failed to spawn unit %s for team %d" % [archetype, team_id])
        return null

    game_state.units[unit.unit_id] = unit
    unit.unit_died.connect(_on_test_unit_died)
    logger.info("CombatTestSuite", "Spawned test unit: %s (%s) at %s" % [unit.unit_id, archetype, position])
    return unit

func _make_units_attack(attacker: Node, target: Node):
    if is_instance_valid(attacker) and is_instance_valid(target):
        if attacker.has_method("attack_target"):
            attacker.attack_target(target)

func _execute_action(unit: Node, action: String, params: Dictionary):
    if not plan_executor:
        logger.error("CombatTestSuite", "PlanExecutor not available.")
        return
        
    var plan = {
        "unit_id": unit.unit_id,
        "goal": "Test action: %s" % action,
        "steps": [{"action": action, "params": params}],
        "triggered_actions": [{
            "action": "attack",
            "trigger_source": "enemies_in_range",
            "trigger_comparison": ">",
            "trigger_value": 0
        }]
    }
    
    var validation = action_validator.validate_plan(plan)
    if validation.valid:
        plan_executor.execute_plan(unit.unit_id, plan)
        logger.info("CombatTestSuite", "Executing test action '%s' for unit %s" % [action, unit.unit_id])
    else:
        logger.error("CombatTestSuite", "Test action validation failed for '%s': %s" % [action, validation.error])

func _on_test_unit_died(unit_id: String):
    logger.info("CombatTestSuite", "Test unit %s confirmed dead." % unit_id)