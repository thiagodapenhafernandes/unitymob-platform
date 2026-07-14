module Seo
  class StrategicLanding
    PROPERTY_PAGES = {
      "frente-mar" => {
        label: "Frente mar",
        title: "Imóveis frente mar",
        params: { characteristics: ["frente_mar"] },
        description: "Seleção de imóveis frente mar para comprar ou investir em Balneário Camboriú e região."
      },
      "quadra-mar" => {
        label: "Quadra mar",
        title: "Imóveis quadra mar",
        params: { characteristics: ["quadra_mar"] },
        description: "Imóveis em quadra mar com localização valorizada e acesso prático à praia."
      },
      "lancamentos" => {
        label: "Lançamentos",
        title: "Lançamentos imobiliários",
        params: { characteristics: ["lancamento"] },
        description: "Lançamentos imobiliários para morar ou investir em Balneário Camboriú, Praia Brava e região."
      },
      "prontos-para-morar" => {
        label: "Pronto para morar",
        title: "Imóveis prontos para morar",
        params: { characteristics: ["pronto"] },
        description: "Imóveis prontos para morar com opções selecionadas com curadoria."
      },
      "centro" => {
        label: "Centro",
        title: "Imóveis no Centro",
        params: { city: ["Centro - Balneário Camboriú"] },
        description: "Imóveis no Centro de Balneário Camboriú para compra, locação ou investimento."
      },
      "barra-sul" => {
        label: "Barra Sul",
        title: "Imóveis na Barra Sul",
        params: { city: ["Barra Sul - Balneário Camboriú"] },
        description: "Imóveis na Barra Sul com alto potencial de valorização e localização estratégica."
      },
      "praia-brava" => {
        label: "Praia Brava",
        title: "Imóveis na Praia Brava",
        params: { city: ["Praia Brava - Itajaí"] },
        description: "Imóveis na Praia Brava para quem busca morar perto do mar ou investir em uma região valorizada."
      }
    }.freeze

    DEVELOPMENT_PAGES = {
      "balneario-camboriu" => {
        label: "Balneário Camboriú",
        title: "Empreendimentos em Balneário Camboriú",
        params: { city: ["Balneário Camboriú"] },
        description: "Empreendimentos em Balneário Camboriú para morar, investir ou acompanhar lançamentos."
      },
      "praia-brava" => {
        label: "Praia Brava",
        title: "Empreendimentos na Praia Brava",
        params: { city: ["Praia Brava - Itajaí"] },
        description: "Empreendimentos na Praia Brava para quem busca localização, valorização e qualidade de vida."
      },
      "centro" => {
        label: "Centro",
        title: "Empreendimentos no Centro",
        params: { city: ["Centro - Balneário Camboriú"] },
        description: "Empreendimentos no Centro de Balneário Camboriú com acesso a serviços, praia e comércio."
      },
      "barra-sul" => {
        label: "Barra Sul",
        title: "Empreendimentos na Barra Sul",
        params: { city: ["Barra Sul - Balneário Camboriú"] },
        description: "Empreendimentos na Barra Sul, uma das regiões mais desejadas de Balneário Camboriú."
      },
      "frente-mar" => {
        label: "Frente mar",
        title: "Empreendimentos frente mar",
        params: { characteristics: ["frente_mar"] },
        description: "Empreendimentos frente mar para quem busca vista, localização e potencial de valorização."
      },
      "vista-mar" => {
        label: "Vista mar",
        title: "Empreendimentos com vista mar",
        params: { characteristics: ["vista_mar"] },
        description: "Empreendimentos com vista mar em regiões valorizadas de Balneário Camboriú e Praia Brava."
      },
      "lancamentos" => {
        label: "Lançamentos",
        title: "Lançamentos em Balneário Camboriú",
        params: { characteristics: ["lancamento"] },
        description: "Lançamentos imobiliários para acompanhar novas oportunidades em Balneário Camboriú e região."
      },
      "prontos-para-morar" => {
        label: "Pronto para morar",
        title: "Empreendimentos prontos para morar",
        params: { characteristics: ["pronto"] },
        description: "Empreendimentos prontos para morar para quem busca mudança planejada e segurança na escolha."
      }
    }.freeze

    PROPERTY_LOCATION_SLUGS = %w[centro barra-sul praia-brava].freeze
    DEVELOPMENT_LOCATION_SLUGS = %w[balneario-camboriu praia-brava centro barra-sul].freeze

    def self.property(slug, tenant: current_tenant)
      property_pages(tenant: tenant)[slug.to_s]
    end

    def self.development(slug, tenant: current_tenant)
      development_pages(tenant: tenant)[slug.to_s]
    end

    def self.property_links(tenant: current_tenant)
      property_pages(tenant: tenant).map { |slug, data| data.merge(slug: slug, path: "/imoveis/#{slug}") }
    end

    def self.development_links(tenant: current_tenant)
      development_pages(tenant: tenant).map { |slug, data| data.merge(slug: slug, path: "/empreendimentos/#{slug}") }
    end

    def self.property_pages(tenant: current_tenant)
      localized_pages(PROPERTY_PAGES, tenant: tenant, location_slugs: PROPERTY_LOCATION_SLUGS)
    end

    def self.development_pages(tenant: current_tenant)
      localized_pages(DEVELOPMENT_PAGES, tenant: tenant, location_slugs: DEVELOPMENT_LOCATION_SLUGS)
    end

    def self.site_name(tenant: current_tenant)
      Tenants::PublicIdentity.new(tenant).name
    end

    def self.property_intro(data, tenant: current_tenant)
      city = Tenants::PublicIdentity.new(tenant).primary_city.presence || "sua região"
      <<~TEXT.squish
        #{data[:title]} reúnem oportunidades selecionadas para quem busca morar, investir ou comparar opções com localização estratégica em #{city} e região. Nesta página, a #{site_name(tenant: tenant)} organiza imóveis com características relevantes para facilitar uma busca mais objetiva, reduzindo o tempo de análise e aproximando você das alternativas com maior aderência ao seu momento.

        Use os filtros para refinar por tipo de imóvel, faixa de valor, dormitórios, suítes, vagas e diferenciais como frente mar, quadra mar, mobiliado, pronto para morar ou lançamento. Se a intenção for investir, observe também localização, liquidez, padrão do empreendimento e potencial de valorização. Para morar, avalie rotina, proximidade da praia, serviços, escolas, comércio e mobilidade.
      TEXT
    end

    def self.development_intro(data, tenant: current_tenant)
      <<~TEXT.squish
        #{data[:title]} apresentam opções para quem deseja comprar para morar, investir ou acompanhar novos projetos em regiões valorizadas do litoral catarinense. Um empreendimento pode estar em fase de lançamento, obras ou pronto para morar, e cada estágio atende a uma intenção diferente: planejamento patrimonial, valorização futura, mudança imediata ou escolha de uma unidade específica.

        Nesta listagem, você pode comparar projetos por localização, estágio, disponibilidade de unidades e diferenciais como vista mar, frente mar, lazer, padrão construtivo e proximidade com a praia. Use a busca por nome do empreendimento ou navegue pelos bairros estratégicos para encontrar oportunidades alinhadas ao seu perfil, seja para uso próprio ou investimento imobiliário.
      TEXT
    end

    def self.localized_pages(source, tenant:, location_slugs:)
      tenant ||= Tenant.public_for
      pages = source
      pages = pages.except(*location_slugs) unless tenant.slug == Tenant::DEFAULT_SLUG

      identity = Tenants::PublicIdentity.new(tenant)
      city = identity.primary_city.presence || "sua região"
      pages.transform_values do |data|
        data.deep_dup.tap do |localized|
          %i[title description].each do |field|
            localized[field] = localized[field].to_s
              .gsub("Balneário Camboriú, Praia Brava e região", "#{city} e região")
              .gsub("Balneário Camboriú e região", "#{city} e região")
              .gsub("Balneário Camboriú", city)
          end
        end
      end
    end

    def self.current_tenant
      Current.tenant || Tenant.public_for
    end
    private_class_method :localized_pages, :current_tenant
  end
end
