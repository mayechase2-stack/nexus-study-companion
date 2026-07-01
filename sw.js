// NEXUS service worker — v16.5
// Network-FIRST: online users always get the freshest files (no stale-cache
// surprises), and a cached copy is kept only as an offline fallback.
const CACHE = 'nexus-v19.2';

self.addEventListener('install', function (e) {
    self.skipWaiting();
});

self.addEventListener('activate', function (e) {
    e.waitUntil(
        caches.keys().then(function (keys) {
            return Promise.all(keys.filter(function (k) { return k !== CACHE; })
                                   .map(function (k) { return caches.delete(k); }));
        }).then(function () { return self.clients.claim(); })
    );
});

self.addEventListener('fetch', function (e) {
    var req = e.request;
    if (req.method !== 'GET') return;
    e.respondWith(
        fetch(req).then(function (res) {
            // Stash a fresh copy of successful same-origin responses for offline use.
            if (res && res.status === 200 && req.url.indexOf(self.location.origin) === 0) {
                var copy = res.clone();
                caches.open(CACHE).then(function (c) { c.put(req, copy); }).catch(function () {});
            }
            return res;
        }).catch(function () {
            return caches.match(req);   // offline → serve cached copy if we have one
        })
    );
});
