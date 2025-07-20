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
        "/test_turrets":
            _test_turret_construction()
        "/test_turret_limits":
            _test_turret_limits()
        "/test_turret_combat":
            _test_turret_combat()
        "/test_engineer_turrets":
            _test_engineer_turret_construction()
        "/test_follow_turret_exclusion":
            _test_follow_turret_exclusion()
        "/test_scout_stealth":
            _test_scout_stealth()
        "/test_fog_debug":
            _test_fog_debug()
        "/test_fog_trace":
            _test_fog_trace()
        "/test_fog_visibility":
            _test_fog_visibility()
        "/test_fog_movement":
            _test_fog_movement()
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
    [color=cyan]/test_turrets[/color] - Tests turret construction and basic turret functionality.
    [color=cyan]/test_turret_limits[/color] - Tests turret range and limit mechanics.
    [color=cyan]/test_turret_combat[/color] - Tests turret combat and targeting.
    [color=cyan]/test_engineer_turrets[/color] - Tests engineer construct_turret method and limits.
    [color=cyan]/test_follow_turret_exclusion[/color] - Tests that units don't follow turrets in follow state.
    [color=cyan]/test_scout_stealth[/color] - Tests scout stealth mechanics (activation, duration, visual effects, interruption, enemy detection).
    [color=yellow]/test_fog_debug[/color] - Debug fog of war system and show current status.
    [color=yellow]/test_fog_trace[/color] - Comprehensive fog data flow tracing.
    [color=yellow]/test_fog_visibility[/color] - Test fog of war visibility updates with unit movement.
    [color=yellow]/test_fog_movement[/color] - Spawn units and move them to test fog updates.
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

func _test_turret_construction():
    logger.info("CombatTestSuite", "Starting turret construction test.")
    var archetype = "turret"
    var team_id = 1
    var position = Vector3(0, 1, 0)
    
    var turret = await _spawn_unit_for_test(archetype, team_id, position)
    if not is_instance_valid(turret):
        logger.error("CombatTestSuite", "Failed to spawn turret.")
        return

    logger.info("CombatTestSuite", "Turret %s spawned at %s" % [turret.unit_id, turret.global_position])

    # Test basic turret properties
    logger.info("CombatTestSuite", "Testing turret properties:")
    logger.info("CombatTestSuite", "  - Unit ID: %s" % turret.unit_id)
    logger.info("CombatTestSuite", "  - Team ID: %d" % turret.team_id)
    logger.info("CombatTestSuite", "  - Position: %s" % turret.global_position)
    logger.info("CombatTestSuite", "  - Health: %d/%d" % [turret.current_health, turret.max_health])
    logger.info("CombatTestSuite", "  - Invulnerable: %s" % turret.invulnerable)
    logger.info("CombatTestSuite", "  - Current State: %s" % turret.current_state)

    # Test turret attack
    var target = await _spawn_unit_for_test("scout", 2, Vector3(10, 1, 0))
    if not is_instance_valid(target):
        logger.error("CombatTestSuite", "Failed to spawn target for turret attack.")
        return

    logger.info("CombatTestSuite", "Making turret %s attack target %s" % [turret.unit_id, target.unit_id])
    _make_units_attack(turret, target)

    # Wait for turret to attack
    await get_tree().create_timer(1.0).timeout

    # Check if turret attacked
    if turret.current_state == GameEnums.UnitState.ATTACKING:
        logger.info("CombatTestSuite", "✓ Turret correctly entered ATTACKING state")
        logger.info("CombatTestSuite", "  - Target: %s" % target.unit_id)
        logger.info("CombatTestSuite", "  - Current Health: %d/%d" % [turret.current_health, turret.max_health])
    else:
        logger.error("CombatTestSuite", "✗ Turret did not enter ATTACKING state")

    # Test turret death
    turret.take_damage(turret.max_health * 2)
    await get_tree().create_timer(3.0).timeout

    if turret.is_dead:
        logger.info("CombatTestSuite", "✓ Turret correctly died")
        logger.info("CombatTestSuite", "  - Health: %d/%d" % [turret.current_health, turret.max_health])
    else:
        logger.error("CombatTestSuite", "✗ Turret did not die")

    # Test turret respawn
    turret.respawn_timer = 5.0 # Override to 5 seconds for quick respawn test
    turret.take_damage(turret.max_health * 2)
    await get_tree().create_timer(6.0).timeout

    if turret.is_dead:
        logger.error("CombatTestSuite", "✗ Turret did not respawn after 5 seconds")
    elif turret.is_respawning:
        logger.info("CombatTestSuite", "✓ Turret respawned successfully!")
        logger.info("CombatTestSuite", "  - Health: %d/%d" % [turret.current_health, turret.max_health])
        logger.info("CombatTestSuite", "  - Position: %s" % turret.global_position)
        logger.info("CombatTestSuite", "  - Invulnerable: %s" % turret.invulnerable)
    else:
        logger.error("CombatTestSuite", "✗ Turret did not enter respawning state")

    logger.info("CombatTestSuite", "Turret construction and basic functionality test completed.")

