extends StaticBody3D

# property_door.gd - Entrance to interiors

@export var property_id: String = ""

func interact(_player):
	var pm = get_node("/root/PropertyManager")
	var prop = pm.get_property(property_id)
	
	if prop:
		if pm.is_owner(property_id):
			enter_property(prop)
		else:
			print("You don't own this property: ", prop.name)
	else:
		print("Unknown property door.")

func enter_property(prop):
	print("Entering ", prop.name)
	# For simplicity, we'll teleport to the interior scene
	# In a real game, you'd load the interior scene.
	# Here we'll just move the player to a "hidden" interior coordinate
	# or change the scene.
	# Let's assume there's a WorldManager that handles interior transition
	
	var interior_scene = load("res://scenes/interiors/apartment_interior.tscn")
	get_tree().change_scene_to_packed(interior_scene)
