module Habitations
  class BrokerIntakeSnapshot
    include ActiveSupport::NumberHelper

    VERSION = 1

    def self.build(habitation, actor:, captured_at: Time.current)
      new(habitation, actor: actor, captured_at: captured_at).to_h
    end

    def self.persist!(records, snapshot:)
      Array(records).each do |record|
        next unless record.respond_to?(:has_attribute?) && record.has_attribute?(:broker_intake_snapshot)
        next if snapshot_present?(record.broker_intake_snapshot)

        record.update_columns(broker_intake_snapshot: snapshot)
      end
    end

    def self.snapshot_present?(snapshot)
      snapshot.is_a?(Hash) && snapshot["captured_at"].present?
    end

    def initialize(habitation, actor:, captured_at:)
      @habitation = habitation
      @actor = actor
      @captured_at = captured_at
    end

    def to_h
      {
        version: VERSION,
        captured_at: @captured_at.iso8601,
        captured_by: {
          id: @actor&.id,
          name: @actor&.name.presence || @actor&.email
        }.compact,
        property_code: @habitation.codigo,
        intake_status: @habitation.intake_status,
        sections: sections
      }.deep_stringify_keys
    end

    private

    def sections
      [
        section("identificacao", "Identificação", [
          row("Tipo de cadastro", @habitation.tipo),
          row("Categoria", @habitation.categoria),
          row("Status comercial", @habitation.status),
          row("Modalidade da captação", modality_label),
          row("Título do anúncio", @habitation.titulo_anuncio),
          row("Empreendimento/Condomínio", @habitation.nome_empreendimento),
          row("Compl.", @habitation.unidade_numero),
          row("Captador", @habitation.primary_captador_name)
        ]),
        section("proprietario", "Proprietário", [
          row("Nome", @habitation.proprietario_nome),
          row("Telefone/WhatsApp", @habitation.proprietario_telefone),
          row("E-mail", @habitation.proprietario_email_display),
          row("Cidade", @habitation.proprietario_cidade),
          row("Código/CPF/CNPJ", @habitation.proprietario_cpf_cnpj)
        ]),
        section("endereco", "Endereço e localização", [
          row("CEP", @habitation.cep),
          row("Tipo do endereço", @habitation.tipo_endereco),
          row("Logradouro", @habitation.logradouro),
          row("Número", @habitation.numero),
          row("Complemento", @habitation.complemento),
          row("Bairro", @habitation.bairro),
          row("Bairro comercial", @habitation.bairro_comercial),
          row("Cidade", @habitation.cidade),
          row("UF", @habitation.uf),
          row("Imediações", @habitation.imediacoes)
        ]),
        section("caracteristicas", "Características do imóvel", [
          row("Dormitórios", @habitation.dormitorios_qtd),
          row("Suítes", @habitation.suites_qtd),
          row("Demi-suítes", @habitation.demi_suites_qtd),
          row("Banheiros", @habitation.banheiros_qtd),
          row("Vagas", @habitation.vagas_qtd),
          row("Salas", @habitation.salas_qtd),
          row("Área privativa", area(@habitation.area_privativa_m2)),
          row("Área total", area(@habitation.area_total_m2)),
          row("Área terreno", area(@habitation.area_terreno_m2)),
          row("Área útil", area(@habitation.area_util_m2)),
          row("Ocupação", @habitation.ocupacao_status),
          row("Situação", @habitation.situacao),
          row("Estado de conservação", @habitation.estado_conservacao),
          row("Andar", @habitation.andar),
          row("Box", @habitation.numero_box),
          row("Tipo de vaga", @habitation.tipo_vaga),
          row("Lote", @habitation.lote),
          row("Quadra", @habitation.respond_to?(:quadra) ? @habitation.quadra : nil),
          row("Dimensões do terreno", @habitation.dimensoes_terreno),
          row("Topografia", @habitation.topografia)
        ]),
        section("caracteristicas_internas", "Características internas", [
          row("Características", list(@habitation.property_features_for_display))
        ]),
        section("empreendimento", "Características do empreendimento", [
          row("Infraestrutura", list(@habitation.leisure_features_for_display)),
          row("Perfil de construção", @habitation.perfil_construcao),
          row("Data de entrega", date(@habitation.data_entrega))
        ]),
        section("negociacao", "Negociação", [
          row("Valor de venda", money(@habitation.valor_venda_cents)),
          row("Valor de locação", money(@habitation.valor_locacao_cents)),
          row("Condomínio", money(@habitation.valor_condominio_cents)),
          row("IPTU", money(@habitation.valor_iptu_cents)),
          row("Valor total aluguel", money(@habitation.displayable_rent_total_cents)),
          row("Saldo devedor", money(@habitation.saldo_devedor_cents)),
          row("Aceita permuta", yes_no(@habitation.aceita_permuta_answer.presence || @habitation.aceita_permuta_flag?)),
          row("Aceita financiamento", yes_no(@habitation.aceita_financiamento_flag?)),
          row("Aceita parcelamento", yes_no(@habitation.aceita_parcelamento_flag?)),
          row("Número de parcelas", @habitation.numero_prestacoes),
          row("Administração de locação", yes_no(@habitation.salute_rental_management_answer.presence || @habitation.salute_rental_management_flag?)),
          row("Garantia locatícia", list(@habitation.rental_guarantee_methods)),
          row("Condições de negociação", @habitation.condicoes_negociacao)
        ]),
        section("visitas", "Visitas e chaves", [
          row("Onde estão as chaves", @habitation.key_location),
          row("Observações de chave", @habitation.key_location_notes),
          row("Zelador", @habitation.zelador_nome),
          row("Telefone do zelador", @habitation.zelador_telefone),
          row("Responsável por reserva", @habitation.responsavel_reserva),
          row("Observações de visita", @habitation.observacoes_visitas)
        ]),
        section("midia", "Fotos e anexos", [
          row("Fluxo de fotos", photo_flow_label),
          row("Agendamento", datetime(@habitation.photo_session_requested_at)),
          row("Classificação das fotos", @habitation.foto_classificacao),
          row("Fotos locais", attached_count(@habitation.photos)),
          row("Fotos importadas", Array(@habitation.pictures).size),
          row("Fichas de cadastro", attached_count(@habitation.fichas_cadastro)),
          row("Autorizações de venda", attached_count(@habitation.autorizacoes_venda))
        ]),
        section("textos", "Textos e observações", [
          row("Descrição pública", plain_text(@habitation.display_description)),
          row("Descrição interna", @habitation.descricao_interna),
          row("Observações", @habitation.observacoes)
        ])
      ]
    end

    def section(key, title, rows)
      {
        key: key,
        title: title,
        rows: rows
      }
    end

    def row(label, value)
      {
        label: label,
        value: display(value)
      }
    end

    def display(value)
      normalized = value.to_s.strip
      normalized.present? ? normalized : "-"
    end

    def list(values)
      Array(values).flatten.map(&:to_s).map(&:strip).compact_blank.uniq.join(", ")
    end

    def money(cents)
      return nil if cents.blank?

      value = cents.to_i
      return nil if value <= 0

      number_to_currency(value / 100.0, unit: "R$", separator: ",", delimiter: ".", format: "%u %n")
    end

    def area(value)
      return nil if value.blank?

      number = BigDecimal(value.to_s)
      return nil if number <= 0

      "#{number.to_s("F").sub(/\.0+\z/, "")} m²"
    rescue ArgumentError
      nil
    end

    def date(value)
      value.present? ? I18n.l(value.to_date) : nil
    end

    def datetime(value)
      value.present? ? I18n.l(value.in_time_zone, format: "%d/%m/%Y %H:%M") : nil
    end

    def yes_no(value)
      case value
      when true then "Sim"
      when false then "Não"
      else Habitation::YES_NO_ANSWERS[value.to_s] || value
      end
    end

    def modality_label
      {
        "venda" => "Venda",
        "locacao_anual" => "Locação anual",
        "locacao_diaria" => "Locação diária",
        "ambos" => "Venda e locação"
      }[@habitation.modalidade] || @habitation.modalidade
    end

    def photo_flow_label
      Habitation::PHOTO_FLOW_CHOICES[@habitation.photo_flow_choice] || @habitation.photo_flow_choice
    end

    def attached_count(attachments)
      attachments.attached? ? attachments.attachments.size.to_s : "0"
    end

    def plain_text(value)
      ActionController::Base.helpers.strip_tags(value.to_s).squish
    end
  end
end
