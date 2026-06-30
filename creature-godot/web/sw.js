// Legacy PWA helper (Godot's index.service.worker.js is the primary SW on production).
// Network-first for game binaries so re-exports load without clearing site data.
const CACHE = 'creature-rts-v4';
const NETWORK_FIRST = new Set([
  'index.html',
  'index.js',
  'index.wasm',
  'index.pck',
]);

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

function isNetworkFirst(url) {
  const name = url.pathname.split('/').pop() || '';
  return NETWORK_FIRST.has(name);
}

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);

  if (isNetworkFirst(url)) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(event.request, copy));
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
