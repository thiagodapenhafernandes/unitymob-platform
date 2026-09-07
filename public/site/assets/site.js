(() => {
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
