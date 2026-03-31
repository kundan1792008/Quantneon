extends PanelContainer

func set_data(data: Dictionary) -> void:
	$MarginContainer/HBoxContainer/VBoxContainer/TargetName.text = data.name
	$MarginContainer/HBoxContainer/VBoxContainer/Type.text = data.type.to_upper()
	$MarginContainer/HBoxContainer/BountyAmount.text = "Đ " + str(data.bounty)
