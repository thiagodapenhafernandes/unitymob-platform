// The displayed photo survives loading failures and stale navigation requests.
export function createPropertyGallery(photos, title) {
  const trigger = document.activeElement;
  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    node.className = className;
    if (text) node.textContent = text;
    return node;
  };
  const button = (className, label, text) => {
    const node = element('button', className, text);
    node.type = 'button'; node.setAttribute('aria-label', label); node.title = label;
    return node;
  };
  const dialog = element('dialog', 'ax-property-gallery');
  dialog.setAttribute('aria-label', `Fotos de ${title}`);
  const header = element('header', 'ax-gallery-header');
  const heading = element('strong', 'ax-gallery-title', title);
  const close = button('ax-gallery-close', 'Fechar galeria', '×');
  close.autofocus = true;
  close.onclick = () => dialog.close();
  header.append(heading, close);
  const stage = element('div', 'ax-gallery-stage');
  const canvas = element('div', 'ax-gallery-canvas');
  const prev = button('ax-gallery-arrow ax-gallery-prev', 'Foto anterior', '‹');
  const next = button('ax-gallery-arrow ax-gallery-next', 'Próxima foto', '›');
  stage.append(canvas, prev, next);
  const footer = element('footer', 'ax-gallery-footer');
  const count = element('span', 'ax-gallery-count');
  const status = element('span', 'ax-gallery-status');
  status.setAttribute('role', 'status');
  count.setAttribute('aria-live', 'polite');
  const thumbs = element('div', 'ax-gallery-thumbs');
  thumbs.setAttribute('aria-label', 'Escolher foto');
  let index = 0, requestId = 0, currentImage, transition;
  const cached = new Map();
  const load = (i) => {
    if (!cached.has(i)) {
      const image = new Image();
      image.referrerPolicy = 'no-referrer';
      image.alt = `${title} — foto ${i + 1}`;
      image.src = photos[i];
      const promise = image.decode().then(() => image);
      cached.set(i, promise);
      promise.catch(() => cached.delete(i));
    }
    return cached.get(i);
  };
  const render = async (target) => {
    index = target;
    const request = ++requestId;
    prev.disabled = index === 0; next.disabled = index === photos.length - 1;
    status.textContent = 'Carregando foto…';
    canvas.setAttribute('aria-busy', 'true');
    try {
      const incoming = await load(target);
      if (request !== requestId || !dialog.open) return;
      if (transition) { transition.onfinish = null; transition.finish(); }
      // Finish a previous fade before starting another, keeping exactly one base layer.
      for (const child of [...canvas.children]) if (child !== currentImage) child.remove();
      const outgoing = currentImage;
      if (incoming !== outgoing) {
        canvas.append(incoming);
        currentImage = incoming;
        if (outgoing && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
          transition = incoming.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 180, easing: 'ease-out' });
          transition.onfinish = () => outgoing.remove();
        } else outgoing?.remove();
      }
      count.textContent = `${target + 1} / ${photos.length}`;
      status.textContent = '';
      [...thumbs.children].forEach((thumb, i) => thumb.setAttribute('aria-current', String(i === target)));
      thumbs.children[target]?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      for (const i of [target - 1, target + 1]) if (i >= 0 && i < photos.length) load(i).catch(() => {});
    } catch {
      if (request === requestId && dialog.open) status.textContent = 'Foto indisponível. Selecione outra ou tente novamente.';
    } finally {
      if (request === requestId) canvas.removeAttribute('aria-busy');
    }
  };
  photos.forEach((src, i) => {
    const thumb = button('ax-gallery-thumb', `Ver foto ${i + 1}`, '');
    const image = new Image(); image.alt = ''; image.loading = 'lazy'; image.referrerPolicy = 'no-referrer'; image.src = src;
    thumb.append(image); thumb.onclick = () => render(i); thumbs.append(thumb);
  });
  prev.onclick = () => { if (index > 0) render(index - 1); };
  next.onclick = () => { if (index < photos.length - 1) render(index + 1); };
  dialog.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      event.preventDefault(); (event.key === 'ArrowLeft' ? prev : next).click();
    }
  });
  dialog.addEventListener('close', () => {
    requestId++; transition?.cancel(); cached.clear(); dialog.remove();
    if (trigger?.isConnected) trigger.focus({ preventScroll: true });
  });
  footer.append(count, status, thumbs);
  dialog.append(header, stage, footer);
  document.body.append(dialog); dialog.showModal();
  if (photos.length) render(0);
  else { prev.disabled = next.disabled = true; status.textContent = 'Nenhuma foto disponível.'; }
  return dialog;
}
