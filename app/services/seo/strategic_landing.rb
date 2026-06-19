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

    def self.property(slug)
      PROPERTY_PAGES[slug.to_s]
    end

    def self.development(slug)
      DEVELOPMENT_PAGES[slug.to_s]
    end

    def self.property_links
      PROPERTY_PAGES.map { |slug, data| data.merge(slug: slug, path: "/imoveis/#{slug}") }
    end

    def self.development_links
      DEVELOPMENT_PAGES.map { |slug, data| data.merge(slug: slug, path: "/empreendimentos/#{slug}") }
    end

    def self.site_name
      LayoutSetting.instance.site_name.presence || "Unitymob"
    rescue StandardError
      "Unitymob"
    end

    def self.property_intro(data)
      <<~TEXT.squish
        #{data[:title]} reúnem oportunidades selecionadas para quem busca morar, investir ou comparar opções com localização estratégica em Balneário Camboriú, Praia Brava e região. Nesta página, a #{site_name} organiza imóveis com características relevantes para facilitar uma busca mais objetiva, reduzindo o tempo de análise e aproximando você das alternativas com maior aderência ao seu momento.

        Use os filtros para refinar por tipo de imóvel, faixa de valor, dormitórios, suítes, vagas e diferenciais como frente mar, quadra mar, mobiliado, pronto para morar ou lançamento. Se a intenção for investir, observe também localização, liquidez, padrão do empreendimento e potencial de valorização. Para morar, avalie rotina, proximidade da praia, serviços, escolas, comércio e mobilidade.
      TEXT
    end

    def self.development_intro(data)
      <<~TEXT.squish
        #{data[:title]} apresentam opções para quem deseja comprar para morar, investir ou acompanhar novos projetos em regiões valorizadas do litoral catarinense. Um empreendimento pode estar em fase de lançamento, obras ou pronto para morar, e cada estágio atende a uma intenção diferente: planejamento patrimonial, valorização futura, mudança imediata ou escolha de uma unidade específica.

        Nesta listagem, você pode comparar projetos por localização, estágio, disponibilidade de unidades e diferenciais como vista mar, frente mar, lazer, padrão construtivo e proximidade com a praia. Use a busca por nome do empreendimento ou navegue pelos bairros estratégicos para encontrar oportunidades alinhadas ao seu perfil, seja para uso próprio ou investimento imobiliário.
      TEXT
    end
  end
end