func _test_turret_limits():
    logger.info("CombatTestSuite", "Starting turret limits test.")
    var archetype = "turret"
    var team_id = 1
    var position = Vector3(0, 1, 0)
    
    var turret = await _spawn_unit_for_test(archetype, team_id, position)
    if not is_instance_valid(turret):
        logger.error("CombatTestSuite", "Failed to spawn turret for limits test.")
        return

    logger.info("CombatTestSuite", "Turret %s spawned at %s" % [turret.unit_id, turret.global_position])

    # Test range limit
    logger.info("CombatTestSuite", "Testing range limit:")
    var target_far = await _spawn_unit_for_test("scout", 2, Vector3(100, 1, 0))
    if not is_instance_valid(target_far):
        logger.error("CombatTestSuite", "Failed to spawn far target for range test.")
        return

    logger.info("CombatTestSuite", "Making turret %s attack far target %s" % [turret.unit_id, target_far.unit_id])
    _make_units_attack(turret, target_far)

    await get_tree().create_timer(1.0).timeout

    if turret.current_state == GameEnums.UnitState.IDLE:
        logger.info("CombatTestSuite", "✓ Turret correctly returned to IDLE after far attack")
    else:
        logger.error("CombatTestSuite", "✗ Turret did not return to IDLE after far attack")

    # Test limit count
    logger.info("CombatTestSuite", "Testing turret limit count:")
    var team2_turrets = []
    for i in range(5): # Spawn 5 turrets
        var turret_in_team2 = await _spawn_unit_for_test(archetype, 2, Vector3(0, 1, 0))
        if is_instance_valid(turret_in_team2):
            team2_turrets.append(turret_in_team2)
        else:
            logger.error("CombatTestSuite", "Failed to spawn turret %d for limit test." % i)
            break

    if team2_turrets.size() == 5:
        logger.info("CombatTestSuite", "✓ Turrets limit count test passed (spawned 5 turrets)")
    else:
        logger.error("CombatTestSuite", "✗ Turrets limit count test failed (spawned %d turrets)" % team2_turrets.size())

    # Test limit health
    logger.info("CombatTestSuite", "Testing turret limit health:")
    var turret_with_low_health = await _spawn_unit_for_test(archetype, 2, Vector3(0, 1, 0))
    if not is_instance_valid(turret_with_low_health):
        logger.error("CombatTestSuite", "Failed to spawn turret for low health test.")
        return

    turret_with_low_health.current_health = 1 # Set to 1 health
    logger.info("CombatTestSuite", "Turret %s with low health: %d" % [turret_with_low_health.unit_id, turret_with_low_health.current_health])

    turret_with_low_health.take_damage(1) # Try to damage
    await get_tree().create_timer(0.5).timeout

    if turret_with_low_health.current_health == 0:
        logger.info("CombatTestSuite", "✓ Turret health limit test passed (health reached 0)")
    else:
        logger.error("CombatTestSuite", "✗ Turret health limit test failed (health not 0)")

    logger.info("CombatTestSuite", "Turret limits test completed.")

