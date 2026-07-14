class PersistDefaultTenantPublicProfile < ActiveRecord::Migration[7.1]
  PROFILE_VALUES = {
    "primary_city" => "Balneário Camboriú",
    "legal_name" => "Salute Locação de Imóveis Ltda - ME",
    "legal_document" => "63.057.499/0001-93",
    "legal_address" => "Av. Atlântica, 3750 - Sala E, Balneário Camboriú - SC, CEP 88330-024",
    "privacy_email" => "privacidade@saluteimoveis.com",
    "creci" => "6834",
    "institutional_mission" => "Proporcionar as melhores soluções imobiliárias, com transparência, ética e excelência no atendimento.",
    "institutional_vision" => "Ser referência no mercado imobiliário, reconhecida pela qualidade dos serviços e satisfação dos clientes.",
    "institutional_values" => "Integridade, comprometimento, inovação e respeito em todas as nossas relações.",
    "useful_links" => [
      "Consulta IPTU|https://www.balneariocamboriu.sc.gov.br/|Consulte e emita segunda via do IPTU|file-text",
      "Cartórios|https://www.cnj.jus.br/servicos-e-consultas/|Consulta de certidões e registros|building",
      "Prefeitura|https://www.balneariocamboriu.sc.gov.br/|Portal da Prefeitura de Balneário Camboriú|house-door",
      "FGTS|https://www.fgts.gov.br/|Consulta saldo e extrato do FGTS|piggy-bank",
      "Caixa Econômica|https://www.caixa.gov.br/voce/habitacao/Paginas/default.aspx|Financiamento habitacional|bank",
      "Simulador Caixa|https://www.caixa.gov.br/voce/habitacao/simulador/Paginas/default.aspx|Simule seu financiamento|calculator"
    ].join("\n")
  }.freeze

  def up
    tenant_id = select_value(<<~SQL.squish)
      SELECT id FROM tenants
      WHERE slug = #{connection.quote(ENV.fetch("DEFAULT_TENANT_SLUG", "default"))}
      ORDER BY id ASC LIMIT 1
    SQL
    return if tenant_id.blank?

    now = connection.quote(Time.current)
    PROFILE_VALUES.each do |field, value|
      key = "public_site.profile.#{field}"
      execute <<~SQL.squish
        INSERT INTO settings (tenant_id, key, value, description, created_at, updated_at)
        VALUES (
          #{connection.quote(tenant_id)},
          #{connection.quote(key)},
          #{connection.quote(value)},
          #{connection.quote("Perfil público migrado: #{field}")},
          #{now},
          #{now}
        )
        ON CONFLICT (tenant_id, key) WHERE tenant_id IS NOT NULL DO NOTHING
      SQL
    end


    execute <<~SQL.squish
      INSERT INTO layout_settings
        (tenant_id, site_name, primary_color, secondary_color, accent_color, admin_primary_color, created_at, updated_at)
      VALUES
        (#{connection.quote(tenant_id)}, 'Salute Imóveis', '#022B3A', '#053C5E', '#BFAB25', '#365F8F', #{now}, #{now})
      ON CONFLICT (tenant_id) DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO contact_settings
        (tenant_id, whatsapp_primary, phone, email_primary, address, business_hours, created_at, updated_at)
      VALUES
        (#{connection.quote(tenant_id)}, '5547991234567', '554733111067', 'contato@saluteimoveis.com', 'Balneário Camboriú - SC', E'Segunda a Sexta: 08:00 - 18:00\\nSábado: 09:00 - 13:00\\nDomingo: Fechado', #{now}, #{now})
      ON CONFLICT (tenant_id) DO NOTHING
    SQL

    execute <<~SQL.squish
      UPDATE contact_settings
      SET business_hours = E'Segunda a Sexta: 08:00 - 18:00\\nSábado: 09:00 - 13:00\\nDomingo: Fechado', updated_at = #{now}
      WHERE tenant_id = #{connection.quote(tenant_id)}
        AND NULLIF(TRIM(business_hours), '') IS NULL
    SQL

    execute <<~SQL.squish
      INSERT INTO footer_settings
        (tenant_id, about_title, about_text, links_title, stores_title, contact_title, social_title, whatsapp, email, copyright_text, created_at, updated_at)
      VALUES (
        #{connection.quote(tenant_id)},
        'Salute Imóveis',
        'Sua imobiliária de confiança em Balneário Camboriú. Tradição e excelência no mercado imobiliário desde sempre.',
        'Links Rápidos', 'Nossas Lojas', 'Contato', 'Redes Sociais',
        '5547988630198', 'contato@saluteimoveis.com',
        '© 2026 Salute Imóveis. Todos os direitos reservados. CRECI 6834',
        #{now}, #{now}
      )
      ON CONFLICT (tenant_id) DO NOTHING
    SQL
  end

  def down
    tenant_id = select_value("SELECT id FROM tenants WHERE slug = #{connection.quote(ENV.fetch('DEFAULT_TENANT_SLUG', 'default'))} ORDER BY id ASC LIMIT 1")
    return if tenant_id.blank?

    keys = PROFILE_VALUES.keys.map { |field| connection.quote("public_site.profile.#{field}") }.join(", ")
    execute "DELETE FROM settings WHERE tenant_id = #{connection.quote(tenant_id)} AND key IN (#{keys})"
  end
end
