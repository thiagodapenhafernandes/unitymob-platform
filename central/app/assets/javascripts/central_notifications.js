(() => {
  if (window.centralNotificationsBound) return;
  window.centralNotificationsBound = true;
  let fetching = false;
  async function refresh() {
    const bell = document.querySelector('[data-central-notifications]');
    if (!bell || document.hidden || fetching) return;
    fetching = true;
    try {
      const response = await fetch(bell.dataset.centralNotifications, {headers:{Accept:'application/json'}});
      if (!response.ok) throw new Error('notifications');
      const result = await response.json();
      if (!bell.isConnected) return;
      const badge = bell.querySelector('[data-notification-count]');
      badge.textContent = result.count > 99 ? '99+' : result.count;
      badge.hidden = result.count === 0;
      bell.querySelector('summary').setAttribute('aria-label', `Avisos: ${result.count} chamados com novidades`);
      const list = bell.querySelector('[data-notification-list]');
      list.replaceChildren();
      result.items.forEach(item => {
        const link = document.createElement('a'); link.href = item.url;
        link.dataset.notificationMessage = item.message_id;
        const title = document.createElement('strong'); title.textContent = item.title;
        const detail = document.createElement('span'); detail.textContent = `${item.kind} · ${item.account}`;
        link.append(title, detail); list.append(link);
      });
      bell.querySelector('[data-notification-status]').textContent = result.count ? (result.count > 30 ? '30 novidades mais recentes. Abra os chamados para ver as demais.' : 'Clique para abrir o atendimento.') : 'Nenhuma novidade por aqui.';
    } catch (_) {
      if (bell.isConnected) bell.querySelector('[data-notification-status]').textContent = 'Não foi possível atualizar os avisos. Tentaremos novamente.';
    } finally { fetching = false; }
  }
  document.addEventListener('click', async event => {
    const link = event.target.closest('[data-notification-message]');
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
    event.preventDefault();
    try {
      await fetch(link.closest('[data-central-notifications]').dataset.centralNotifications, {method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify({message_id:link.dataset.notificationMessage})});
    } finally { window.Turbo ? Turbo.visit(link.href) : location.assign(link.href); }
  });
  document.addEventListener('keydown', event => { if(event.key === 'Escape') document.querySelector('[data-central-notifications]')?.removeAttribute('open'); });
  document.addEventListener('turbo:load', refresh);
  document.addEventListener('visibilitychange', refresh);
  setInterval(refresh,15000);
  refresh();
})();
