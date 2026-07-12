module Habitations
  class OperationalSummary
    Issue = Data.define(:severity, :code, :label)
    Channel = Data.define(:key, :label, :active) do
      def active? = active
    end

    attr_reader :habitation

    def initialize(habitation)
      @habitation = habitation
    end

    def photo_count
      habitation.photos.attachments.size
    end

    def document_count
      habitation.fichas_cadastro.attachments.size + habitation.autorizacoes_venda.attachments.size
    end

    def responsible_name
      habitation.admin_user&.name.presence || "Sem responsável"
    end

    def site_label
      return "Fora do site" unless habitation.exibir_no_site_flag?
      return "Publicado" if habitation.publicly_viewable?

      "Marcado, mas indisponível"
    end

    def portal_channels
      Habitation::PORTAL_PUBLICATION_FIELDS.filter_map do |key, field|
        next unless habitation.has_attribute?(field)

        Channel.new(key:, label: key.to_s.humanize, active: boolean(habitation.public_send(field)))
      end
    end

    def active_portals
      portal_channels.select(&:active)
    end

    def issues
      @issues ||= begin
        rows = []
        rows << Issue.new(severity: :warning, code: :missing_title, label: "Título público não informado") if habitation.titulo_anuncio.blank?
        rows << Issue.new(severity: :warning, code: :missing_address, label: "Endereço não informado") if habitation.endereco.blank?
        rows << Issue.new(severity: :warning, code: :missing_responsible, label: "Imóvel sem responsável") if habitation.admin_user.blank?
        rows << Issue.new(severity: :warning, code: :missing_photos, label: "Imóvel sem fotos locais") if photo_count.zero?
        rows << Issue.new(severity: :warning, code: :missing_price, label: "Imóvel sem valor de venda ou locação") if !habitation.empreendimento? && !public_price?

        if habitation.exibir_no_site_flag? && !habitation.publicly_viewable?
          rows << Issue.new(severity: :danger, code: :site_state_conflict, label: "Marcado para o site, mas indisponível: #{public_unavailable_label}")
        end
        if active_portals.any? && !habitation.publicly_viewable?
          rows << Issue.new(severity: :danger, code: :portal_state_conflict, label: "Portais ativos enquanto o imóvel está indisponível no site")
        end
        rows
      end
    end

    def next_action
      issues.find { |issue| issue.severity == :danger }&.label || issues.first&.label || "Acompanhar alterações e canais ativos."
    end

    private

    def public_price?
      habitation.valor_venda_cents.to_i.positive? || habitation.valor_locacao_cents.to_i.positive?
    end

    def public_unavailable_label
      {
        "exibir_no_site_flag=false" => "fora do site",
        "sem fotos" => "sem foto pública válida",
        "sem preco" => "sem preço público"
      }.fetch(habitation.public_unavailable_reason, habitation.public_unavailable_reason.to_s.sub("status=", "status "))
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
