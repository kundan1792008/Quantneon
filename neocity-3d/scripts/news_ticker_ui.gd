extends Control

@onready var ticker_container = $VBoxContainer/Panel/TickerContainer
@onready var ticker_label = $VBoxContainer/Panel/TickerContainer/TickerLabel
@onready var panel = $VBoxContainer/Panel

var message_queue: Array = []
var is_playing: bool = false
var current_tween: Tween = null
const SCROLL_SPEED: float = 120.0 # Pixels per second

func _ready() -> void:
	panel.hide()
	ticker_label.text = ""
	
	if NetworkManager.socket:
		NetworkManager.socket.on("global_broadcast", _on_global_broadcast)
		
	# Test mode if needed
	# queue_message("BREAKING: Data breach reported at Quantum Collective HQ.")
	# queue_message("Ripperdoc 'Doc Chrome' offering discounts on Kiroshi optics.")

func _on_global_broadcast(data: Dictionary) -> void:
	var msg = data.headline + " --- " + data.body
	queue_message(msg)

func queue_message(msg: String) -> void:
	message_queue.append(msg)
	if not is_playing:
		_play_next()

func _play_next() -> void:
	if message_queue.size() == 0:
		is_playing = false
		panel.hide()
		return
		
	is_playing = true
	panel.show()
	
	var msg = message_queue.pop_front()
	ticker_label.text = msg
	
	# Wait a frame for the label to resize based on text
	await get_tree().process_frame
	
	var container_width = ticker_container.size.x
	var text_width = ticker_label.size.x
	
	# Start offscreen right
	ticker_label.position.x = container_width
	
	# Target is offscreen left
	var target_x = -text_width - 50
	var distance = container_width - target_x
	var duration = distance / SCROLL_SPEED
	
	if current_tween:
		current_tween.kill()
		
	current_tween = create_tween()
	current_tween.tween_property(ticker_label, "position:x", target_x, duration).from(ticker_label.position.x)
	current_tween.tween_callback(_play_next)
