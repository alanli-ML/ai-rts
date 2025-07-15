# TextureTest.gd - Simple test for texture loading functionality
extends Node3D

func _ready() -> void:
	print("=== Texture Loading Test ===")
	
	# Test loading character textures
	_test_character_textures()
	
	# Test loading weapon texture
	_test_weapon_texture()
	
	# Test manual texture assignment
	_test_manual_texture_assignment()

func _test_character_textures() -> void:
	"""Test loading all character textures"""
	print("Testing character textures...")
	
	var character_textures = [
		"texture-a.png", "texture-b.png", "texture-c.png", "texture-d.png",
		"texture-e.png", "texture-f.png", "texture-g.png", "texture-h.png",
		"texture-i.png", "texture-j.png", "texture-k.png", "texture-l.png",
		"texture-m.png", "texture-n.png", "texture-o.png", "texture-p.png",
		"texture-q.png", "texture-r.png"
	]
	
	var base_path = "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/Textures/"
	var loaded_count = 0
	
	for texture_name in character_textures:
		var texture_path = base_path + texture_name
		var texture = load(texture_path)
		
		if texture:
			print("  ✓ Loaded: %s (size: %dx%d)" % [texture_name, texture.get_width(), texture.get_height()])
			loaded_count += 1
		else:
			print("  ✗ Failed: %s" % texture_name)
	
	print("Character textures: %d/%d loaded successfully" % [loaded_count, character_textures.size()])

func _test_weapon_texture() -> void:
	"""Test loading weapon texture"""
	print("Testing weapon texture...")
	
	var weapon_texture_path = "res://assets/kenney/kenney_blaster-kit-2/Models/GLB format/Textures/colormap.png"
	var texture = load(weapon_texture_path)
	
	if texture:
		print("  ✓ Weapon texture loaded: %dx%d" % [texture.get_width(), texture.get_height()])
	else:
		print("  ✗ Weapon texture failed to load")

func _test_manual_texture_assignment() -> void:
	"""Test creating a simple mesh with manual texture assignment"""
	print("Testing manual texture assignment...")
	
	# Create a simple quad mesh
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2, 2)
	
	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = quad_mesh
	mesh_instance.position = Vector3(0, 0, -5)
	add_child(mesh_instance)
	
	# Try to apply a character texture
	var texture_path = "res://assets/kenney/kenney_blocky-characters_20/Models/GLB format/Textures/texture-a.png"
	var texture = load(texture_path)
	
	if texture:
		var material = StandardMaterial3D.new()
		material.albedo_texture = texture
		material.albedo_color = Color.WHITE
		mesh_instance.material_override = material
		print("  ✓ Manual texture assignment successful")
	else:
		print("  ✗ Manual texture assignment failed")
	
	# Create a second quad for weapon texture
	var weapon_quad_mesh = QuadMesh.new()
	weapon_quad_mesh.size = Vector2(1, 1)
	
	var weapon_mesh_instance = MeshInstance3D.new()
	weapon_mesh_instance.mesh = weapon_quad_mesh
	weapon_mesh_instance.position = Vector3(3, 0, -5)
	add_child(weapon_mesh_instance)
	
	# Try to apply weapon texture
	var weapon_texture_path = "res://assets/kenney/kenney_blaster-kit-2/Models/GLB format/Textures/colormap.png"
	var weapon_texture = load(weapon_texture_path)
	
	if weapon_texture:
		var weapon_material = StandardMaterial3D.new()
		weapon_material.albedo_texture = weapon_texture
		weapon_material.albedo_color = Color.WHITE
		weapon_mesh_instance.material_override = weapon_material
		print("  ✓ Manual weapon texture assignment successful")
	else:
		print("  ✗ Manual weapon texture assignment failed")
	
	print("=== Texture Loading Test Complete ===")
	
	# Exit after a few seconds for quick testing
	await get_tree().create_timer(3.0).timeout
	get_tree().quit() 