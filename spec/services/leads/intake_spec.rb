require "rails_helper"

RSpec.describe Leads::Intake do
  let(:tenant) { Tenant.create!(name: "Entrada central", slug: "intake-#{SecureRandom.hex(4)}") }
  let(:phone) { "47999990890" }
  before do
    allow_any_instance_of(Lead).to receive(:route_lead)
    allow(Leads::NotificationDispatcher).to receive(:notify_complement)
    LeadSetting.instance(tenant: tenant).update!(stickiness_match: "phone_or_email")
  end

  it "reutiliza o contato entre canais, sem depender de imóvel, janela ou responsável da entrada" do
    owner = create(:admin_user, tenant: tenant)
    incoming_owner = create(:admin_user, tenant: tenant)
    original = create(:lead, tenant: tenant, phone: phone, email: "cliente@example.test",
      admin_user: owner, status: "Em Atendimento", origin: "Meta Ads", created_at: 1.year.ago)
    property = create(:habitation, tenant: tenant)
    result = nil
    expect {
      result = described_class.create!(tenant: tenant, name: "Novo nome", phone: "+55 (47) 99999-0890",
        email: "CLIENTE@example.test", origin: "Migração externa", admin_user: incoming_owner,
        property_id: property.id, notes: "Nova consulta", custom_answers: { "Interesse" => "Locação" },
        other_information: { "source" => "c2s", "external_lead_payload" => { "message" => "Contato" } })
    }.not_to change { tenant.leads.count }
    expect(result).to eq(original)
    expect(result.intake_reused).to eq(true)
    expect(result.reload).to have_attributes(admin_user_id: owner.id, status: "Em Atendimento", origin: "Meta Ads")
    expect(result.property_interests.pluck(:habitation_id)).to include(property.id)
    activity = result.activities.find_by!(kind: "inquiry_complemented")
    expect(activity.metadata).to include("inquiry_origin" => "Migração externa", "body" => "Nova consulta")
    expect(activity.metadata["inquiry_information"]["external_lead_payload"]).to eq({ "message" => "Contato" })
  end

  it "torna a nova consulta de lead arquivado visível sem duplicar o cadastro" do
    original = create(:lead, tenant: tenant, phone: phone, status: "Descartado")
    original.update_columns(archived_at: 1.day.ago)
    LeadSetting.instance(tenant: tenant).update!(stickiness_enabled: false)
    expect {
      result = described_class.create!(tenant: tenant, name: "Nova entrada", phone: phone, origin: "OLX")
      expect(result.id).to eq(original.id)
    }.not_to change { tenant.leads.count }
    expect(original.reload.status).to eq(Lead.default_status(tenant: tenant, pipeline: original.lead_pipeline))
    expect(original.archived_at).to be_nil
  end

  it "respeita telefone, telefone OU e-mail, e telefone E e-mail da conta" do
    create(:lead, tenant: tenant, phone: phone, email: "cliente@example.test")
    contact = tenant.leads.new(phone: "47988881234", email: "  CLIENTE@example.test  ")
    setting = LeadSetting.instance(tenant: tenant)
    setting.update!(stickiness_match: "phone")
    expect(described_class.find_existing(contact)).to be_nil
    setting.update!(stickiness_match: "phone_and_email")
    expect(described_class.find_existing(contact)).to be_nil
    contact.phone = phone
    expect(described_class.find_existing(contact)).to be_present
    setting.update!(stickiness_match: "phone_or_email")
    contact.phone = "47988881234"
    expect(described_class.find_existing(contact)).to be_present
  end

  it "não cruza contas e não casa contatos vazios" do
    create(:lead, tenant: tenant, phone: phone)
    other = Tenant.create!(name: "Outra", slug: "intake-other-#{SecureRandom.hex(4)}")
    expect(described_class.find_existing(other.leads.new(phone: phone))).to be_nil
    expect(described_class.find_existing(tenant.leads.new)).to be_nil
  end

  it "mantém referência de eventos diferentes e não repete o histórico em reentregas" do
    original = described_class.create!(tenant: tenant, name: "Cliente", phone: phone,
      other_information: { "meta_leadgen_id" => "meta-primeiro" })
    2.times do
      described_class.create!(tenant: tenant, name: "Cliente", phone: phone,
        other_information: { "meta_leadgen_id" => "meta-segundo" })
    end
    expect(tenant.leads.count).to eq(1)
    expect(original.activities.where(kind: "inquiry_complemented").count).to eq(1)
    expect(described_class.find_received_event(tenant: tenant, reference: "meta:meta-segundo")).to eq(original)
    expect(original.reload.other_information["meta_leadgen_id"]).to eq("meta-primeiro")
  end

  it "reconhece reentrega pelo ID original mesmo se o contato mudar" do
    original = described_class.create!(tenant: tenant, name: "Cliente", phone: phone,
      other_information: { "portal_lead_id" => "original" })
    expect {
      result = described_class.create!(tenant: tenant, name: "Cliente", phone: "47988881234",
        other_information: { "portal_lead_id" => "original" })
      expect(result).to eq(original)
    }.not_to change { tenant.leads.count }
    expect(original.activities.where(kind: "inquiry_complemented")).to be_empty
  end

  it "associa IDs C2S adicionais sem substituir a identidade do registro" do
    original = described_class.create!(tenant: tenant, name: "Cliente", phone: phone, external_lead_id: "c2s-primeiro")
    result = described_class.create!(tenant: tenant, name: "Cliente", phone: phone, external_lead_id: "c2s-segundo")
    expect(result.id).to eq(original.id)
    expect(result.external_lead_id).to eq("c2s-primeiro")
    expect(described_class.find_received_event(tenant: tenant, reference: "c2s:c2s-segundo")).to eq(original)
  end
