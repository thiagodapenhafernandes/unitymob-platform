(() => {
  const descriptions = [
    'Encontre ou crie leads na conversa, respeitando as permissões da sua imobiliária.',
    'Registre o contato e os próximos passos. O histórico continua no próprio CRM.',
    'Busque imóveis na carteira, selecione as opções e confirme o envio na conversa.',
    'Organize tarefas, follow-ups, visitas e compromissos sem perder o contexto do lead.'
  ];
  document.querySelectorAll('[data-demo]').forEach(button => {
    button.addEventListener('click', () => {
      const index = Number(button.dataset.demo);
      document.querySelectorAll('[data-demo]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
      const preview = document.getElementById('extension-preview');
      preview.src = `assets/whatsapp-${index}.png`;
      preview.alt = descriptions[index - 1];
      document.getElementById('extension-caption').textContent = descriptions[index - 1];
    });
  });
  document.querySelectorAll('.faq-q').forEach(button => {
    button.setAttribute('aria-expanded', String(button.closest('.faq-item').classList.contains('open')));
  });
})();
