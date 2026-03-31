extends Node

@export var day_length_seconds: float = 1200.0 # 20 minutes real time
@export var rain_particles_scene: PackedScene = preload("res://scenes/rain_particles.tscn")

var directional_light: DirectionalLight3D
var world_environment: WorldEnvironment
var current_rain: GPUParticles3D
var target_time: float = 8.0 # Default 8 AM
var smoothed_time: float = 8.0

func _ready():
    # Attempt to find main environment nodes
    directional_light = get_tree().root.find_child("DirectionalLight3D", true, false)
    world_environment = get_tree().root.find_child("WorldEnvironment", true, false)
    
    if NetworkManager:
        NetworkManager.connect("zone_update_received", _on_zone_update)

func _process(delta: float):
    # Smoothly interpolate the time to avoid snapping
    smoothed_time = lerp(smoothed_time, target_time, delta * 2.0)
    
    if directional_light:
        _update_sun_position(smoothed_time)
        _update_lighting_energy(smoothed_time)

func _update_sun_position(time: float):
    # Map 0-24 time to an angle. 
    # 6 AM = -90 deg (Sunrise), 12 PM = -90 (High Noon, Y-down), 6 PM = 90 deg (Sunset)
    # Actually, proper mapping for X axis rotation:
    # 6:00 -> 0 degrees (horizon)
    # 12:00 -> 90 degrees (straight down)
    # 18:00 -> 180 degrees (horizon opposite)
    
    var time_fraction = (time - 6.0) / 12.0 # 0 at 6AM, 1 at 6PM
    var angle_deg = lerp(0.0, 180.0, time_fraction)
    
    # We want it to rotate around the X axis
    directional_light.rotation_degrees.x = -angle_deg
    
    # Disable shadow if it's nighttime to save performance and hide weird under-lighting
    directional_light.shadow_enabled = (time > 6.0 and time < 18.0)

func _update_lighting_energy(time: float):
    # Darker at night
    var is_day = time >= 6.0 and time <= 18.0
    
    if world_environment:
        var night_color = Color(0.05, 0.05, 0.1)
        var day_color = Color(1.0, 1.0, 1.0)
        
        var t = 0.0
        if time < 6.0: t = time / 6.0 # 0 to 1 scaling towards dawn
        elif time > 18.0: t = 1.0 - ((time - 18.0) / 6.0) # 1 to 0 scaling towards midnight
        else: t = 1.0 # Full day
        
        # Smooth curve for dawn/dusk
        t = smoothstep(0.0, 1.0, t)
        
        # Adjust light energy
        directional_light.light_energy = lerp(0.1, 1.0, t)
        
        # We can also dynamically adjust sky shader parameters here if needed

func _on_zone_update(snapshot: Dictionary):
    if snapshot.has("time"):
        # Handle day wrap-around for lerping
        if abs(snapshot.time - target_time) > 12.0:
            smoothed_time = snapshot.time # Snap to prevent backward spinning
        target_time = snapshot.time
        
    if snapshot.has("weather"):
        _set_weather(snapshot.weather)

func _set_weather(weather: String):
    var local_player = get_tree().root.find_child("Player", true, false)
    if not local_player: return
    
    if weather == "rain":
        if not is_instance_valid(current_rain):
            current_rain = rain_particles_scene.instantiate()
            local_player.add_child(current_rain)
            # Position above player
            current_rain.position = Vector3(0, 15, 0)
        current_rain.emitting = true
    else:
        if is_instance_valid(current_rain):
            current_rain.emitting = false
            # We don't queue_free immediately so trails can fade out naturally
