// Service worker for /field PWA.
// Scope: /field/  — installed via navigator.serviceWorker.register("/field-service-worker.js", { scope: "/field/" })
//
// Strategy:
//   - Cache shell (network-first, fallback offline page)
//   - Location pings: try network, queue in IndexedDB on failure, retry with Background Sync
//
// NOTE: Keep this file minimal and dependency-free. Bumps cache version when shipping changes.

const CACHE_VERSION = "v2";
const SHELL_CACHE = `field-shell-${CACHE_VERSION}`;
const PING_QUEUE_DB = "field-ping-queue";
const PING_QUEUE_STORE = "pings";

const SHELL_URLS = [
  "/field",
  "/field-icons/icon-192.png",
  "/field-icons/icon-512.png",
  "https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css",
  "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.css"
];

// ---------- Install / Activate ----------
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE).then((cache) =>
      cache.addAll(SHELL_URLS).catch(() => {
        // Don't block install if shell assets aren't ready.
      })
    )
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== SHELL_CACHE).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

// ---------- Fetch ----------
self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);

  // Cachear CDNs que o field usa (Bootstrap, Bootstrap Icons) para
  // funcionarem offline.
  const isTrustedCdn = url.origin === "https://cdn.jsdelivr.net";
  if (isTrustedCdn && request.method === "GET") {
    event.respondWith(
      caches.match(request).then((cached) => {
        if (cached) return cached;
        return fetch(request).then((resp) => {
          if (resp && resp.status === 200) {
            const clone = resp.clone();
            caches.open(SHELL_CACHE).then((c) => c.put(request, clone).catch(() => {}));
          }
          return resp;
        });
      })
    );
    return;
  }

  // Only handle same-origin /field/* requests beyond this point.
  if (url.origin !== self.location.origin) return;
  if (!url.pathname.startsWith("/field")) return;

  // Location ping: try network, queue on failure.
  if (request.method === "POST" && url.pathname === "/field/location_pings") {
    event.respondWith(handlePingPost(request));
    return;
  }

  // Navigation / GET: network-first, cache fallback.
  if (request.method === "GET") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response && response.status === 200) {
            const clone = response.clone();
            caches.open(SHELL_CACHE).then((cache) => cache.put(request, clone).catch(() => {}));
          }
          return response;
        })
        .catch(() => caches.match(request).then((cached) => cached || caches.match("/field")))
    );
  }
});

// ---------- Ping queue (IndexedDB) ----------
function openPingDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(PING_QUEUE_DB, 1);
    req.onupgradeneeded = (e) => {
      e.target.result.createObjectStore(PING_QUEUE_STORE, { keyPath: "id", autoIncrement: true });
    };
    req.onsuccess = (e) => resolve(e.target.result);
    req.onerror = (e) => reject(e.target.error);
  });
}

async function queuePing(body, headers) {
  const db = await openPingDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(PING_QUEUE_STORE, "readwrite");
    tx.objectStore(PING_QUEUE_STORE).add({ body, headers, queued_at: Date.now() });
    tx.oncomplete = resolve;
    tx.onerror = (e) => reject(e.target.error);
  });
}

async function drainPingQueue() {
  const db = await openPingDb();
  const tx = db.transaction(PING_QUEUE_STORE, "readwrite");
  const store = tx.objectStore(PING_QUEUE_STORE);
  const all = await new Promise((resolve) => {
    const req = store.getAll();
    req.onsuccess = () => resolve(req.result || []);
    req.onerror = () => resolve([]);
  });

  for (const entry of all) {
    try {
      const resp = await fetch("/field/location_pings", {
        method: "POST",
        body: entry.body,
        headers: entry.headers,
        credentials: "include"
      });
      if (resp && resp.ok) {
        store.delete(entry.id);
      }
    } catch (_) {
      // Keep in queue, will retry on next sync.
    }
  }
}

async function handlePingPost(request) {
  const clone = request.clone();
  try {
    const response = await fetch(request);
    if (response && response.ok) return response;
    throw new Error("non-ok response");
  } catch (_) {
    // Offline / network error: queue and return synthetic 202 Accepted.
    const body = await clone.text();
    const headers = {};
    clone.headers.forEach((v, k) => { headers[k] = v; });
    try { await queuePing(body, headers); } catch (_) {}
    if (self.registration.sync) {
      try { await self.registration.sync.register("field-ping-queue"); } catch (_) {}
    }
    return new Response(JSON.stringify({ queued: true }), {
      status: 202,
      headers: { "Content-Type": "application/json" }
    });
  }
}

// ---------- Background Sync ----------
self.addEventListener("sync", (event) => {
  if (event.tag === "field-ping-queue") {
    event.waitUntil(drainPingQueue());
  }
});

self.addEventListener("message", (event) => {
  if (event.data && event.data.type === "DRAIN_PING_QUEUE") {
    event.waitUntil(drainPingQueue());
  }
});

// ---------- Push Notifications ----------
self.addEventListener("push", (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) {}
  const title = data.title || "Salute Campo";
  const options = {
    body:  data.body || "Nova atualização",
    icon:  data.icon || "/field-icons/icon-192.png",
    badge: "/field-icons/icon-192.png",
    data:  { url: data.url || "/field" }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = event.notification.data?.url || "/field";
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.includes(target) && "focus" in c) return c.focus();
      }
      if (clients.openWindow) return clients.openWindow(target);
    })
  );
});