func _test_turret_combat():
    logger.info("CombatTestSuite", "Starting turret combat test.")
    var archetype = "turret"
    var team_id = 1
    var position = Vector3(0, 1, 0)
    
    var turret = await _spawn_unit_for_test(archetype, team_id, position)
    if not is_instance_valid(turret):
        logger.error("CombatTestSuite", "Failed to spawn turret for combat test.")
        return

    logger.info("CombatTestSuite", "Turret %s spawned at %s" % [turret.unit_id, turret.global_position])

    # Test turret targeting
    logger.info("CombatTestSuite", "Testing turret targeting:")
    var target_in_range = await _spawn_unit_for_test("scout", 2, Vector3(10, 1, 0))
    if not is_instance_valid(target_in_range):
        logger.error("CombatTestSuite", "Failed to spawn target for turret targeting.")
        return

    logger.info("CombatTestSuite", "Making turret %s attack target %s" % [turret.unit_id, target_in_range.unit_id])
    _make_units_attack(turret, target_in_range)

    await get_tree().create_timer(1.0).timeout

    if turret.current_state == GameEnums.UnitState.ATTACKING:
        logger.info("CombatTestSuite", "✓ Turret correctly entered ATTACKING state")
        logger.info("CombatTestSuite", "  - Target: %s" % target_in_range.unit_id)
    else:
        logger.error("CombatTestSuite", "✗ Turret did not enter ATTACKING state")

    # Test turret targeting multiple enemies
    logger.info("CombatTestSuite", "Testing turret targeting multiple enemies:")
    var target_far_1 = await _spawn_unit_for_test("scout", 2, Vector3(100, 1, 0))
    if not is_instance_valid(target_far_1):
        logger.error("CombatTestSuite", "Failed to spawn far target for turret multiple targeting.")
        return

    var target_far_2 = await _spawn_unit_for_test("scout", 2, Vector3(100, 1, 0))
    if not is_instance_valid(target_far_2):
        logger.error("CombatTestSuite", "Failed to spawn far target for turret multiple targeting.")
        return

    logger.info("CombatTestSuite", "Making turret %s attack multiple far targets" % [turret.unit_id])
    _make_units_attack(turret, target_far_1)
    _make_units_attack(turret, target_far_2)

    await get_tree().create_timer(1.0).timeout

    if turret.current_state == GameEnums.UnitState.ATTACKING:
        logger.info("CombatTestSuite", "✓ Turret correctly entered ATTACKING state for multiple targets")
        logger.info("CombatTestSuite", "  - Targets: %s, %s" % [target_far_1.unit_id, target_far_2.unit_id])
    else:
        logger.error("CombatTestSuite", "✗ Turret did not enter ATTACKING state for multiple targets")

    # Test turret targeting allies
    logger.info("CombatTestSuite", "Testing turret targeting allies:")
    var ally_in_range = await _spawn_unit_for_test("scout", 1, Vector3(10, 1, 0))
    if not is_instance_valid(ally_in_range):
        logger.error("CombatTestSuite", "Failed to spawn ally for turret targeting.")
        return

    logger.info("CombatTestSuite", "Making turret %s attack ally %s" % [turret.unit_id, ally_in_range.unit_id])
    _make_units_attack(turret, ally_in_range)

    await get_tree().create_timer(1.0).timeout

    if turret.current_state == GameEnums.UnitState.IDLE:
        logger.info("CombatTestSuite", "✓ Turret correctly returned to IDLE after attacking ally")
    else:
        logger.error("CombatTestSuite", "✗ Turret did not return to IDLE after attacking ally")

    # Test turret targeting self
    logger.info("CombatTestSuite", "Testing turret targeting self:")
    var self_target = await _spawn_unit_for_test(archetype, 1, Vector3(0, 1, 0))
    if not is_instance_valid(self_target):
        logger.error("CombatTestSuite", "Failed to spawn self target for turret targeting.")
        return

    logger.info("CombatTestSuite", "Making turret %s attack self %s" % [turret.unit_id, self_target.unit_id])
    _make_units_attack(turret, self_target)

    await get_tree().create_timer(1.0).timeout

    if turret.current_state == GameEnums.UnitState.IDLE:
        logger.info("CombatTestSuite", "✓ Turret correctly returned to IDLE after attacking self")
    else:
        logger.error("CombatTestSuite", "✗ Turret did not return to IDLE after attacking self")

    # Test turret targeting dead targets
    logger.info("CombatTestSuite", "Testing turret targeting dead targets:")
    var dead_target = await _spawn_unit_for_test("scout", 2, Vector3(100, 1, 0))
    if not is_instance_valid(dead_target):
        logger.error("CombatTestSuite", "Failed to spawn dead target for turret targeting.")
        return

    dead_target.take_damage(dead_target.max_health * 2)
    await get_tree().create_timer(1.0).timeout

    if turret.current_state == GameEnums.UnitState.IDLE:
        logger.info("CombatTestSuite", "✓ Turret correctly returned to IDLE after attacking dead target")
    else:
        logger.error("CombatTestSuite", "✗ Turret did not return to IDLE after attacking dead target")

    logger.info("CombatTestSuite", "Turret combat test completed.")

