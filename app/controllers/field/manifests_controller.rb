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
          response.headers["Cache-Control"] = "private, max-age=300"
          response.headers["Vary"] = "Cookie"
          render json: manifest_payload
        end
      end
    end

    private

    def manifest_payload
      identity = Field::PwaIdentity.new(field_manifest_tenant)

      {
        id: identity.manifest_id,
        name: identity.full_name,
        short_name: identity.short_name,
        description: "Check-in geolocalizado dos corretores em plantão.",
        start_url: identity.start_url,
        scope: "/",
        display: "standalone",
        orientation: "portrait",
        background_color: "#f8f9fa",
        theme_color: identity.theme_color,
        lang: "pt-BR",
        categories: ["business", "productivity"],
        icons: [
          { src: identity.icon_src(192), sizes: "192x192", type: "image/png", purpose: "any maskable" },
          { src: identity.icon_src(512), sizes: "512x512", type: "image/png", purpose: "any maskable" }
        ]
      }
    end

    def field_manifest_tenant
      current_admin_user&.tenant || public_tenant
    end
  end
end
