class HabitationAuditLog < ApplicationRecord
  include TenantScoped

  ACTIONS = %w[
    created updated deleted published unpublished intake_status_changed
    attachments_changed broker_assignments_changed bulk_updated
  ].freeze
  SOURCE_LABELS = {
    "admin" => "Admin",
    "captacao" => "Captação",
    "integracao" => "Integração",
    "sistema" => "Sistema"
  }.freeze
  DISPLAY_IGNORED_FIELDS = %w[
    agenciador
    data_atualizacao_crm
    imovel_dwv
    pictures
    photo_ids_order
  ].freeze
  DISPLAY_IGNORED_WHEN_AFTER_BLANK_FIELDS = %w[
    perfil_construcao
    tipo_vaga
  ].freeze

  FIELD_LABELS = {
    "status" => "Status comercial",
    "exibir_no_site_flag" => "Publicação no site",
    "titulo_anuncio" => "Título do anúncio",
    "descricao_web" => "Descrição do imóvel",
    "nome_empreendimento" => "Nome do empreendimento",
    "codigo_empreendimento" => "Código do empreendimento",
    "categoria" => "Tipo do imóvel",
    "tipo" => "Modelo do cadastro",
    "situacao" => "Situação",
    "motivo_suspensao" => "Motivo de suspensão",
    "valor_venda_cents" => "Valor de venda",
    "valor_locacao_cents" => "Valor de locação",
    "valor_alugado_terceiros_cents" => "Valor alugado por terceiros",
    "valor_vendido_terceiros_cents" => "Valor vendido por terceiros",
    "valor_condominio_cents" => "Condomínio",
    "valor_iptu_cents" => "IPTU",
    "valor_promocional_cents" => "Valor promocional",
    "valor_comissao_cents" => "Valor da comissão",
    "valor_livre_proprietario_cents" => "Proprietário (livre)",
    "proprietario" => "Proprietário",
    "proprietario_codigo" => "Código do proprietário",
    "proprietario_email" => "E-mail do proprietário",
    "proprietario_celular" => "Celular do proprietário",
    "proprietario_telefone_comercial" => "Telefone comercial do proprietário",
    "proprietario_telefone_residencial" => "Telefone residencial do proprietário",
    "proprietor_id" => "Cadastro do proprietário",
    "corretor_nome" => "Corretor",
    "admin_user_id" => "Captador responsável",
    "admin_review_notes" => "Nota interna",
    "admin_review_return_reason" => "Motivo da devolução",
    "caracteristicas" => "Características",
    "caracteristica_unica" => "Características únicas",
    "infra_estrutura" => "Infraestrutura",
    "pictures" => "Fotos importadas",
    "photo_ids_order" => "Ordem das fotos",
    "videos" => "Vídeos",
    "plantas" => "Plantas",
    "fotos_empreendimento" => "Fotos do empreendimento",
    "photos_attachments" => "Fotos anexadas",
    "fichas_cadastro_attachments" => "Fichas de cadastro",
    "autorizacoes_venda_attachments" => "Autorizações de venda",
    "broker_assignments" => "Corretores vinculados",
    "intake_status" => "Status da captação",
    "intake_origin" => "Origem da captação",
    "intake_modalidade" => "Modalidade da captação",
    "publicar_zapimoveis" => "Publicar no Zap Imóveis",
    "publicar_viva_real_vrsync" => "Publicar no Viva Real",
    "publicar_imovelweb" => "Publicar no Imovelweb",
    "publicar_imovelweb_2" => "Publicar no Imovelweb 2",
    "publicar_chaves_na_mão" => "Publicar no Chaves na Mão",
    "publicar_chaves_na_mao" => "Publicar no Chaves na Mão",
    "publicar_casa_mineira" => "Publicar no Casa Mineira",
    "publicar_lais_ai" => "Publicar na Lais AI",
    "publicar_netimoveis_2" => "Publicar no Netimóveis",
    "publicar_loft" => "Publicar no Loft",
    "address.tipo_endereco" => "Tipo do endereço",
    "address.logradouro" => "Logradouro",
    "address.numero" => "Número",
    "address.complemento" => "Complemento",
    "address.bairro" => "Bairro",
    "address.bairro_comercial" => "Bairro comercial",
    "address.cidade" => "Cidade",
    "address.uf" => "UF",
    "address.cep" => "CEP",
    "address.pais" => "País",
    "address.imediacoes" => "Imediações"
  }.freeze

  CURRENCY_FIELDS = %w[
    valor_venda_cents valor_locacao_cents valor_alugado_terceiros_cents valor_vendido_terceiros_cents
    valor_condominio_cents valor_iptu_cents valor_promocional_cents valor_comissao_cents valor_livre_proprietario_cents
  ].freeze

  belongs_to :habitation, optional: true
  belongs_to :admin_user, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :source, presence: true
  validates :habitation_id, presence: true

  self.record_timestamps = false
  before_create :set_created_at

  scope :recent, -> { order(created_at: :desc) }

  def readonly?
    persisted?
  end

  def actor_name
    tenant_admin_user&.then { |user| user.name.presence || user.email.presence } || "Sistema"
  end

  def source_label
    SOURCE_LABELS[source] || source.to_s.humanize
  end

  def title
    case action
    when "created" then "#{actor_name} criou o imóvel"
    when "published" then "#{actor_name} publicou o imóvel no site"
    when "unpublished" then "#{actor_name} retirou o imóvel do site"
    when "intake_status_changed" then "#{actor_name} alterou o fluxo da captação"
    when "attachments_changed" then "#{actor_name} alterou anexos do imóvel"
    when "broker_assignments_changed" then "#{actor_name} alterou corretores vinculados"
    when "bulk_updated" then "#{actor_name} fez uma alteração em massa no imóvel"
    when "deleted" then "#{actor_name} excluiu o imóvel"
    else "#{actor_name} alterou o imóvel"
    end
  end

  def change_summaries
    changeset.to_h.filter_map do |field, values|
      next if DISPLAY_IGNORED_FIELDS.include?(field.to_s)

      before = values.is_a?(Hash) ? fetch_change_value(values, "before") : nil
      after = values.is_a?(Hash) ? fetch_change_value(values, "after") : nil
      next if DISPLAY_IGNORED_WHEN_AFTER_BLANK_FIELDS.include?(field.to_s) && blank_audit_value?(after)
      next if display_noop?(field, before, after)

      {
        field: field,
        label: field_label(field),
        before: display_value(field, before),
        after: display_value(field, after)
      }
    end
  end

  def display_noop?(field, before, after)
    audit_display_value_for_compare(field, before) == audit_display_value_for_compare(field, after)
  end

  def audit_display_value_for_compare(field, value)
    case value
    when nil
      nil
    when String
      normalized = value.strip
      return normalized.gsub(/\D/, "").presence if phone_field?(field)

      normalized.presence
    when Array
      normalized = value.map { |item| audit_display_value_for_compare(field, item) }.compact
      normalized.presence
    when Hash
      normalized = value.to_h.transform_values { |item| audit_display_value_for_compare(field, item) }.reject { |_key, item| item.nil? }
      normalized.presence
    else
      value
    end
  end

  def blank_audit_value?(value)
    audit_display_value_for_compare(nil, value).blank?
  end

  def phone_field?(field)
    field.to_s.match?(/telefone|celular/)
  end

  def field_label(field)
    FIELD_LABELS[field.to_s] || field.to_s.humanize
  end

  def display_value(field, value)
    return "vazio" if value.nil? || value == ""

    if CURRENCY_FIELDS.include?(field.to_s)
      cents = value.to_i
      return "vazio" if cents.zero?

      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: "R$", separator: ",", delimiter: ".")
    elsif value == true
      "Sim"
    elsif value == false
      "Não"
    elsif value.is_a?(Array)
      compact = value.reject(&:blank?)
      return "vazio" if compact.blank?

      return compact.map { |item| display_hash_item(field, item) }.join(", ")
    elsif value.is_a?(Hash)
      display_hash_item(field, value)
    else
      value.to_s
    end
  end

  def display_hash_item(field, item)
    return item.to_s unless item.is_a?(Hash)

    normalized = item.stringify_keys

    if field.to_s.end_with?("_attachments")
      filename = normalized["filename"].presence || "arquivo"
      details = [normalized["content_type"], human_file_size(normalized["byte_size"])].compact_blank.join(", ")
      return details.present? ? "#{filename} (#{details})" : filename
    end

    if field.to_s == "broker_assignments"
      name = normalized["admin_user_name"].presence || normalized["admin_user_id"].presence || "corretor"
      role = normalized["role"].presence
      commission = [normalized["commission_type"], normalized["commission_value"]].compact_blank.join(" ")
      return [name, role, commission].compact_blank.join(" - ")
    end

    normalized.values.flatten.reject(&:blank?).join(", ").presence || normalized.to_json
  end

  def human_file_size(value)
    return nil if value.blank?

    ActionController::Base.helpers.number_to_human_size(value.to_i)
  end

  def fetch_change_value(values, key)
    values.key?(key) ? values[key] : values[key.to_sym]
  end

  def self.publication_fields
    %w[
      exibir_no_site_flag publicar_zapimoveis publicar_viva_real_vrsync publicar_imovelweb publicar_imovelweb_2
      publicar_chaves_na_mao publicar_casa_mineira publicar_lais_ai publicar_netimoveis_2 publicar_loft
      destaque_chaves_na_mao periodo_locacao_chaves_na_mao modelo_casa_mineira tipo_publicacao_viva_real
      divulgar_endereco_viva_real tipo_publicacao_imovelweb mostrar_mapa_imovelweb tipo_publicacao_imovelweb_2
      mostrar_mapa_imovelweb_2
    ]
  end

  def self.intake_fields
    %w[intake_status intake_origin intake_modalidade submitted_for_review_at admin_reviewed_at admin_reviewed_by_id admin_review_notes admin_review_return_reason]
  end

  private

  def set_created_at
    self.created_at ||= Time.current
  end

  def tenant_admin_user
    return if admin_user_id.blank?

    tenant.admin_users.find_by(id: admin_user_id)
  end
end