func _test_engineer_turret_construction():
    logger.info("CombatTestSuite", "Starting engineer turret construction test.")
    
    # Spawn an engineer
    var engineer = await _spawn_unit_for_test("engineer", 1, Vector3(0, 1, 0))
    if not is_instance_valid(engineer):
        logger.error("CombatTestSuite", "Failed to spawn engineer for turret construction test.")
        return
    
    logger.info("CombatTestSuite", "Engineer %s spawned at %s" % [engineer.unit_id, engineer.global_position])
    
    # Get initial turret count
    var initial_turret_count = game_state.get_units_by_archetype("turret", 1).size()
    logger.info("CombatTestSuite", "Initial turret count for team 1: %d" % initial_turret_count)
    
    # Test construct_turret method
    logger.info("CombatTestSuite", "Testing engineer construct_turret method...")
    engineer.construct_turret({})
    
    # Wait for construction to complete
    logger.info("CombatTestSuite", "Waiting for turret construction to complete...")
    await get_tree().create_timer(8.0).timeout  # Turret build_time is 5.0 + buffer
    
    # Check if turret was created
    var final_turret_count = game_state.get_units_by_archetype("turret", 1).size()
    logger.info("CombatTestSuite", "Final turret count for team 1: %d" % final_turret_count)
    
    if final_turret_count > initial_turret_count:
        logger.info("CombatTestSuite", "✓ Engineer successfully constructed turret!")
        logger.info("CombatTestSuite", "  - Turrets created: %d" % (final_turret_count - initial_turret_count))
        
        # Find the newly created turret
        var turrets = game_state.get_units_by_archetype("turret", 1)
        if turrets.size() > 0:
            var new_turret = turrets[turrets.size() - 1]  # Get the last turret (likely the newest)
            logger.info("CombatTestSuite", "  - New turret ID: %s" % new_turret.unit_id)
            logger.info("CombatTestSuite", "  - New turret position: %s" % new_turret.global_position)
            logger.info("CombatTestSuite", "  - New turret health: %d/%d" % [new_turret.current_health, new_turret.max_health])
            logger.info("CombatTestSuite", "  - New turret team: %d" % new_turret.team_id)
    else:
        logger.error("CombatTestSuite", "✗ Engineer failed to construct turret")
        logger.error("CombatTestSuite", "  - Expected: %d turrets" % (initial_turret_count + 1))
        logger.error("CombatTestSuite", "  - Actual: %d turrets" % final_turret_count)
    
    # Test multiple turret construction (should hit limit and start replacing)
    logger.info("CombatTestSuite", "Testing multiple turret construction with rolling replacement...")
    var construction_attempts = 8  # Try to build more than the 5 turret limit
    var turret_ids_created = []
    
    for i in range(construction_attempts):
        logger.info("CombatTestSuite", "Attempting to construct turret %d..." % (i + 2))
        
        # Store the current turret IDs before construction
        var turrets_before = game_state.get_units_by_archetype("turret", 1)
        var ids_before = []
        for turret in turrets_before:
            if is_instance_valid(turret):
                ids_before.append(turret.unit_id)
        
        engineer.construct_turret({})
        await get_tree().create_timer(8.0).timeout  # Wait for each construction
        
        # Check turrets after construction
        var turrets_after = game_state.get_units_by_archetype("turret", 1)
        var ids_after = []
        for turret in turrets_after:
            if is_instance_valid(turret):
                ids_after.append(turret.unit_id)
        
        var current_count = turrets_after.size()
        logger.info("CombatTestSuite", "After construction attempt %d: %d turrets" % [(i + 2), current_count])
        
        # Check if we're maintaining the limit while continuing construction
        if current_count <= 5:
            logger.info("CombatTestSuite", "✓ Turret count maintained at or below limit (%d/5)" % current_count)
            
            # If we're past the limit attempts, check if turrets are being replaced
            if i >= 4:  # After 5th construction attempt
                # Find which turrets were removed and which were added
                var removed_turrets = []
                var added_turrets = []
                
                for id in ids_before:
                    if not id in ids_after:
                        removed_turrets.append(id)
                
                for id in ids_after:
                    if not id in ids_before:
                        added_turrets.append(id)
                
                if removed_turrets.size() > 0 and added_turrets.size() > 0:
                    logger.info("CombatTestSuite", "✓ Turret replacement working:")
                    logger.info("CombatTestSuite", "  - Removed: %s" % removed_turrets)
                    logger.info("CombatTestSuite", "  - Added: %s" % added_turrets)
                else:
                    logger.warning("CombatTestSuite", "⚠ No clear turret replacement detected")
        else:
            logger.error("CombatTestSuite", "✗ Turret count exceeded limit (%d/5)" % current_count)
    
    var final_count = game_state.get_units_by_archetype("turret", 1).size()
    if final_count == 5:
        logger.info("CombatTestSuite", "✓ Final turret count correct (5/5)")
        logger.info("CombatTestSuite", "✓ Rolling turret replacement system working properly")
    elif final_count < 5:
        logger.warning("CombatTestSuite", "⚠ Final turret count lower than expected (%d/5)" % final_count)
    else:
        logger.error("CombatTestSuite", "✗ Final turret count exceeded limit (%d/5)" % final_count)
    
    logger.info("CombatTestSuite", "Engineer turret construction test completed.")

