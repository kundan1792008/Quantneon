extends Control

@onready var panel_vbox: VBoxContainer = $Panel/VBoxContainer
@onready var close_button: Button = $Panel/VBoxContainer/Header/CloseButton
@onready var title_label: Label = $Panel/VBoxContainer/Header/Title
@onready var target_info: Label = $Panel/VBoxContainer/TargetInfo
@onready var program_list: VBoxContainer = $Panel/VBoxContainer/ProgramList
@onready var result_label: RichTextLabel = $Panel/VBoxContainer/ResultLabel

var current_terminal_id: String = ""
var terminal_defense: int = 1

var sequence: Array = []
var current_step: int = 0
var time_left: float = 10.0
var game_active: bool = false
var grid: GridContainer = null
var timer_label: Label = null

func _ready() -> void:
    hide()
    close_button.pressed.connect(close_deck)
    if NetworkManager.socket:
        NetworkManager.socket.on("hack_result", _on_hack_result)
        NetworkManager.socket.on("hack_started", _on_hack_started)

func open_deck(terminal_id: String, ice_level: int) -> void:
    current_terminal_id = terminal_id
    terminal_defense = ice_level
    
    # Send start request to backend 
    if NetworkManager.socket_client:
        NetworkManager.socket_client.send_event("hack_start", {"terminalId": terminal_id})
    else:
        _start_minigame() # Offline fallback

func _on_hack_started(data: Dictionary) -> void:
    if current_terminal_id == data.terminalId:
        terminal_defense = data.defense
        _start_minigame()

func _start_minigame() -> void:
    program_list.hide() # Hide old static buttons
    
    # Reset State
    game_active = true
    current_step = 0
    time_left = max(5.0, 15.0 - (terminal_defense * 1.5))
    sequence.clear()
    
    # Setup Timer UI
    if not timer_label:
        timer_label = Label.new()
        timer_label.add_theme_font_size_override("font_size", 20)
        timer_label.add_theme_color_override("font_color", Color.RED)
        timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        panel_vbox.add_child(timer_label)
        panel_vbox.move_child(timer_label, 1)
        
    # Setup Grid UI
    if not grid:
        grid = GridContainer.new()
        grid.columns = 4
        grid.set_h_size_flags(Control.SIZE_EXPAND_FILL)
        grid.add_theme_constant_override("h_separation", 10)
        grid.add_theme_constant_override("v_separation", 10)
        panel_vbox.add_child(grid)
    else:
        for child in grid.get_children():
            child.queue_free()
            
    # Generate Hex Sequence
    var possible_codes = ["E9", "1C", "55", "BD", "FF", "0A", "77", "42"]
    var seq_length = min(3 + (terminal_defense / 2), 6)
    
    var target_display = ""
    for i in range(seq_length):
        var code = possible_codes[randi() % possible_codes.size()]
        sequence.append(code)
        target_display += code + " "
        
    target_info.text = "TARGET SEQUENCE:\n" + target_display
    result_label.text = "[center][color=gray]Match the sequence before ICE detects you...[/color][/center]"
    
    # Fill Grid
    var grid_codes = sequence.duplicate()
    while grid_codes.size() < 16:
        grid_codes.append(possible_codes[randi() % possible_codes.size()])
    grid_codes.shuffle()
    
    for code in grid_codes:
        var btn = Button.new()
        btn.text = code
        btn.custom_minimum_size = Vector2(80, 50)
        btn.set_h_size_flags(Control.SIZE_EXPAND_FILL)
        btn.pressed.connect(func(): _on_hex_clicked(btn, code))
        grid.add_child(btn)

    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    show()

func _process(delta: float) -> void:
    if game_active and visible:
        time_left -= delta
        if timer_label:
            timer_label.text = "TRACE DETECTED - ICE IN: %.2f s" % time_left
        if time_left <= 0:
            _fail_game()

func _on_hex_clicked(btn: Button, code: String) -> void:
    if not game_active: return
    
    if code == sequence[current_step]:
        btn.disabled = true
        btn.modulate = Color(0, 1, 0) # Green success
        current_step += 1
        
        # Update display
        var display = ""
        for i in range(sequence.size()):
            if i < current_step:
                display += "[color=green]" + sequence[i] + "[/color] "
            else:
                display += "[color=white]" + sequence[i] + "[/color] "
        
        target_info.text = "TARGET SEQUENCE:\n" 
        result_label.text = "[center]" + display + "[/center]"
        
        if current_step >= sequence.size():
            _win_game()
    else:
        time_left -= 2.0 # Penalty
        btn.modulate = Color(1, 0, 0)
        
        # Shake effect
        var tween = create_tween()
        $Panel.position.x += 10
        tween.tween_property($Panel, "position:x", $Panel.position.x - 20, 0.05)
        tween.tween_property($Panel, "position:x", $Panel.position.x + 10, 0.05)

func _win_game() -> void:
    game_active = false
    result_label.text = "[center][b][color=green]ACCESS GRANTED![/color][/b]\nExtracting payload...[/center]"
    if NetworkManager.socket_client:
        NetworkManager.socket_client.send_event("hack_submit", {"terminalId": current_terminal_id, "success": true})

func _fail_game() -> void:
    game_active = false
    result_label.text = "[center][b][color=red]ACCESS DENIED[/color][/b]\nBlack ICE triggered![/center]"
    if NetworkManager.socket_client:
        NetworkManager.socket_client.send_event("hack_submit", {"terminalId": current_terminal_id, "success": false})

func _on_hack_result(data: Dictionary) -> void:
    if not visible: return 
    
    if data.success:
        result_label.text = "[center][b][color=green]HACK SUCCESSFUL![/color][/b]\nExtracted: %d NeonCoins\nDisconnecting...[/center]" % data.loot
        await get_tree().create_timer(2.0).timeout
        close_deck()
    else:
        var msg = data.get("message", "HACK FAILED")
        if data.has("damageTaken") and data.damageTaken > 0:
            result_label.text = "[center][b][color=red]ICE TRIGGERED![/color][/b]\nSystem feedback loop caused %d physical damage![/center]" % data.damageTaken
        else:
            result_label.text = "[center][color=red]%s[/color][/center]" % msg
            
        await get_tree().create_timer(3.0).timeout
        close_deck()

func close_deck() -> void:
    game_active = false
    hide()
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
