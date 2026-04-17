## FactionUI — Full faction management dashboard.
##
## Panels:
##   • Overview      — Faction name, tag, treasury, stats at a glance.
##   • Members       — Scrollable member list with role badges; kick/promote/demote actions.
##   • Territory Map — 2-D grid overlay showing faction colours on city blocks.
##   • War Status    — Active war list with real-time score progress bars.
##   • Leaderboard   — Cross-district faction ranking table.
##   • Chat          — Faction-scoped chat channel.
##
## The panel is shown/hidden via the "F" key (handled externally or by player_controller.gd).
## All data is pulled from /root/FactionManager and /root/TerritoryWar signals.

extends CanvasLayer

# ── Tab indices ────────────────────────────────────────────────────────────────

const TAB_OVERVIEW:   int = 0
const TAB_MEMBERS:    int = 1
const TAB_MAP:        int = 2
const TAB_WAR:        int = 3
const TAB_LEADERBOARD: int = 4
const TAB_CHAT:       int = 5

# ── Colors ─────────────────────────────────────────────────────────────────────

const COLOR_LEADER:    Color = Color(1.0, 0.85, 0.0)   # gold
const COLOR_OFFICER:   Color = Color(0.4, 0.8, 1.0)    # cyan
const COLOR_MEMBER:    Color = Color(0.85, 0.85, 0.85) # light grey
const COLOR_WAR_ATT:   Color = Color(1.0, 0.3, 0.2)    # red-orange
const COLOR_WAR_DEF:   Color = Color(0.3, 0.6, 1.0)    # blue
const COLOR_NEUTRAL:   Color = Color(0.4, 0.4, 0.4)    # grey
const COLOR_CEASEFIRE: Color = Color(0.9, 0.9, 0.2)    # yellow

## Map cell size in pixels.
const MAP_CELL_SIZE: int = 14

# ── Node references ────────────────────────────────────────────────────────────

@onready var bg_dim: ColorRect    = $BgDim
@onready var main_panel: Panel    = $MainPanel
@onready var close_btn: Button    = $MainPanel/Header/CloseBtn
@onready var title_lbl: Label     = $MainPanel/Header/TitleLabel
@onready var tab_bar: HBoxContainer = $MainPanel/TabBar
@onready var content_stack: Node  = $MainPanel/ContentStack  # e.g. a TabContainer or VBoxContainer

# Overview tab nodes
@onready var ov_faction_name: Label   = $MainPanel/ContentStack/Overview/FactionName
@onready var ov_faction_tag: Label    = $MainPanel/ContentStack/Overview/FactionTag
@onready var ov_treasury: Label       = $MainPanel/ContentStack/Overview/Treasury
@onready var ov_territory_count: Label = $MainPanel/ContentStack/Overview/TerritoryCount
@onready var ov_member_count: Label   = $MainPanel/ContentStack/Overview/MemberCount
@onready var ov_war_wins: Label       = $MainPanel/ContentStack/Overview/WarWins
@onready var ov_building_value: Label = $MainPanel/ContentStack/Overview/BuildingValue
@onready var ov_no_faction_msg: Label = $MainPanel/ContentStack/Overview/NoFactionMessage
@onready var ov_create_btn: Button    = $MainPanel/ContentStack/Overview/CreateFactionBtn
@onready var ov_leave_btn: Button     = $MainPanel/ContentStack/Overview/LeaveFactionBtn
@onready var ov_disband_btn: Button   = $MainPanel/ContentStack/Overview/DisbandFactionBtn

# Members tab nodes
@onready var member_list: VBoxContainer = $MainPanel/ContentStack/Members/ScrollContainer/MemberList
@onready var apply_btn: Button          = $MainPanel/ContentStack/Members/ApplyBtn
@onready var invite_field: LineEdit     = $MainPanel/ContentStack/Members/InviteField
@onready var invite_btn: Button         = $MainPanel/ContentStack/Members/InviteBtn
@onready var applications_list: VBoxContainer = $MainPanel/ContentStack/Members/Applications/List

# Territory map tab nodes
@onready var map_grid: GridContainer    = $MainPanel/ContentStack/TerritoryMap/MapGrid
@onready var map_legend: VBoxContainer  = $MainPanel/ContentStack/TerritoryMap/Legend

