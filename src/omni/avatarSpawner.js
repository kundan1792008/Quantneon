const DEFAULT_LANES = Object.freeze([
  { x: -2.5, y: 0, z: -2.5 },
  { x: 2.5, y: 0, z: -2.5 },
  { x: -2.5, y: 0, z: 2.5 },
  { x: 2.5, y: 0, z: 2.5 }
]);

export function createLowLatencySpawner({ lanes = DEFAULT_LANES, now = () => performance.now() } = {}) {
  let laneCursor = 0;
  const activePlayers = new Map();

  function nextLane() {
    const lane = lanes[laneCursor % lanes.length];
    laneCursor += 1;
    return lane;
  }

  return {
    spawnAvatar({ playerId, seedOffset = { x: 0, y: 0, z: 0 } }) {
      if (!playerId) {
        throw new Error('playerId is required');
      }

      const lane = nextLane();
      const spawn = {
        playerId,
        x: lane.x + seedOffset.x,
        y: lane.y + seedOffset.y,
        z: lane.z + seedOffset.z,
        spawnedAt: now()
      };

      activePlayers.set(playerId, spawn);
      return spawn;
    },

    getAvatar(playerId) {
      return activePlayers.get(playerId);
    },

    listActiveAvatars() {
      return Array.from(activePlayers.values());
    }
  };
}