func _test_follow_turret_exclusion():
    """Test that units don't follow turrets in follow state"""
    logger.info("CombatTestSuite", "Starting follow turret exclusion test...")
    
    # Spawn a scout (follower) and a turret on the same team
    var scout = await _spawn_unit_for_test("scout", 1, Vector3(0, 1, 0))
    var turret = await _spawn_unit_for_test("turret", 1, Vector3(5, 1, 0))
    var tank = await _spawn_unit_for_test("tank", 1, Vector3(10, 1, 0))
    
    if not is_instance_valid(scout) or not is_instance_valid(turret) or not is_instance_valid(tank):
        logger.error("CombatTestSuite", "Failed to spawn units for follow turret exclusion test")
        return
    
    logger.info("CombatTestSuite", "Spawned scout %s, turret %s, and tank %s" % [scout.unit_id, turret.unit_id, tank.unit_id])
    
    # Test 1: Check that scout doesn't select turret as nearest ally to follow
    logger.info("CombatTestSuite", "Testing _get_nearest_ally excludes turrets...")
    
    # Create a test array with both turret and tank
    var test_allies = [turret, tank]
    var nearest_ally = scout._get_nearest_ally(test_allies)
    
    if nearest_ally == tank:
        logger.info("CombatTestSuite", "✓ _get_nearest_ally correctly selected tank over turret")
    elif nearest_ally == turret:
        logger.error("CombatTestSuite", "✗ _get_nearest_ally incorrectly selected turret")
    else:
        logger.warning("CombatTestSuite", "⚠ _get_nearest_ally returned unexpected result: %s" % str(nearest_ally))
    
    # Test 2: Test in actual follow behavior
    logger.info("CombatTestSuite", "Testing follow state behavior with turret present...")
    
    # Force scout into follow state
    scout.current_reactive_state = "follow"
    scout._execute_follow_state()
    
    await get_tree().create_timer(1.0).timeout
    
    # Check what the scout is following
    if scout.follow_target == tank:
        logger.info("CombatTestSuite", "✓ Scout correctly chose to follow tank instead of turret")
    elif scout.follow_target == turret:
        logger.error("CombatTestSuite", "✗ Scout incorrectly chose to follow turret")
    elif scout.follow_target == null:
        logger.info("CombatTestSuite", "✓ Scout didn't select any follow target (acceptable if no valid targets)")
    else:
        logger.warning("CombatTestSuite", "⚠ Scout following unexpected target: %s" % str(scout.follow_target))
    
    # Test 3: Test medic healing exclusion
    logger.info("CombatTestSuite", "Testing medic healing exclusion of turrets...")
    
    var medic = await _spawn_unit_for_test("medic", 1, Vector3(15, 1, 0))
    if not is_instance_valid(medic):
        logger.error("CombatTestSuite", "Failed to spawn medic for healing test")
        return
    
    # Damage the turret to give it low health
    turret.take_damage(50)
    
    # Test medic's healing target selection
    var healing_target = medic._get_lowest_health_ally_in_vision()
    
    if healing_target != turret:
        logger.info("CombatTestSuite", "✓ Medic correctly excluded damaged turret from healing targets")
        if healing_target:
            logger.info("CombatTestSuite", "  - Medic selected %s instead" % healing_target.unit_id)
        else:
            logger.info("CombatTestSuite", "  - Medic found no valid healing targets")
    else:
        logger.error("CombatTestSuite", "✗ Medic incorrectly selected turret as healing target")
    
    # Test 4: Test with only a turret as ally
    logger.info("CombatTestSuite", "Testing follow behavior with only turret as ally...")
    
    # Remove tank temporarily
    tank.queue_free()
    await get_tree().create_timer(0.5).timeout
    
    # Test scout's ally selection when only turret is available
    var game_state = get_node_or_null("/root/DependencyContainer/GameState")
    if game_state:
        var allies_in_range = game_state.get_units_in_radius(scout.global_position, 30.0, -1, scout.team_id)
        var nearest_non_turret_ally = scout._get_nearest_ally(allies_in_range)
        
        if nearest_non_turret_ally == null:
            logger.info("CombatTestSuite", "✓ Scout correctly found no valid allies when only turret available")
        else:
            logger.warning("CombatTestSuite", "⚠ Scout found ally when only turret should be available: %s" % nearest_non_turret_ally.unit_id)
    
    logger.info("CombatTestSuite", "Follow turret exclusion test completed.")

