import test from 'node:test';
import assert from 'node:assert/strict';
import { buildOmniPlatformRoadmap, buildGodotBootstrap } from '../src/omni/godotShell.js';
import { createLowLatencySpawner } from '../src/omni/avatarSpawner.js';
import { createQuantchatDeepLink } from '../src/omni/quantchatDeepLink.js';

test('buildOmniPlatformRoadmap returns Next.js + Capacitor targets', () => {
  const roadmap = buildOmniPlatformRoadmap();
  assert.equal(roadmap.phase, '1-month');
  assert.equal(roadmap.shell.framework, 'nextjs');
  assert.equal(roadmap.targets[1].wrapper, 'capacitor');
});

test('buildGodotBootstrap uses frame-safe defaults', () => {
  const bootstrap = buildGodotBootstrap();
  assert.equal(bootstrap.canvasId, 'quantneon-metaverse-canvas');
  assert.equal(bootstrap.preserveDrawingBuffer, false);
});

test('spawner distributes avatars without collisions and records timestamp', () => {
  const spawner = createLowLatencySpawner({ now: () => 42.5 });
  const a = spawner.spawnAvatar({ playerId: 'alpha' });
  const b = spawner.spawnAvatar({ playerId: 'beta' });

  assert.notDeepEqual({ x: a.x, y: a.y, z: a.z }, { x: b.x, y: b.y, z: b.z });
  assert.equal(a.spawnedAt, 42.5);
  assert.equal(spawner.getAvatar('beta')?.playerId, 'beta');
});

test('silent deep link is generated and dispatched asynchronously', async () => {
  const captured = [];
  const deeplink = createQuantchatDeepLink();
  const url = deeplink.openSilently({
    roomId: 'room-77',
    avatarId: 'avatar-12',
    transport: (deepLinkUrl) => captured.push(deepLinkUrl)
  });

  assert.match(url, /^quantchat:\/\/open\?/);
  assert.equal(captured.length, 0);

  await new Promise((resolve) => setTimeout(resolve, 5));
  assert.equal(captured.length, 1);
  assert.equal(captured[0], url);
});
