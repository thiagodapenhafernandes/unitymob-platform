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
      {
        name: "Salute Imóveis — Campo",
        short_name: "Salute Campo",
        description: "Check-in geolocalizado dos corretores em plantão.",
        start_url: "/field",
        scope: "/",
        display: "standalone",
        orientation: "portrait",
        background_color: "#f8f9fa",
        theme_color: "#0d6efd",
        lang: "pt-BR",
        categories: ["business", "productivity"],
        icons: [
          { src: "/field-icons/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any maskable" },
          { src: "/field-icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any maskable" }
        ]
      }
    end
  end
end
