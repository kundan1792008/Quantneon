extends StaticBody3D

# exit_door.gd - Return to main city

func interact(_player):
	print("Returning to Neo City...")
	# In a real game, you'd load the previous world state.
	# Here we'll just reload the main scene.
	get_tree().change_scene_to_file("res://scenes/main.tscn")
