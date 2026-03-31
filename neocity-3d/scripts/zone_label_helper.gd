## Helper for War Map Zone Labels
extends Label

var f_names = {
	"NEXUS_ORDER": "Nexus Order",
	"SHADOW_SYNDICATE": "Shadow Syndicate",
	"FREE_CODERS": "Free Coders",
	"QUANTUM_COLLECTIVE": "Quantum Collective",
	"NONE": "Neutral"
}

var f_colors = {
	"NEXUS_ORDER": Color.SKY_BLUE,
	"SHADOW_SYNDICATE": Color.CORAL,
	"FREE_CODERS": Color.LIME_GREEN,
	"QUANTUM_COLLECTIVE": Color.GOLD,
	"NONE": Color.GRAY
}

func update_status(faction: String, influence: float):
	text = f_names.get(faction, "Unknown") + " (" + str(int(influence)) + "%)"
	modulate = f_colors.get(faction, Color.WHITE)
