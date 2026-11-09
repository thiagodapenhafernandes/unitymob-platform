require 'rails_helper'

RSpec.describe Instagram::PropertyJourney do
  include ActiveSupport::Testing::TimeHelpers
  let(:tenant) { Tenant.default }
  let(:lead) { create(:lead, tenant: tenant, name: '@edna', phone: nil, instagram_account_id: '12345', instagram_scoped_id: '98765', skip_automatic_routing: true) }
  let(:property) { create(:habitation, tenant: tenant) }
  let(:token) { described_class.reference(lead) }

  before { allow_any_instance_of(Tenant).to receive(:public_base_url).and_return('https://catalogo.example') }

  def inquiry(phone: '47998887777')
    build(:lead, tenant: tenant, name: 'Edna Azevedo', phone: phone, email: nil, property_id: property.id, skip_automatic_routing: true)
  end

  it 'valida assinatura, expiração e conta sem revelar dados no link' do
    expect(described_class.resolve(tenant, token)).to eq(lead)
    expect(described_class.resolve(tenant, token + 'x')).to be_nil
    expect(described_class.resolve(tenant, ['invalid'])).to be_nil
    other = Tenant.create!(name: 'Outra', slug: "ig-journey-#{SecureRandom.hex(3)}")
    expect(described_class.resolve(other, token)).to be_nil
    travel_to 31.days.from_now do
      expect(described_class.resolve(tenant, token)).to be_nil
    end
  end

  it 'conserva links malformados sem impedir a identificação de outro imóvel válido na mensagem' do
    body = "Veja https://[invalido e https://catalogo.example/imoveis/#{property.slug}"
    tracked = described_class.track_links(lead, body)
    expect(tracked).to include('https://[invalido', 'ig_ref=')
  end

  it 'registra envio confirmado uma vez e não classifica envio como interesse' do
    url = "https://catalogo.example/imoveis/#{property.slug}"
    message = lead.instagram_messages.create!(message_id: 'out-1', direction: 'outbound', body: url, occurred_at: Time.current)
    2.times { described_class.record_message(message) }
    expect(lead.activities.where(kind: 'instagram_property_event').count).to eq(1)
    expect(lead.activities.where(kind: 'instagram_property_event').first.metadata['event']).to eq('sent')
    expect(lead.property_interests).to be_empty
    inbound = lead.instagram_messages.create!(message_id: 'in-1', direction: 'inbound', body: 'Gostei desse, como é o pagamento?', occurred_at: Time.current)
    described_class.record_message(inbound)
    expect(lead.property_interests.pluck(:habitation_id)).to eq([property.id])
  end

  it 'mantém a ordem das opções e não inventa interesse para pedido ambíguo' do
    second = create(:habitation, tenant: tenant)
    body = [second, property].map { |p| "https://catalogo.example/imoveis/#{p.slug}" }.join("\n")
    lead.instagram_messages.create!(message_id: 'out-2', direction: 'outbound', body: body, occurred_at: Time.current)
    lead.instagram_messages.create!(message_id: 'in-2', direction: 'inbound', body: 'Gostei', occurred_at: Time.current)
    expect(lead.property_interests).to be_empty
    lead.instagram_messages.create!(message_id: 'in-3', direction: 'inbound', body: 'Quero visitar a segunda', occurred_at: Time.current)
    expect(lead.property_interests.pluck(:habitation_id)).to eq([property.id])
  end

  it 'não transforma rejeição de imóvel em interesse' do
    lead.instagram_messages.create!(message_id: 'out-no', direction: 'outbound', body: "https://catalogo.example/imoveis/#{property.slug}", occurred_at: Time.current)
    lead.instagram_messages.create!(message_id: 'in-no', direction: 'inbound', body: 'Não tenho interesse nesse imóvel', occurred_at: Time.current)
    expect(lead.property_interests).to be_empty
  end

  it 'não absorve contato existente de outra pessoa mesmo quando o Instagram ainda não tem telefone' do
    existing = create(:lead, tenant: tenant, phone: '5547998887777', skip_automatic_routing: true)
    result = described_class.receive!(inquiry, token: token)
    expect(result.id).to eq(existing.id)
    expect(lead.reload.phone).to be_blank
    expect(lead.client_name).to be_blank
  end

  it 'completa o contato original sem duplicação, preservando responsável, origem e histórico' do
    owner = create(:admin_user, tenant: tenant)
    lead.update!(admin_user: owner)
    expect { @result = described_class.receive!(inquiry, token: token) }.not_to change(Lead, :count)
    expect(@result.id).to eq(lead.id)
    expect(lead.reload).to have_attributes(client_name: 'Edna Azevedo', admin_user_id: owner.id)
    expect(lead.phone).to be_present
    expect(lead.property_interests.pluck(:habitation_id)).to eq([property.id])
    expect(lead.activities.where(kind: 'instagram_property_event').last.metadata['event']).to eq('converted')
    expect { described_class.receive!(inquiry, token: token) }.not_to change { lead.activities.where(kind: 'instagram_property_event').count }
  end

  it 'não sobrescreve identidade em link encaminhado nem absorve outro cadastro da conta' do
    lead.update!(phone: '5547991112233', client_name: 'Original')
    result = described_class.receive!(inquiry, token: token)
    expect(result.id).not_to eq(lead.id)
    expect(lead.reload).to have_attributes(phone: '5547991112233', client_name: 'Original')
    expect(lead.property_interests).to be_empty
  end
  it 'completa dados pelo site sem distribuir enquanto o atendimento automático estiver ativo' do
    lead.update_columns(other_information: {'instagram_capture' => {'step' => 'phone', 'cursor' => 0}})
    expect(Leads::RoutingService).not_to receive(:route!)
    expect { described_class.receive!(inquiry, token: token) }.to have_enqueued_job(Instagram::CaptureJob).with(tenant.id, lead.id)
    expect(lead.reload).to be_instagram_automation_holding
    expect(lead.admin_user_id).to be_nil
    expect(Instagram::CaptureAnswer.complete?(lead)).to be(true)
  end

end
