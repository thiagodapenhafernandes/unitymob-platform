# frozen_string_literal: true

module Habitations
  class BrokerEditPolicy
    # Matriz do card #1 (Trello bO2XlxBo): o que o CORRETOR restrito pode editar
    # no imóvel, organizada por aba/seção como no formulário. Lista POSITIVA —
    # qualquer campo fora daqui permanece bloqueado.
    #
    # O GATILHO de "corretor restrito" já vem do módulo de Perfil/Permissão
    # (Admin::HabitationsController#broker_restricted_habitation_edit? →
    # can_edit_protected_habitation_fields? = tenant_owner? || owns_all_resource?(:imoveis)).
    # Ou seja: quem tem o recurso `imoveis` com escopo "all" (ou é dono do tenant)
    # edita tudo; os demais caem nesta matriz.
    #
    # RECONCILIAÇÃO FUTURA (Opção B — matriz configurável por perfil): a estrutura
    # abaixo é aba => seção => [campos] justamente para facilitar migrar cada
    # seção para um toggle lido de Profile.permissions (ex.:
    # permissions.dig("imoveis", "editable_sections")). Ver memória
    # permissions-reconcile-profile-module. Por ora é regra fixa.
    EDITABLE_MATRIX = {
      # ======================= Aba "Visão geral" =======================
      visao_geral: {
        # "Tipo de cadastro": SÓ estes. NÃO inclui `tipo` nem `categoria`.
        tipo_cadastro: %w[status situacao ocupacao_status estado_conservacao motivo_suspensao],
        # "Vínculo do empreendimento": só data de entrega e perfil de construção.
        # NÃO pode alterar nome/código do empreendimento.
        vinculo_empreendimento: %w[data_entrega perfil_construcao],
        # "Endereço e localização": SOMENTE "Imediações". NÃO altera
        # logradouro/nº/bairro/cidade/UF/complemento/bloco/lote, nem a
        # "Localização pública" (public_map_display_mode / public_street_view_mode).
        # Imediações vive na tabela addresses, então chega como
        # address_attributes[imediacoes]; o path aninhado é liberado no #filter
        # e o front (broker-field-policy) reconhece "address_attributes.imediacoes".
        endereco: %w[imediacoes address_attributes.imediacoes],
        # "Dimensões e estrutura física": tudo.
        dimensoes_estrutura: %w[
          dormitorios_qtd suites_qtd demi_suites_qtd salas_qtd varandas_qtd
          banheiros_qtd banheiro_social_qtd hidromassagem_qtd vagas_qtd elevadores_qtd
          andar numero_box tipo_vaga
          area_privativa_m2 area_total_m2 area_terreno_m2 area_util_m2
          dimensoes_terreno topografia face frente_terreno_m fundo_terreno_m
        ],
        # "Financeiro e valores": tudo. As reduções de venda/locação (valor anterior
        # e promocional) o sistema trata sozinho — por isso NÃO ficam liberadas aqui.
        financeiro: %w[
          valor_venda_formatted valor_locacao_formatted valor_condominio_formatted
          valor_iptu_formatted valor_alugado_terceiros_formatted
          valor_vendido_terceiros_formatted saldo_devedor_formatted
        ]
      },
      # ======================= Aba "Características" =======================
      caracteristicas: {
        # "Destaque e texto público": Destaque / Característica única.
        destaque_texto_publico: %w[destaque_web_flag caracteristica_unica],
        # AMBÍGUO no card (ele lista só Destaque/Característica única nesta seção):
        # se o corretor DEVE editar o texto do anúncio, descomente a linha abaixo.
        # texto_anuncio: %w[titulo_anuncio descricao_web],
        #
        # "Características internas": tudo. (Só não pode CRIAR/EDITAR opções no
        # botão "Gerenciar" — isso é o recurso `catalogos`/attribute_options,
        # controlado à parte pelo módulo de permissão.)
        caracteristicas_internas: %w[caracteristicas]
      },
      # ======================= Aba "Infraestrutura" =======================
      infraestrutura: {
        # "Dados do edifício": tudo.
        dados_edificio: %w[construtora tipo_fachada descricao_empreendimento],
        # "Descrição e capacidade": Nº andares, Ano constr., Elevadores,
        # Imóveis/andar, Total imóveis.
        descricao_capacidade: %w[andares_qtd ano_construcao elevadores_qtd aptos_andar aptos_edificio],
        # "Infraestrutura e lazer": tudo (idem "Gerenciar" fica de fora).
        infraestrutura_lazer: %w[infra_estrutura]
      },
      # ======================= Aba "Comercial" =======================
      comercial: {
        # "Condições comerciais": tudo, exceto a parte de valores automáticos.
        condicoes_comerciais: %w[
          condicoes_negociacao aceita_financiamento_flag aceita_parcelamento_flag numero_prestacoes
          aceita_permuta_flag aceita_permuta_veiculo_flag aceita_permuta_imovel_flag aceita_permuta_outros_flag
          valor_aceito_permuta_formatted permuta_valor_formatted permuta_veiculo_valor_formatted
          permuta_outros_valor_formatted tipo_veiculo_aceito_permuta ano_minimo_veiculo_aceito_permuta
          permuta_localizacao permuta_dormitorios_qtd permuta_suites_qtd permuta_garagens_qtd
          permuta_outros_descricao rental_guarantee_method inscricao_imobiliaria matricula_imovel zona
        ],
        # "Proprietário e comissões": NÃO altera dados do proprietário; só PODE
        # ADICIONAR e-mail e cidade quando faltam (o #filter remove se já
        # preenchidos). Comissões e "valor livre do proprietário": bloqueados.
        proprietario: %w[proprietario_email proprietario_cidade],
        # "Publicação em portais": bloqueada (publicar_* / tipo_publicacao_* etc.).
        publicacao_portais: [],
        # "Atendimento, chaves e reservas": tudo, EXCETO "Região foco" (regiao_foco).
        atendimento_chaves: %w[
          key_location key_location_notes senha_portaria senha_imovel
          zelador_nome zelador_telefone observacoes_visitas responsavel_reserva observacoes
        ],
        # "Responsáveis e agenciamento" / "Comissão e operação": bloqueados.
        responsaveis_agenciamento: [],
        comissao_operacao: []
      },
      # ======================= Aba "Mídia": pode alterar =======================
      midia: {
        # NOTA (card #16): a "Classificação das fotos" (foto_classificacao) NÃO
        # pode ser alterada pelo corretor — por isso fica FORA da lista, ainda que
        # a aba Mídia seja liberada.
        media: %w[
          photos ordered_photo_ids ordered_picture_indices site_hidden_photo_ids
          site_hidden_picture_urls videos tour_virtual podcast_url plantas
          fotos_empreendimento use_development_photos_flag
        ]
      }
      # ======================= Aba "Documentos": bloqueada (nada) =======================
      # ======================= Aba "SEO & Controle": bloqueada =======================
      # (meta_title / meta_description / meta_keywords / slug — nada editável)
    }.freeze

    # Todos os campos liberados (inclui o path aninhado address_attributes.imediacoes,
    # que o front usa para reconhecer o widget de Imediações).
    ALLOWED_FIELDS = EDITABLE_MATRIX.values.flat_map(&:values).flatten.uniq.freeze

    # Só os campos de topo (nível habitation[...]) — usado no slice do servidor.
    TOP_LEVEL_ALLOWED_FIELDS = ALLOWED_FIELDS.reject { |field| field.include?(".") }.freeze

    # Sub-chaves liberadas dentro de address_attributes (Endereço: só Imediações).
    ALLOWED_ADDRESS_SUBKEYS = %w[imediacoes id].freeze

    def self.filter(parameters, habitation:)
      filtered = parameters.slice(*TOP_LEVEL_ALLOWED_FIELDS)

      # Endereço: mantém address_attributes apenas com Imediações (+ id p/ o
      # update do registro aninhado). Todo o resto do endereço fica de fora.
      address = parameters["address_attributes"]
      if address.is_a?(Hash) || address.is_a?(ActionController::Parameters)
        allowed_address = address.slice(*ALLOWED_ADDRESS_SUBKEYS)
        filtered["address_attributes"] = allowed_address if allowed_address.keys.any? { |key| key != "id" }
      end

      filtered.delete("proprietario_email") if habitation.proprietario_email.present?
      filtered.delete("proprietario_cidade") if habitation.proprietario_cidade.present?
      filtered
    end

    def self.allowed_fields
      ALLOWED_FIELDS
    end
  end
end
