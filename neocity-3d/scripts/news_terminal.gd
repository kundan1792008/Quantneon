extends Node3D

@onready var status_label: Label3D = $StatusLabel

func _ready():
	add_to_group("interactables")
	
func interact(player):
	print("Player reading news at terminal.")
	
	if NetworkManager.socket:
		# Just request the history which triggers the UI popup.
		NetworkManager.socket.emit("get_news_history", {})
		
		# For local testing, we could directly show a UI if not connected.
		# NewsTerminalUI.show_ui()