end

RSpec.describe "Entrada simultânea de leads", type: :model do
  self.use_transactional_tests = false

  it "recebe dois canais ao mesmo tempo e mantém um único cadastro" do
    tenant = Tenant.default
    phone = "479#{rand(10000000..99999999)}"
    email = "concurrent-#{SecureRandom.hex(8)}@example.test"
    gate = Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          inquiry = Tenant.find(tenant.id).leads.new(name: "Contato simultâneo", phone: phone,
            email: email, origin: index.zero? ? "grupo_zap" : "Migração externa")
          inquiry.skip_automatic_routing = true
          Leads::Intake.receive!(inquiry).id
        end
      end
    end
    2.times { gate << true }
    threads.each { |thread| expect(thread.join(15)).to be_present }
    expect(threads.map(&:value).uniq.length).to eq(1)
    expect(tenant.leads.where(email: email).count).to eq(1)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    tenant&.leads&.where(email: email)&.destroy_all if email
  end
end

RSpec.describe "Criação concorrente com distribuição", type: :model do
  self.use_transactional_tests = false

  it "não redistribui na criação quando outra consulta já distribuiu o cadastro" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    rule = create(:distribution_rule, tenant: tenant, source_site: false, source_portal: true)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: broker)
    email = "routing-race-#{SecureRandom.hex(8)}@example.test"
    phone = "479#{rand(10000000..99999999)}"
    callback_ready = Queue.new
    release_callback = Queue.new
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    allow_any_instance_of(Lead).to receive(:route_lead).and_wrap_original do |method, *args|
      if Thread.current[:first_lead_ingress]
        callback_ready << true
        release_callback.pop
      end
      method.call(*args)
    end
    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:first_lead_ingress] = true
        Leads::Intake.create!(tenant: Tenant.find(tenant.id), name: "Cliente", phone: phone, email: email,
          origin: "grupo_zap", other_information: { "portal_lead_id" => "first-#{email}" }).id
      end
    end
    require "timeout"
    Timeout.timeout(15) { callback_ready.pop }
    second = Leads::Intake.create!(tenant: Tenant.find(tenant.id), name: "Cliente", phone: phone, email: email,
      origin: "grupo_zap", other_information: { "portal_lead_id" => "second-#{email}" })
    release_callback << true
    expect(first.join(15)).to be_present
    expect(first.value).to eq(second.id)
    expect(tenant.leads.where(email: email).count).to eq(1)
    expect(second.activities.where(kind: "distributed").count).to eq(1)
    expect(second.reload.admin_user_id).to eq(broker.id)
  ensure
    release_callback << true if first&.alive?
    first&.join(2)
    first&.kill if first&.alive?
    tenant&.leads&.where(email: email)&.destroy_all if email
    rule&.destroy!
    broker&.destroy!
  end
end
