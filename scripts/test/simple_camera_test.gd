extends Node3D

func _ready():
	print("=== SIMPLE CAMERA MOUSE CONTROLS TEST ===")
	print("Testing RTS Camera with mouse controls...")
	
	# Create ground plane
	var ground = MeshInstance3D.new()
	ground.name = "Ground"
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(50, 50)
	ground.mesh = plane_mesh
	
	var ground_material = StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.3, 0.8, 0.3)
	ground.material_override = ground_material
	
	add_child(ground)
	
	# Create some reference objects 
	_create_reference_objects()
	
	# Create RTS camera with mouse controls
	var rts_camera = RTSCamera.new()
	rts_camera.name = "RTSCamera"
	
	# Position camera to view the scene
	rts_camera.position = Vector3(0, 0, 0)
	rts_camera.current_zoom = 20.0
	rts_camera.target_zoom = 20.0
	
	add_child(rts_camera)
	
	# Create lighting
	var light = DirectionalLight3D.new()
	light.name = "Light"
	light.position = Vector3(10, 10, 10)
	light.rotation_degrees = Vector3(-45, -45, 0)
	add_child(light)
	
	print("RTS Camera setup complete!")
	print("")
	print("MOUSE CONTROLS:")
	print("  - Mouse wheel: Zoom in/out")
	print("  - Middle mouse drag: Pan camera")
	print("  - Edge scrolling: Move mouse to screen edges")
	print("")
	print("KEYBOARD CONTROLS:")
	print("  - W/A/S/D: Move camera")
	print("")
	print("Test the controls by moving your mouse and using the controls!")

func _create_reference_objects():
	"""Create some cubes as reference points"""
	var positions = [
		Vector3(-10, 1, -10), Vector3(0, 1, -10), Vector3(10, 1, -10),
		Vector3(-10, 1, 0), Vector3(0, 1, 0), Vector3(10, 1, 0),
		Vector3(-10, 1, 10), Vector3(0, 1, 10), Vector3(10, 1, 10)
	]
	
	var colors = [
		Color.RED, Color.GREEN, Color.BLUE,
		Color.YELLOW, Color.WHITE, Color.CYAN,
		Color.MAGENTA, Color.ORANGE, Color.PURPLE
	]
	
	for i in range(positions.size()):
		var cube = MeshInstance3D.new()
		cube.name = "Cube%d" % i
		cube.mesh = BoxMesh.new()
		cube.position = positions[i]
		
		var material = StandardMaterial3D.new()
		material.albedo_color = colors[i]
		cube.material_override = material
		
		add_child(cube)
	
	print("Created 9 reference cubes in a 3x3 grid") 