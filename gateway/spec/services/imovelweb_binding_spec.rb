require 'spec_helper'

RSpec.describe Gateway::ImovelwebBinding do
  let(:key) { SecureRandom.uuid }
  let(:client) { instance_double(Gateway::ImovelwebClient) }
  let(:binding) { described_class.new(environment:'production', client_code:'47294717', client_key:key) }
  let(:advertiser) { {client_code:'47294717', advertiser_code:'47294717', administrator_email:'owner@example.com'} }
  before do
    allow(Gateway::AdminAuth).to receive(:digest) { |value| OpenSSL::HMAC.hexdigest('SHA256','binding-test-secret',value) }
    allow(Gateway::ImovelwebClient).to receive(:new).with(environment:'production').and_return(client)
    allow(client).to receive(:authorized_advertiser).with(client_code:'47294717', administrator:true).and_return(advertiser)
    allow(Gateway::Discovery).to receive(:send_code)
  end

  def code_for(challenge)
    expect(challenge[:email_hint]).to eq('o***@example.com')
    expect(Gateway::Discovery).to have_received(:send_code).with('owner@example.com', anything, purpose: :imovelweb_binding)
    @code
  end

  it 'never treats a numeric code or provider consent alone as proof of tenant ownership' do
    expect(binding.verification).to include(confirmed:false,ownership_required:true,advertiser_code:'47294717',email_hint:'o***@example.com')
    expect(Gateway::Discovery).not_to have_received(:send_code)
    allow(client).to receive(:authorized_advertiser).and_return(nil)
    expect(binding.verification).to eq(confirmed:false)
  end

  it 'preserves a previously bound route without requesting email confirmation' do
    WebhookRoute.create!(provider:'imovelweb',client_key:key,imovelweb_client_code:'47294717',imovelweb_environment:'production',active:true,target_url:'https://crm.example.com',forwarding_secret:'s'*32)
    expect(binding.verification).to include(confirmed:true,ownership_required:false)
    expect(Gateway::Discovery).not_to have_received(:send_code)
  end

  it 'does not accept an unverified inactive reservation as ownership' do
    WebhookRoute.create!(provider:'imovelweb',client_key:key,imovelweb_client_code:'47294717',imovelweb_environment:'production',active:false,target_url:'https://crm.example.com',forwarding_secret:'s'*32)
    expect(binding.verification).to include(confirmed:false,ownership_required:true)
  end

  it 'sends to the administrator supplied by the provider and scopes proof to the exact connection' do
    allow(Gateway::Discovery).to receive(:send_code) { |_,code,**| @code=code }
    challenge=binding.start
    row=ImovelwebBindingChallenge.last
    expect(row.attributes.values).not_to include(@code,challenge[:challenge_token])
    code_for(challenge)
    proof=binding.confirm(token:challenge[:challenge_token],code:@code).fetch(:binding_proof)
    expect(binding.verification(proof:proof)).to include(confirmed:true)
    other=described_class.new(environment:'production',client_code:'47294717',client_key:SecureRandom.uuid)
    expect(other.verification(proof:proof)).to include(confirmed:false)
    binding.consume_proof!(proof)
    expect(binding.valid_proof?(proof)).to be(false)
  end

  it 'persists failed attempts, locks after five and rejects expired or reused codes' do
    allow(Gateway::Discovery).to receive(:send_code) { |_,code,**| @code=code }
    token=binding.start.fetch(:challenge_token)
    wrong=@code=='000000' ? '000001' : '000000'
    5.times { expect { binding.confirm(token:token,code:wrong) }.to raise_error(described_class::Error,'invalid_code') }
    expect(ImovelwebBindingChallenge.last.attempts).to eq(5)
    expect { binding.confirm(token:token,code:@code) }.to raise_error(described_class::Error)
    token=binding.start.fetch(:challenge_token)
    ImovelwebBindingChallenge.last.update!(expires_at:1.minute.ago)
    expect { binding.confirm(token:token,code:@code) }.to raise_error(described_class::Error)
  end

  it 'rate limits sends by advertiser and refuses unknown administrator addresses' do
    3.times { binding.start }
    expect { binding.start }.to raise_error(described_class::Error,'rate_limited')
    expect(Gateway::Discovery).to have_received(:send_code).exactly(3).times
  end

  it 'refuses conflicting routes even with valid provider consent' do
    WebhookRoute.create!(provider:'imovelweb',client_key:SecureRandom.uuid,imovelweb_client_code:'47294717',imovelweb_environment:'production',active:true,target_url:'https://other.example.com',forwarding_secret:'s'*32)
    expect { binding.verification }.to raise_error(described_class::Error,'advertiser_already_linked')
    expect(Gateway::Discovery).not_to have_received(:send_code)
  end

  it 'fails closed when email delivery fails or the portal has no administrator email' do
    allow(Gateway::Discovery).to receive(:send_code).and_raise(IOError,'private detail')
    expect { binding.start }.to raise_error(described_class::Error,'email_delivery_failed')
    expect(ImovelwebBindingChallenge.last.consumed_at).to be_present
    advertiser[:administrator_email]=nil
    expect { binding.start }.to raise_error(described_class::Error,'administrator_email_unavailable')
  end
end
