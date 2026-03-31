const WEB_TARGET = Object.freeze({
  platform: 'web',
  renderer: 'webgl2',
  entry: '/godot/game.pck'
});

const MOBILE_TARGET = Object.freeze({
  platform: 'mobile',
  wrapper: 'capacitor',
  renderer: 'webgl2',
  fpsLimit: 60
});

export function buildOmniPlatformRoadmap() {
  return {
    phase: '1-month',
    shell: {
      framework: 'nextjs',
      integration: 'godot-web-export'
    },
    targets: [WEB_TARGET, MOBILE_TARGET]
  };
}

export function buildGodotBootstrap({ canvasId = 'quantneon-metaverse-canvas' } = {}) {
  return {
    canvasId,
    preserveDrawingBuffer: false,
    lowLatencyAudio: true,
    threadSafeCallbacks: true
  };
}
