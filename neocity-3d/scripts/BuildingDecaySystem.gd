## BuildingDecaySystem.gd
## ---------------------------------------------------------------------------
## Ghost-building decay engine — the "social shame" half of issue #12.
##
## Rules
##   • Every owned block has a `last_visit` timestamp.  If the owner has not
##     physically entered the block (or applied any customization) for more
##     than `decay_grace_days`, the building begins to decay.
##   • Decay advances through 5 discrete stages:
##         0 pristine  → 1 faded → 2 grimy → 3 overgrown → 4 ghost
##     Each stage applies a visual modifier (colour tint, graffiti overlay,
##     broken-window mesh swap) that the renderer listens for.
##   • Decayed buildings broadcast a city-wide "ghost sighting" — other
##     players see a notification ("Block (3,-2) in Wastelands has been
##     abandoned for 9 days by @nyxstrider 👻").  That is the shame vector.
##   • Rent on decayed buildings is reduced by `RentEconomy` which queries
##     the current decay level via `BuildingDecaySystem.decay_level_for`.
##   • Full restoration requires the owner to visit AND apply a customization
##     within the same day.  Stage 4 (ghost) can also be "reclaimed" by
##     another player for a heavy fee if the original owner doesn't return
##     within `ghost_claim_unlock_days`.
##   • Leaderboard penalty: every completed decay stage subtracts points.
##
## Autoload name: `BuildingDecaySystem`.
## ---------------------------------------------------------------------------
extends Node

# ── Tunables ────────────────────────────────────────────────────────────────

## Real-time days of inactivity before decay begins.
@export var decay_grace_days: int = 7

## Days *between* subsequent stages once decay has started.
@export var decay_step_days: int = 2

## After how many days at stage 4 can anyone claim the block?
@export var ghost_claim_unlock_days: int = 14

## Point penalty applied to the city leaderboard per decay stage.
@export var leaderboard_penalty_per_stage: int = 20

## Claim-steal fee multiplier — stealing a ghost block costs price × this.
@export var ghost_steal_price_mult: float = 1.75

## Interval at which the system scans all blocks for decay transitions.
@export var scan_interval_sec: float = 30.0

## Descriptive label for each stage (0..4).
const STAGE_LABELS: Array[String] = [
	"pristine",
	"faded",
	"grimy",
	"overgrown",
	"ghost",
]

## Visual tint broadcast to renderers for each stage (HSV-value).
const STAGE_TINTS: Array[Color] = [
	Color(1.00, 1.00, 1.00, 1.0),
	Color(0.85, 0.85, 0.80, 1.0),
	Color(0.65, 0.62, 0.55, 1.0),
	Color(0.42, 0.45, 0.35, 1.0),
	Color(0.22, 0.24, 0.26, 1.0),
]

## Overlay texture hints per stage — a renderer may swap in these graffiti
## decals.  Paths are advisory; absent textures are simply ignored.
const STAGE_OVERLAY_HINTS: Array[String] = [
	"",
	"res://materials/decay/dust.png",
	"res://materials/decay/grime.png",
	"res://materials/decay/vines.png",
	"res://materials/decay/ghost.png",
]

# ── State ───────────────────────────────────────────────────────────────────

## {block_key: Dictionary} — decay record per owned block.
##   {
##     "block_key": String,
##     "owner_id": String,
##     "stage": int,                  # 0..4
##     "last_visit": int,             # unix s
##     "stage_since": int,             # unix s — when we entered current stage
##     "ghost_since": int,             # unix s — only valid at stage 4
##     "notified": Dictionary,         # set of stages already broadcast
##     "restore_progress": float,      # 0..1 for smooth UI bar
##   }
var decay_state: Dictionary = {}

## List of the most recent ghost sightings broadcast city-wide (ring buffer).
var ghost_feed: Array = []
const GHOST_FEED_MAX: int = 40

## Tick accumulator.
var _scan_accum: float = 0.0

## Cached reference to LandOwnershipService (resolved lazily).
var _los_ref: Node = null

## Set to true after the first scan so emitters don't spam on world load.
var _did_initial_scan: bool = false

