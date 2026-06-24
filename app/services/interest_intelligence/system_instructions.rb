module InterestIntelligence
  module SystemInstructions
    DEFAULT_TEXT = <<~TEXT.squish.freeze
      Interprete o interesse imobiliário do lead usando primeiro sinais explícitos e depois sinais comportamentais.
      Priorize imóveis com aderência de finalidade, cidade, bairro, tipo, faixa de preço, dormitórios e recorrência de visualização.
      Não substitua a curadoria do corretor: quando houver dúvida, gere tarefa ou nota interna em vez de enviar imóveis diretamente ao cliente.
      Considere interesse forte quando o lead visualizar imóveis parecidos, repetir buscas com os mesmos filtros ou converter em um imóvel da mesma região/perfil.
      Considere perfil incompleto quando faltarem localização, faixa de preço ou tipo de imóvel suficientes para uma recomendação confiável.
    TEXT

    module_function

    def effective_text(setting = LayoutSetting.instance)
      setting.interest_intelligence_instructions.presence || DEFAULT_TEXT
    end
  end
end
