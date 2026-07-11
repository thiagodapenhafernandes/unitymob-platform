# frozen_string_literal: true

module Habitations
  class BrokerEditPolicy
    # Lista positiva: qualquer campo novo permanece bloqueado para corretores
    # até ser deliberadamente incluído aqui.
    ALLOWED_FIELDS = %w[
      tipo categoria status situacao ocupacao_status estado_conservacao motivo_suspensao
      codigo_empreendimento nome_empreendimento data_entrega perfil_construcao
      address_attributes
      dormitorios_qtd suites_qtd demi_suites_qtd salas_qtd varandas_qtd banheiros_qtd
      banheiro_social_qtd hidromassagem_qtd vagas_qtd elevadores_qtd bloco lote andar
      numero_box tipo_vaga area_privativa_m2 area_total_m2 area_terreno_m2 area_util_m2
      dimensoes_terreno topografia face
      valor_venda_formatted valor_locacao_formatted valor_alugado_terceiros_formatted
      valor_vendido_terceiros_formatted valor_condominio_formatted valor_iptu_formatted
      valor_promocional_formatted saldo_devedor_formatted
      destaque_web_flag caracteristica_unica caracteristicas titulo_anuncio descricao_web
      construtora tipo_fachada descricao_empreendimento andares_qtd ano_construcao
      aptos_andar aptos_edificio infra_estrutura
      condicoes_negociacao aceita_financiamento_flag aceita_parcelamento_flag numero_prestacoes
      aceita_permuta_flag aceita_permuta_veiculo_flag aceita_permuta_imovel_flag
      aceita_permuta_outros_flag valor_aceito_permuta_formatted permuta_valor_formatted
      permuta_veiculo_valor_formatted permuta_outros_valor_formatted tipo_veiculo_aceito_permuta
      ano_minimo_veiculo_aceito_permuta permuta_localizacao permuta_dormitorios_qtd
      permuta_suites_qtd permuta_garagens_qtd permuta_outros_descricao rental_guarantee_method
      proprietario_email proprietario_cidade
      responsavel_reserva key_location key_location_notes senha_portaria senha_imovel
      zelador_nome zelador_telefone observacoes_visitas observacoes
      photos ordered_photo_ids ordered_picture_indices site_hidden_photo_ids
      site_hidden_picture_urls videos tour_virtual podcast_url foto_classificacao plantas
      fotos_empreendimento use_development_photos_flag
    ].freeze

    def self.filter(parameters, habitation:)
      filtered = parameters.slice(*ALLOWED_FIELDS)
      filtered.delete("proprietario_email") if habitation.proprietario_email.present?
      filtered.delete("proprietario_cidade") if habitation.proprietario_cidade.present?
      filtered
    end

    def self.allowed_fields
      ALLOWED_FIELDS
    end
  end
end