# ── Signals ─────────────────────────────────────────────────────────────────

signal decay_stage_changed(block_key, new_stage, old_stage)
signal decay_visual_update(block_key, stage, tint, overlay_path)
signal ghost_sighting_broadcast(block_key, owner_id, owner_name, days_absent)
signal restoration_started(block_key, owner_id)
signal restoration_completed(block_key, owner_id, stages_recovered)
signal ghost_reclaimed(block_key, old_owner_id, new_owner_id, fee_paid)
signal shame_toast(message)
signal decay_snapshot_ready(snapshot)

# ── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	var los := _los()
	if los:
		los.connect("block_registry_updated", Callable(self, "_on_registry_updated"))
		los.connect("ownership_changed", Callable(self, "_on_ownership_changed"))
		los.connect("customization_changed", Callable(self, "_on_customization_changed"))
	var socket := get_node_or_null("/root/SocketIOClient")
	if socket:
		socket.on_event("decay_snapshot", Callable(self, "_on_remote_snapshot"))
		socket.on_event("ghost_sighting", Callable(self, "_on_remote_ghost_sighting"))

func _process(delta: float) -> void:
	_scan_accum += delta
	if _scan_accum < scan_interval_sec:
		return
	_scan_accum = 0.0
	scan_all_blocks()

# ── Public API — scanning ───────────────────────────────────────────────────

## Full sweep of every owned block.  Advances decay stages where due and
## emits visual updates / ghost sightings.  Safe to call at any time.
func scan_all_blocks() -> void:
	var los := _los()
	if los == null: return
	var now: int = int(Time.get_unix_time_from_system())
	var processed: int = 0
	for key in los.blocks.keys():
		var block: Dictionary = los.blocks[key]
		if block.owner_id == "":
			# Unowned: wipe decay record so reclaimed blocks start fresh.
			if decay_state.has(key):
				decay_state.erase(key)
			continue
		var rec: Dictionary = _ensure_record(key, block)
		var stage := _compute_stage(block.last_visit, now)
		if stage != rec.stage:
			_transition(key, rec, stage, now)
		processed += 1
	if not _did_initial_scan:
		_did_initial_scan = true
		emit_signal("decay_snapshot_ready", current_snapshot())
	# Periodic snapshot refresh every scan.
	if processed > 0:
		emit_signal("decay_snapshot_ready", current_snapshot())

## Query the current decay stage for a block.  0 if not tracked.
func decay_level_for(block_key: String) -> int:
	if decay_state.has(block_key):
		return int(decay_state[block_key].stage)
	return 0

## Returns a copy of the full decay record for UI / debug.
func decay_record(block_key: String) -> Dictionary:
	return decay_state.get(block_key, {}).duplicate(true)

## Returns all currently ghosted blocks (stage >= 4) sorted by longest absent.
func ghost_blocks() -> Array:
	var out: Array = []
	for key in decay_state.keys():
		var r: Dictionary = decay_state[key]
		if int(r.stage) >= 4:
			out.append(r.duplicate(true))
	out.sort_custom(func(a, b): return int(a.ghost_since) < int(b.ghost_since))
	return out

## Blocks the local player owns that are currently decaying (stage >= 1).
func my_decaying_blocks(owner_id: String) -> Array:
	var out: Array = []
	for key in decay_state.keys():
		var r: Dictionary = decay_state[key]
		if str(r.owner_id) == owner_id and int(r.stage) >= 1:
			out.append(r.duplicate(true))
	out.sort_custom(func(a, b): return int(a.stage) > int(b.stage))
	return out

## Aggregate snapshot — used by the real-estate UI.
func current_snapshot() -> Dictionary:
	var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	for r in decay_state.values():
		var s := int(r.stage)
		counts[s] = int(counts.get(s, 0)) + 1
	return {
		"tracked": decay_state.size(),
		"by_stage": counts,
		"recent_ghosts": ghost_feed.duplicate(),
	}

# ── Public API — restoration ────────────────────────────────────────────────

