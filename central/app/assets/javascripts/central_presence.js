(() => {
  if (window.centralPresenceBound) return;
  window.centralPresenceBound = true;
  let pending = false;
  async function heartbeat() {
    const marker = document.querySelector('[data-central-presence]');
    if (!marker || document.hidden || pending) return;
    pending = true;
    try {
      await fetch(marker.dataset.centralPresence, {method:'POST', credentials:'same-origin', headers:{'X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content, Accept:'application/json'}});
    } catch (_) { /* Sem confirmação, a presença vence no servidor. */ }
    finally { pending = false; }
  }
  setInterval(heartbeat, 30000);
  document.addEventListener('visibilitychange', heartbeat);
  document.addEventListener('turbo:load', heartbeat);
  heartbeat();
})();
