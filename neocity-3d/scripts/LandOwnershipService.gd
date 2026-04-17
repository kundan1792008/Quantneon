## LandOwnershipService.gd
## ---------------------------------------------------------------------------
## Core service backing the Virtual Real Estate Economy (issue #12).
##
## Responsibilities
##   • Block claiming — every cell of the procedural city is addressable by a
##     district name and a (x,z) block coordinate.  Players claim empty blocks
##     for a Quant-token price that scales with district desirability.
##   • Ownership registry — authoritative client-side mirror of the server
##     state received through SocketIOClient.  Also runs an offline / single-
##     player simulation when the server is unreachable so the dopamine loop
##     never stops.
##   • City leaderboard — maintains a weekly "Top Landowners" ranking using
##     a rolling window and resets every Monday 00:00 UTC.
##   • Customization streaks — every in-world day an owner visits and updates
##     their building extends the streak; streaks unlock cosmetic tiers
##     ("glows bronze / silver / gold / holographic") broadcast as signals so
##     the renderer can apply the effect.
##   • Neighborhood drama — detects rival clans building adjacent to a player
##     and surfaces "defend your territory" prompts.
##   • FOMO event zones — time-limited rectangular areas inside the city that
##     double rent, grant extra leaderboard points and despawn on expiry.
##
## The script is an Autoload (registered as `LandOwnershipService` in
## project.godot) and never holds references to visual nodes directly — it
## only emits signals that the real-estate UI, minimap and renderer listen to.
## ---------------------------------------------------------------------------
extends Node

# ── Tunables ────────────────────────────────────────────────────────────────

## Side length of one city block in world units.  Must match city_generator.
@export var block_size: float = 40.0

## Base price for an empty block in Quant tokens (QNT).  Scaled per district.
@export var base_claim_price: int = 1000

## Number of streak days required to unlock each cosmetic tier.
@export var streak_tiers: Array[int] = [3, 7, 12, 30, 90]

## Cosmetic name applied for each tier (index-matched with streak_tiers).
@export var streak_tier_names: Array[String] = [
	"bronze_trim",
	"silver_trim",
	"gold_glow",
	"neon_pulse",
	"holographic",
]

## Window (in seconds) used for the "Top Landowners This Week" leaderboard.
@export var leaderboard_window_sec: int = 60 * 60 * 24 * 7 # 7 days

## Max neighborhood distance (in blocks) used to detect rival clan builds.
@export var rival_detection_radius: int = 2

## Interval between periodic ticks (leaderboard prune, event expiry, streaks).
@export var tick_interval_sec: float = 5.0

## District multipliers applied on top of `base_claim_price`.
@export var district_multipliers: Dictionary = {
	"neotokyo": 3.2,
	"shibuya_sprawl": 2.6,
	"chrome_harbor": 2.0,
	"old_town": 1.4,
	"wastelands": 0.6,
}

# ── State ───────────────────────────────────────────────────────────────────

## {block_key: Dictionary} — authoritative per-block record.
## block_key is the String "district:x:z".  A record looks like:
##   {
##     "district": String,
##     "x": int,
##     "z": int,
##     "owner_id": String or "",      # "" means unowned
##     "owner_name": String,
##     "clan_id": String,
##     "price": int,
##     "claimed_at": int,             # Unix seconds
##     "last_visit": int,              # Unix seconds
##     "streak_days": int,
##     "streak_last_day": int,         # julian day
##     "cosmetic_tier": int,           # index into streak_tier_names
##     "customization": Dictionary,    # free-form: {"roof":"pyramid", ...}
##     "leaderboard_points": int,
##     "in_event_zone": String,        # "" or event id
##     "decay_level": int,             # 0 pristine → 4 ghost
##   }
var blocks: Dictionary = {}

## {owner_id: Array[String]} — index from a player id to every block_key they
## currently own.  Recomputed lazily from `blocks` whenever an owner changes.
var _blocks_by_owner: Dictionary = {}

## {clan_id: Array[String]} — same as `_blocks_by_owner` but keyed by clan.
var _blocks_by_clan: Dictionary = {}

