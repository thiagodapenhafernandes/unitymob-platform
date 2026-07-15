# frozen_string_literal: true

module Habitations
  # Representação COMPLETA do cadastro de imóvel para a trava de edição por
  # perfil (card #1 / Opção B). É a fonte única que alimenta:
  #   1) o modal de "Campos do cadastro" na tela de Perfil/Permissão (checkboxes);
  #   2) o enforcement (BrokerEditPolicy + broker-field-policy + guards de
  #      mídia/IA/responsáveis).
  #
  # Cada item tem uma `key` estável (salva em
  # profile.permissions["imoveis"]["locked_fields"]) e um `label` humano.
  # `kind`:
  #   :field  -> input do formulário (param habitation[<key>] ou path aninhado)
  #   :flag   -> toggle/checkbox (param habitation[<key>])
  #   :action -> botão/ação que não é um param simples (IA, Gerenciar, etc.);
  #              o enforcement é específico (ver ACTION_ENFORCEMENT).
  #
  # REGRA (card #1, decisões): só o DONO da conta edita tudo; todo o resto é por
  # perfil. Campo novo nasce TRAVADO. Perfil novo nasce com tudo travado.
  # A completude é garantida por spec (cadastro_field_registry_spec) que varre o
  # formulário e falha se algum campo `habitation[...]` não estiver aqui.
  module CadastroFieldRegistry
    GROUPS = [
      {
        tab: "Visão geral", section: "Tipo de cadastro",
        items: [
          { key: "tipo", label: "Tipo de cadastro" },
          { key: "categoria", label: "Categoria" },
          { key: "status", label: "Status comercial" },
          { key: "situacao", label: "Situação" },
          { key: "ocupacao_status", label: "Ocupação" },
          { key: "estado_conservacao", label: "Estado" },
          { key: "motivo_suspensao", label: "Motivo de suspensão" }
        ]
      },
      {
        tab: "Visão geral", section: "Vínculo do empreendimento",
        items: [
          { key: "codigo_empreendimento", label: "Código do empreendimento" },
          { key: "nome_empreendimento", label: "Nome do empreendimento" },
          { key: "data_entrega", label: "Data de entrega" },
          { key: "perfil_construcao", label: "Perfil de construção" },
          { key: "acao:vincular_empreendimento", label: "Botão + (cadastrar/vincular empreendimento)", kind: :action }
        ]
      },
      {
        tab: "Visão geral", section: "Endereço e localização",
        items: [
          { key: "tipo_endereco", label: "Tipo de logradouro" },
          { key: "logradouro", label: "Logradouro", param_path: "address_attributes.logradouro" },
          { key: "numero", label: "Número", param_path: "address_attributes.numero" },
          { key: "complemento", label: "Complemento", param_path: "address_attributes.complemento" },
          { key: "bairro", label: "Bairro", param_path: "address_attributes.bairro" },
          { key: "bairro_comercial", label: "Bairro comercial", param_path: "address_attributes.bairro_comercial" },
          { key: "cidade", label: "Cidade", param_path: "address_attributes.cidade" },
          { key: "uf", label: "UF", param_path: "address_attributes.uf" },
          { key: "bloco", label: "Bloco / Unidade", param_path: "address_attributes.bloco" },
          { key: "imediacoes", label: "Imediações", param_path: "address_attributes.imediacoes" },
          { key: "public_map_display_mode", label: "Localização pública (mapa)" },
          { key: "public_street_view_mode", label: "Localização pública (street view)" }
        ]
      },
      {
        tab: "Visão geral", section: "Dimensões e estrutura física",
        items: [
          { key: "dormitorios_qtd", label: "Dormitórios" },
          { key: "suites_qtd", label: "Suítes" },
          { key: "demi_suites_qtd", label: "Demi-suítes" },
          { key: "salas_qtd", label: "Salas" },
          { key: "varandas_qtd", label: "Varandas" },
          { key: "banheiros_qtd", label: "Banheiros" },
          { key: "banheiro_social_qtd", label: "Banheiros sociais" },
          { key: "hidromassagem_qtd", label: "Hidromassagens" },
          { key: "vagas_qtd", label: "Vagas" },
          { key: "elevadores_qtd", label: "Elevadores" },
          { key: "andar", label: "Andar" },
          { key: "numero_box", label: "Nº do box" },
          { key: "tipo_vaga", label: "Tipo de vaga" },
          { key: "area_privativa_m2", label: "Área privativa (m²)" },
          { key: "area_total_m2", label: "Área total (m²)" },
          { key: "area_terreno_m2", label: "Área do terreno (m²)" },
          { key: "area_util_m2", label: "Área útil (m²)" },
          { key: "dimensoes_terreno", label: "Dimensões do terreno" },
          { key: "frente_terreno_m", label: "Frente do terreno (m)" },
          { key: "fundo_terreno_m", label: "Fundo do terreno (m)" },
          { key: "topografia", label: "Topografia" },
          { key: "face", label: "Face / Posição solar" }
        ]
      },
      {
        tab: "Características", section: "Destaque e texto público",
        items: [
          { key: "destaque_web_flag", label: "Destaque Web", kind: :flag },
          { key: "caracteristica_unica", label: "Característica única" },
          { key: "titulo_anuncio", label: "Título do anúncio" },
          { key: "descricao_web", label: "Descrição do imóvel para internet" },
          { key: "acao:gerar_ia", label: "Botão Gerar com IA", kind: :action }
        ]
      },
      {
        tab: "Características", section: "Características internas",
        items: [
          { key: "caracteristicas", label: "Características internas (seleção)" },
          { key: "acao:gerenciar_caracteristicas", label: "Botão Gerenciar (características internas)", kind: :action }
        ]
      },
      {
        tab: "Infraestrutura", section: "Dados do edifício",
        items: [
          { key: "construtora", label: "Construtora" },
          { key: "agenciador", label: "Agenciador" },
          { key: "tipo_fachada", label: "Tipo de fachada" },
          { key: "descricao_empreendimento", label: "Descrição do empreendimento" }
        ]
      },
      {
        tab: "Infraestrutura", section: "Descrição e capacidade",
        items: [
          { key: "andares_qtd", label: "Nº de andares" },
          { key: "ano_construcao", label: "Ano de construção" },
          # "elevadores_qtd" é o mesmo param da seção "Dimensões e estrutura física"
          # (renderizado nos dois lugares); travado por lá para não duplicar a chave.
          { key: "aptos_andar", label: "Imóveis por andar" },
          { key: "aptos_edificio", label: "Total de imóveis" }
        ]
      },
      {
        tab: "Infraestrutura", section: "Infraestrutura e lazer",
        items: [
          { key: "infra_estrutura", label: "Infraestrutura e lazer (seleção)" },
          { key: "acao:gerenciar_infraestrutura", label: "Botão Gerenciar (infraestrutura e lazer)", kind: :action }
        ]
      },
      {
        tab: "Comercial", section: "Financeiro e valores",
        items: [
          { key: "valor_venda_formatted", label: "Valor de venda" },
          { key: "valor_locacao_formatted", label: "Valor de locação" },
          { key: "valor_condominio_formatted", label: "Condomínio" },
          { key: "valor_iptu_formatted", label: "IPTU" },
          { key: "valor_por_m2_formatted", label: "Valor por m²" },
          { key: "valor_alugado_terceiros_formatted", label: "Valor comercializado (locação)" },
          { key: "valor_vendido_terceiros_formatted", label: "Valor comercializado (venda)" },
          { key: "valor_venda_anterior_formatted", label: "Valor de venda anterior (automático)" },
          { key: "valor_locacao_anterior_formatted", label: "Valor de locação anterior (automático)" },
          { key: "valor_promocional_formatted", label: "Valor promocional (automático)" },
          { key: "valor_promocional_indicador", label: "Indicador de promoção", kind: :flag },
          { key: "saldo_devedor_formatted", label: "Saldo devedor" }
        ]
      },
      {
        tab: "Comercial", section: "Condições comerciais",
        items: [
          { key: "condicoes_negociacao", label: "Condições de negociação" },
          { key: "aceita_financiamento_flag", label: "Aceita financiamento", kind: :flag },
          { key: "aceita_parcelamento_flag", label: "Aceita parcelamento", kind: :flag },
          { key: "numero_prestacoes", label: "Nº de prestações" },
          { key: "inscricao_imobiliaria", label: "Inscrição imobiliária" },
          { key: "matricula_imovel", label: "Matrícula do imóvel" },
          { key: "zona", label: "Zona" }
        ]
      },
      {
        tab: "Comercial", section: "Permuta",
        items: [
          { key: "aceita_permuta_flag", label: "Aceita permuta", kind: :flag },
          { key: "aceita_permuta_veiculo_flag", label: "Permuta: veículo", kind: :flag },
          { key: "aceita_permuta_imovel_flag", label: "Permuta: imóvel", kind: :flag },
          { key: "aceita_permuta_outros_flag", label: "Permuta: outros", kind: :flag },
          { key: "valor_aceito_permuta_formatted", label: "Valor aceito em permuta" },
          { key: "permuta_valor_formatted", label: "Valor da permuta" },
          { key: "permuta_veiculo_valor_formatted", label: "Valor permuta (veículo)" },
          { key: "permuta_outros_valor_formatted", label: "Valor permuta (outros)" },
          { key: "tipo_veiculo_aceito_permuta", label: "Tipo de veículo aceito" },
          { key: "ano_minimo_veiculo_aceito_permuta", label: "Ano mínimo do veículo" },
          { key: "permuta_localizacao", label: "Permuta: localização" },
          { key: "permuta_dormitorios_qtd", label: "Permuta: dormitórios" },
          { key: "permuta_suites_qtd", label: "Permuta: suítes" },
          { key: "permuta_garagens_qtd", label: "Permuta: garagens" },
          { key: "permuta_outros_descricao", label: "Permuta: descrição (outros)" },
          { key: "rental_guarantee_method", label: "Garantia de locação" }
        ]
      },
      {
        tab: "Comercial", section: "Proprietário e comissões",
        items: [
          { key: "proprietario", label: "Proprietário (nome)" },
          { key: "proprietario_email", label: "E-mail do proprietário" },
          { key: "proprietario_cidade", label: "Cidade do proprietário" },
          { key: "proprietario_celular", label: "Celular do proprietário" },
          { key: "proprietario_telefone_comercial", label: "Telefone comercial do proprietário" },
          { key: "proprietario_telefone_residencial", label: "Telefone residencial do proprietário" },
          { key: "proprietor_id", label: "Vínculo do proprietário (pesquisa/cadastro)" },
          { key: "captador_commission_percentage", label: "Comissão do captador (%)" },
          { key: "broker_commission_percentage", label: "Comissão do corretor (%)" },
          { key: "valor_comissao_formatted", label: "Valor da comissão" },
          { key: "valor_livre_proprietario_formatted", label: "Valor livre do proprietário" },
          { key: "home_corporate_flag", label: "Home corporativo", kind: :flag },
          { key: "home_corporate_position", label: "Posição no home corporativo" },
          { key: "salute_rental_management_flag", label: "Administração de locação Salute", kind: :flag }
        ]
      },
      {
        tab: "Comercial", section: "Atendimento, chaves e reservas",
        items: [
          { key: "regiao_foco", label: "Região foco" },
          { key: "key_location", label: "Localização das chaves" },
          { key: "key_location_notes", label: "Observações das chaves" },
          { key: "senha_portaria", label: "Senha da portaria" },
          { key: "senha_imovel", label: "Senha do imóvel" },
          { key: "zelador_nome", label: "Nome do zelador" },
          { key: "zelador_telefone", label: "Telefone do zelador" },
          { key: "responsavel_reserva", label: "Responsável pela reserva" },
          { key: "observacoes_visitas", label: "Observações de visitas" },
          { key: "observacoes", label: "Observações gerais" }
        ]
      },
      {
        tab: "Comercial", section: "Responsáveis e agenciamento",
        items: [
          { key: "admin_user_id", label: "Captador responsável" },
          { key: "acao:gerenciar_responsaveis", label: "Adicionar/Remover responsáveis", kind: :action }
        ]
      },
      {
        tab: "Comercial", section: "Publicação em portais",
        items: [
          { key: "exibir_no_site_flag", label: "Exibir no site", kind: :flag },
          { key: "publicar_zapimoveis", label: "Publicar: ZAP Imóveis", kind: :flag },
          { key: "publicar_viva_real_vrsync", label: "Publicar: Viva Real", kind: :flag },
          { key: "publicar_imovelweb", label: "Publicar: ImovelWeb", kind: :flag },
          { key: "publicar_imovelweb_2", label: "Publicar: ImovelWeb 2", kind: :flag },
          { key: "publicar_chaves_na_mao", label: "Publicar: Chaves na Mão", kind: :flag },
          { key: "publicar_casa_mineira", label: "Publicar: Casa Mineira", kind: :flag },
          { key: "publicar_netimoveis_2", label: "Publicar: Netimóveis", kind: :flag },
          { key: "publicar_loft", label: "Publicar: Loft", kind: :flag },
          { key: "publicar_lais_ai", label: "Publicar: Lais IA", kind: :flag },
          { key: "tipo_publicacao_viva_real", label: "Tipo de publicação (Viva Real)" },
          { key: "divulgar_endereco_viva_real", label: "Divulgar endereço (Viva Real)", kind: :flag },
          { key: "tipo_publicacao_imovelweb", label: "Tipo de publicação (ImovelWeb)" },
          { key: "mostrar_mapa_imovelweb", label: "Mostrar mapa (ImovelWeb)", kind: :flag },
          { key: "tipo_publicacao_imovelweb_2", label: "Tipo de publicação (ImovelWeb 2)" },
          { key: "mostrar_mapa_imovelweb_2", label: "Mostrar mapa (ImovelWeb 2)", kind: :flag },
          { key: "destaque_chaves_na_mao", label: "Destaque (Chaves na Mão)", kind: :flag },
          { key: "periodo_locacao_chaves_na_mao", label: "Período de locação (Chaves na Mão)" },
          { key: "modelo_casa_mineira", label: "Modelo (Casa Mineira)" }
        ]
      },
      {
        tab: "Mídia", section: "Mídia e uploads",
        items: [
          { key: "photos", label: "Fotos (upload/ordem/ocultar)" },
          { key: "videos", label: "Vídeos" },
          { key: "tour_virtual", label: "Tour virtual" },
          { key: "podcast_url", label: "Podcast (URL)" },
          { key: "plantas", label: "Plantas" },
          { key: "fotos_empreendimento", label: "Fotos do empreendimento" },
          { key: "use_development_photos_flag", label: "Usar fotos do empreendimento", kind: :flag },
          { key: "foto_classificacao", label: "Classificação das fotos" }
        ]
      },
      {
        tab: "Sinalizadores", section: "Exibição e sinalizadores",
        items: [
          { key: "lancamento_flag", label: "Lançamento", kind: :flag },
          { key: "exclusivo_flag", label: "Exclusivo", kind: :flag },
          { key: "tem_placa_flag", label: "Tem placa", kind: :flag },
          { key: "festival_salute_flag", label: "Festival Salute", kind: :flag },
          { key: "imovel_dwv", label: "Imóvel DWV" }
        ]
      },
      {
        tab: "Documentos", section: "Documentos",
        items: [
          { key: "fichas_cadastro", label: "Fichas de cadastro" },
          { key: "autorizacoes_venda", label: "Autorizações de venda" }
        ]
      },
      {
        tab: "SEO & Controle", section: "SEO e controle",
        items: [
          { key: "meta_title", label: "Meta Title" },
          { key: "meta_description", label: "Meta Description" },
          { key: "meta_keywords", label: "Meta Keywords" },
          { key: "slug", label: "URL amigável (Slug)" }
        ]
      }
    ].freeze

    # Campos do formulário deliberadamente FORA da trava (sempre livres/estruturais):
    # não representam edição de conteúdo do imóvel.
    NON_LOCKABLE_FORM_FIELDS = %w[
      id codigo intake_status name
    ].freeze

    module_function

    def groups = GROUPS

    def all_items = GROUPS.flat_map { |group| group[:items] }

    def all_keys = all_items.map { |item| item[:key] }

    def item(key) = all_items.find { |i| i[:key] == key.to_s }

    def field_items = all_items.reject { |i| i[:kind] == :action }

    # key -> param path de topo (habitation[<path>]); ignora ações e paths aninhados.
    def top_level_param_for(key)
      found = item(key)
      return nil unless found && found[:kind] != :action

      path = found[:param_path] || found[:key]
      path.include?(".") ? nil : path
    end
  end
end
