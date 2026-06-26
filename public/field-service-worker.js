// Service worker for /field PWA.
// Scope: /field/  — installed via navigator.serviceWorker.register("/field-service-worker.js", { scope: "/field/" })
//
// Strategy:
//   - Cache shell (network-first, fallback offline page)
//   - Location pings: try network, queue in IndexedDB on failure, retry with Background Sync
//
// NOTE: Keep this file minimal and dependency-free. Bumps cache version when shipping changes.

const CACHE_VERSION = "v5";
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
// Logs com prefixo [push] para inspeção via Safari Web Inspector no iPhone:
// se "event received" não aparece, o push nem chegou ao aparelho (entrega Apple);
// se aparece mas "showNotification FAILED", é o iOS bloqueando a exibição.
self.addEventListener("push", (event) => {
  console.log("[push] event received", new Date().toISOString());

  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    console.warn("[push] falha ao ler JSON do payload", e, event.data && event.data.text && event.data.text());
  }
  console.log("[push] payload", data);

  const title = data.title || "Salute Campo";
  const options = {
    body:  data.body || "Nova atualização",
    icon:  data.icon || "/field-icons/icon-192.png",
    badge: "/field-icons/icon-192.png",
    tag: data.tag || undefined,
    renotify: Boolean(data.tag),
    requireInteraction: Boolean(data.require_interaction || data.requireInteraction),
    timestamp: data.timestamp || Date.now(),
    data:  {
      url: data.url || "/field",
      accept_url: data.accept_url || data.acceptUrl,
      tag: data.tag
    }
  };

  event.waitUntil(Promise.all([
    notifyPushReceived(data),
    self.registration.showNotification(title, options)
      .then(() => console.log("[push] showNotification OK"))
      .catch((err) => console.error("[push] showNotification FAILED", err)),
    refreshPushSubscription("push")
  ]));
});

self.addEventListener("pushsubscriptionchange", (event) => {
  console.warn("[push] pushsubscriptionchange — inscrição trocada pelo navegador", event);
  const oldEndpoint = event.oldSubscription && event.oldSubscription.endpoint;
  event.waitUntil(refreshPushSubscription("pushsubscriptionchange", oldEndpoint, event.newSubscription));
});

async function refreshPushSubscription(reason, oldEndpoint, providedSubscription) {
  try {
    const keyResp = await fetch("/field/push_subscriptions/vapid_key", {
      credentials: "include",
      headers: { "Accept": "application/json" }
    });
    if (!keyResp.ok) {
      console.warn("[push] renovação ignorada: VAPID key indisponível", keyResp.status, reason);
      return;
    }

    const data = await keyResp.json();
    const publicKey = data.public_key;
    if (!publicKey) {
      console.warn("[push] renovação ignorada: VAPID public key ausente", reason);
      return;
    }

    let subscription = providedSubscription || await self.registration.pushManager.getSubscription();
    const previousEndpoint = oldEndpoint || (subscription && subscription.endpoint);

    if (subscription && !subscriptionUsesServerKey(subscription, publicKey)) {
      console.warn("[push] subscription usa VAPID antigo; renovando no service worker", reason);
      await subscription.unsubscribe();
      subscription = null;
    }

    if (!subscription) {
      subscription = await self.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey)
      });
    }

    const saveResp = await fetch("/field/push_subscriptions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Field-Service-Worker": "push-renewal"
      },
      credentials: "include",
      body: JSON.stringify({
        subscription: subscription.toJSON(),
        old_endpoint: previousEndpoint,
        reason: reason
      })
    });

    if (saveResp.ok) {
      console.log("[push] subscription renovada/sincronizada", reason);
    } else {
      console.warn("[push] falha ao salvar subscription renovada", saveResp.status, reason);
    }
  } catch (error) {
    console.warn("[push] refreshPushSubscription falhou", reason, error);
  }
}

async function notifyPushReceived(data) {
  try {
    const subscription = await self.registration.pushManager.getSubscription();
    if (!subscription) return;

    await fetch("/field/push_subscriptions/received", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Field-Service-Worker": "push-received"
      },
      credentials: "include",
      body: JSON.stringify({
        endpoint: subscription.endpoint,
        reason: "push",
        tag: data.tag || null
      })
    });
  } catch (error) {
    console.warn("[push] falha ao registrar recebimento no device", error);
  }
}

function subscriptionUsesServerKey(subscription, publicKey) {
  try {
    const currentKey = subscription.options && subscription.options.applicationServerKey;
    if (!currentKey) return true;

    const serverKey = urlBase64ToUint8Array(publicKey);
    const current = new Uint8Array(currentKey);
    if (current.length !== serverKey.length) return false;

    return current.every((value, index) => value === serverKey[index]);
  } catch (error) {
    console.warn("[push] falha ao comparar VAPID da subscription", error);
    return true;
  }
}

function urlBase64ToUint8Array(base64) {
  const padding = "=".repeat((4 - base64.length % 4) % 4);
  const base = (base64 + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base);
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const target = data.url || "/field";
  const acceptUrl = data.acceptUrl || data.accept_url;

  event.waitUntil((async () => {
    // Registra o aceite em background (não bloqueia a abertura do destino).
    // É isso que mantém o sistema no meio sem mostrar tela: o clique abre o
    // WhatsApp direto (target) e o servidor só "ouve" este evento.
    if (acceptUrl) {
      try {
        await fetch(acceptUrl, { method: "GET", credentials: "include", keepalive: true });
      } catch (e) {
        console.warn("[push] beacon de aceite falhou", e);
      }
    }

    // Abre o destino direto (conversa do WhatsApp do lead, ou tela do sistema).
    const list = await clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const c of list) {
      if (c.url.includes(target) && "focus" in c) return c.focus();
    }
    if (clients.openWindow) return clients.openWindow(target);
  })());
});
