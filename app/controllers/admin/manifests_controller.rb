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
          response.headers["Cache-Control"] = "private, max-age=300"
          response.headers["Vary"] = "Cookie"
          render json: manifest_payload
        end
      end
    end

    private

    def manifest_payload
      layout = layout_setting
      tenant = manifest_tenant
      brand = layout.site_name.to_s.strip.presence || tenant&.name.to_s.strip.presence || "Unitymob"
      icon_version = layout.updated_at.to_i

      {
        id: tenant&.slug.present? ? "/admin?tenant=#{tenant.slug}" : "/admin",
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
          { src: admin_icon_src(192, tenant, icon_version), sizes: "192x192", type: "image/png", purpose: "any maskable" },
          { src: admin_icon_src(512, tenant, icon_version), sizes: "512x512", type: "image/png", purpose: "any maskable" }
        ]
      }
    end

    def layout_setting
      tenant = manifest_tenant
      LayoutSetting.find_by(tenant: tenant) || LayoutSetting.instance(tenant: tenant)
    end

    def manifest_tenant
      @manifest_tenant ||= current_admin_user&.tenant || public_tenant
    end

    def admin_icon_src(size, tenant, icon_version)
      tenant&.slug.present? ? "/pwa-icon-#{size}?tenant=#{tenant.slug}&v=#{icon_version}" : "/pwa-icon-#{size}?v=#{icon_version}"
    end
  end
end