## Ring buffer of leaderboard points gained in the last
## `leaderboard_window_sec` seconds.  Each entry is
## {"owner_id", "owner_name", "points", "ts"}.
var _leaderboard_events: Array = []

## Cached snapshot recomputed on every tick.  Array of
## {"owner_id","owner_name","points","blocks_owned","rank"}.
var _leaderboard_snapshot: Array = []

## {event_id: Dictionary} — active FOMO event zones.  Each event has
## `{id, name, district, min_x, max_x, min_z, max_z, ends_at, rent_mult,
##   points_mult, reward_item}`.
var event_zones: Dictionary = {}

## Id of the local player (pulled from NetworkManager on world enter).
var local_player_id: String = ""
var local_player_clan: String = ""

## Flag — true once we've synced at least once with the server.
var synced_with_server: bool = false

## Tick accumulator.
var _tick_accum: float = 0.0

## Day counter — derived from OS.  We use julian days so a "streak" survives
## local timezone changes.  Updated on every tick.
var _current_julian_day: int = 0

# ── Signals ─────────────────────────────────────────────────────────────────

signal block_registry_updated           # Fired whenever any block record changes.
signal block_claimed(block_key, record) # Successful claim.
signal block_released(block_key, record)
signal claim_rejected(block_key, reason)
signal ownership_changed(block_key, old_owner_id, new_owner_id)
signal leaderboard_updated(snapshot)
signal streak_advanced(block_key, streak_days, tier_index, tier_name)
signal streak_broken(block_key, lost_days)
signal rival_detected(block_key, rival_clan_id, rival_block_key)
signal event_zone_started(event_id, data)
signal event_zone_ending_soon(event_id, seconds_left)
signal event_zone_ended(event_id)
signal customization_changed(block_key, customization)
signal toast(message, severity) # severity ∈ {"info","warn","reward","drama"}

# ── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	_current_julian_day = _julian_day_now()
	var net := get_node_or_null("/root/NetworkManager")
	if net:
		net.connect("world_entered", Callable(self, "_on_world_entered"))
	var socket := get_node_or_null("/root/SocketIOClient")
	if socket:
		socket.on_event("block_registry_sync", Callable(self, "_on_registry_sync"))
		socket.on_event("block_claim_result", Callable(self, "_on_claim_result"))
		socket.on_event("block_updated", Callable(self, "_on_block_updated"))
		socket.on_event("leaderboard_updated", Callable(self, "_on_leaderboard_update"))
		socket.on_event("event_zone_started", Callable(self, "_on_event_started"))
		socket.on_event("event_zone_ended", Callable(self, "_on_event_ended"))
	# If no network, seed with procedural stub blocks so the UI has something
	# to display in offline mode.
	if net == null:
		_seed_offline_world()

func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < tick_interval_sec:
		return
	_tick_accum = 0.0
	_advance_day_if_needed()
	_prune_leaderboard_events()
	_recompute_leaderboard()
	_expire_event_zones()

# ── Network event handlers ──────────────────────────────────────────────────

func _on_world_entered(data) -> void:
	if data.has("player"):
		local_player_id = str(data.player.get("id", ""))
		local_player_clan = str(data.player.get("clanId", ""))
	if data.has("blocks"):
		ingest_block_snapshot(data.blocks)

func _on_registry_sync(payload) -> void:
	if payload is Dictionary and payload.has("blocks"):
		ingest_block_snapshot(payload.blocks)

func _on_claim_result(result) -> void:
	if not (result is Dictionary): return
	var key: String = str(result.get("block_key", ""))
	if result.get("success", false):
		if result.has("block"):
			_store_block(result.block)
		emit_signal("block_claimed", key, blocks.get(key, {}))
		emit_signal("toast", "You own %s now." % _pretty_name(key), "reward")
	else:
		var reason := str(result.get("reason", "unknown"))
		emit_signal("claim_rejected", key, reason)
		emit_signal("toast", "Claim failed: %s" % reason, "warn")

func _on_block_updated(block) -> void:
	if block is Dictionary:
		_store_block(block)
		emit_signal("block_registry_updated")

