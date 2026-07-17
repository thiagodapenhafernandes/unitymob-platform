# frozen_string_literal: true

# Manifest do PWA da plataforma (/admin). Sem ele o iOS abre o atalho dentro
# do Safari (sem standalone) e o Web Push em iOS fica indisponível — push só
# funciona em PWA instalado com manifest válido. Dinâmico para herdar a marca
# do cliente (nome e cores de Identidade e Marca).
module Admin
  class ManifestsController < ApplicationController
    # Buscado pelo navegador fora do ciclo autenticado.
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
      layout = layout_setting
      brand = layout.site_name.to_s.strip.presence || "Salute Imóveis"
      icon_version = layout.updated_at.to_i

      {
        id: "/admin",
        name: "#{brand} — Plataforma",
        short_name: brand.truncate(12, omission: ""),
        description: "CRM e atendimento #{brand}.",
        start_url: "/admin/",
        scope: "/",
        display: "standalone",
        background_color: "#ffffff",
        theme_color: layout.admin_primary_color.presence || "#365F8F",
        lang: "pt-BR",
        categories: %w[business productivity],
        icons: [
          { src: "/pwa-icon-192?v=#{icon_version}", sizes: "192x192", type: "image/png", purpose: "any maskable" },
          { src: "/pwa-icon-512?v=#{icon_version}", sizes: "512x512", type: "image/png", purpose: "any maskable" }
        ]
      }
    end

    def layout_setting
      tenant = current_admin_user&.tenant || Tenant.public_for
      LayoutSetting.find_by(tenant: tenant) || LayoutSetting.instance(tenant: tenant)
    end
  end
end
