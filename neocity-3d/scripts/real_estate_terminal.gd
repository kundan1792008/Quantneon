extends StaticBody3D

# real_estate_terminal.gd - Open the property purchase UI

func interact(_player):
	if has_node("/root/RealEstateUI"):
		get_node("/root/RealEstateUI").show_ui()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
