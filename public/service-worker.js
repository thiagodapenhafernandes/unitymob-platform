const CACHE = "salute-admin-cache-v2";
const offlineFallbackPage = "/admin";
const fieldFallbackPage = "/field";

self.addEventListener("install", function (event) {
  console.log("[ServiceWorker] Install");
  self.skipWaiting(); // Force activation of new serviceworker

  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      console.log("[ServiceWorker] Caching offline page");
      return cache.addAll([offlineFallbackPage, fieldFallbackPage]);
    })
  );
});

self.addEventListener("activate", function (event) {
  console.log("[ServiceWorker] Activate");
  event.waitUntil(clients.claim()); // Take control of clients immediately
});

self.addEventListener("fetch", function (event) {
  // Only intercept navigation requests (for offline support)
  // Let everything else (images, css, js) go direct to network
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request).catch(function () {
        const fallback = event.request.url.includes("/admin/captacoes") ? fieldFallbackPage : offlineFallbackPage;
        return caches.match(fallback);
      })
    );
  }
});
