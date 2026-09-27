class PublicThemeGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  class_option :label, type: :string, desc: "Rótulo no select de Modelo visual (padrão: nome humanizado)"
  class_option :tenant_slugs, type: :string, desc: "Contas em CSV (ex.: salute). Omitido = global, como o Padrão"

  def create_stylesheet
    template "theme.css.tt", "app/assets/stylesheets/public_site_themes/#{file_name}.css"
  end

  def register_metadata
    # Destroy não repete as opções do generate, então o revoke! nativo do
    # inject (que recalcula o bloco) nunca casa: revertemos pela chave, com
    # force: true, única forma do gsub_file rodar fora de :invoke no Thor.
    if self.behavior == :revoke
      gsub_file "app/models/tenant.rb",
                /^    "#{Regexp.escape(file_name)}" => \{\n(?:.*\n)*?    \},\n/,
                "", force: true
      return
    end
    return if self.behavior == :pretend
    slugs = options[:tenant_slugs].to_s.split(",").map(&:strip).reject(&:blank?)
    lines = ["    \"#{file_name}\" => {"]
    lines << "      label: \"#{options[:label].presence || file_name.humanize}\","
    lines << "      description: \"Tema #{file_name} (#{file_name}.css).\","
    lines << "      tenant_slugs: #{slugs.inspect}," if slugs.any?
    # Variante default: o tema herda todos os componentes compartilhados; o
    # CSS gerado é só a pele. Desenho próprio = trocar partials aqui depois.
    lines << "      variant: \"default\","
    lines << "      components: DEFAULT_THEME_COMPONENTS"
    lines << "    },"
    # Âncora: o fecho de PUBLIC_SITE_THEME_METADATA (o primeiro "}.freeze" do
    # arquivo é o de DEFAULT_THEME_COMPONENTS).
    inject_into_file "app/models/tenant.rb", before: "  }.freeze\n\n  # Temas = folhas CSS do diretório" do
      "#{lines.join("\n")}\n"
    end
  end
end