## Owner visits their block.  Call from player_controller when stepping
## onto the block.  If currently decaying, a restoration is queued — full
## recovery also requires customization within `restoration_same_day_sec`.
func register_owner_presence(block_key: String, owner_id: String) -> void:
	var los := _los()
	if los == null: return
	var block: Dictionary = los.get_block(block_key)
	if block.is_empty() or block.owner_id != owner_id:
		return
	var now: int = int(Time.get_unix_time_from_system())
	# Update last_visit in the canonical registry.
	_touch_last_visit(block_key, now)
	var rec: Dictionary = decay_state.get(block_key, {})
	if rec.is_empty() or int(rec.stage) == 0:
		return
	emit_signal("restoration_started", block_key, owner_id)
	emit_signal("shame_toast",
		"Welcome back! Customize the building to fully restore it.")
	rec.restore_progress = 0.5
	decay_state[block_key] = rec

## Call from LandOwnershipService on customization success — this completes
## a restoration even if the player never walked over the block (you designed
## it in the companion app).
func register_customization(block_key: String, owner_id: String) -> void:
	var rec: Dictionary = decay_state.get(block_key, {})
	if rec.is_empty(): return
	if str(rec.owner_id) != owner_id: return
	if int(rec.stage) == 0: return
	var recovered: int = int(rec.stage)
	_restore_fully(block_key, owner_id, recovered)

func _restore_fully(block_key: String, owner_id: String, stages_recovered: int) -> void:
	var rec: Dictionary = decay_state[block_key]
	var old: int = int(rec.stage)
	rec.stage = 0
	rec.stage_since = int(Time.get_unix_time_from_system())
	rec.ghost_since = 0
	rec.restore_progress = 1.0
	rec.notified = {}
	decay_state[block_key] = rec
	emit_signal("decay_stage_changed", block_key, 0, old)
	emit_signal("decay_visual_update", block_key, 0, STAGE_TINTS[0], STAGE_OVERLAY_HINTS[0])
	emit_signal("restoration_completed", block_key, owner_id, stages_recovered)
	emit_signal("shame_toast",
		"Your building is restored to pristine condition! (+%d QNT tenant confidence)" %
			(stages_recovered * 25))
	_sync_los_decay_level(block_key, 0)

# ── Public API — reclaim (social punishment) ────────────────────────────────

## Another player attempts to seize a ghost block.  Fails if the block is
## not at stage 4 or hasn't been ghosted long enough.  Returns true on
## successful reclaim.
func attempt_ghost_reclaim(block_key: String, claimant_id: String,
		claimant_name: String, claimant_clan: String,
		claimant_balance: int) -> bool:
	var rec: Dictionary = decay_state.get(block_key, {})
	if rec.is_empty() or int(rec.stage) < 4:
		emit_signal("shame_toast", "That building isn't a ghost yet.")
		return false
	var now: int = int(Time.get_unix_time_from_system())
	if now - int(rec.ghost_since) < ghost_claim_unlock_days * 86400:
		var remaining: int = (ghost_claim_unlock_days * 86400 - (now - int(rec.ghost_since))) / 3600
		emit_signal("shame_toast",
			"The owner still has %d hours to come back before you can reclaim." % remaining)
		return false
	var los := _los()
	if los == null: return false
	var block: Dictionary = los.get_block(block_key)
	if block.is_empty(): return false
	var fee: int = int(round(int(block.price) * ghost_steal_price_mult))
	if claimant_balance < fee:
		emit_signal("shame_toast",
			"Reclaim fee %d QNT exceeds your balance." % fee)
		return false
	var old_owner: String = str(rec.owner_id)
	var parts := block_key.split(":")
	if parts.size() != 3: return false
	los.transfer_block(block_key, claimant_id, claimant_name, claimant_clan)
	# Start fresh.
	decay_state.erase(block_key)
	_sync_los_decay_level(block_key, 0)
	emit_signal("ghost_reclaimed", block_key, old_owner, claimant_id, fee)
	emit_signal("shame_toast",
		"%s reclaimed a ghost block from %s for %d QNT!" % [
			claimant_name, old_owner, fee])
	var socket := get_node_or_null("/root/SocketIOClient")
	if socket and socket.has_method("send_event"):
		socket.send_event("ghost_reclaim", {
			"block_key": block_key,
			"claimant_id": claimant_id,
			"fee": fee,
		})
	return true

