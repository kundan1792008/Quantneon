## Mission HUD Controller
## Displays active quest details and updates dynamically.

extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var title_label: Label = panel.find_child("TitleLabel", true, false) as Label
@onready var desc_label: Label = panel.find_child("DescLabel", true, false) as Label
@onready var progress_label: Label = panel.find_child("ProgressLabel", true, false) as Label

var current_quest_data = null

func _ready():
	panel.visible = false

func update_quest(quest_data):
	current_quest_data = quest_data
	if quest_data == null:
		panel.visible = false
		return
		
	panel.visible = true
	title_label.text = quest_data.title
	desc_label.text = quest_data.description
	progress_label.text = "Objective: %d / %d" % [quest_data.progress, quest_data.goal]
	
	# Visual feedback if progress updated
	var tween = create_tween()
	tween.tween_property(panel, "scale", Vector3(1.05, 1.05, 1.05), 0.1)
	tween.tween_property(panel, "scale", Vector3.ONE, 0.1)

func show_completion(title: String):
	title_label.text = "MISSION COMPLETE"
	desc_label.text = title
	progress_label.text = "REWARD ISSUED"
	
	var tween = create_tween()
	panel.modulate = Color.GREEN
	tween.tween_interval(3.0)
	tween.tween_callback(func(): panel.visible = false; panel.modulate = Color.WHITE)