# War tab nodes
@onready var war_list: VBoxContainer    = $MainPanel/ContentStack/WarStatus/WarList
@onready var declare_war_zone_field: LineEdit = $MainPanel/ContentStack/WarStatus/DeclarePanel/ZoneField
@onready var declare_war_btn: Button    = $MainPanel/ContentStack/WarStatus/DeclarePanel/DeclareBtn
@onready var war_cost_label: Label      = $MainPanel/ContentStack/WarStatus/DeclarePanel/CostLabel

# Leaderboard tab nodes
@onready var leaderboard_list: VBoxContainer = $MainPanel/ContentStack/Leaderboard/ScrollContainer/List
@onready var leaderboard_refresh_btn: Button  = $MainPanel/ContentStack/Leaderboard/RefreshBtn
@onready var season_info_lbl: Label           = $MainPanel/ContentStack/Leaderboard/SeasonInfo

# Chat tab nodes
@onready var chat_log: VBoxContainer  = $MainPanel/ContentStack/Chat/ScrollContainer/ChatLog
@onready var chat_scroll: ScrollContainer = $MainPanel/ContentStack/Chat/ScrollContainer
@onready var chat_input: LineEdit     = $MainPanel/ContentStack/Chat/ChatInput
@onready var chat_send_btn: Button    = $MainPanel/ContentStack/Chat/SendBtn

# ── Runtime state ─────────────────────────────────────────────────────────────

var _active_tab: int = TAB_OVERVIEW
## Map cells: {zone_id: ColorRect}
var _map_cells: Dictionary = {}
## War progress bars: {war_id: {att_bar: ProgressBar, def_bar: ProgressBar, label: Label}}
var _war_bars: Dictionary = {}
## Leaderboard rows: Array of Control nodes
var _leaderboard_rows: Array = []
## Chat message count (for capping render).
var _chat_message_count: int = 0
const MAX_CHAT_MESSAGES: int = 100

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	_connect_signals()
	_connect_manager_signals()
	_update_overview()
	_update_members()
	_build_territory_map()
	_update_war_list()
	_refresh_leaderboard_from_season()
	print("[FactionUI] Ready.")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			toggle_visible()
		elif event.keycode == KEY_ESCAPE and visible:
			hide_panel()

# ── Visibility ────────────────────────────────────────────────────────────────

func toggle_visible() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()

func show_panel() -> void:
	visible = true
	_refresh_current_tab()

func hide_panel() -> void:
	visible = false

# ── Signal wiring ─────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	if is_instance_valid(close_btn):
		close_btn.pressed.connect(hide_panel)
	if is_instance_valid(ov_create_btn):
		ov_create_btn.pressed.connect(_on_create_faction_pressed)
	if is_instance_valid(ov_leave_btn):
		ov_leave_btn.pressed.connect(_on_leave_faction_pressed)
	if is_instance_valid(ov_disband_btn):
		ov_disband_btn.pressed.connect(_on_disband_faction_pressed)
	if is_instance_valid(apply_btn):
		apply_btn.pressed.connect(_on_apply_pressed)
	if is_instance_valid(invite_btn):
		invite_btn.pressed.connect(_on_invite_pressed)
	if is_instance_valid(declare_war_btn):
		declare_war_btn.pressed.connect(_on_declare_war_pressed)
		declare_war_btn.text = "Declare War (Cost: %d QT)" % TerritoryWar.WAR_DECLARATION_COST if has_node("/root/TerritoryWar") else "Declare War"
	if is_instance_valid(war_cost_label):
		war_cost_label.text = "Cost: %d QT" % 1000
	if is_instance_valid(leaderboard_refresh_btn):
		leaderboard_refresh_btn.pressed.connect(_on_leaderboard_refresh_pressed)
	if is_instance_valid(chat_send_btn):
		chat_send_btn.pressed.connect(_on_chat_send_pressed)
	if is_instance_valid(chat_input):
		chat_input.text_submitted.connect(_on_chat_text_submitted)

	# Tab buttons
	var tab_buttons: Array = tab_bar.get_children() if is_instance_valid(tab_bar) else []
	for i in range(tab_buttons.size()):
		var btn: Button = tab_buttons[i] as Button
		if btn:
			btn.pressed.connect(_on_tab_pressed.bind(i))

