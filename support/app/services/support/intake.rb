class Support::Intake
  OPTIONS = {
    'attempted_action' => ['Cadastrar algo novo', 'Alterar uma informação', 'Procurar ou abrir uma informação', 'Enviar uma mensagem ou arquivo', 'Entrar na minha conta', 'Tirar uma dúvida'],
    'expected_result' => ['Salvar as informações', 'Abrir a tela ou encontrar o que procurei', 'Enviar ou receber a mensagem', 'Concluir a ação normalmente', 'Entender como usar esta função'],
    'actual_result' => ['Apareceu uma mensagem de erro', 'A tela ficou carregando ou travou', 'O botão não respondeu', 'A informação não foi salva', 'A informação está diferente do esperado', 'Não encontrei o que preciso', 'Não sei como fazer'],
    'impact' => ['Não consigo continuar meu trabalho', 'Consigo continuar, mas com dificuldade', 'Acontece às vezes', 'É uma dúvida ou sugestão']
  }.freeze

  # Uma única fonte de permissões: as telas que o próprio menu já oferece a este usuário.
  def self.screens(view)
    html = Nokogiri::HTML.fragment(view.render('admin/shared/sidebar'))
    html.css('a.ax-nav__link[href]').filter_map do |link|
      path = URI.parse(link['href']).path
      label = link.at_css('span')&.text.to_s.squish
      [label, path] if path.start_with?('/admin') && label.present?
    end.uniq
  end

  def self.normalize(choices, details, screens)
    Support::Ticket::QUESTIONS.keys.to_h do |key|
      answer = choices[key].to_s
      allowed = key == 'menu_module' ? screens.map(&:first) : OPTIONS.fetch(key)
      value = answer == 'other' ? details[key].to_s.strip : allowed.include?(answer) ? answer : ''
      [key, value.first(4000)]
    end
  end
end