func _on_leaderboard_update(payload) -> void:
	if payload is Dictionary and payload.has("entries"):
		_leaderboard_snapshot = payload.entries
		emit_signal("leaderboard_updated", _leaderboard_snapshot)

func _on_event_started(data) -> void:
	if data is Dictionary and data.has("id"):
		event_zones[str(data.id)] = data
		_tag_blocks_in_event(data)
		emit_signal("event_zone_started", str(data.id), data)
		emit_signal("toast", "EVENT LIVE: %s" % data.get("name", "???"), "reward")

func _on_event_ended(data) -> void:
	var id := str(data) if typeof(data) != TYPE_DICTIONARY else str(data.get("id", ""))
	if event_zones.has(id):
		_untag_blocks_in_event(event_zones[id])
		event_zones.erase(id)
		emit_signal("event_zone_ended", id)

# ── Snapshot ingestion ──────────────────────────────────────────────────────

## Replace or merge the block database with a batch coming from the server.
func ingest_block_snapshot(batch: Array) -> void:
	for raw in batch:
		if raw is Dictionary:
			_store_block(raw)
	_rebuild_owner_index()
	synced_with_server = true
	emit_signal("block_registry_updated")

func _store_block(raw: Dictionary) -> void:
	var rec := _normalize_block(raw)
	var key := _block_key(rec.district, rec.x, rec.z)
	var previous: Dictionary = blocks.get(key, {})
	blocks[key] = rec
	if previous.is_empty() or previous.get("owner_id", "") != rec.owner_id:
		emit_signal("ownership_changed", key, previous.get("owner_id", ""), rec.owner_id)
		_rebuild_owner_index()
	# Customization may have changed independently.
	if previous.get("customization", {}) != rec.customization:
		emit_signal("customization_changed", key, rec.customization)

func _normalize_block(raw: Dictionary) -> Dictionary:
	return {
		"district": str(raw.get("district", "neotokyo")),
		"x": int(raw.get("x", 0)),
		"z": int(raw.get("z", 0)),
		"owner_id": str(raw.get("owner_id", raw.get("ownerId", ""))),
		"owner_name": str(raw.get("owner_name", raw.get("ownerName", ""))),
		"clan_id": str(raw.get("clan_id", raw.get("clanId", ""))),
		"price": int(raw.get("price", base_claim_price)),
		"claimed_at": int(raw.get("claimed_at", raw.get("claimedAt", 0))),
		"last_visit": int(raw.get("last_visit", raw.get("lastVisit", 0))),
		"streak_days": int(raw.get("streak_days", raw.get("streakDays", 0))),
		"streak_last_day": int(raw.get("streak_last_day", raw.get("streakLastDay", 0))),
		"cosmetic_tier": int(raw.get("cosmetic_tier", raw.get("cosmeticTier", -1))),
		"customization": raw.get("customization", {}),
		"leaderboard_points": int(raw.get("leaderboard_points", raw.get("lbPoints", 0))),
		"in_event_zone": str(raw.get("in_event_zone", raw.get("eventZoneId", ""))),
		"decay_level": int(raw.get("decay_level", raw.get("decayLevel", 0))),
	}

# ── Offline simulation seed ─────────────────────────────────────────────────

func _seed_offline_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var districts: Array = district_multipliers.keys()
	for district in districts:
		for x in range(-4, 5):
			for z in range(-4, 5):
				var rec := {
					"district": district,
					"x": x,
					"z": z,
					"owner_id": "",
					"owner_name": "",
					"clan_id": "",
					"price": price_for_block(district, x, z),
					"claimed_at": 0,
					"last_visit": 0,
					"streak_days": 0,
					"streak_last_day": 0,
					"cosmetic_tier": -1,
					"customization": {},
					"leaderboard_points": 0,
					"in_event_zone": "",
					"decay_level": 0,
				}
				# Assign a handful of NPC owners for realism.
				if rng.randf() < 0.15:
					var npc_id := "npc_%d" % rng.randi_range(100, 999)
					rec.owner_id = npc_id
					rec.owner_name = "Citizen-%s" % npc_id.right(3)
					rec.claimed_at = int(Time.get_unix_time_from_system()) - rng.randi_range(0, 600000)
					rec.last_visit = rec.claimed_at + rng.randi_range(0, 500000)
				blocks[_block_key(district, x, z)] = rec
	_rebuild_owner_index()
	emit_signal("block_registry_updated")

