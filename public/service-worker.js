const CACHE = "salute-admin-cache-v3";
const offlineFallbackPage = "/offline.html";
const fieldFallbackPage = "/field";

self.addEventListener("install", function (event) {
  console.log("[ServiceWorker] Install");
  self.skipWaiting(); // Force activation of new serviceworker

  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      console.log("[ServiceWorker] Caching offline page");
      return cache.addAll([offlineFallbackPage, fieldFallbackPage]).catch(function () {});
    })
  );
});

self.addEventListener("activate", function (event) {
  console.log("[ServiceWorker] Activate");
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) { return k !== CACHE; }).map(function (k) { return caches.delete(k); }));
    }).then(function () { return clients.claim(); })
  );
});

self.addEventListener("fetch", function (event) {
  // Only intercept navigation requests (for offline support)
  // Let everything else (images, css, js) go direct to network
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request).catch(function () {
        const fallback = event.request.url.includes("/admin/captacoes") ? fieldFallbackPage : offlineFallbackPage;
        return caches.match(fallback).then(function (cached) {
          return cached || caches.match(offlineFallbackPage);
        });
      })
    );
  }
});