func _connect_manager_signals() -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm:
		fm.faction_updated.connect(_on_faction_updated)
		fm.members_updated.connect(_on_members_updated)
		fm.faction_message_received.connect(_on_chat_message)
		fm.application_received.connect(_on_application_received)
		fm.invite_received.connect(_on_invite_received)
		fm.faction_stats_updated.connect(_on_faction_stats_updated)
		fm.district_factions_updated.connect(_on_district_factions_updated)

	var tw: Node = get_node_or_null("/root/TerritoryWar")
	if tw:
		tw.war_declared.connect(_on_war_declared)
		tw.war_scores_updated.connect(_on_war_scores_updated)
		tw.war_resolved.connect(_on_war_resolved)
		tw.territory_captured.connect(_on_territory_captured)
		tw.ceasefire_started.connect(_on_ceasefire_started)
		tw.ceasefire_ended.connect(_on_ceasefire_ended)

	var ss: Node = get_node_or_null("/root/SeasonSystem")
	if ss:
		ss.season_updated.connect(_on_season_updated)
		ss.leaderboard_updated.connect(_on_season_leaderboard_updated)

# ── Tab switching ─────────────────────────────────────────────────────────────

func _on_tab_pressed(tab_index: int) -> void:
	_active_tab = tab_index
	_show_tab(tab_index)
	_refresh_current_tab()

func _show_tab(tab_index: int) -> void:
	if not is_instance_valid(content_stack):
		return
	var children: Array = content_stack.get_children()
	for i in range(children.size()):
		children[i].visible = (i == tab_index)

func _refresh_current_tab() -> void:
	match _active_tab:
		TAB_OVERVIEW:   _update_overview()
		TAB_MEMBERS:    _update_members()
		TAB_MAP:        _build_territory_map()
		TAB_WAR:        _update_war_list()
		TAB_LEADERBOARD: _refresh_leaderboard_from_season()
		TAB_CHAT:       _scroll_chat_to_bottom()

# ── Overview panel ─────────────────────────────────────────────────────────────

func _update_overview() -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm == null or not fm.is_in_faction():
		_set_label_safe(ov_faction_name, "— No Faction —")
		_set_label_safe(ov_faction_tag, "")
		_set_label_safe(ov_treasury, "")
		_set_label_safe(ov_territory_count, "")
		_set_label_safe(ov_member_count, "")
		_set_label_safe(ov_war_wins, "")
		_set_label_safe(ov_building_value, "")
		if is_instance_valid(ov_no_faction_msg):
			ov_no_faction_msg.visible = true
		_show_btns(false, false, false)
		return

	if is_instance_valid(ov_no_faction_msg):
		ov_no_faction_msg.visible = false

	var f: Dictionary = fm.local_faction
	_set_label_safe(ov_faction_name, f.get("name", "Unknown"))
	_set_label_safe(ov_faction_tag, "[%s]" % f.get("tag", "?"))
	_set_label_safe(ov_treasury, "Treasury: %d QT" % int(f.get("treasury", 0)))
	_set_label_safe(ov_territory_count, "Territories: %d" % int(f.get("territory_count", 0)))
	_set_label_safe(ov_member_count, "Members: %d" % int(f.get("member_count", 0)))
	_set_label_safe(ov_war_wins, "War Wins: %d" % int(f.get("war_wins", 0)))
	_set_label_safe(ov_building_value, "Building Value: %d QT" % int(f.get("total_building_value", 0)))

	var is_leader: bool = fm.local_role == "leader"
	_show_btns(true, is_leader, not is_leader)

func _show_btns(show_leave: bool, show_disband: bool, show_create: bool) -> void:
	if is_instance_valid(ov_leave_btn):    ov_leave_btn.visible    = show_leave
	if is_instance_valid(ov_disband_btn):  ov_disband_btn.visible  = show_disband
	if is_instance_valid(ov_create_btn):   ov_create_btn.visible   = show_create

# ── Members panel ──────────────────────────────────────────────────────────────