# ── Block key / pricing helpers ─────────────────────────────────────────────

func _block_key(district: String, x: int, z: int) -> String:
	return "%s:%d:%d" % [district, x, z]

func _pretty_name(block_key: String) -> String:
	var parts := block_key.split(":")
	if parts.size() != 3:
		return block_key
	return "Block (%s,%s) in %s" % [parts[1], parts[2], parts[0].capitalize()]

func price_for_block(district: String, x: int, z: int) -> int:
	var mult: float = float(district_multipliers.get(district, 1.0))
	# Center-weighted: blocks closer to origin cost more.
	var centrality := 1.0 + 0.5 * (1.0 / (1.0 + abs(x) + abs(z)))
	return int(round(base_claim_price * mult * centrality))

# ── Public API — claiming ───────────────────────────────────────────────────

## Attempt to claim a block.  Returns true if the local request was valid
## (price check + unowned).  The authoritative answer comes back via
## `block_claimed` / `claim_rejected` once the server responds.
func claim_block(district: String, x: int, z: int, bidder_balance: int,
		bidder_id: String = "", bidder_name: String = "",
		bidder_clan: String = "") -> bool:
	if bidder_id == "":
		bidder_id = local_player_id
		bidder_name = bidder_name if bidder_name != "" else _resolve_local_name()
		bidder_clan = local_player_clan
	var key := _block_key(district, x, z)
	if not blocks.has(key):
		emit_signal("claim_rejected", key, "unknown_block")
		return false
	var rec: Dictionary = blocks[key]
	if rec.owner_id != "":
		emit_signal("claim_rejected", key, "already_owned")
		emit_signal("toast", "That block already belongs to %s." % rec.owner_name, "warn")
		return false
	if bidder_balance < rec.price:
		emit_signal("claim_rejected", key, "insufficient_funds")
		emit_signal("toast", "Not enough QNT to claim %s (need %d)." % [
			_pretty_name(key), rec.price], "warn")
		return false
	# Optimistic local update.  Server will confirm.
	rec.owner_id = bidder_id
	rec.owner_name = bidder_name
	rec.clan_id = bidder_clan
	rec.claimed_at = int(Time.get_unix_time_from_system())
	rec.last_visit = rec.claimed_at
	rec.streak_days = 1
	rec.streak_last_day = _julian_day_now()
	rec.cosmetic_tier = -1
	rec.decay_level = 0
	blocks[key] = rec
	_rebuild_owner_index()
	_award_leaderboard_points(bidder_id, bidder_name, 100 + int(rec.price / 50), "claim")
	_send_to_server("claim_block", {
		"district": district, "x": x, "z": z,
		"bidder_id": bidder_id, "price": rec.price,
	})
	emit_signal("block_claimed", key, rec)
	emit_signal("block_registry_updated")
	emit_signal("toast", "Claimed %s for %d QNT!" % [_pretty_name(key), rec.price], "reward")
	_check_neighborhood_rivalry(key)
	return true

## Release a block the caller owns (sells it back to the city for 40% value).
func release_block(district: String, x: int, z: int, seller_id: String = "") -> bool:
	if seller_id == "":
		seller_id = local_player_id
	var key := _block_key(district, x, z)
	if not blocks.has(key):
		return false
	var rec: Dictionary = blocks[key]
	if rec.owner_id != seller_id:
		emit_signal("claim_rejected", key, "not_owner")
		return false
	var refund := int(rec.price * 0.4)
	rec.owner_id = ""
	rec.owner_name = ""
	rec.clan_id = ""
	rec.streak_days = 0
	rec.cosmetic_tier = -1
	rec.customization = {}
	rec.decay_level = 0
	blocks[key] = rec
	_rebuild_owner_index()
	_send_to_server("release_block", {"district": district, "x": x, "z": z, "refund": refund})
	emit_signal("block_released", key, rec)
	emit_signal("toast", "Released %s for %d QNT refund." % [_pretty_name(key), refund], "info")
	return true

