require "rails_helper"

RSpec.describe "API de captação de imóveis", type: :request do
  before { host! "localhost" }


  let(:token) { SecureRandom.hex(32) }
  let!(:tenant) do
    Tenant.create!(name: "Captação", slug: "captacao-api",
                   property_intake_token_digest: Digest::SHA256.hexdigest(token))
  end
  let(:payload) do
    {
      external_id: "CAP-123", captured_at: "2026-11-06T14:30:00-03:00",
      captador: { external_id: "CAPTADOR-002", nome: "Mariana Exemplo" },
      proprietario: { nome: "Carlos Exemplo", telefone: "+5551999990000" },
      imovel: {
        categoria: "apartamento", modalidade: "venda", titulo: "Apartamento com varanda",
        descricao: "Apartamento com varanda.", valor_venda_centavos: 85_000_000,
        quartos: 3, area_privativa_m2: 92.5,
        endereco: { cep: "90000-000", logradouro: "Rua Exemplo", numero: "120",
                    bairro: "Centro", cidade: "Porto Alegre", uf: "RS" }
      }
    }
  end

  def send_intake(body = payload, credential: token)
    post "/api/v1/property_intakes", params: body,
         headers: { "Authorization" => "Bearer #{credential}" }, as: :json
  end

  it "cria uma captação na fila da conta, mantém o protocolo no reenvio e rejeita alterações" do
    expect { send_intake }.to change { tenant.habitations.count }.by(1)
    expect(response).to have_http_status(:created)
    original = response.parsed_body
    receipt = PropertyIntakeReceipt.for_tenant(tenant).find_by!(external_id: "CAP-123")
    expect(original).to eq("protocolo" => receipt.protocol, "external_id" => "CAP-123",
                           "status" => "pendente_revisao")
    expect(receipt.captador_external_id).to eq("CAPTADOR-002")
    expect(receipt.habitation).to have_attributes(
      intake_status: "submitted_for_admin_review", exibir_no_site_flag: false,
      categoria: "Apartamento", valor_venda_cents: 85_000_000
    )
    expect(receipt.habitation.address.logradouro).to eq("Rua Exemplo")

    expect { send_intake(payload.to_a.reverse.to_h) }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(original)

    expect { send_intake(payload.merge(captured_at: "2026-11-06T15:30:00-03:00")) }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:conflict)
  end

  it "isola IDs e a conta de destino pelo token" do
    other_token = SecureRandom.hex(32)
    other = Tenant.create!(name: "Outra conta", slug: "outra-captacao-api",
                           property_intake_token_digest: Digest::SHA256.hexdigest(other_token))
    send_intake
    send_intake(payload.merge(tenant_id: tenant.id), credential: other_token)

    expect(response).to have_http_status(:created)
    expect(tenant.habitations.count).to eq(1)
    expect(other.habitations.count).to eq(1)
  end

  it "importa a foto antes de confirmar o protocolo e não baixa de novo no reenvio" do
    url = "https://midia.example.com/sala.png"
    payload[:imovel][:fotos] = [{ url: url, ordem: 1 }]
    policy = Automation::WebhookUrlPolicy
    allow(policy).to receive(:resolve).with("midia.example.com").and_return([IPAddr.new("93.184.215.14")])
    http = Net::HTTP.new("midia.example.com", 443, nil)
    allow(Net::HTTP).to receive(:new).with("midia.example.com", 443, nil).and_return(http)
    photo_response = Net::HTTPOK.new("1.1", "200", "OK")
    image = File.binread(Rails.root.join("spec/fixtures/files/watermark.png"))
    allow(photo_response).to receive(:read_body).and_yield(image)
    expect(http).to receive(:request).once.and_yield(photo_response)

    send_intake
    expect(response).to have_http_status(:created)
    habitation = PropertyIntakeReceipt.for_tenant(tenant).sole.habitation
    expect(habitation.ordered_photos.first.download).to eq(image)
    expect(habitation.photo_ids_order).to eq(habitation.photos.attachments.ids)

    send_intake
    expect(response).to have_http_status(:ok)
  end

  it "rejeita credenciais inválidas e fotos em destinos privados sem criar registros" do
    expect { send_intake(credential: SecureRandom.hex(32)) }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:unauthorized)

    payload[:imovel][:fotos] = [{ url: "https://127.0.0.1/foto.jpg", ordem: 1 }]
    expect { send_intake }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
  it "recebe os campos adicionais sem título e descrição e vincula o captador da conta" do
    user = create(:admin_user, tenant: tenant, email: "captador@example.com")
    payload[:captador][:email] = " CAPTADOR@example.com "
    payload[:imovel].except!(:titulo, :descricao)
    payload[:imovel].merge!(categoria: "casa_em_condominio", torre: "B", demi_suites: 2,
      nome_condominio: "Condomínio Exemplo", area_total_m2: 120.5, tipo_vaga: "Privativa",
      box: "12", onde_estao_as_chaves: "Portaria", permuta: true, parcelamento: false,
      administracao_locacao: true, tipo_cadastro: "Unitário", observacoes_internas: "Interna",
      observacoes_restritas: "Restrita")
    send_intake
    expect(response).to have_http_status(:created)
    property = PropertyIntakeReceipt.for_tenant(tenant).sole.habitation
    expect(property).to have_attributes(bloco: "B", demi_suites_qtd: 2,
      nome_empreendimento: "Condomínio Exemplo", area_total_m2: 120.5,
      tipo_vaga: "Privativa", numero_box: "12", key_location: "Portaria",
      aceita_permuta_flag: true, aceita_parcelamento_flag: false,
      rental_management_flag: true, tipo: "Unitário", descricao_interna: "Interna",
      observacoes: "Restrita", intake_status: "submitted_for_admin_review", exibir_no_site_flag: false)
    expect(property.broker_assignments.sole).to have_attributes(admin_user_id: user.id, role: "captador")
  end

  it "não vincula captador de outra conta nem inativo" do
    other = Tenant.create!(name: "Outra", slug: "outra-captador")
    user = create(:admin_user, tenant: other)
    payload[:captador][:email] = user.email
    expect { send_intake }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    user = create(:admin_user, tenant: tenant, active: false)
    payload[:captador][:email] = user.email
    expect { send_intake }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "rejeita booleanos ambíguos e tipos de documento desconhecidos" do
    payload[:imovel][:permuta] = "false"
    expect { send_intake }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    payload[:imovel].delete(:permuta)
    payload[:documentos] = [{ tipo: "publico", url: "https://example.com/doc.pdf" }]
    expect { send_intake }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "anexa autorização e documentos nas coleções internas e preserva a idempotência" do
    payload[:documentos] = [{ tipo: "autorizacao", url: "https://example.com/autorizacao.pdf" },
                            { tipo: "documento", url: "https://example.com/documento.pdf" }]
    payload[:documentos].each do |doc|
      file = Tempfile.new(["intake", ".pdf"], binmode: true)
      file.write("%PDF-1.4\nDocumento de teste")
      file.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "documento.pdf", type: "application/pdf")
      expect(Habitations::ExternalIntakePhoto).to receive(:download).with(doc[:url], document: true).once.and_return(upload)
    end
    send_intake
    expect(response).to have_http_status(:created)
    property = PropertyIntakeReceipt.for_tenant(tenant).sole.habitation
    expect(property.autorizacoes_venda.count).to eq(1)
    expect(property.documentos.count).to eq(1)
    expect(property.photos).not_to be_attached
    expect(property.documentos.first.blob.metadata["tenant_id"]).to eq(tenant.id)
    send_intake
    expect(response).to have_http_status(:ok)
    expect(property.reload.documentos.count).to eq(1)
  end

  it "consulta por endereço incluindo revisão, sem expor outra conta ou dados internos" do
    send_intake
    property = PropertyIntakeReceipt.for_tenant(tenant).sole.habitation
    other_token = SecureRandom.hex(32)
    other = Tenant.create!(name: "Outra", slug: "outra-busca",
      property_intake_token_digest: Digest::SHA256.hexdigest(other_token))
    send_intake(payload, credential: other_token)
    get "/api/v1/properties/search", params: { cep: "90000000", numero: "120", logradouro: "rua exemplo" },
      headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)
    items = response.parsed_body.fetch("imoveis")
    expect(items.size).to eq(1)
    expect(items.first).to include("codigo" => property.codigo, "status" => "em_revisao", "modalidade" => "venda")
    expect(items.first.keys).to match_array(%w[codigo endereco torre categoria modalidade status])
    get "/api/v1/properties/search", params: { cep: "90000-000", numero: "121" },
      headers: { "Authorization" => "Bearer #{token}" }
    expect(response.parsed_body).to eq("imoveis" => [])
  end

  it "exige token válido e filtros suficientes para consultar" do
    get "/api/v1/properties/search"
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/properties/search", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "não grava captação nem anexos quando um documento falha" do
    payload[:documentos] = [{ tipo: "autorizacao", url: "https://127.0.0.1/autorizacao.pdf" }]
    expect { send_intake }.not_to change(Habitation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(PropertyIntakeReceipt.for_tenant(tenant)).to be_empty
  end

  it "distingue complemento, torre e status comercial na busca" do
    send_intake
    property = PropertyIntakeReceipt.for_tenant(tenant).sole.habitation
    property.update!(bloco: "A", status: "Suspenso", motivo_suspensao: "Teste")
    property.address.update!(complemento: "Apto 10")
    headers = { "Authorization" => "Bearer #{token}" }
    filters = { numero: "120", logradouro: "RUA EXEMPLO", cidade: "Porto Alegre", uf: "rs", torre: "a", complemento: "apto 10" }
    get "/api/v1/properties/search", params: filters, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("imoveis").size).to eq(1)
    property.update!(intake_status: "internal")
    get "/api/v1/properties/search", params: filters, headers: headers
    expect(response.parsed_body.fetch("imoveis").sole.fetch("status")).to eq("inativo")
    get "/api/v1/properties/search", params: filters.merge(complemento: ""), headers: headers
    expect(response.parsed_body).to eq("imoveis" => [])
    get "/api/v1/properties/search", params: filters.merge(torre: "B"), headers: headers
    expect(response.parsed_body).to eq("imoveis" => [])
  end

  describe "características e tipo de logradouro" do
    let!(:feature) { tenant.attribute_options.create!(context: "habitation", category: "feature", name: "Área de serviço") }
    let!(:infrastructure) { tenant.attribute_options.create!(context: "habitation", category: "infrastructure", name: "Piscina") }

    it "recebe nomes e IDs, elimina repetidos, mantém endereço separado e permite reenvio" do
      payload[:imovel][:caracteristicas_internas] = [feature.id, "area de servico", feature.id.to_s]
      payload[:imovel][:infraestrutura_lazer] = [infrastructure.name, infrastructure.id]
      payload[:imovel][:endereco].merge!(tipo_logradouro: "Avenida", logradouro: "Exemplo")
      send_intake
      expect(response).to have_http_status(:created)
      property = PropertyIntakeReceipt.for_tenant(tenant).sole.habitation
      expect(property.property_features_for_display).to eq([feature.name])
      expect(property.leisure_features_for_display).to eq([infrastructure.name])
      expect(property.address).to have_attributes(tipo_endereco: "Avenida", logradouro: "Exemplo")
      expect(property.tipo_endereco).to eq("Avenida")
      expect { send_intake }.not_to change(Habitation, :count)
      expect(response).to have_http_status(:ok)
    end

    it "aceita listas vazias" do
      payload[:imovel].merge!(caracteristicas_internas: [], infraestrutura_lazer: [])
      send_intake
      expect(response).to have_http_status(:created)
      property = PropertyIntakeReceipt.for_tenant(tenant).sole.habitation
      expect(property.property_features_for_display).to eq([])
      expect(property.leisure_features_for_display).to eq([])
    end

    it "rejeita opção de outra conta, categoria ou contexto, sem criar captação" do
      other = Tenant.create!(name: "Outro catálogo", slug: "outro-catalogo")
      foreign = other.attribute_options.create!(context: "habitation", category: "feature", name: "Adega exclusiva")
      lead_option = tenant.attribute_options.create!(context: "lead", category: "source", name: "Origem exclusiva")
      [foreign.id, foreign.name, infrastructure.id, lead_option.id, "Não cadastrada"].each do |value|
        payload[:imovel][:caracteristicas_internas] = [value]
        expect { send_intake }.not_to change(Habitation, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.fetch("error")).to include("caracteristicas_internas")
      end
      expect(PropertyIntakeReceipt.for_tenant(tenant)).to be_empty
    end

    it "rejeita listas malformadas e tipos de logradouro inválidos" do
      [nil, "Piscina", {}, [nil], [true], [1.5], [{ id: feature.id }], [""], ["x" * 256], [-1]].each do |value|
        payload[:imovel][:infraestrutura_lazer] = value
        expect { send_intake }.not_to change(Habitation, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
      payload[:imovel].delete(:infraestrutura_lazer)
      [nil, "", 123, "x" * 256].each do |value|
        payload[:imovel][:endereco][:tipo_logradouro] = value
        expect { send_intake }.not_to change(Habitation, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "consulta somente IDs e nomes atuais da conta e respeita renomeações e remoções" do
      other = Tenant.create!(name: "Outro catálogo", slug: "outro-catalogo")
      other.attribute_options.create!(context: "habitation", category: "feature", name: "Adega exclusiva")
      tenant.attribute_options.create!(context: "lead", category: "source", name: "Origem exclusiva")
      headers = { "Authorization" => "Bearer #{token}" }
      get "/api/v1/property_features", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "caracteristicas_internas" => [{ "id" => feature.id, "nome" => feature.name }],
        "infraestrutura_lazer" => [{ "id" => infrastructure.id, "nome" => infrastructure.name }]
      )
      feature.update!(name: "Adega")
      infrastructure.destroy!
      get "/api/v1/property_features", headers: headers
      expect(response.parsed_body).to eq(
        "caracteristicas_internas" => [{ "id" => feature.id, "nome" => "Adega" }],
        "infraestrutura_lazer" => []
      )
      payload[:imovel][:caracteristicas_internas] = [feature.id]
      send_intake
      expect(response).to have_http_status(:created)
      expect(PropertyIntakeReceipt.for_tenant(tenant).sole.habitation.property_features_for_display).to eq(["Adega"])
      payload[:external_id] = "CAP-REMOVIDA"
      payload[:imovel][:infraestrutura_lazer] = [infrastructure.id]
      expect { send_intake }.not_to change(Habitation, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "exige credencial válida e rejeita token revogado ou conta inativa na consulta" do
      get "/api/v1/property_features"
      expect(response).to have_http_status(:unauthorized)
      get "/api/v1/property_features", headers: { "Authorization" => "Bearer #{SecureRandom.hex(32)}" }
      expect(response).to have_http_status(:unauthorized)
      tenant.update!(active: false)
      get "/api/v1/property_features", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
      tenant.update!(active: true, property_intake_token_digest: nil)
      get "/api/v1/property_features", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

end
