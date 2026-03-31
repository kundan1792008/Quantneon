function scheduleNonBlocking(task) {
  if (typeof requestAnimationFrame === 'function') {
    requestAnimationFrame(() => setTimeout(task, 0));
    return;
  }

  setTimeout(task, 0);
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

      const url = `${baseUrl}?source=${encodeURIComponent(source)}&room=${encodeURIComponent(roomId)}&avatar=${encodeURIComponent(avatarId)}&mode=silent`;

      scheduleNonBlocking(() => {
        transport(url);
      });

      return url;
    }
  };
}