## Transfer ownership (gifting / trades).  Used by inventory-trade flows.
func transfer_block(block_key: String, new_owner_id: String, new_owner_name: String,
		new_clan: String = "") -> bool:
	if not blocks.has(block_key):
		return false
	var rec: Dictionary = blocks[block_key]
	var old := rec.owner_id
	rec.owner_id = new_owner_id
	rec.owner_name = new_owner_name
	rec.clan_id = new_clan
	rec.streak_days = 0
	rec.cosmetic_tier = -1
	blocks[block_key] = rec
	_rebuild_owner_index()
	emit_signal("ownership_changed", block_key, old, new_owner_id)
	emit_signal("block_registry_updated")
	_send_to_server("transfer_block", {"block_key": block_key, "new_owner": new_owner_id})
	return true

# ── Public API — customization & streaks ────────────────────────────────────

## Apply a customization delta ("roof","walls","sign_text","color" etc.) to a
## block you own.  If at least one field changes today the streak is extended.
func apply_customization(block_key: String, changes: Dictionary,
		player_id: String = "") -> bool:
	if player_id == "":
		player_id = local_player_id
	if not blocks.has(block_key):
		return false
	var rec: Dictionary = blocks[block_key]
	if rec.owner_id != player_id:
		emit_signal("toast", "You don't own that block.", "warn")
		return false
	var changed := false
	var custom: Dictionary = rec.customization.duplicate(true)
	for k in changes.keys():
		if custom.get(k, null) != changes[k]:
			custom[k] = changes[k]
			changed = true
	rec.customization = custom
	rec.last_visit = int(Time.get_unix_time_from_system())
	blocks[block_key] = rec
	emit_signal("customization_changed", block_key, custom)
	if changed:
		_bump_streak(block_key)
	_send_to_server("customize_block", {"block_key": block_key, "changes": changes})
	return changed

## Mark that the player physically visited the block today.  This also
## counts toward the streak even without customization changes IF the
## player also spent >=60 real seconds on it.  The caller (player_controller
## or a trigger volume) passes the dwell time.
func register_visit(block_key: String, dwell_sec: int, player_id: String = "") -> void:
	if player_id == "":
		player_id = local_player_id
	if not blocks.has(block_key):
		return
	var rec: Dictionary = blocks[block_key]
	if rec.owner_id != player_id:
		return
	rec.last_visit = int(Time.get_unix_time_from_system())
	blocks[block_key] = rec
	if dwell_sec >= 60:
		_bump_streak(block_key)

func _bump_streak(block_key: String) -> void:
	var rec: Dictionary = blocks[block_key]
	var today := _julian_day_now()
	if rec.streak_last_day == today:
		return  # already counted today
	if rec.streak_last_day > 0 and today - rec.streak_last_day > 1:
		var lost: int = rec.streak_days
		rec.streak_days = 1
		rec.streak_last_day = today
		rec.cosmetic_tier = -1
		blocks[block_key] = rec
		emit_signal("streak_broken", block_key, lost)
		emit_signal("toast", "Your %d-day streak on %s was broken!" % [
			lost, _pretty_name(block_key)], "warn")
		return
	rec.streak_days += 1
	rec.streak_last_day = today
	var new_tier := _tier_for_streak(rec.streak_days)
	var tier_changed := new_tier != rec.cosmetic_tier
	rec.cosmetic_tier = new_tier
	blocks[block_key] = rec
	_award_leaderboard_points(rec.owner_id, rec.owner_name, 10 + rec.streak_days, "streak")
	emit_signal("streak_advanced", block_key, rec.streak_days, new_tier, _tier_name(new_tier))
	if tier_changed and new_tier >= 0:
		emit_signal("toast", "Your building on %s now glows %s!" % [
			_pretty_name(block_key), _tier_name(new_tier)], "reward")

func _tier_for_streak(days: int) -> int:
	var tier := -1
	for i in range(streak_tiers.size()):
		if days >= streak_tiers[i]:
			tier = i
	return tier