func _update_members() -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if not is_instance_valid(member_list) or fm == null:
		return
	# Clear existing rows.
	for child in member_list.get_children():
		child.queue_free()

	var members: Array = fm.get_local_faction_members()
	for m in members:
		member_list.add_child(_build_member_row(m, fm))

	# Show/hide officer tools.
	var is_officer: bool = fm.local_role == "leader" or fm.local_role == "officer"
	if is_instance_valid(applications_list):
		applications_list.get_parent().visible = is_officer
		_rebuild_applications(fm)
	if is_instance_valid(invite_field):
		invite_field.visible = is_officer
	if is_instance_valid(invite_btn):
		invite_btn.visible = is_officer
	if is_instance_valid(apply_btn):
		apply_btn.visible = not fm.is_in_faction()

func _build_member_row(member: Dictionary, fm: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_lbl := Label.new()
	var role_lbl := Label.new()
	var kick_btn := Button.new()

	name_lbl.text = member.get("player_name", "Unknown")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var role: String = member.get("role", "member")
	role_lbl.text = fm.role_label(role)
	match role:
		"leader":  role_lbl.add_theme_color_override("font_color", COLOR_LEADER)
		"officer": role_lbl.add_theme_color_override("font_color", COLOR_OFFICER)
		_:         role_lbl.add_theme_color_override("font_color", COLOR_MEMBER)

	kick_btn.text = "Kick"
	var pid: String = member.get("player_id", "")
	kick_btn.pressed.connect(func(): _on_kick_member(pid))

	var can_kick: bool = (fm.local_role == "leader") or \
						 (fm.local_role == "officer" and role == "member")
	kick_btn.visible = can_kick and pid != fm.local_faction.get("leader_id", "")

	row.add_child(name_lbl)
	row.add_child(role_lbl)
	row.add_child(kick_btn)
	return row

func _rebuild_applications(fm: Node) -> void:
	if not is_instance_valid(applications_list):
		return
	for child in applications_list.get_children():
		child.queue_free()
	for app in fm.pending_applications:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = app.get("player_name", "?")
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var accept_btn := Button.new()
		accept_btn.text = "Accept"
		var reject_btn := Button.new()
		reject_btn.text = "Reject"
		var apid: String = app.get("player_id", "")
		accept_btn.pressed.connect(func(): _on_accept_application(apid))
		reject_btn.pressed.connect(func(): _on_reject_application(apid))
		row.add_child(lbl)
		row.add_child(accept_btn)
		row.add_child(reject_btn)
		applications_list.add_child(row)

# ── Territory map panel ────────────────────────────────────────────────────────

## Builds (or rebuilds) the 2-D territory map overlay.
## Uses zone_owners from TerritoryWar and faction colours from FactionManager.
func _build_territory_map() -> void:
	if not is_instance_valid(map_grid):
		return
	for child in map_grid.get_children():
		child.queue_free()
	_map_cells.clear()

	var tw: Node = get_node_or_null("/root/TerritoryWar")
	var fm: Node = get_node_or_null("/root/FactionManager")
	if tw == null:
		return

	var zone_owners: Dictionary = tw.zone_owners
	if zone_owners.is_empty():
		var placeholder := Label.new()
		placeholder.text = "No zone data yet.\nEnter a district to populate the map."
		map_grid.add_child(placeholder)
		return

	# Determine grid dimensions from zone IDs (expected format: "gx_gz").
	var grid_coords: Array = []
	for zone_id in zone_owners.keys():
		var parts: Array = zone_id.split("_")
		if parts.size() >= 2:
			grid_coords.append(Vector2i(int(parts[0]), int(parts[1])))

	if grid_coords.is_empty():
		return

	var min_x: int = grid_coords[0].x
	var min_z: int = grid_coords[0].y
	var max_x: int = grid_coords[0].x
	var max_z: int = grid_coords[0].y
	for gc in grid_coords:
		min_x = min(min_x, gc.x)
		min_z = min(min_z, gc.y)
		max_x = max(max_x, gc.x)
		max_z = max(max_z, gc.y)

	var cols: int = max_x - min_x + 1
	map_grid.columns = cols

	# Sort zone_ids so the grid renders row-by-row.
	var sorted_zones: Array = zone_owners.keys()
	sorted_zones.sort()

	for zone_id in sorted_zones:
		var owner_id: String = zone_owners[zone_id]
		var cell_color: Color = _faction_color(owner_id, fm)
		# Ceasefire tint.
		if tw.is_zone_in_ceasefire(zone_id):
			cell_color = COLOR_CEASEFIRE.lerp(cell_color, 0.5)
		var cell := ColorRect.new()
		cell.custom_minimum_size = Vector2(MAP_CELL_SIZE, MAP_CELL_SIZE)
		cell.color = cell_color
		cell.tooltip_text = "%s\n%s" % [zone_id, _owner_name(owner_id, fm)]
		map_grid.add_child(cell)
		_map_cells[zone_id] = cell

	_build_map_legend(fm, tw)

func _build_map_legend(fm: Node, _tw: Node) -> void:
	if not is_instance_valid(map_legend):
		return
	for child in map_legend.get_children():
		child.queue_free()
	if fm == null:
		return
	# Add neutral entry.
	_add_legend_entry("Neutral", COLOR_NEUTRAL)
	_add_legend_entry("Ceasefire", COLOR_CEASEFIRE)
	for faction_id in fm.all_factions.keys():
		var f: Dictionary = fm.all_factions[faction_id]
		var color: Color = _faction_color(faction_id, fm)
		_add_legend_entry(f.get("name", faction_id), color)

func _add_legend_entry(label_text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.color = color
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(swatch)
	row.add_child(lbl)
	map_legend.add_child(row)

func _faction_color(faction_id: String, fm: Node) -> Color:
	if faction_id == "" or fm == null:
		return COLOR_NEUTRAL
	var f: Dictionary = fm.all_factions.get(faction_id, {})
	var hex: String = f.get("color_hex", "")
	if hex == "":
		return COLOR_NEUTRAL
	return Color.html(hex) if hex.is_valid_html_color() else COLOR_NEUTRAL

func _owner_name(faction_id: String, fm: Node) -> String:
	if faction_id == "" or fm == null:
		return "Neutral"
	var f: Dictionary = fm.all_factions.get(faction_id, {})
	return f.get("name", faction_id)

# ── War status panel ───────────────────────────────────────────────────────────

func _update_war_list() -> void:
	if not is_instance_valid(war_list):
		return
	for child in war_list.get_children():
		child.queue_free()
	_war_bars.clear()

	var tw: Node = get_node_or_null("/root/TerritoryWar")
	var fm: Node = get_node_or_null("/root/FactionManager")
	if tw == null:
		return

	var wars: Array = tw.active_wars.values()
	if wars.is_empty():
		var lbl := Label.new()
		lbl.text = "No active wars."
		war_list.add_child(lbl)
		return

	for war in wars:
		if war.get("status", "") == "resolved":
			continue
		war_list.add_child(_build_war_card(war, fm, tw))

func _build_war_card(war: Dictionary, fm: Node, tw: Node) -> PanelContainer:
	var card := PanelContainer.new()
	var vbox := VBoxContainer.new()
	card.add_child(vbox)

	var war_id: String  = war.get("war_id", "")
	var att_id: String  = war.get("attacker_faction_id", "")
	var def_id: String  = war.get("defender_faction_id", "")
	var zone_id: String = war.get("zone_id", "")

	var title_lbl := Label.new()
	title_lbl.text = "%s  ⚔  %s  |  Zone: %s" % [
		_owner_name(att_id, fm), _owner_name(def_id, fm), zone_id]
	title_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_lbl)

	# Time remaining.
	var time_lbl := Label.new()
	var secs_left: int = tw.war_seconds_remaining(war_id)
	time_lbl.text = "Time Left: " + tw.format_time_remaining(secs_left)
	vbox.add_child(time_lbl)

	# Score bars.
	var score_box := HBoxContainer.new()
	var att_bar   := ProgressBar.new()
	var def_bar   := ProgressBar.new()
	var score_lbl := Label.new()

	att_bar.max_value = 1.0
	att_bar.value     = 0.5
	att_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	att_bar.add_theme_color_override("fill", COLOR_WAR_ATT)

	def_bar.max_value = 1.0
	def_bar.value     = 0.5
	def_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	def_bar.add_theme_color_override("fill", COLOR_WAR_DEF)

	score_lbl.text = "0 vs 0"
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	score_box.add_child(att_bar)
	score_box.add_child(score_lbl)
	score_box.add_child(def_bar)
	vbox.add_child(score_box)

	# Ceasefire badge.
	if tw.is_zone_in_ceasefire(zone_id):
		var cf_lbl := Label.new()
		cf_lbl.text = "⚠ CEASEFIRE — %s remaining" % tw.format_time_remaining(tw.ceasefire_seconds_remaining(zone_id))
		cf_lbl.add_theme_color_override("font_color", COLOR_CEASEFIRE)
		vbox.add_child(cf_lbl)

	# Forfeit button (local faction's war only).
	if fm != null and fm.is_in_faction():
		var local_fid: String = fm.local_faction.get("id", "")
		if local_fid == att_id or local_fid == def_id:
			var forfeit_btn := Button.new()
			forfeit_btn.text = "Forfeit War"
			forfeit_btn.pressed.connect(func(): tw.forfeit_war(war_id, local_fid))
			vbox.add_child(forfeit_btn)

	_war_bars[war_id] = {"att_bar": att_bar, "def_bar": def_bar, "score_lbl": score_lbl, "time_lbl": time_lbl}
	# Apply current scores immediately.
	_update_war_bars(war_id, int(war.get("attacker_score", 0)), int(war.get("defender_score", 0)))
	return card

func _update_war_bars(war_id: String, att_score: int, def_score: int) -> void:
	if not _war_bars.has(war_id):
		return
	var bars: Dictionary = _war_bars[war_id]
	var total: float = float(att_score + def_score)
	var att_ratio: float = (float(att_score) / total) if total > 0.0 else 0.5
	var def_ratio: float = 1.0 - att_ratio
	if is_instance_valid(bars.get("att_bar")):
		bars["att_bar"].value = att_ratio
	if is_instance_valid(bars.get("def_bar")):
		bars["def_bar"].value = def_ratio
	if is_instance_valid(bars.get("score_lbl")):
		bars["score_lbl"].text = "%d  vs  %d" % [att_score, def_score]

# ── Leaderboard panel ──────────────────────────────────────────────────────────

func _refresh_leaderboard_from_season() -> void:
	var ss: Node = get_node_or_null("/root/SeasonSystem")
	if ss == null:
		return
	_populate_leaderboard(ss.faction_leaderboard)
	if is_instance_valid(season_info_lbl):
		var days: int = ss.days_remaining_in_season()
		season_info_lbl.text = "Season %d  |  %d days remaining" % [ss.current_season_number, days]

func _populate_leaderboard(entries: Array) -> void:
	if not is_instance_valid(leaderboard_list):
		return
	for child in leaderboard_list.get_children():
		child.queue_free()
	_leaderboard_rows.clear()

	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var row: HBoxContainer = _build_leaderboard_row(i + 1, entry)
		leaderboard_list.add_child(row)
		_leaderboard_rows.append(row)

func _build_leaderboard_row(rank: int, entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var rank_lbl   := Label.new()
	var name_lbl   := Label.new()
	var score_lbl  := Label.new()
	var terr_lbl   := Label.new()
	var wins_lbl   := Label.new()

	rank_lbl.text  = "#%d" % rank
	rank_lbl.custom_minimum_size = Vector2(30, 0)
	name_lbl.text  = entry.get("faction_name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_lbl.text = "Score: %d" % int(entry.get("season_score", 0))
	score_lbl.custom_minimum_size = Vector2(90, 0)
	terr_lbl.text  = "Terr: %d" % int(entry.get("territory_count", 0))
	terr_lbl.custom_minimum_size = Vector2(60, 0)
	wins_lbl.text  = "Wins: %d" % int(entry.get("war_wins", 0))
	wins_lbl.custom_minimum_size = Vector2(60, 0)

	if rank <= 3:
		var gold_colors: Array = [Color(1.0, 0.85, 0.0), Color(0.8, 0.8, 0.8), Color(0.8, 0.5, 0.2)]
		rank_lbl.add_theme_color_override("font_color", gold_colors[rank - 1])

	row.add_child(rank_lbl)
	row.add_child(name_lbl)
	row.add_child(score_lbl)
	row.add_child(terr_lbl)
	row.add_child(wins_lbl)
	return row

# ── Chat panel ────────────────────────────────────────────────────────────────

func _append_chat_message(sender: String, message: String, _timestamp: int) -> void:
	if not is_instance_valid(chat_log):
		return
	if _chat_message_count >= MAX_CHAT_MESSAGES:
		var oldest: Node = chat_log.get_child(0)
		oldest.queue_free()
		_chat_message_count -= 1

	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content    = true
	lbl.scroll_active  = false
	lbl.text = "[color=#7fd4ff][b]%s[/b][/color]: %s" % [sender.xml_escape(), message.xml_escape()]
	chat_log.add_child(lbl)
	_chat_message_count += 1
	_scroll_chat_to_bottom()

func _scroll_chat_to_bottom() -> void:
	if is_instance_valid(chat_scroll):
		await get_tree().process_frame
		chat_scroll.scroll_vertical = chat_scroll.get_v_scroll_bar().max_value

# ── Action handlers ────────────────────────────────────────────────────────────

func _on_create_faction_pressed() -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm == null:
		return
	# In a real scene this would open a creation dialog.
	# For now use a simple default name derivation.
	fm.create_faction("New Faction", "NF", "#ff00aa", "downtown")

func _on_leave_faction_pressed() -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm:
		fm.leave_faction()

func _on_disband_faction_pressed() -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm:
		fm.disband_faction()

func _on_apply_pressed() -> void:
	# Without a target faction selector we cannot apply here.
	# A real implementation would open a faction browser first.
	push_warning("[FactionUI] Apply requires selecting a target faction.")

func _on_invite_pressed() -> void:
	if not is_instance_valid(invite_field):
		return
	var player_name: String = invite_field.text.strip_edges()
	if player_name == "":
		return
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm:
		fm.invite_player("", player_name)  # server resolves name → id
	invite_field.text = ""

func _on_kick_member(player_id: String) -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm:
		fm.kick_member(player_id)

func _on_accept_application(player_id: String) -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm:
		fm.accept_application(player_id)
	_update_members()

func _on_reject_application(player_id: String) -> void:
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm:
		fm.reject_application(player_id)
	_update_members()

func _on_declare_war_pressed() -> void:
	if not is_instance_valid(declare_war_zone_field):
		return
	var zone_id: String = declare_war_zone_field.text.strip_edges()
	if zone_id == "":
		return
	var fm: Node = get_node_or_null("/root/FactionManager")
	var tw: Node = get_node_or_null("/root/TerritoryWar")
	if fm == null or tw == null or not fm.is_in_faction():
		return
	tw.declare_war(fm.local_faction.get("id", ""), zone_id)
	declare_war_zone_field.text = ""

func _on_leaderboard_refresh_pressed() -> void:
	var ss: Node = get_node_or_null("/root/SeasonSystem")
	if ss:
		ss.request_leaderboard()

func _on_chat_send_pressed() -> void:
	_send_chat_message()

func _on_chat_text_submitted(_text: String) -> void:
	_send_chat_message()

func _send_chat_message() -> void:
	if not is_instance_valid(chat_input):
		return
	var msg: String = chat_input.text.strip_edges()
	if msg == "":
		return
	var fm: Node = get_node_or_null("/root/FactionManager")
	if fm:
		fm.send_faction_chat(msg)
	chat_input.text = ""

# ── Manager signal handlers ────────────────────────────────────────────────────

func _on_faction_updated(_faction_data: Dictionary) -> void:
	if _active_tab == TAB_OVERVIEW:
		_update_overview()
	elif _active_tab == TAB_MEMBERS:
		_update_members()

func _on_members_updated(_members: Array) -> void:
	if _active_tab == TAB_MEMBERS:
		_update_members()

func _on_chat_message(sender_name: String, message: String, timestamp: int) -> void:
	_append_chat_message(sender_name, message, timestamp)

func _on_application_received(_applicant_id: String, applicant_name: String) -> void:
	if _active_tab == TAB_MEMBERS:
		_update_members()
	_show_toast("New application from %s" % applicant_name, Color(0.4, 1.0, 0.4))

func _on_invite_received(faction_id: String, faction_name: String, inviter_name: String) -> void:
	_show_toast("%s invited you to join %s" % [inviter_name, faction_name], Color(0.4, 0.8, 1.0))
	# Auto-show invite dialog.
	_show_invite_dialog(faction_id, faction_name, inviter_name)

func _on_faction_stats_updated(_faction_id: String, _stats: Dictionary) -> void:
	if _active_tab == TAB_OVERVIEW:
		_update_overview()

func _on_district_factions_updated(_district_id: String, _factions: Array) -> void:
	if _active_tab == TAB_MAP:
		_build_territory_map()

func _on_war_declared(_war_data: Dictionary) -> void:
	if _active_tab == TAB_WAR:
		_update_war_list()
	else:
		_show_toast("⚔  War declared!", COLOR_WAR_ATT)

func _on_war_scores_updated(war_id: String, att_score: int, def_score: int) -> void:
	_update_war_bars(war_id, att_score, def_score)
	# Also refresh time remaining label.
	var tw: Node = get_node_or_null("/root/TerritoryWar")
	if tw and _war_bars.has(war_id):
		var secs: int = tw.war_seconds_remaining(war_id)
		var time_lbl: Label = _war_bars[war_id].get("time_lbl")
		if is_instance_valid(time_lbl):
			time_lbl.text = "Time Left: " + tw.format_time_remaining(secs)

func _on_war_resolved(war_id: String, winner_faction_id: String, _loser_faction_id: String) -> void:
	_war_bars.erase(war_id)
	if _active_tab == TAB_WAR:
		_update_war_list()
	var fm: Node = get_node_or_null("/root/FactionManager")
	var winner_name: String = _owner_name(winner_faction_id, fm)
	_show_toast("🏆 War resolved! Winner: %s" % winner_name, Color(1.0, 0.85, 0.0))

func _on_territory_captured(zone_id: String, new_owner_faction_id: String, _prev: String) -> void:
	# Update map cell colour.
	if _map_cells.has(zone_id):
		var fm: Node = get_node_or_null("/root/FactionManager")
		_map_cells[zone_id].color = _faction_color(new_owner_faction_id, fm)
	var fm: Node = get_node_or_null("/root/FactionManager")
	_show_toast("📍 Territory %s captured by %s" % [zone_id, _owner_name(new_owner_faction_id, fm)],
		Color(1.0, 0.5, 0.2))

func _on_ceasefire_started(zone_id: String, _expires_unix: int) -> void:
	if _map_cells.has(zone_id):
		_map_cells[zone_id].color = COLOR_CEASEFIRE
	_show_toast("🕊 Ceasefire on zone %s" % zone_id, COLOR_CEASEFIRE)

func _on_ceasefire_ended(zone_id: String) -> void:
	if _active_tab == TAB_MAP:
		_build_territory_map()
	else:
		_show_toast("Zone %s ceasefire ended — war is possible again." % zone_id, Color(1.0, 0.6, 0.0))

func _on_season_updated(season_data: Dictionary) -> void:
	if is_instance_valid(season_info_lbl):
		var ss: Node = get_node_or_null("/root/SeasonSystem")
		var days: int = ss.days_remaining_in_season() if ss else 0
		season_info_lbl.text = "Season %d  |  %d days remaining" % [
			int(season_data.get("season_number", 0)), days]

func _on_season_leaderboard_updated(entries: Array) -> void:
	if _active_tab == TAB_LEADERBOARD:
		_populate_leaderboard(entries)

# ── Invite dialog (inline, lightweight) ───────────────────────────────────────

func _show_invite_dialog(faction_id: String, faction_name: String, inviter_name: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Faction Invite"
	dialog.dialog_text = "%s has invited you to join [%s].\nAccept?" % [inviter_name, faction_name]
	dialog.get_ok_button().text = "Accept"
	dialog.add_button("Decline", true, "decline")
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		var fm: Node = get_node_or_null("/root/FactionManager")
		if fm:
			fm.accept_invite(faction_id)
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(action: String):
		if action == "decline":
			var fm: Node = get_node_or_null("/root/FactionManager")
			if fm:
				fm.decline_invite(faction_id)
		dialog.queue_free()
	)

# ── Toast notification ─────────────────────────────────────────────────────────

func _show_toast(message: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = message
	lbl.add_theme_color_override("font_color", color)
	lbl.position = Vector2(20, 20)
	lbl.z_index  = 100
	add_child(lbl)
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tween.tween_callback(lbl.queue_free)

# ── Utility ────────────────────────────────────────────────────────────────────

func _set_label_safe(node: Label, text: String) -> void:
	if is_instance_valid(node):
		node.text = text