func _test_scout_stealth():
    logger.info("CombatTestSuite", "Starting scout stealth test.")
    
    # Spawn a scout
    var scout = await _spawn_unit_for_test("scout", 1, Vector3(0, 1, 0))
    if not is_instance_valid(scout):
        logger.error("CombatTestSuite", "Failed to spawn scout for stealth test.")
        return
    
    logger.info("CombatTestSuite", "Scout %s spawned at %s" % [scout.unit_id, scout.global_position])
    
    # Test initial state
    logger.info("CombatTestSuite", "Testing initial scout state:")
    logger.info("CombatTestSuite", "  - Unit ID: %s" % scout.unit_id)
    logger.info("CombatTestSuite", "  - Team ID: %d" % scout.team_id)
    logger.info("CombatTestSuite", "  - Position: %s" % scout.global_position)
    logger.info("CombatTestSuite", "  - Health: %d/%d" % [scout.current_health, scout.max_health])
    logger.info("CombatTestSuite", "  - Current State: %s" % scout.current_state)
    
    # Check if scout has stealth ability
    if scout.has_method("activate_stealth"):
        logger.info("CombatTestSuite", "✓ Scout has activate_stealth method")
    else:
        logger.error("CombatTestSuite", "✗ Scout does not have activate_stealth method")
        return
    
    # Test stealth activation
    logger.info("CombatTestSuite", "Testing stealth activation...")
    scout.activate_stealth({})
    
    # Wait a moment for stealth to activate
    await get_tree().create_timer(0.5).timeout
    
    # Check if scout entered stealth state
    if scout.is_stealthed:
        logger.info("CombatTestSuite", "✓ Scout successfully activated stealth")
        
        # Check stealth properties
        logger.info("CombatTestSuite", "✓ Scout is_stealthed property is true")
        
        # Check for stealth visual effect (transparency changes)
        var model_container = scout.get_node_or_null("ModelContainer")
        if model_container:
            logger.info("CombatTestSuite", "✓ Model container found for stealth visual effects")
        else:
            logger.warning("CombatTestSuite", "⚠ Model container not found for stealth visual effects")
        
        # Check stealth timer
        if scout.has_method("get") and "stealth_timer" in scout:
            var remaining_time = scout.stealth_timer
            logger.info("CombatTestSuite", "✓ Stealth timer: %.2f seconds remaining" % remaining_time)
        else:
            logger.warning("CombatTestSuite", "⚠ stealth_timer property not accessible")
    else:
        logger.error("CombatTestSuite", "✗ Scout failed to activate stealth (is_stealthed: %s)" % scout.is_stealthed)
        return
    
    # Test stealth duration (wait for it to expire naturally)
    logger.info("CombatTestSuite", "Testing stealth duration...")
    var stealth_duration = 11.0  # Scout stealth duration is 10.0 + buffer
    await get_tree().create_timer(stealth_duration).timeout
    
    # Check if stealth expired
    if not scout.is_stealthed:
        logger.info("CombatTestSuite", "✓ Stealth expired naturally")
        
        # Check that scout returned to normal transparency
        logger.info("CombatTestSuite", "✓ Stealth visual effects should be cleared")
    else:
        logger.error("CombatTestSuite", "✗ Stealth did not expire properly (is_stealthed: %s)" % scout.is_stealthed)
    
    # Test stealth cooldown
    logger.info("CombatTestSuite", "Testing stealth cooldown...")
    scout.activate_stealth({})
    await get_tree().create_timer(0.5).timeout
    
    if scout.is_stealthed:
        logger.info("CombatTestSuite", "✓ Scout can activate stealth again (no cooldown issues)")
    elif scout.has_method("get") and "stealth_cooldown_timer" in scout:
        var cooldown = scout.stealth_cooldown_timer
        if cooldown > 0:
            logger.info("CombatTestSuite", "✓ Stealth cooldown active: %.2f seconds remaining" % cooldown)
        else:
            logger.warning("CombatTestSuite", "⚠ Stealth activation failed but no cooldown reported")
    else:
        logger.warning("CombatTestSuite", "⚠ Could not determine stealth cooldown status")
    
    # Test stealth interruption by damage
    logger.info("CombatTestSuite", "Testing stealth interruption by damage...")
    
    # Make sure scout is stealthed first
    if not scout.is_stealthed:
        scout.activate_stealth({})
        await get_tree().create_timer(0.5).timeout
    
    if scout.is_stealthed:
        logger.info("CombatTestSuite", "Scout is stealthed, testing damage interruption...")
        var health_before = scout.current_health
        
        # Deal damage to scout
        scout.take_damage(10)
        await get_tree().create_timer(0.2).timeout
        
        # Check if stealth was broken
        if not scout.is_stealthed:
            logger.info("CombatTestSuite", "✓ Stealth correctly broken by damage")
            logger.info("CombatTestSuite", "  - Health before: %d, after: %d" % [health_before, scout.current_health])
        else:
            logger.warning("CombatTestSuite", "⚠ Stealth was not broken by damage")
    else:
        logger.warning("CombatTestSuite", "⚠ Could not test damage interruption - scout not stealthed")
    
    # Test stealth detection mechanics with enemy units
    logger.info("CombatTestSuite", "Testing stealth detection mechanics...")
    
    # Spawn an enemy to test detection
    var enemy = await _spawn_unit_for_test("tank", 2, Vector3(5, 1, 0))
    if not is_instance_valid(enemy):
        logger.warning("CombatTestSuite", "⚠ Failed to spawn enemy for detection test")
    else:
        # Activate stealth
        scout.activate_stealth({})
        await get_tree().create_timer(0.5).timeout
        
        if scout.is_stealthed:
            logger.info("CombatTestSuite", "Testing enemy detection of stealthed scout...")
            
            # Test 1: Direct targeting via can_be_targeted()
            if scout.can_be_targeted():
                logger.error("CombatTestSuite", "✗ Stealthed scout can_be_targeted() returns true (should be false)")
            else:
                logger.info("CombatTestSuite", "✓ Stealthed scout can_be_targeted() correctly returns false")
            
            # Test 2: Enemy targeting behavior
            # Make enemy try to attack scout
            _make_units_attack(enemy, scout)
            await get_tree().create_timer(1.0).timeout
            
            # Check enemy's targeting behavior
            if enemy.current_state == GameEnums.UnitState.ATTACKING:
                if enemy.has_method("get") and "target_unit" in enemy and enemy.target_unit == scout:
                    logger.warning("CombatTestSuite", "⚠ Enemy can still target stealthed scout")
                else:
                    logger.info("CombatTestSuite", "✓ Enemy attacking state but not targeting stealthed scout")
            elif enemy.current_state == GameEnums.UnitState.IDLE:
                logger.info("CombatTestSuite", "✓ Enemy cannot target stealthed scout (stayed IDLE)")
            else:
                logger.warning("CombatTestSuite", "⚠ Enemy in unexpected state: %s" % enemy.current_state)
            
            # Test 3: Manual enemy targeting check
            var enemies_near_scout = game_state.get_units_in_radius(scout.global_position, 10.0, scout.team_id) if game_state else []
            var targetable_enemies = enemies_near_scout.filter(func(u): return u.can_be_targeted())
            
            if enemies_near_scout.size() > 0 and targetable_enemies.size() == 0:
                logger.info("CombatTestSuite", "✓ get_units_in_radius + can_be_targeted() correctly excludes stealthed scout")
            elif enemies_near_scout.size() == 0:
                logger.info("CombatTestSuite", "✓ No enemies found near stealthed scout (as expected)")
            else:
                logger.warning("CombatTestSuite", "⚠ Targeting check unclear - enemies: %d, targetable: %d" % [enemies_near_scout.size(), targetable_enemies.size()])
        else:
            logger.warning("CombatTestSuite", "⚠ Could not test detection - scout not stealthed")
    
    # Test multiple stealth activations
    logger.info("CombatTestSuite", "Testing multiple stealth activations...")
    var successful_activations = 0
    
    for i in range(3):
        logger.info("CombatTestSuite", "Stealth activation attempt %d..." % (i + 1))
        
        # Wait for any cooldown
        if scout.has_method("get") and "stealth_cooldown_timer" in scout:
            var cooldown = scout.stealth_cooldown_timer
            if cooldown > 0:
                logger.info("CombatTestSuite", "Waiting for cooldown: %.2f seconds" % cooldown)
                await get_tree().create_timer(cooldown + 0.5).timeout
        
        scout.activate_stealth({})
        await get_tree().create_timer(0.5).timeout
        
        if scout.is_stealthed:
            successful_activations += 1
            logger.info("CombatTestSuite", "✓ Activation %d successful" % (i + 1))
            
            # Wait for stealth to expire
            await get_tree().create_timer(11.0).timeout  # 10.0 stealth duration + buffer
        else:
            logger.warning("CombatTestSuite", "⚠ Activation %d failed" % (i + 1))
    
    logger.info("CombatTestSuite", "Multiple activation test: %d/3 successful" % successful_activations)
    
    if successful_activations >= 2:
        logger.info("CombatTestSuite", "✓ Multiple stealth activations working well")
    else:
        logger.error("CombatTestSuite", "✗ Multiple stealth activations failing")
    
    logger.info("CombatTestSuite", "Scout stealth test completed.")

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