func _tier_name(tier_index: int) -> String:
	if tier_index < 0 or tier_index >= streak_tier_names.size():
		return "none"
	return streak_tier_names[tier_index]

# ── Public API — leaderboard ────────────────────────────────────────────────

func get_leaderboard(top_n: int = 10) -> Array:
	if _leaderboard_snapshot.is_empty():
		_recompute_leaderboard()
	if top_n >= _leaderboard_snapshot.size():
		return _leaderboard_snapshot.duplicate()
	return _leaderboard_snapshot.slice(0, top_n)

func get_local_rank() -> int:
	if local_player_id == "":
		return -1
	for entry in _leaderboard_snapshot:
		if entry.owner_id == local_player_id:
			return int(entry.rank)
	return -1

func _award_leaderboard_points(owner_id: String, owner_name: String,
		points: int, reason: String) -> void:
	if owner_id == "" or points <= 0:
		return
	# FOMO event multiplier — if the triggering block is inside an event zone
	# we can't know here, so the caller should pre-multiply.  We still apply
	# a global soft multiplier if ANY event is active.
	var mult := 1.0
	for ev in event_zones.values():
		mult = max(mult, float(ev.get("points_mult", 1.0)))
	var final := int(points * mult)
	_leaderboard_events.append({
		"owner_id": owner_id,
		"owner_name": owner_name,
		"points": final,
		"ts": int(Time.get_unix_time_from_system()),
		"reason": reason,
	})

func _prune_leaderboard_events() -> void:
	var cutoff: int = int(Time.get_unix_time_from_system()) - leaderboard_window_sec
	var keep: Array = []
	for e in _leaderboard_events:
		if int(e.ts) >= cutoff:
			keep.append(e)
	_leaderboard_events = keep

func _recompute_leaderboard() -> void:
	var by_owner: Dictionary = {}
	for e in _leaderboard_events:
		var id: String = e.owner_id
		if not by_owner.has(id):
			by_owner[id] = {"owner_id": id, "owner_name": e.owner_name, "points": 0}
		by_owner[id].points += int(e.points)
	# Add a passive +1 per owned block so just-holding property ranks.
	for owner_id in _blocks_by_owner.keys():
		if not by_owner.has(owner_id):
			var any_block_key: String = _blocks_by_owner[owner_id][0]
			by_owner[owner_id] = {
				"owner_id": owner_id,
				"owner_name": blocks[any_block_key].owner_name,
				"points": 0,
			}
		by_owner[owner_id].points += _blocks_by_owner[owner_id].size()
		by_owner[owner_id]["blocks_owned"] = _blocks_by_owner[owner_id].size()
	var arr: Array = by_owner.values()
	arr.sort_custom(func(a, b): return int(a.points) > int(b.points))
	for i in range(arr.size()):
		arr[i]["rank"] = i + 1
		if not arr[i].has("blocks_owned"):
			arr[i]["blocks_owned"] = _blocks_by_owner.get(arr[i].owner_id, []).size()
	_leaderboard_snapshot = arr
	emit_signal("leaderboard_updated", _leaderboard_snapshot)

# ── Public API — neighborhood competition ───────────────────────────────────

## Returns every block within `rival_detection_radius` of the given key.
func neighbors_of(block_key: String) -> Array:
	var parts := block_key.split(":")
	if parts.size() != 3: return []
	var district: String = parts[0]
	var x: int = int(parts[1])
	var z: int = int(parts[2])
	var out: Array = []
	for dx in range(-rival_detection_radius, rival_detection_radius + 1):
		for dz in range(-rival_detection_radius, rival_detection_radius + 1):
			if dx == 0 and dz == 0:
				continue
			var k := _block_key(district, x + dx, z + dz)
			if blocks.has(k):
				out.append(k)
	return out

