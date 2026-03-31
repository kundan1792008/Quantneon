## Hacking Mini-game for Neo City Heists
## Displays a sequence of keys the player must press.

extends Control

signal completed
signal failed

var sequence = ["W", "A", "S", "D"]
var current_index = 0
var timer = 5.0

@onready var label = $Panel/VBoxContainer/InstructionLabel
@onready var progress_bar = $Panel/VBoxContainer/ProgressBar

func _ready():
	_generate_sequence()
	_update_ui()
	set_process(true)

func _generate_sequence():
	sequence = []
	var keys = ["W", "A", "S", "D", "Q", "E"]
	for i in range(5):
		sequence.append(keys[randi() % keys.size()])

func _process(delta):
	timer -= delta
	if progress_bar:
		progress_bar.value = (timer / 5.0) * 100
	
	if timer <= 0:
		emit_signal("failed")
		queue_free()

func _input(event):
	if event is InputEventKey and event.is_pressed():
		var key_name = OS.get_keycode_string(event.keycode)
		if key_name == sequence[current_index]:
			current_index += 1
			if current_index >= sequence.size():
				emit_signal("completed")
				queue_free()
			else:
				_update_ui()
		else:
			# Wrong key - reset or fail? Let's just reset index for now
			current_index = 0
			_update_ui()

func _update_ui():
	if label:
		var display = ""
		for i in range(sequence.size()):
			if i < current_index:
				display += "[color=green]" + sequence[i] + "[/color] "
			elif i == current_index:
				display += "[b]" + sequence[i] + "[/b] "
			else:
				display += sequence[i] + " "
		label.text = "DECRYPTING: " + display