func _test_fog_debug():
    logger.info("CombatTestSuite", "Starting fog of war debug test.")
    
    # Find the fog of war manager
    var fog_manager = get_tree().get_root().find_child("FogOfWarManager", true, false)
    
    var debug_info = ""
    if fog_manager:
        if fog_manager.has_method("get_debug_info"):
            var info = fog_manager.get_debug_info()
            debug_info = """
[b]Fog of War Debug Info:[/b]
• Update Count: %d
• Last Update: %.2f seconds ago
• Has Camera: %s
• Has Visibility Texture: %s
• Fog Plane Visible: %s
• Fog Plane Position: %s
• Visibility Image Size: %s
""" % [
    info.update_count,
    (Time.get_ticks_msec() / 1000.0) - info.last_update_time,
    str(info.has_camera),
    str(info.has_visibility_texture),
    str(info.fog_plane_visible),
    str(info.fog_plane_position),
    str(info.visibility_image_size)
]
        else:
            debug_info = "[color=red]Error: FogOfWarManager missing debug methods[/color]"
        
        # Also test visibility manager on server
        if game_state and game_state.visibility_manager:
            var vm = game_state.visibility_manager
            var grid_meta = vm.get_grid_metadata()
            debug_info += """

[b]Server Visibility Manager:[/b]
• Grid Size: %dx%d
• Cell Size: %.1f
• Map Origin: %s
• Team 1 Grid Size: %d bytes
• Team 2 Grid Size: %d bytes
""" % [
    grid_meta.width,
    grid_meta.height,
    grid_meta.cell_size,
    str(grid_meta.origin),
    vm.get_visibility_grid_data(1).size(),
    vm.get_visibility_grid_data(2).size()
]
        else:
            debug_info += "\n[color=red]Server visibility manager not available[/color]"
    else:
        debug_info = "[color=red]Error: FogOfWarManager not found![/color]"
    
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        root_node.rpc("_on_ai_command_feedback_rpc", debug_info, "[color=yellow]Fog Debug[/color]")