func _check_neighborhood_rivalry(block_key: String) -> void:
	var rec: Dictionary = blocks.get(block_key, {})
	if rec.is_empty() or rec.clan_id == "":
		return
	for nk in neighbors_of(block_key):
		var nb: Dictionary = blocks[nk]
		if nb.owner_id == "" or nb.owner_id == rec.owner_id:
			continue
		if nb.clan_id != "" and nb.clan_id != rec.clan_id:
			emit_signal("rival_detected", block_key, nb.clan_id, nk)
			emit_signal("toast",
				"Rival clan %s is building next to your block at %s — defend your territory!" % [
					nb.clan_id, _pretty_name(block_key)], "drama")
			_award_leaderboard_points(rec.owner_id, rec.owner_name, 5, "rival_defend")

## Returns a summary of neighborhood heat for minimap overlays.  Each entry
## is {block_key, clan_id, owner_id, hostile:bool}.
func neighborhood_heatmap_for(owner_id: String) -> Array:
	var out: Array = []
	if not _blocks_by_owner.has(owner_id):
		return out
	for bk in _blocks_by_owner[owner_id]:
		for nk in neighbors_of(bk):
			var nb: Dictionary = blocks[nk]
			if nb.owner_id == "" or nb.owner_id == owner_id:
				continue
			out.append({
				"block_key": nk,
				"clan_id": nb.clan_id,
				"owner_id": nb.owner_id,
				"hostile": nb.clan_id != "" and nb.clan_id != local_player_clan,
			})
	return out

# ── Public API — FOMO event zones ───────────────────────────────────────────

## Start a time-limited event zone.  Typically called by the server, but the
## single-player sim can use it too.  `duration_sec` defaults to 48 h.
func start_event_zone(id: String, name: String, district: String,
		min_x: int, max_x: int, min_z: int, max_z: int,
		duration_sec: int = 48 * 3600, rent_mult: float = 2.0,
		points_mult: float = 2.0, reward_item: String = "") -> Dictionary:
	var data := {
		"id": id,
		"name": name,
		"district": district,
		"min_x": min_x, "max_x": max_x,
		"min_z": min_z, "max_z": max_z,
		"ends_at": int(Time.get_unix_time_from_system()) + duration_sec,
		"rent_mult": rent_mult,
		"points_mult": points_mult,
		"reward_item": reward_item,
	}
	event_zones[id] = data
	_tag_blocks_in_event(data)
	emit_signal("event_zone_started", id, data)
	emit_signal("toast", "EVENT LIVE: %s — %d h only!" % [name, duration_sec / 3600], "reward")
	return data

func end_event_zone(id: String) -> void:
	if not event_zones.has(id): return
	_untag_blocks_in_event(event_zones[id])
	event_zones.erase(id)
	emit_signal("event_zone_ended", id)

func _tag_blocks_in_event(data: Dictionary) -> void:
	for x in range(int(data.min_x), int(data.max_x) + 1):
		for z in range(int(data.min_z), int(data.max_z) + 1):
			var key := _block_key(str(data.district), x, z)
			if blocks.has(key):
				blocks[key].in_event_zone = str(data.id)

func _untag_blocks_in_event(data: Dictionary) -> void:
	for x in range(int(data.min_x), int(data.max_x) + 1):
		for z in range(int(data.min_z), int(data.max_z) + 1):
			var key := _block_key(str(data.district), x, z)
			if blocks.has(key) and blocks[key].in_event_zone == str(data.id):
				blocks[key].in_event_zone = ""

func _expire_event_zones() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var to_end: Array = []
	for id in event_zones.keys():
		var ev: Dictionary = event_zones[id]
		var left: int = int(ev.ends_at) - now
		if left <= 0:
			to_end.append(id)
		elif left <= 3600 and left > 3595:
			emit_signal("event_zone_ending_soon", id, left)
			emit_signal("toast", "%s ends in 1 hour — last chance!" % ev.name, "drama")
		elif left <= 600 and left > 595:
			emit_signal("event_zone_ending_soon", id, left)
			emit_signal("toast", "%s ends in 10 minutes — FINAL CALL!" % ev.name, "drama")
	for id in to_end:
		end_event_zone(id)

func is_block_in_event_zone(block_key: String) -> bool:
	if not blocks.has(block_key): return false
	return blocks[block_key].in_event_zone != ""

