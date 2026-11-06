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
end