# ── Internal — stage math ───────────────────────────────────────────────────

func _compute_stage(last_visit: int, now: int) -> int:
	if last_visit <= 0:
		return 0  # never-visited fresh claims get a grace period
	var days_since: float = float(now - last_visit) / 86400.0
	if days_since < float(decay_grace_days):
		return 0
	var steps: int = int(floor((days_since - decay_grace_days) / float(decay_step_days))) + 1
	return clamp(steps, 0, 4)

func _ensure_record(block_key: String, block: Dictionary) -> Dictionary:
	if decay_state.has(block_key):
		# Keep record in sync if ownership changed or last_visit moved.
		var r: Dictionary = decay_state[block_key]
		r.owner_id = str(block.owner_id)
		r.last_visit = int(block.last_visit)
		decay_state[block_key] = r
		return r
	var rec := {
		"block_key": block_key,
		"owner_id": str(block.owner_id),
		"stage": 0,
		"last_visit": int(block.last_visit),
		"stage_since": int(Time.get_unix_time_from_system()),
		"ghost_since": 0,
		"notified": {},
		"restore_progress": 0.0,
	}
	decay_state[block_key] = rec
	return rec

func _transition(block_key: String, rec: Dictionary, new_stage: int, now: int) -> void:
	var old: int = int(rec.stage)
	rec.stage = new_stage
	rec.stage_since = now
	if new_stage >= 4 and old < 4:
		rec.ghost_since = now
	elif new_stage < 4:
		rec.ghost_since = 0
	decay_state[block_key] = rec
	emit_signal("decay_stage_changed", block_key, new_stage, old)
	emit_signal("decay_visual_update", block_key, new_stage,
		STAGE_TINTS[new_stage], STAGE_OVERLAY_HINTS[new_stage])
	_sync_los_decay_level(block_key, new_stage)
	_penalize_leaderboard(rec, new_stage, old)
	_broadcast_shame(block_key, rec, new_stage)

func _penalize_leaderboard(rec: Dictionary, new_stage: int, old: int) -> void:
	if new_stage <= old: return
	var los := _los()
	if los == null: return
	# Award negative points via the same accrual API.
	if los.has_method("_award_leaderboard_points"):
		var diff := new_stage - old
		los._award_leaderboard_points(rec.owner_id, _owner_name_for(rec.owner_id),
			-leaderboard_penalty_per_stage * diff, "decay")

func _broadcast_shame(block_key: String, rec: Dictionary, stage: int) -> void:
	if rec.notified.has(stage): return
	rec.notified[stage] = true
	decay_state[block_key] = rec
	if stage == 1:
		return  # stage 1 is silent (just colour drift)
	var los := _los()
	var days_absent := 0
	if los:
		var block: Dictionary = los.get_block(block_key)
		if block:
			days_absent = int((int(Time.get_unix_time_from_system()) -
				int(block.last_visit)) / 86400)
	var owner_name := _owner_name_for(rec.owner_id)
	var msg := ""
	match stage:
		2:
			msg = "%s is starting to look grimy (%d days absent)." % [
				_pretty(block_key), days_absent]
		3:
			msg = "Vines are overgrowing %s — %s hasn't returned for %d days!" % [
				_pretty(block_key), owner_name, days_absent]
		4:
			msg = "👻 GHOST BUILDING: %s has been abandoned for %d days by %s." % [
				_pretty(block_key), days_absent, owner_name]
	if msg == "": return
	emit_signal("ghost_sighting_broadcast", block_key, rec.owner_id, owner_name, days_absent)
	emit_signal("shame_toast", msg)
	_push_ghost_feed({
		"block_key": block_key,
		"owner_id": rec.owner_id,
		"owner_name": owner_name,
		"stage": stage,
		"days_absent": days_absent,
		"ts": int(Time.get_unix_time_from_system()),
		"msg": msg,
	})
	var socket := get_node_or_null("/root/SocketIOClient")
	if socket and socket.has_method("send_event"):
		socket.send_event("ghost_sighting", {
			"block_key": block_key,
			"stage": stage,
			"days_absent": days_absent,
			"owner_id": rec.owner_id,
		})