func event_multipliers_for(block_key: String) -> Dictionary:
	var default := {"rent_mult": 1.0, "points_mult": 1.0}
	if not blocks.has(block_key): return default
	var ev_id: String = blocks[block_key].in_event_zone
	if ev_id == "" or not event_zones.has(ev_id): return default
	var ev: Dictionary = event_zones[ev_id]
	return {"rent_mult": float(ev.rent_mult), "points_mult": float(ev.points_mult)}

# ── Public API — lookups ────────────────────────────────────────────────────

func get_block(block_key: String) -> Dictionary:
	return blocks.get(block_key, {}).duplicate(true)

func blocks_owned_by(owner_id: String) -> Array:
	return _blocks_by_owner.get(owner_id, []).duplicate()

func blocks_of_clan(clan_id: String) -> Array:
	return _blocks_by_clan.get(clan_id, []).duplicate()

func owner_of(block_key: String) -> String:
	return str(blocks.get(block_key, {}).get("owner_id", ""))

func block_key_from_world(pos: Vector3, district: String) -> String:
	var x := int(floor(pos.x / block_size))
	var z := int(floor(pos.z / block_size))
	return _block_key(district, x, z)

func world_center_of(block_key: String) -> Vector3:
	var parts := block_key.split(":")
	if parts.size() != 3:
		return Vector3.ZERO
	var x := int(parts[1])
	var z := int(parts[2])
	return Vector3(
		(x + 0.5) * block_size,
		0.0,
		(z + 0.5) * block_size)

func describe_block(block_key: String) -> String:
	if not blocks.has(block_key): return "Unknown block"
	var rec: Dictionary = blocks[block_key]
	if rec.owner_id == "":
		return "%s — unowned (%d QNT)" % [_pretty_name(block_key), rec.price]
	var desc := "%s — owned by %s" % [_pretty_name(block_key), rec.owner_name]
	if rec.streak_days > 1:
		desc += " — %d-day streak (%s)" % [rec.streak_days, _tier_name(rec.cosmetic_tier)]
	if rec.in_event_zone != "":
		desc += " — EVENT: %s" % rec.in_event_zone
	if rec.decay_level > 0:
		desc += " — decaying (%d)" % rec.decay_level
	return desc

# ── Helpers ─────────────────────────────────────────────────────────────────

func _rebuild_owner_index() -> void:
	_blocks_by_owner.clear()
	_blocks_by_clan.clear()
	for key in blocks.keys():
		var rec: Dictionary = blocks[key]
		if rec.owner_id == "":
			continue
		if not _blocks_by_owner.has(rec.owner_id):
			_blocks_by_owner[rec.owner_id] = []
		_blocks_by_owner[rec.owner_id].append(key)
		if rec.clan_id != "":
			if not _blocks_by_clan.has(rec.clan_id):
				_blocks_by_clan[rec.clan_id] = []
			_blocks_by_clan[rec.clan_id].append(key)

func _resolve_local_name() -> String:
	var net := get_node_or_null("/root/NetworkManager")
	if net and net.has_method("get_local_player_name"):
		return net.get_local_player_name()
	return "You"

func _send_to_server(event_name: String, payload: Dictionary) -> void:
	var socket := get_node_or_null("/root/SocketIOClient")
	if socket and socket.has_method("send_event"):
		socket.send_event(event_name, payload)

func _julian_day_now() -> int:
	# Days since 1970-01-01 UTC — sufficient for streak tracking.
	return int(Time.get_unix_time_from_system() / 86400)

func _advance_day_if_needed() -> void:
	var today := _julian_day_now()
	if today == _current_julian_day:
		return
	# On day rollover, break streaks that missed yesterday.
	_current_julian_day = today
	for key in blocks.keys():
		var rec: Dictionary = blocks[key]
		if rec.owner_id == "" or rec.streak_last_day == 0:
			continue
		if today - rec.streak_last_day > 1:
			var lost: int = rec.streak_days
			rec.streak_days = 0
			rec.cosmetic_tier = -1
			blocks[key] = rec
			if lost > 0:
				emit_signal("streak_broken", key, lost)
