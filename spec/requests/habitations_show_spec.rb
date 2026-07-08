require "rails_helper"

RSpec.describe "Habitation details", type: :request do
  before do
    host! "localhost"
  end

  def public_photo_url(filename)
    "#{Storage::PublicPropertyPhoto.public_base_url}/spec/#{filename}"
  end

  describe "GET /imoveis/:id" do
    it "renders a public habitation by slug" do
      habitation = create(:habitation, codigo: "8397", slug: "casa-em-condominio-8397")

      get habitation_path(habitation, format: :json)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("codigo")).to eq("8397")
    end

    it "não renderiza imóvel público de outro tenant pelo slug" do
      other_tenant = Tenant.create!(name: "Outro hab public #{SecureRandom.hex(3)}", slug: "outro-hab-public-#{SecureRandom.hex(3)}")
      habitation = create(:habitation, tenant: other_tenant, codigo: "TENANT-X", slug: "imovel-outro-tenant")

      get habitation_path(habitation)

      expect(response).to redirect_to(habitations_path)
      expect(flash[:alert]).to eq("Imóvel não encontrado ou indisponível no momento.")
    end

    it "não encontra imóvel de outro tenant pela busca por código" do
      other_tenant = Tenant.create!(name: "Outro hab public #{SecureRandom.hex(3)}", slug: "outro-hab-public-#{SecureRandom.hex(3)}")
      create(:habitation, tenant: other_tenant, codigo: "BUSCA-X", slug: "busca-outro-tenant")

      get search_by_code_path, params: { code: "BUSCA-X" }

      expect(response).to redirect_to(habitations_path(search: "BUSCA-X"))
      expect(flash[:alert]).to include("não encontrado")
    end

    it "falls back to the trailing code when the slug changed" do
      create(:habitation, codigo: "8397", slug: "slug-atual-8397")

      get "/imoveis/casa-em-condominio-8397.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("codigo")).to eq("8397")
    end

    it "treats a numeric public URL as the property code" do
      create(:habitation, codigo: "8397", slug: "casa-em-condominio-8397")

      get "/imoveis/8397.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("codigo")).to eq("8397")
    end

    it "redirects unavailable habitations to the listing" do
      habitation = create(:habitation, :unavailable, codigo: "8397", slug: "casa-em-condominio-8397")

      get habitation_path(habitation)

      expect(response).to redirect_to(habitations_path)
      expect(flash[:alert]).to eq("Imóvel não encontrado ou indisponível no momento.")
    end

    it "does not render past delivery dates" do
      habitation = create(
        :habitation,
        codigo: "7677",
        slug: "apartamento-balneario-camboriu-centro-7677",
        data_entrega: 1.month.ago.to_date
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Previsão de entrega")
      expect(response.body).not_to include("Entrega")
    end

    it "uses the first property photo as the social sharing image" do
      habitation = create(
        :habitation,
        codigo: "OG-IMG",
        slug: "apartamento-og-image",
        pictures: [
          { "url" => public_photo_url("first-property.jpg"), "ordem" => 1, "principal" => true }
        ]
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(property="og:image" content="#{public_photo_url("first-property.jpg")}"))
      expect(response.body).not_to include(%(property="og:image" content="http://localhost/icon.png"))
    end

    it "does not expose broker phone or direct whatsapp link in the responsible attendant card" do
      broker = create(:admin_user, name: "Eliane Rosa", creci: "CREI24685", phone: "(47) 99905-8447")
      habitation = create(:habitation, codigo: "BROKER-CARD", slug: "apartamento-broker-card")
      share_link = HabitationShareLink.create!(habitation: habitation, admin_user: broker)

      get habitation_path(habitation, share_token: share_link.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atendimento com corretor responsável")
      expect(response.body).to include("Eliane Rosa")
      expect(response.body).to include("CREI24685")
      expect(response.body).to include("Falar com corretor")
      expect(response.body).not_to include("(47) 99905-8447")
      expect(response.body).not_to include("https://wa.me/5547999058447")
      expect(response.body).not_to include(">WhatsApp<")
    end

    it "replaces past delivery dates with ready-to-move status when marked as ready" do
      habitation = create(
        :habitation,
        codigo: "7677",
        slug: "apartamento-balneario-camboriu-centro-7677",
        data_entrega: 1.month.ago.to_date,
        situacao: "Pronto para Morar"
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Previsão de entrega")
      expect(response.body).not_to include("Entrega")
      expect(response.body).to include("Situação")
      expect(response.body).to include("Pronto para morar")
    end

    it "renders future delivery dates with the full year" do
      habitation = create(
        :habitation,
        codigo: "7678",
        slug: "apartamento-balneario-camboriu-centro-7678",
        data_entrega: Date.new(2027, 2, 1)
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Previsão de entrega")
      expect(response.body).to include("01 de Fevereiro de 2027")
    end

    it "renders the RealEstateListing JSON-LD in the document head" do
      habitation = create(
        :habitation,
        codigo: "8397",
        slug: "casa-em-condominio-8397",
        cidade: "Balneário Camboriú",
        uf: "SC",
        dormitorios_qtd: 3,
        banheiros_qtd: 2
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      script = document.at_css("head script[type='application/ld+json']")
      payload = JSON.parse(script.text)

      expect(payload["@type"]).to eq("RealEstateListing")
      expect(payload["identifier"]).to eq("8397")
      expect(payload["url"]).to eq("http://localhost/imoveis/casa-em-condominio-8397")
      expect(document.css("body script[type='application/ld+json']")).to be_empty
    end

    it "adds readable spacing to plain text descriptions without spaces after punctuation" do
      habitation = create(
        :habitation,
        codigo: "DESC-SPACE",
        slug: "descricao-espacada",
        descricao_web: "Primeira frase.Segunda frase!Terceira frase?"
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Primeira frase. Segunda frase! Terceira frase?")
    end

    it "splits a long single-block rich text description into readable paragraphs" do
      long_description = [
        "Este apartamento localizado em Barra Norte apresenta uma área privativa ampla e bem distribuída.",
        "A unidade conta com quatro suítes e ambientes planejados para conforto e privacidade.",
        "O condomínio disponibiliza piscina coletiva, sala fitness, salão de festas e portaria vinte e quatro horas.",
        "A localização é estratégica e oferece acesso facilitado à orla, serviços, comércio e opções de lazer.",
        "Para obter mais detalhes sobre esta oportunidade, entre em contato com nossa equipe especializada.",
        "A Salute Imóveis está localizada em Balneário Camboriú e atende compradores e vendedores com acompanhamento consultivo.",
        "O imóvel reúne características importantes para quem busca praticidade, segurança e uma rotina próxima ao mar.",
        "Os valores e as condições comerciais podem sofrer alteração sem aviso prévio conforme disponibilidade."
      ].join(" ")
      habitation = create(
        :habitation,
        codigo: "DESC-RICH",
        slug: "descricao-rica",
        pictures: [{ "url" => public_photo_url("descricao.jpg") }],
        descricao_web: %(<div class="trix-content"><div>#{long_description}</div></div>)
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      description_section = document.css("section").detect { |section| section.text.include?("Descrição") && section.text.include?("Este apartamento localizado") }
      paragraphs = description_section.css("p").map { |paragraph| paragraph.text.squish }

      expect(paragraphs.size).to be >= 2
      expect(paragraphs.join(" ")).to include("Este apartamento localizado em Barra Norte")
      expect(paragraphs.join(" ")).to include("A Salute Imóveis está localizada em Balneário Camboriú")
    end

    it "does not show the development name in unit details" do
      development = create(:habitation, codigo: "DEV-UNIT", tipo: "Empreendimento", nome_empreendimento: "Residencial Oculto")
      unit = create(
        :habitation,
        codigo: "UNIT-DETAIL",
        slug: "unidade-sem-empreendimento",
        codigo_empreendimento: development.codigo,
        nome_empreendimento: "Residencial Oculto",
        titulo_anuncio: "Apartamento unidade",
        address_attributes: {
          logradouro: "Rua Unidade",
          numero: "101",
          bairro: "Centro",
          cidade: "Balneário Camboriú",
          uf: "SC"
        }
      )

      get habitation_path(unit)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Residencial Oculto")
    end

    it "does not expose the condominium name in regular property details" do
      habitation = create(
        :habitation,
        codigo: "PUBLIC-NO-CONDO",
        slug: "publico-sem-condominio",
        nome_empreendimento: "Blue Sky Residence",
        titulo_anuncio: "Apartamento à venda 3 suítes"
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Blue Sky Residence")
      expect(response.body).not_to include("Empreendimento</p>")
    end

    it "shows included taxes instead of strategic placeholder condominium and IPTU values" do
      habitation = create(
        :habitation,
        codigo: "TAX-INCLUDED",
        slug: "taxas-inclusas",
        status: "Aluguel",
        valor_venda_cents: 0,
        valor_locacao_cents: 5_000_00,
        valor_condominio_cents: 1,
        valor_iptu_cents: 100
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Taxas inclusas")
      expect(response.body).not_to include("R$ 0,01")
      expect(response.body).not_to include("R$ 1,00")
    end

    it "shows reduced rent in the public details page" do
      habitation = create(
        :habitation,
        codigo: "RENT-DISCOUNT",
        slug: "locacao-reduzida",
        status: "Aluguel",
        valor_venda_cents: 0,
        valor_locacao_anterior_cents: 6_000_00,
        valor_locacao_cents: 5_000_00
      )

      get habitation_path(habitation)

      expect(response).to have_http_status(:ok)
      page_text = Nokogiri::HTML(response.body).text.squish
      expect(page_text).to include("Locação com preço reduzido")
      expect(page_text).to include("R$ 6.000,00")
      expect(page_text).to include("R$ 5.000,00")
    end
  end

  describe "GET /empreendimento/:id" do
    it "uses the development name as the public URL slug" do
      development = create(
        :habitation,
        codigo: "4652",
        slug: nil,
        tipo: "Empreendimento",
        nome_empreendimento: "Nome do Empreendimento",
        valor_venda_cents: 0,
        pictures: [],
        fotos_empreendimento: [{ "url" => public_photo_url("development.jpg") }]
      )

      expect(development.slug).to eq("nome-do-empreendimento")
      expect(empreendimento_details_path(development)).to eq("/empreendimento/nome-do-empreendimento")

      get empreendimento_details_path(development)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nome do Empreendimento")
    end

    it "keeps legacy development URLs with a trailing code working" do
      development = create(
        :habitation,
        codigo: "4652",
        slug: "nome-do-empreendimento",
        tipo: "Empreendimento",
        nome_empreendimento: "Nome do Empreendimento",
        valor_venda_cents: 0,
        pictures: [],
        fotos_empreendimento: [{ "url" => public_photo_url("development.jpg") }]
      )

      get "/empreendimento/empreendimento-balneario-camboriu-centro-4652"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(development.nome_empreendimento)
    end
  end

  describe "GET /imoveis" do
    it "does not list developments" do
      development = create(
        :habitation,
        codigo: "9001",
        slug: "empreendimento-9001",
        tipo: "Empreendimento",
        nome_empreendimento: "Vista Atlântico",
        valor_venda_cents: 0,
        pictures: [],
        fotos_empreendimento: [{ "url" => public_photo_url("development.jpg") }]
      )
      create(
        :habitation,
        codigo: "9002",
        codigo_empreendimento: development.codigo,
        address_attributes: {
          logradouro: "Rua Unidade",
          numero: "102",
          bairro: "Centro",
          cidade: "Balneário Camboriú",
          uf: "SC"
        }
      )

      get habitations_path(format: :json)

      expect(response).to have_http_status(:ok)
      codes = JSON.parse(response.body).map { |item| item.fetch("codigo") }
      expect(codes).to include("9002")
      expect(codes).not_to include("9001")
    end

    it "does not return developments even with category=Empreendimento" do
      development = create(
        :habitation,
        codigo: "9001",
        slug: "empreendimento-9001",
        tipo: "Empreendimento",
        nome_empreendimento: "Vista Atlântico",
        valor_venda_cents: 0,
        pictures: [],
        fotos_empreendimento: [{ "url" => public_photo_url("development.jpg") }]
      )
      create(
        :habitation,
        codigo: "9002",
        codigo_empreendimento: development.codigo,
        address_attributes: {
          logradouro: "Rua Unidade",
          numero: "103",
          bairro: "Centro",
          cidade: "Balneário Camboriú",
          uf: "SC"
        }
      )

      get habitations_path(category: "Empreendimento", format: :json)

      expect(response).to have_http_status(:ok)
      codes = JSON.parse(response.body).map { |item| item.fetch("codigo") }
      expect(codes).to be_empty
    end

    it "does not list DWV development records without a type" do
      create(
        :habitation,
        codigo: "DWV-625786",
        slug: "apartamento-dwv-625786",
        tipo: nil,
        categoria: "Apartamento",
        titulo_anuncio: "NF Raro By Sierra",
        imovel_dwv: "Sim",
        situacao: "Pré Lançamento"
      )

      get habitations_path(format: :json)

      expect(response).to have_http_status(:ok)
      codes = JSON.parse(response.body).map { |item| item.fetch("codigo") }
      expect(codes).not_to include("DWV-625786")
    end

    it "filters listing requests with array params sent by the home search" do
      matching = create(
        :habitation,
        codigo: "9101",
        categoria: "Apartamento",
        valor_venda_cents: 1_000_000_00,
        valor_locacao_cents: 0
      ).tap { |habitation| habitation.address.update!(cidade: "Balneário Camboriú", bairro: "Centro") }
      create(
        :habitation,
        codigo: "9102",
        categoria: "Casa",
        valor_venda_cents: 1_000_000_00,
        valor_locacao_cents: 0
      ).tap { |habitation| habitation.address.update!(cidade: "Balneário Camboriú", bairro: "Centro") }
      create(
        :habitation,
        codigo: "9103",
        categoria: "Apartamento",
        valor_venda_cents: 1_000_000_00,
        valor_locacao_cents: 0
      ).tap { |habitation| habitation.address.update!(cidade: "Itajaí", bairro: "Centro") }

      get habitations_path(
        category: ["Apartamento"],
        city: ["Centro - Balneário Camboriú"],
        transaction_type: "venda",
        format: :json
      )

      expect(response).to have_http_status(:ok)
      codes = JSON.parse(response.body).map { |item| item.fetch("codigo") }
      expect(codes).to include(matching.codigo)
      expect(codes).not_to include("9102", "9103")
    end

    it "accepts legacy home search param names" do
      matching = create(
        :habitation,
        codigo: "9201",
        categoria: "Apartamento",
        cidade: "Balneário Camboriú",
        bairro: "Centro",
        valor_venda_cents: 1_000_000_00,
        valor_locacao_cents: 0
      )
      create(
        :habitation,
        codigo: "9202",
        categoria: "Apartamento",
        cidade: "Balneário Camboriú",
        bairro: "Centro",
        valor_venda_cents: 0,
        valor_locacao_cents: 4_000_00
      )

      get habitations_path(
        finalidade: "Venda",
        tipo: "Apartamento",
        cidade: "Centro - Balneário Camboriú",
        format: :json
      )

      expect(response).to have_http_status(:ok)
      codes = JSON.parse(response.body).map { |item| item.fetch("codigo") }
      expect(codes).to include(matching.codigo)
      expect(codes).not_to include("9202")
    end

    it "filters by fixed price ranges" do
      matching = create(:habitation, codigo: "9301", valor_venda_cents: 1_500_000_00)
      create(:habitation, codigo: "9302", valor_venda_cents: 3_500_000_00)

      get habitations_path(price_range: "1000000-2000000", transaction_type: "venda", format: :json)

      expect(response).to have_http_status(:ok)
      codes = JSON.parse(response.body).map { |item| item.fetch("codigo") }
      expect(codes).to include(matching.codigo)
      expect(codes).not_to include("9302")
    end

    it "filters rent by rental price ranges" do
      matching = create(:habitation, codigo: "9401", status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 7_500_00)
      create(:habitation, codigo: "9402", status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 18_000_00)
      create(
        :habitation,
        codigo: "9403",
        status: "Aluguel",
        valor_venda_cents: 0,
        valor_locacao_cents: 4_000_00,
        valor_condominio_cents: 3_000_00,
        valor_iptu_cents: 1_000_00,
        valor_total_aluguel_cents: 8_000_00
      )

      get habitations_path(price_range: "5000-10000", transaction_type: "aluguel", format: :json)

      expect(response).to have_http_status(:ok)
      codes = JSON.parse(response.body).map { |item| item.fetch("codigo") }
      expect(codes).to include(matching.codigo)
      expect(codes).not_to include("9402")
      expect(codes).not_to include("9403")
    end
  end
end
