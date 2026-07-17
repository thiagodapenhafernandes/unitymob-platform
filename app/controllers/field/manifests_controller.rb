# frozen_string_literal: true

# PWA manifest para /field. Servido dinamicamente para permitir customização
# por ambiente (dev/prod) sem compilar assets estáticos.
module Field
  class ManifestsController < ApplicationController
    # Manifest pode ser buscado antes do login pelo browser — não exigir auth.
    skip_before_action :verify_authenticity_token, raise: false

    def show
      respond_to do |format|
        format.json do
          response.headers["Cache-Control"] = "public, max-age=3600"
          render json: manifest_payload
        end
      end
    end

    private

    def manifest_payload
      identity = Tenants::PublicIdentity.new(public_tenant)
      layout = LayoutSetting.instance(tenant: public_tenant)
      brand = identity.name
      icon_version = layout.updated_at.to_i
      {
        id: "/field",
        name: "#{brand} — Campo",
        short_name: "#{brand} Campo".truncate(12, omission: ""),
        description: "Check-in geolocalizado dos corretores em plantão.",
        start_url: "/field",
        scope: "/",
        display: "standalone",
        orientation: "portrait",
        background_color: "#f8f9fa",
        theme_color: layout.admin_primary_color.presence || "#365F8F",
        lang: "pt-BR",
        categories: ["business", "productivity"],
        icons: [
          { src: "/pwa-icon-192?v=#{icon_version}", sizes: "192x192", type: "image/png", purpose: "any maskable" },
          { src: "/pwa-icon-512?v=#{icon_version}", sizes: "512x512", type: "image/png", purpose: "any maskable" }
        ]
      }
    end
  end
end
