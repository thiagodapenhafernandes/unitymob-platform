class LeadAuditLog < ApplicationRecord
  ACTIONS = {
    "created" => "Criado",
    "updated" => "Atualizado",
    "status_changed" => "Status alterado",
    "assigned" => "Corretor alterado",
    "deleted" => "Excluído"
  }.freeze

  SOURCES = {
    "admin" => "Admin",
    "site" => "Site",
    "meta" => "Meta Leads",
    "distribution" => "Distribuição",
    "system" => "Sistema"
  }.freeze

  FIELD_LABELS = {
    "name" => "Nome",
    "email" => "E-mail",
    "phone" => "Telefone",
    "client_name" => "Nome do cliente",
    "client_email" => "E-mail do cliente",
    "client_phone" => "Telefone do cliente",
    "status" => "Status",
    "notes" => "Observações",
    "origin" => "Origem",
    "lead_type" => "Tipo",
    "property_id" => "Imóvel",
    "admin_user_id" => "Corretor",
    "distribution_rule_id" => "Regra de distribuição",
    "source_url" => "URL de origem",
    "product" => "Produto",
    "custom_answers" => "Respostas personalizadas",
    "other_information" => "Informações extras"
  }.freeze

  belongs_to :lead, optional: true
  belongs_to :admin_user, optional: true

  validates :lead_id, :action, :source, presence: true
  validates :action, inclusion: { in: ACTIONS.keys }
  validates :source, inclusion: { in: SOURCES.keys }

  self.record_timestamps = false
  before_create :set_created_at

  scope :recent, -> { order(created_at: :desc) }

  def readonly?
    persisted?
  end

  def actor_name
    admin_user&.name.presence || admin_user&.email.presence || "Sistema"
  end

  def action_label
    ACTIONS[action] || action.to_s.humanize
  end

  def source_label
    SOURCES[source] || source.to_s.humanize
  end

  def title
    case action
    when "created" then "#{actor_name} criou o lead"
    when "deleted" then "#{actor_name} excluiu o lead"
    when "status_changed" then "#{actor_name} alterou o status do lead"
    when "assigned" then "#{actor_name} alterou o corretor do lead"
    else "#{actor_name} atualizou o lead"
    end
  end

  def change_summaries
    changeset.to_h.map do |field, values|
      {
        field: field,
        label: FIELD_LABELS[field] || field.to_s.humanize,
        before: display_value(field, fetch_change_value(values, "before")),
        after: display_value(field, fetch_change_value(values, "after"))
      }
    end
  end

  private

  def set_created_at
    self.created_at ||= Time.current
  end

  def fetch_change_value(values, key)
    return values[key] if values.is_a?(Hash) && values.key?(key)
    return values[key.to_sym] if values.is_a?(Hash) && values.key?(key.to_sym)
  end

  def display_value(field, value)
    return "vazio" if value.blank?

    case field
    when "admin_user_id"
      AdminUser.find_by(id: value)&.name || "Usuário ##{value}"
    when "property_id"
      Habitation.find_by(id: value)&.codigo || "Imóvel ##{value}"
    when "distribution_rule_id"
      DistributionRule.find_by(id: value)&.name || "Regra ##{value}"
    else
      value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
    end
  end
end