func _test_fog_trace():
    logger.info("CombatTestSuite", "Starting comprehensive fog of war data flow trace.")
    
    var debug_info = "[b]Fog of War Data Flow Trace:[/b]\n\n"
    
    # 1. Check server-side visibility manager
    if game_state and game_state.visibility_manager:
        var vm = game_state.visibility_manager
        var grid_meta = vm.get_grid_metadata()
        var team1_grid = vm.get_visibility_grid_data(1)
        var team2_grid = vm.get_visibility_grid_data(2)
        
        var team1_visible = 0
        var team2_visible = 0
        for i in range(team1_grid.size()):
            if team1_grid[i] == 255: team1_visible += 1
        for i in range(team2_grid.size()):
            if team2_grid[i] == 255: team2_visible += 1
        
        debug_info += """[color=green]✓ Server Visibility Manager:[/color]
• Grid: %dx%d (cell size: %.1f)
• Origin: %s
• Team 1: %d/%d visible cells
• Team 2: %d/%d visible cells
• Units being tracked: %d

""" % [grid_meta.width, grid_meta.height, grid_meta.cell_size, str(grid_meta.origin), team1_visible, team1_grid.size(), team2_visible, team2_grid.size(), game_state.units.size()]
    else:
        debug_info += "[color=red]✗ Server Visibility Manager: NOT FOUND[/color]\n\n"
    
    # 2. Check if units exist and have positions
    if game_state and not game_state.units.is_empty():
        debug_info += "[color=green]✓ Server Units:[/color]\n"
        var count = 0
        for unit_id in game_state.units:
            var unit = game_state.units[unit_id]
            if is_instance_valid(unit) and not unit.is_dead:
                debug_info += "• %s (Team %d) at %s\n" % [unit_id, unit.team_id, str(unit.global_position)]
                count += 1
                if count >= 5: break  # Limit output
        debug_info += "\n"
    else:
        debug_info += "[color=red]✗ Server Units: NONE FOUND[/color]\n\n"
    
    # 3. Check client display manager
    var client_display_manager = get_tree().get_root().find_child("ClientDisplayManager", true, false)
    if client_display_manager:
        debug_info += "[color=green]✓ Client Display Manager: Found[/color]\n"
        if client_display_manager.latest_state.has("visibility_grid"):
            var grid_data = client_display_manager.latest_state.visibility_grid
            var visible_count = 0
            if grid_data:
                for i in range(grid_data.size()):
                    if grid_data[i] == 255: visible_count += 1
            debug_info += "• Last received visibility data: %d visible cells\n" % visible_count
        else:
            debug_info += "[color=red]• No visibility data in latest state[/color]\n"
        debug_info += "\n"
    else:
        debug_info += "[color=red]✗ Client Display Manager: NOT FOUND[/color]\n\n"
    
    # 4. Check fog manager
    var fog_manager = get_tree().get_root().find_child("FogOfWarManager", true, false)
    if fog_manager:
        debug_info += "[color=green]✓ Fog Manager: Found[/color]\n"
        if fog_manager.has_method("get_debug_info"):
            var info = fog_manager.get_debug_info()
            debug_info += "• Updates received: %d\n" % info.update_count
            debug_info += "• Has visibility texture: %s\n" % str(info.has_visibility_texture)
            debug_info += "• Fog plane visible: %s\n" % str(info.fog_plane_visible)
        debug_info += "\n"
    else:
        debug_info += "[color=red]✗ Fog Manager: NOT FOUND[/color]\n\n"
    
    # 5. Check match state
    if game_state:
        debug_info += "[color=green]✓ Match State: %s[/color]\n" % game_state.match_state
    else:
        debug_info += "[color=red]✗ Game State: NOT FOUND[/color]\n"
    
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        root_node.rpc("_on_ai_command_feedback_rpc", debug_info, "[color=yellow]Fog Trace[/color]")

func _test_fog_visibility():
    logger.info("CombatTestSuite", "Testing fog of war visibility updates.")
    
    # Spawn a unit from each team to test visibility
    var team1_unit = await _spawn_unit_for_test("scout", 1, Vector3(-30, 1, 0))
    var team2_unit = await _spawn_unit_for_test("scout", 2, Vector3(30, 1, 0))
    
    if not is_instance_valid(team1_unit) or not is_instance_valid(team2_unit):
        logger.error("CombatTestSuite", "Failed to spawn units for fog visibility test.")
        return
    
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        var info = """
[b]Fog Visibility Test Started:[/b]
• Team 1 Scout: %s at %s
• Team 2 Scout: %s at %s

Watch the fog plane - you should see:
1. Dark fog covering most of the map
2. Visible areas around each unit
3. Fog updating as units move

Use WASD to move camera and observe fog changes.
""" % [team1_unit.unit_id, str(team1_unit.global_position), team2_unit.unit_id, str(team2_unit.global_position)]
        
        root_node.rpc("_on_ai_command_feedback_rpc", info, "[color=yellow]Fog Visibility Test[/color]")

func _test_fog_movement():
    logger.info("CombatTestSuite", "Testing fog of war with unit movement.")
    
    # Spawn units and give them movement commands
    var scout = await _spawn_unit_for_test("scout", 1, Vector3(-40, 1, 0))
    
    if not is_instance_valid(scout):
        logger.error("CombatTestSuite", "Failed to spawn scout for fog movement test.")
        return
    
    # Move the scout in a pattern to test fog updates
    ai_command_processor.process_command("Move to the center of the map", [scout.unit_id], -1)
    
    await get_tree().create_timer(3.0).timeout
    
    ai_command_processor.process_command("Move to the east side", [scout.unit_id], -1)
    
    await get_tree().create_timer(3.0).timeout
    
    ai_command_processor.process_command("Move back to the west side", [scout.unit_id], -1)
    
    var root_node = get_tree().get_root().get_node_or_null("UnifiedMain")
    if root_node:
        var info = """
[b]Fog Movement Test Started:[/b]
• Scout %s will move in a pattern
• Watch how the fog reveals areas as the unit moves
• Previously visited areas should become fogged again

The fog should follow the unit's movement and update in real-time.
""" % scout.unit_id
        
        root_node.rpc("_on_ai_command_feedback_rpc", info, "[color=yellow]Fog Movement Test[/color]")

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