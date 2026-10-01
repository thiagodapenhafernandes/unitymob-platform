# Status de publicação compartilhado (formulários públicos, páginas): Inativo, Rascunho, Publicado.
# Só "published" está no ar: `active` continua existindo como coluna derivada do status, então
# scopes e telas antigas (`.active`, `active?`) seguem funcionando sem mudança.
module PublishableStatus
  extend ActiveSupport::Concern

  STATUSES = { "inactive" => "Inativo", "draft" => "Rascunho", "published" => "Publicado" }.freeze

  included do
    validates :status, inclusion: { in: STATUSES.keys }
    before_validation :sync_status_and_active
  end

  def draft? = status == "draft"

  def published? = status == "published"

  def status_label
    STATUSES.fetch(status, status.to_s.humanize)
  end

  private

  # status manda; quem ainda grava só `active` (código antigo) continua funcionando.
  def sync_status_and_active
    self.status = active? ? "published" : "inactive" if active_changed? && !status_changed?
    self.active = published?
  end
end
