function scheduleNonBlocking(task) {
  if (typeof requestAnimationFrame === 'function') {
    requestAnimationFrame(task);
    return;
  }

  setTimeout(task, 0);
}

function buildDeepLinkUrl({ baseUrl, source, roomId, avatarId }) {
  const params = new URLSearchParams({
    source,
    room: roomId,
    avatar: avatarId,
    mode: 'silent'
  });

  return `${baseUrl}?${params.toString()}`;
}

export function createQuantchatDeepLink({
  baseUrl = 'quantchat://open',
  source = 'quantneon-metaverse'
} = {}) {
  return {
    openSilently({ roomId, avatarId, transport = (url) => url }) {
      if (!roomId || !avatarId) {
        throw new Error('roomId and avatarId are required');
      }

      const url = buildDeepLinkUrl({ baseUrl, source, roomId, avatarId });

      scheduleNonBlocking(() => {
        transport(url);
      });

      return url;
    }
  };
}
