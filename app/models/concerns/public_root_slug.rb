# Landing pages and articles share the same first-level public namespace.
module PublicRootSlug
  extend ActiveSupport::Concern

  included do
    validate :available_public_root_slug, if: :will_save_change_to_slug?
    before_save :lock_public_root_slug, if: :will_save_change_to_slug?
  end

  private

  def available_public_root_slug
    return if slug.blank? || tenant_id.blank?

    if %w[admin field api webhooks integrations rails assets packs cable jobs].include?(slug.to_s.downcase)
      errors.add(:slug, "é reservado pelo sistema")
      return
    end
    route = Rails.application.routes.recognize_path("/#{slug}", method: :get)
    unless route[:controller] == "landing_pages" && route[:action] == "show"
      errors.add(:slug, "é reservado pelo sistema")
    end
    other_class = is_a?(BlogArticle) ? LandingPage : BlogArticle
    if other_class.where(tenant_id: tenant_id, slug: slug).exists? || SeoRedirect.where(tenant_id: tenant_id, from_path: "/#{slug}", active: true).exists?
      errors.add(:slug, "já está em uso por outra página")
    end
  rescue ActionController::RoutingError
    errors.add(:slug, "não é um endereço válido")
  end

  def lock_public_root_slug
    # Serialize cross-table namespace claims within this tenant, inside save's transaction.
    self.class.connection.execute("SELECT pg_advisory_xact_lock(72419, #{Integer(tenant_id)})")
    available_public_root_slug
    throw(:abort) if errors[:slug].any?
  end
end
