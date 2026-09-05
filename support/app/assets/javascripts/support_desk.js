//= require support_labels
//= require support_image_engine
//= require support_image_editor
(() => {
  if (window.supportDeskBound) return;
  window.supportDeskBound = true;
  let moreObserver;
  function setup() {
    observeMore();
    const total = document.querySelector('[data-support-queue-total]');
    if (total && document.querySelector('[data-support-total]')) document.querySelector('[data-support-total]').textContent = total.dataset.supportQueueTotal;
    const thread = document.querySelector('[data-support-tabs]');
    if (thread) activateTab(thread, thread.closest('turbo-frame')?.dataset.activeTab || 'conversation');
    const inbox = document.querySelector('[data-support-inbox]');
    if (inbox?.dataset.selectedTicket) inbox.querySelectorAll('[data-support-ticket-link]').forEach(link => { if (link.dataset.supportTicketLink === inbox.dataset.selectedTicket) link.setAttribute('aria-current', 'true'); });
    document.querySelectorAll("form[data-support-draft]").forEach(form => {
      if (form.dataset.bound) return;
      form.dataset.bound = "true";
      const key = "unitymob-support:" + form.dataset.supportDraft;
      const fields = [...form.querySelectorAll("textarea,input[type=text],select")];
      try {
        const saved = JSON.parse(sessionStorage.getItem(key) || "null");
        if (saved && Date.now() - saved.time < 86400000) fields.forEach(field => { if (!field.value && saved.values[field.name]) field.value = saved.values[field.name]; });
      } catch (_) { /* Armazenamento restrito não impede envio. */ }
      form.addEventListener("input", () => {
        form.dataset.dirty = "true";
        try { sessionStorage.setItem(key, JSON.stringify({time: Date.now(), values: Object.fromEntries(fields.map(field => [field.name, field.value]))})); } catch (_) {}
      });
      form.addEventListener("turbo:submit-end", event => {
        if (event.detail.success) { try { sessionStorage.removeItem(key); } catch (_) {} }
      });
    });
    document.querySelectorAll('[data-support-choice]').forEach(group => {
      const select = group.querySelector('select');
      const detail = group.querySelector('textarea');
      const sync = () => { detail.parentElement.hidden = select.value !== 'other'; detail.required = select.value === 'other'; };
      if (!select.dataset.choiceBound) { select.dataset.choiceBound = 'true'; select.addEventListener('change', sync); }
      sync();
    });
    document.querySelectorAll("form[data-support-handoff]").forEach(form => {
      if (!form.dataset.sent) { form.dataset.sent = "true"; form.requestSubmit(); }
    });
  }
  function activateTab(thread, key) {
    thread.querySelectorAll('[data-support-tab]').forEach(button => button.setAttribute('aria-selected', String(button.dataset.supportTab === key)));
    thread.querySelectorAll('[data-support-tab-panel]').forEach(panel => panel.hidden = panel.dataset.supportTabPanel !== key);
    if (thread.closest('turbo-frame')) thread.closest('turbo-frame').dataset.activeTab = key;
  }
  async function loadRecipients(form) {
    const account = form.querySelector('[data-outreach-account]').value;
    const users = form.querySelector('[data-outreach-user]');
    const status = form.querySelector('[data-outreach-status]');
    users.replaceChildren();
    const token = String(Date.now()); form.dataset.lookup = token;
    if (!account) { status.textContent = 'Selecione a conta.'; return; }
    status.textContent = 'Buscando usuários…';
    try {
      const url = new URL(form.dataset.supportOutreach, location.href);
      url.searchParams.set('account_id', account); url.searchParams.set('q', form.querySelector('[data-outreach-search]').value);
      const response = await fetch(url, {headers:{Accept:'application/json'}, credentials:'same-origin'});
      if (!response.ok) throw new Error('lookup');
      const result = await response.json(); if (form.dataset.lookup !== token) return;
      users.add(new Option('Selecione o usuário', ''));
      result.users.forEach(user => users.add(new Option(`${user.name} · ${user.email}`, user.id)));
      status.textContent = result.users.length ? 'Selecione o destinatário. Até 30 resultados; refine a busca se necessário.' : 'Nenhum usuário ativo encontrado.';
    } catch (_) { if (form.dataset.lookup === token) status.textContent = 'A conta não respondeu. Tente novamente.'; }
  }
  document.addEventListener('change', event => {
    if (event.target.matches('[data-outreach-account]')) loadRecipients(event.target.form);
    if (event.target.matches('[data-support-assign]')) { event.target.closest('[data-support-inbox]')?.setAttribute('data-conversation-open',''); event.target.form.requestSubmit(); }
  });
  document.addEventListener('turbo:submit-start', event => {
    const form = event.target;
    if (form.matches('[data-support-filter-form]')) {
      const url = new URL(form.action); new FormData(form).forEach((value,key) => url.searchParams.set(key,value));
      const queue = document.querySelector('[data-support-queue]'); if (queue) queue.dataset.supportQueue = url.href;
    }
  });
  document.addEventListener('keydown', event => {
    if (!event.target.matches('[data-support-tab]') || !['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
    const tabs = [...event.target.closest('[role=tablist]').querySelectorAll('[data-support-tab]')];
    const index = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length-1 : (tabs.indexOf(event.target)+(event.key === 'ArrowRight' ? 1 : -1)+tabs.length)%tabs.length;
    event.preventDefault(); tabs[index].click(); tabs[index].focus();
  });
  let polling = false;
  async function poll() {
    if (document.hidden || polling) return;
    const panel = document.querySelector("[data-support-poll]");
    const reminder = document.querySelector("[data-support-reminder]");
    if (!panel && !reminder) return;
    polling = true;
    try {
      if (panel) {
        const response = await fetch(panel.dataset.supportPoll, {headers: {Accept: "application/json"}, credentials: "same-origin"});
        if (response.ok) {
          const result = await response.json();
          const editing = document.querySelector("form[data-dirty=true]") || [...document.querySelectorAll("input[type=file]")].some(input => input.files.length) || /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
          if (panel.isConnected && result.version !== panel.dataset.supportVersion && window.Turbo) {
            const frame = panel.closest('turbo-frame#support_conversation');
            const playing = [...panel.querySelectorAll('audio')].some(audio => !audio.paused);
            if (frame && !playing) {
              if (!editing) { frame.src ? frame.reload() : frame.src = panel.dataset.supportUrl; }
              else {
                const html = await fetch(panel.dataset.supportUrl, {headers: {'Turbo-Frame': 'support_conversation'}, credentials: 'same-origin'});
                if (html.ok && panel.isConnected) {
                  const incoming = new DOMParser().parseFromString(await html.text(), 'text/html').querySelector('.ax-conversation');
                  const feed = panel.querySelector('.ax-conversation');
                  if (incoming && !feed.querySelector('form[data-dirty=true]') && !feed.contains(document.activeElement)) feed.replaceWith(incoming);
                }
              }
            } else if (!frame && !editing && !playing) window.Turbo.visit(location.href, {action: "replace"});
          }
        }
      }
      if (reminder) {
        const response = await fetch(reminder.dataset.supportNotification, {headers: {Accept: "application/json"}, credentials: "same-origin"});
        if (response.ok && reminder.isConnected) {
          const result = await response.json();
          document.querySelectorAll("[data-support-unread-count]").forEach(badge => {
            const count = Number(result.count) || 0;
            badge.hidden = count === 0;
            badge.textContent = count > 99 ? "99+" : String(count);
            badge.setAttribute("aria-label", `${count} chamados com resposta não lida`);
          });
          const urgent = result.count > 0 || result.awaiting_count > 0;
          reminder.dataset.state = result.state || "";
          reminder.dataset.snooze = urgent ? "30" : "240";
          let dismissed = false;
          try {
            const saved = JSON.parse(sessionStorage.getItem("support-reminder:" + reminder.dataset.supportScope) || "null");
            dismissed = saved && saved.state === result.state && Date.now() - saved.time < Number(reminder.dataset.snooze) * 60000;
          } catch (_) {}
          reminder.hidden = !result.state || dismissed || String(result.ticket_id) === reminder.dataset.supportCurrentTicket;
          reminder.querySelector("[data-support-reminder-title]").textContent = result.resolved ? "Seu chamado foi finalizado" : urgent ? "O suporte respondeu ao seu chamado" : "Seu chamado está em atendimento";
          reminder.querySelector("[data-support-reminder-body]").textContent = result.resolved ? "Confira a conclusão do atendimento e o histórico da conversa." : urgent ? "Abra o chamado para conferir a resposta e continuar o atendimento." : "Você pode continuar trabalhando. Avisaremos quando houver uma resposta.";
          const link = reminder.querySelector("[data-support-reminder-link]");
          link.href = result.url;
          link.textContent = urgent ? "Ver resposta" : "Acompanhar chamado";
        }
      }
    } catch (_) { /* A próxima consulta recupera indisponibilidades transitórias. */ }
    finally { polling = false; }
  }
  function observeMore() {
    moreObserver?.disconnect();
    const queue = document.querySelector('[data-support-queue]');
    const link = queue?.querySelector('[data-support-more-link]');
    if (!link || !window.IntersectionObserver) return;
    moreObserver = new IntersectionObserver(entries => { if (entries.some(entry => entry.isIntersecting)) loadMore(link); }, {root:queue, rootMargin:'120px'});
    moreObserver.observe(link);
  }
  async function loadMore(link) {
    const queue = link.closest('[data-support-queue]');
    if (!queue || queue.dataset.loadingMore || queue.hasAttribute('busy')) return;
    const source = queue.dataset.supportQueue;
    queue.dataset.loadingMore = 'true'; link.textContent = 'Carregando…';
    moreObserver?.disconnect();
    let loaded = false;
    try {
      const response = await fetch(link.href, {headers:{'Turbo-Frame':'support_queue'}, credentials:'same-origin'});
      if (!response.ok) throw new Error('page');
      const documentPage = new DOMParser().parseFromString(await response.text(),'text/html');
      const incoming = documentPage.querySelector('#support_queue');
      if (!incoming) throw new Error('frame');
      if (!queue.isConnected || queue.dataset.supportQueue !== source || !link.isConnected) return;
      const ids = new Set([...queue.querySelectorAll('[data-support-ticket-link]')].map(item => item.dataset.supportTicketLink));
      incoming.querySelectorAll('.ax-support-ticket-card').forEach(card => {
        if (!ids.has(card.querySelector('[data-support-ticket-link]').dataset.supportTicketLink)) queue.insertBefore(card, link.closest('[data-support-more]'));
      });
      link.closest('[data-support-more]').replaceWith(incoming.querySelector('[data-support-more]'));
      queue.dataset.expanded = 'true'; loaded = true;
    } catch (_) { if (link.isConnected) link.textContent = 'Não foi possível carregar. Tentar novamente'; }
    finally { delete queue.dataset.loadingMore; if (loaded) setup(); }
  }
  function refreshQueue() {
    const queue = document.querySelector('[data-support-queue]');
    if (!queue || queue.dataset.loadingMore || queue.dataset.expanded || queue.scrollTop > 20 || document.hidden || (queue.contains(document.activeElement) && /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) || queue.hasAttribute('busy') || queue.querySelector('form[data-dirty=true]')) return;
    if (queue.src === new URL(queue.dataset.supportQueue, location.href).href) queue.reload(); else queue.src = queue.dataset.supportQueue;
  }
  setInterval(poll, 15000);
  setInterval(refreshQueue, 15000);
  document.addEventListener('turbo:submit-end', event => { if (event.detail.success) delete event.target.dataset.dirty; if (event.detail.success && event.target.closest('#support_conversation')) refreshQueue(); });
  document.addEventListener("click", async event => {
    const more = event.target.closest("[data-support-more-link]");
    if (more) { event.preventDefault(); loadMore(more); return; }
    const tab = event.target.closest('[data-support-tab]');
    if (tab) activateTab(tab.closest('[data-support-tabs]'), tab.dataset.supportTab);
    const filter = event.target.closest('[data-support-filter]');
    if (filter) {
      const form = filter.closest('form'); const field = form.elements[filter.dataset.supportFilter];
      field.value = filter.dataset.toggle && field.value === filter.dataset.value ? '' : filter.dataset.value;
      form.querySelectorAll(`[data-support-filter="${filter.dataset.supportFilter}"]`).forEach(button => button.setAttribute('aria-pressed', String(button.dataset.value === field.value)));
      const chips = [...form.querySelectorAll('[data-support-filter]')];
      chips.forEach(button => button.disabled = true);
      try {
        const preferences = Object.fromEntries(['status','origin','mine','order'].map(key => [key, form.elements[key].value]));
        const response = await fetch(form.dataset.supportPreferencesUrl, {method:'PATCH', headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify({preferences})});
        if (!response.ok) throw new Error('preferences');
      } catch (_) { alert('O filtro será aplicado, mas não foi possível salvar sua preferência. Tente novamente.'); }
      finally { chips.forEach(button => button.disabled = false); }
      if(form.isConnected) form.requestSubmit();
    }
    const lookup = event.target.closest('[data-outreach-search-button]'); if (lookup) loadRecipients(lookup.form);
    const format = event.target.closest('[data-support-format]');
    if (format) {
      const input = format.closest('.ax-support-editor').querySelector('textarea');
      const selected = input.value.slice(input.selectionStart,input.selectionEnd) || 'texto';
      const marker = format.dataset.supportFormat === 'bold' ? '**' : '*';
      const replacement = format.dataset.supportFormat === 'list' ? selected.split('\n').map(line => '- '+line).join('\n') : marker+selected+marker;
      input.setRangeText(replacement,input.selectionStart,input.selectionEnd,'select'); input.dispatchEvent(new Event('input',{bubbles:true})); input.focus();
    }
    const ticketLink = event.target.closest('[data-support-ticket-link]');
    if (ticketLink) {
      const inbox = ticketLink.closest('[data-support-inbox]');
      if (inbox) {
        const conversation = inbox.querySelector('#support_conversation'); if (conversation) conversation.dataset.activeTab = 'conversation';
        inbox.setAttribute('data-conversation-open', '');
        inbox.dataset.selectedTicket = ticketLink.dataset.supportTicketLink;
        inbox.querySelectorAll('[data-support-ticket-link]').forEach(link => link.removeAttribute('aria-current'));
        ticketLink.setAttribute('aria-current', 'true');
      }
    }
    const back = event.target.closest('[data-support-inbox-back]');
    if (back && back.closest('[data-support-inbox]')) { event.preventDefault(); back.closest('[data-support-inbox]').removeAttribute('data-conversation-open'); }
    const trigger = event.target.closest("[data-support-new-url]");
    if (trigger) {
      const frame = document.querySelector("#support-modal turbo-frame");
      if (frame && (!frame.src || frame.querySelector("[data-support-created]"))) {
        const url = new URL(trigger.dataset.supportNewUrl, location.href).href;
        if (frame.src === url) frame.reload(); else frame.src = url;
      }
    }
    const dismiss = event.target.closest("[data-support-reminder-dismiss]");
    if (dismiss) {
      const reminder = dismiss.closest("[data-support-reminder]");
      reminder.hidden = true;
      try { sessionStorage.setItem("support-reminder:" + reminder.dataset.supportScope, JSON.stringify({state: reminder.dataset.state, time: Date.now()})); } catch (_) {}
    }
  });
  document.addEventListener("turbo:frame-load", event => { if (event.target.id === 'support_queue') { delete event.target.dataset.expanded; delete event.target.dataset.loadingMore; } setup(); poll(); });
  document.addEventListener("turbo:load", poll);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });
  document.addEventListener('paste', event => {
    const form = event.target.closest('form[data-support-draft]') || document.querySelector('#support-modal:not([hidden]) form[data-support-draft]');
    const input = form?.querySelector('input[type=file]');
    const images = [...(event.clipboardData?.files || [])].filter(file => file.type.startsWith('image/'));
    if (!input || !images.length) return;
    const files = new DataTransfer();
    [...input.files, ...images].forEach(file => files.items.add(file));
    input.files = files.files;
    input.dispatchEvent(new Event('change', {bubbles: true}));
  });
  document.addEventListener("input", event => { if (event.target.form) event.target.form.dataset.dirty = "true"; });
  document.addEventListener("turbo:load", setup);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", setup); else setup();
})();
