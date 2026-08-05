class NeutralizeLegacyPublicHomeDefaults < ActiveRecord::Migration[7.1]
  LEGACY_HERO_TITLE = "Compre ou alugue na imobiliária mais amada de Balneário Camboriú.".freeze
  LEGACY_HERO_SUBTITLE = "Aqui o lar é o centro das grandes histórias da vida.".freeze
  LEGACY_CTA_TITLE = "Pronto para Encontrar Seu Imóvel?".freeze
  LEGACY_CTA_SUBTITLE = "Entre em contato conosco e descubra as melhores oportunidades do mercado.".freeze

  def up
    execute <<~SQL.squish
      UPDATE home_settings
         SET hero_title = 'Encontre o imóvel ideal com a ' || tenants.name || '.',
             hero_subtitle = 'Compra, locação e oportunidades imobiliárias em um só lugar.',
             cta_title = 'Pronto para encontrar seu imóvel?',
             cta_subtitle = 'Entre em contato e descubra as melhores oportunidades para o seu momento.',
             updated_at = CURRENT_TIMESTAMP
        FROM tenants
       WHERE home_settings.tenant_id = tenants.id
         AND tenants.slug <> 'default'
         AND home_settings.hero_title = #{quote(LEGACY_HERO_TITLE)}
         AND home_settings.hero_subtitle = #{quote(LEGACY_HERO_SUBTITLE)}
         AND home_settings.cta_title = #{quote(LEGACY_CTA_TITLE)}
         AND home_settings.cta_subtitle = #{quote(LEGACY_CTA_SUBTITLE)}
    SQL
  end

  def down
    # Irreversível de propósito: não reintroduzimos copy da Salute em tenants não-default.
  end
end