func _push_ghost_feed(entry: Dictionary) -> void:
	ghost_feed.push_front(entry)
	while ghost_feed.size() > GHOST_FEED_MAX:
		ghost_feed.pop_back()

# ── Signal plumbing to other services ───────────────────────────────────────

func _on_registry_updated() -> void:
	# A no-op fast-path.  Full decay advancement is still driven by the
	# periodic scan to avoid burst cost on big snapshot ingests.
	if not _did_initial_scan:
		scan_all_blocks()

func _on_ownership_changed(block_key: String, _old, _new) -> void:
	# A new owner means a clean slate.
	if decay_state.has(block_key):
		decay_state.erase(block_key)
	scan_all_blocks()

func _on_customization_changed(block_key: String, _data) -> void:
	var los := _los()
	if los == null: return
	var block: Dictionary = los.get_block(block_key)
	if block.is_empty() or block.owner_id == "": return
	register_customization(block_key, block.owner_id)

func _on_remote_snapshot(payload) -> void:
	if not (payload is Dictionary): return
	if payload.has("records"):
		for r in payload.records:
			if r is Dictionary and r.has("block_key"):
				decay_state[str(r.block_key)] = r

func _on_remote_ghost_sighting(payload) -> void:
	if not (payload is Dictionary): return
	var block_key: String = str(payload.get("block_key", ""))
	if block_key == "": return
	var entry := {
		"block_key": block_key,
		"owner_id": str(payload.get("owner_id", "")),
		"owner_name": _owner_name_for(str(payload.get("owner_id", ""))),
		"stage": int(payload.get("stage", 4)),
		"days_absent": int(payload.get("days_absent", 0)),
		"ts": int(Time.get_unix_time_from_system()),
		"msg": "%s has been spotted as a ghost building!" % _pretty(block_key),
	}
	_push_ghost_feed(entry)
	emit_signal("ghost_sighting_broadcast",
		block_key, entry.owner_id, entry.owner_name, entry.days_absent)
	emit_signal("shame_toast", entry.msg)

# ── Helpers ─────────────────────────────────────────────────────────────────

func _los() -> Node:
	if _los_ref == null or not is_instance_valid(_los_ref):
		_los_ref = get_node_or_null("/root/LandOwnershipService")
	return _los_ref

func _touch_last_visit(block_key: String, now: int) -> void:
	var los := _los()
	if los == null: return
	if not los.blocks.has(block_key): return
	var rec: Dictionary = los.blocks[block_key]
	rec.last_visit = now
	los.blocks[block_key] = rec
	if decay_state.has(block_key):
		decay_state[block_key].last_visit = now

func _sync_los_decay_level(block_key: String, level: int) -> void:
	var los := _los()
	if los == null: return
	if not los.blocks.has(block_key): return
	los.blocks[block_key].decay_level = level

func _owner_name_for(owner_id: String) -> String:
	if owner_id == "": return "unknown"
	var los := _los()
	if los == null: return owner_id
	var owned: Array = los.blocks_owned_by(owner_id)
	if owned.is_empty(): return owner_id
	return str(los.get_block(owned[0]).get("owner_name", owner_id))

func _pretty(block_key: String) -> String:
	var los := _los()
	if los and los.has_method("describe_block"):
		var parts := block_key.split(":")
		if parts.size() == 3:
			return "Block (%s,%s) in %s" % [parts[1], parts[2],
				parts[0].capitalize()]
	return block_key

## Returns a localized stage label for HUD overlays.
func stage_label(stage: int) -> String:
	if stage < 0 or stage >= STAGE_LABELS.size():
		return "unknown"
	return STAGE_LABELS[stage]

## Pretty printer for ghost feed entries (used by news ticker).
func format_ghost_feed_entry(entry: Dictionary) -> String:
	return "[%s] %s" % [stage_label(int(entry.get("stage", 0))).to_upper(),
		str(entry.get("msg", ""))]
