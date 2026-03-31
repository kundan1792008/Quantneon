extends Node3D

@export var point_id: String = ""
@export var radius: float = 5.0
@export var controlling_faction: String = "NONE"
@export var capturing_faction: String = "NONE"
@export var progress: float = 0.0

@onready var holo_mesh: MeshInstance3D = $HoloMesh
@onready var faction_label: Label3D = $FactionLabel
@onready var progress_label: Label3D = $ProgressLabel

var faction_colors = {
    "NEXUS_ORDER": Color(0.0, 0.4, 1.0, 0.4), # Neon Blue
    "SHADOW_SYNDICATE": Color(0.8, 0.0, 1.0, 0.4), # Neon Purple
    "FREE_CODERS": Color(0.0, 1.0, 0.0, 0.4), # Neon Green
    "QUANTUM_COLLECTIVE": Color(1.0, 0.8, 0.0, 0.4), # Neon Gold
    "NONE": Color(0.4, 0.4, 0.4, 0.2) # Grey
}

var faction_names = {
    "NEXUS_ORDER": "NEXUS ORDER",
    "SHADOW_SYNDICATE": "SHADOW SYNDICATE",
    "FREE_CODERS": "FREE CODERS",
    "QUANTUM_COLLECTIVE": "QUANTUM COLLECTIVE",
    "NONE": "UNCLAIMED SECTOR"
}

func _ready():
    # Scale Hologram to match radius from backend
    holo_mesh.scale = Vector3(radius / 5.0, 1.0, radius / 5.0)
    _update_visuals()

func update_state(data: Dictionary):
    point_id = data.id
    radius = float(data.radius)
    controlling_faction = data.controllingFaction
    capturing_faction = data.capturingFaction
    progress = float(data.progress)
    
    _update_visuals()

func _update_visuals():
    # Update Hologram Color
    var mat: Material = holo_mesh.get_surface_override_material(0)
    if mat and mat is StandardMaterial3D:
        var target_color = faction_colors.get(controlling_faction, faction_colors["NONE"])
        mat.albedo_color = target_color
        mat.emission = target_color
    
    # Update Faction Banner
    faction_label.text = faction_names.get(controlling_faction, faction_names["NONE"])
    faction_label.modulate = faction_colors.get(controlling_faction, Color.WHITE)
    faction_label.modulate.a = 1.0 # Make text opaque
    
    # Update Progress Indicator
    if progress > 0 and progress < 100:
        var cap_color = faction_colors.get(capturing_faction, Color.WHITE)
        progress_label.text = "%.1f%% [%s]" % [progress, faction_names.get(capturing_faction, "UNKNOWN")]
        progress_label.modulate = cap_color
        progress_label.modulate.a = 1.0
        progress_label.visible = true
    elif progress == 100:
        progress_label.text = "SECURED"
        progress_label.modulate = faction_label.modulate
        progress_label.visible = true
    else:
        progress_label.visible = false

func _process(delta: float):
    # Rotate Hologram slowly
    holo_mesh.rotate_y(0.2 * delta)

