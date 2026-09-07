(() => {
  const descriptions = [
    'Encontre ou crie leads na conversa, respeitando as permissões da sua imobiliária.',
    'Registre o contato e os próximos passos. O histórico continua no próprio CRM.',
    'Busque imóveis na carteira, selecione as opções e confirme o envio na conversa.',
    'Organize tarefas, follow-ups, visitas e compromissos sem perder o contexto do lead.'
  ];
  let previewAnimation;
  let animatePreview = false;
  const preview = document.getElementById('extension-preview');
  preview.addEventListener('load', () => {
    if (!animatePreview || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    previewAnimation?.cancel();
    previewAnimation = preview.animate([{opacity: .6}, {opacity: 1}], {duration: 240, easing: 'cubic-bezier(0.23, 1, 0.32, 1)'});
  });
  document.querySelectorAll('[data-demo]').forEach(button => {
    button.addEventListener('click', event => {
      if (button.getAttribute('aria-pressed') === 'true') return;
      previewAnimation?.cancel();
      animatePreview = event.detail > 0;
      const index = Number(button.dataset.demo);
      document.querySelectorAll('[data-demo]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
      const preview = document.getElementById('extension-preview');
      preview.src = `assets/whatsapp-${index}.png`;
      preview.alt = descriptions[index - 1];
      document.getElementById('extension-caption').textContent = descriptions[index - 1];
    });
  });
  document.querySelectorAll('.faq-q').forEach((button, index) => {
    const item = button.closest('.faq-item');
    const answer = item.querySelector('.faq-a');
    const content = answer.querySelector('.faq-a-content');
    const isOpen = () => item.classList.contains('open');
    answer.id = `faq-answer-${index}`;
    button.setAttribute('aria-controls', answer.id);
    button.setAttribute('aria-expanded', String(isOpen()));
    button.querySelector('span').setAttribute('aria-hidden', 'true');
    answer.inert = !isOpen();
    button.addEventListener('click', () => {
      const open = !isOpen();
      // Start from the rendered height so rapid reversals remain continuous.
      answer.style.height = `${answer.getBoundingClientRect().height}px`;
      void answer.offsetHeight;
      item.classList.toggle('open', open);
      button.setAttribute('aria-expanded', String(open));
      answer.inert = !open;
      answer.style.height = open ? `${content.scrollHeight}px` : '0px';
      if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
        answer.style.height = open ? 'auto' : '0px';
      }
    });
    answer.addEventListener('transitionend', event => {
      if (event.propertyName === 'height' && isOpen()) answer.style.height = 'auto';
    });
  });
})();
