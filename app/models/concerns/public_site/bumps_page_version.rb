module PublicSite
  # Registros que aparecem no site público: ao confirmar a gravação, sobe a
  # versão da conta (PublicSite::PageVersion) e o cache de página renova.
  # Sobrescreva public_page_version_tenant_id (quando o registro não tem
  # tenant_id direto) e public_page_version_relevant? (para ignorar gravações
  # operacionais, como contadores e estado de sincronização).
  module BumpsPageVersion
    extend ActiveSupport::Concern

    included do
      after_commit :bump_public_page_version
    end

    private

    def bump_public_page_version
      return unless public_page_version_relevant?

      tenant_id = public_page_version_tenant_id
      tenant_id.present? ? PublicSite::PageVersion.bump(tenant_id) : PublicSite::PageVersion.bump_all
    end

    def public_page_version_tenant_id
      try(:tenant_id)
    end

    def public_page_version_relevant?
      true
    end
  end
end
