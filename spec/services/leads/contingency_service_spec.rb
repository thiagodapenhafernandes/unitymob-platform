require "rails_helper"

RSpec.describe Leads::ContingencyService do
  include ActiveSupport::Testing::TimeHelpers
  let(:tenant) { Tenant.create!(name: "Contingência", slug: "contingency-#{SecureRandom.hex(4)}") }
  let(:agent) { create(:admin_user, tenant: tenant) }
  let(:destination) { create(:distribution_rule, tenant: tenant, source_site: false) }
  let(:source) do
    create(:distribution_rule, tenant: tenant, contingency_enabled: true, contingency_rule: destination,
      contingency_triggers: %w[unavailable outside_hours pool_timeout acceptance_timeout deactivated])
  end
  let(:lead) { create(:lead, tenant: tenant, origin: "Site", admin_user: nil, distribution_rule: source) }
  around { |example| Current.set(tenant: tenant) { example.run } }
  before do
    allow_any_instance_of(Lead).to receive(:route_lead)
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    allow(Leads::NotificationDispatcher).to receive(:notify_shark_tank)
    allow(Leads::NotificationDispatcher).to receive(:notify_lost_turn)
    allow(Leads::NotificationDispatcher).to receive(:push_to)
    LeadSetting.instance(tenant: tenant).update!(stickiness_enabled: false)
    create(:distribution_rule_agent, distribution_rule: destination, admin_user: agent)
  end

  def distribute
    Leads::DistributorService.distribute_to(lead, source)
    lead.reload
  end

  it "encaminha imediatamente sem candidatos e não exige os filtros de origem do destino" do
    distribute
    expect(lead).to have_attributes(admin_user_id: agent.id, distribution_rule_id: destination.id,
      contingency_source_rule_id: source.id, contingency_pending: false, status: "Aguardando Aceite")
    expect(lead.activities.where(kind: "contingency_forwarded").count).to eq(1)
    expect(tenant.leads.count).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:deliver).once
  end

  it "continua com a regra de origem quando o recurso está desligado" do
    source.update!(contingency_enabled: false)
    distribute
    expect(lead.contingency_forwarded_at).to be_nil
    expect(lead.admin_user_id).to be_nil
    expect(lead.distribution_rule_id).to eq(source.id)
  end

  it "aguarda o prazo configurado sem reiniciar a espera nas tentativas" do
    source.update!(contingency_unavailable_minutes: 10)
    distribute
    started = lead.distribution_cycle_started_at
    expect(lead.contingency_forwarded_at).to be_nil
    travel_to(started + 5.minutes) { described_class.check!(lead) }
    expect(lead.reload.distribution_cycle_started_at).to eq(started)
    travel_to(started + 10.minutes + 1.second) { described_class.check!(lead) }
    expect(lead.reload.admin_user_id).to eq(agent.id)
  end

  it "retoma a regra de origem se um candidato ficar disponível antes do prazo" do
    source.update!(contingency_unavailable_minutes: 10)
    distribute
    create(:distribution_rule_agent, distribution_rule: source, admin_user: agent)
    described_class.check!(lead)
    expect(lead.reload).to have_attributes(admin_user_id: agent.id, distribution_rule_id: source.id,
      contingency_forwarded_at: nil)
  end

  it "não considera aceite nem distribui outra vez se uma automação falhar após atribuir" do
    allow(Automation::Dispatcher).to receive(:dispatch).and_call_original
    allow(Automation::Dispatcher).to receive(:dispatch).with(:lead_assigned, anything, any_args).and_raise("automação indisponível")
    distribute
    described_class.check!(lead)
    expect(lead.reload).to have_attributes(admin_user_id: agent.id, status: "Aguardando Aceite", contingency_pending: false)
    expect(lead.activities.where(kind: "distributed").count).to eq(1)
    expect(lead.activities.where(kind: "distribution_failed").count).to eq(1)
  end

  it "encaminha a falta de check-in sem ignorar o check-in do destino" do
    source.update!(require_active_checkin: true)
    destination.update!(require_active_checkin: true)
    distribute
    expect(lead).to have_attributes(contingency_pending: true, admin_user_id: nil)
    destination.update!(require_active_checkin: false)
    described_class.check!(lead)
    expect(lead.reload).to have_attributes(contingency_pending: false, admin_user_id: agent.id)
  end

  it "mantém pendente e avisa uma vez quando o destino não consegue receber" do
    destination.distribution_rule_agents.destroy_all
    manager = create(:admin_user, :admin, tenant: tenant)
    distribute
    2.times { described_class.check!(lead) }
    expect(lead.reload.contingency_pending?).to eq(true)
    expect(lead.activities.where(kind: "contingency_pending").count).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:push_to).with(manager, anything).once
  end

  it "tenta novamente o mesmo destino após a disponibilidade voltar" do
    source
    destination.update!(active: false)
    distribute
    expect(lead.contingency_pending?).to eq(true)
    destination.update!(active: true)
    2.times { described_class.check!(lead) }
    expect(lead.reload.admin_user_id).to eq(agent.id)
    expect(lead.activities.where(kind: "contingency_forwarded").count).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:deliver).once
  end

  it "respeita o horário do destino e libera sem devolver à origem" do
    allow_any_instance_of(DistributionRule).to receive(:outside_represamento_hours?).and_return(false)
    allow_any_instance_of(DistributionRule).to receive(:outside_represamento_hours?) { |rule| rule.id == destination.id }
    distribute
    expect(lead.contingency_pending?).to eq(true)
    allow_any_instance_of(DistributionRule).to receive(:outside_represamento_hours?).and_return(false)
    described_class.check!(lead)
    expect(lead.reload.distribution_rule_id).to eq(destination.id)
    expect(lead.admin_user_id).to eq(agent.id)
  end

  it "encaminha fora do horário somente quando a situação está marcada" do
    source.update!(represamento_active: true)
    allow_any_instance_of(DistributionRule).to receive(:outside_represamento_hours?) { |rule| rule.id == source.id }
    distribute
    expect(lead.distribution_rule_id).to eq(destination.id)
    expect(lead.contingency_reason).to eq("outside_hours")
  end

  it "preserva represamento por horário quando não se escolhe esse motivo" do
    source.update!(represamento_active: true, contingency_triggers: ["unavailable"])
    allow_any_instance_of(DistributionRule).to receive(:outside_represamento_hours?) { |rule| rule.id == source.id }
    distribute
    expect(lead).to have_attributes(status: "Represado", contingency_forwarded_at: nil)
  end

  it "encaminha um bolsão sem ninguém assumir após o prazo, sem renovar por reaviso" do
    source.update!(distribution_mode: :shark_tank, contingency_triggers: ["pool_timeout"], contingency_pool_minutes: 10)
    create(:distribution_rule_agent, distribution_rule: source, admin_user: agent)
    distribute
    started = lead.distribution_cycle_started_at
    travel_to(started + 8.minutes) { lead.activities.create!(kind: "pool_renotified") }
    travel_to(started + 11.minutes) { described_class.check!(lead) }
    expect(lead.reload).to have_attributes(admin_user_id: agent.id, contingency_reason: "pool_timeout")
  end

  it "usa o prazo total sem aceite, mesmo após outra distribuição na mesma regra" do
    source.update!(contingency_triggers: ["acceptance_timeout"], contingency_acceptance_minutes: 10)
    create(:distribution_rule_agent, distribution_rule: source, admin_user: agent)
    distribute
    started = lead.distribution_cycle_started_at
    travel_to(started + 8.minutes) { Leads::DistributorService.distribute_to(lead, source) }
    travel_to(started + 11.minutes) { described_class.check!(lead) }
    expect(lead.reload.contingency_reason).to eq("acceptance_timeout")
    expect(lead.distribution_cycle_started_at).to eq(started)
  end

  it "não reinicia a espera de um lead anterior à configuração ao migrar seu ciclo" do
    source.update!(contingency_triggers: ["acceptance_timeout"], contingency_acceptance_minutes: 10)
    create(:distribution_rule_agent, distribution_rule: source, admin_user: agent)
    lead.update!(admin_user: agent, status: "Aguardando Aceite", created_at: 1.hour.ago)
    first_receipt = lead.activities.create!(kind: "received", created_at: 1.hour.ago)
    lead.activities.create!(kind: "received", created_at: 1.minute.ago)
    described_class.check!(lead)
    expect(lead.reload.contingency_reason).to eq("acceptance_timeout")
    expect(lead.distribution_cycle_started_at).to eq(first_receipt.created_at)
  end

  it "não encaminha atendimento já iniciado, mesmo com prazo vencido" do
    lead.update!(admin_user: agent, status: "Em Atendimento", distribution_cycle_started_at: 1.day.ago)
    expect { described_class.check!(lead) }.not_to change { lead.reload.contingency_forwarded_at }
  end

  it "encaminha pendentes de uma regra desativada" do
    lead.update!(distribution_cycle_started_at: Time.current)
    source.update!(active: false)
    described_class.check!(lead)
    expect(lead.reload).to have_attributes(admin_user_id: agent.id, contingency_reason: "deactivated")
  end

  it "não encaminha um cadastro arquivado" do
    lead.update!(status: "Descartado", archived_at: Time.current)
    described_class.check!(lead)
    expect(lead.reload.contingency_forwarded_at).to be_nil
  end

  it "não volta à origem em uma tentativa posterior de roteamento" do
    distribute
    create(:distribution_rule_agent, distribution_rule: source, admin_user: agent)
    lead.update!(admin_user: nil, status: "Novo")
    Leads::DistributorService.distribute_to(lead, source)
    expect(lead.reload.distribution_rule_id).to eq(destination.id)
    expect(lead.activities.where(kind: "contingency_forwarded").count).to eq(1)
  end

  it "não permite destino de outra conta mesmo com configuração adulterada" do
    other = create(:distribution_rule, tenant: Tenant.create!(name: "Contingência", slug: "contingency-#{SecureRandom.hex(4)}"))
    source.update_columns(contingency_rule_id: other.id)
    distribute
    expect(lead.contingency_forwarded_at).to be_nil
    expect(lead.distribution_rule_id).to eq(source.id)
  end

  it "usa o destino padrão para uma entrada sem regra compatível" do
    source.update!(active: false)
    LeadSetting.instance(tenant: tenant).update!(default_distribution_rule: destination)
    lead.update!(distribution_rule: nil, origin: "canal-sem-regra")
    Leads::DistributorService.find_and_distribute(lead)
    expect(lead.reload).to have_attributes(admin_user_id: agent.id, contingency_reason: "no_matching_rule")
  end

  it "não aplica o padrão a registros históricos sem recebimento operacional" do
    LeadSetting.instance(tenant: tenant).update!(default_distribution_rule: destination)
    lead.update!(distribution_rule: nil)
    described_class.check!(lead)
    expect(lead.reload.contingency_forwarded_at).to be_nil
  end

  it "não encaminha histórico importado mesmo com regra vinculada" do
    lead.activities.create!(kind: "external_lead_imported")
    described_class.check!(lead)
    expect(lead.reload.contingency_forwarded_at).to be_nil
  end

  it "não encaminha quando o aceite ocorreu antes da tentativa" do
    lead.update!(admin_user: agent, status: "Em Atendimento")
    expect(described_class.try_forward!(lead, rule: source, reason: "unavailable")).to eq(false)
    expect(lead.reload.admin_user_id).to eq(agent.id)
    expect(lead.contingency_forwarded_at).to be_nil
  end

  it "faz a expiração individual respeitar o prazo total de contingência" do
    allow(DistributionRule).to receive(:pocket_requires_secure_push?).and_return(true)
    source.update!(pocket_active: true, pocket_time: 1, contingency_triggers: ["acceptance_timeout"], contingency_acceptance_minutes: 2)
    create(:distribution_rule_agent, distribution_rule: source, admin_user: agent)
    distribute
    started = lead.distribution_cycle_started_at
    travel_to(started + 3.minutes) do
      expect(Leads::PocketExpirationService.expire!(lead)).to eq(:forwarded)
    end
    expect(lead.reload.distribution_rule_id).to eq(destination.id)
    expect(lead.activities.where(kind: "contingency_forwarded").count).to eq(1)
  end

  it "não volta à origem quando a reserva do destino final vence" do
    allow(DistributionRule).to receive(:pocket_requires_secure_push?).and_return(true)
    destination.update!(pocket_active: true, pocket_time: 1)
    next_agent = create(:admin_user, tenant: tenant)
    create(:distribution_rule_agent, distribution_rule: destination, admin_user: next_agent, position: 2)
    distribute
    travel_to(Time.current + 2.minutes) { Leads::PocketExpirationService.expire!(lead) }
    expect(lead.reload).to have_attributes(distribution_rule_id: destination.id, admin_user_id: next_agent.id)
    expect(lead.activities.where(kind: "contingency_forwarded").count).to eq(1)
  end

  it "permite um novo ciclo para uma consulta real após encerramento" do
    distribute
    lead.update!(status: "Descartado", archived_at: Time.current)
    result = Leads::Intake.create!(tenant: tenant, name: lead.name, phone: lead.phone, origin: "Site")
    expect(result.id).to eq(lead.id)
    expect(result.contingency_pending?).to eq(false)
    expect(result.activities.where(kind: "contingency_forwarded").count).to eq(2)
  end

  it "preserva o dono fidelizado antes de avaliar a contingência" do
    create(:distribution_rule_agent, distribution_rule: source, admin_user: agent)
    lead.update!(admin_user: agent, status: "Em Atendimento")
    LeadSetting.instance(tenant: tenant).update!(stickiness_enabled: true, stickiness_owner: "any_assignment")
    result = Leads::Intake.create!(tenant: tenant, name: lead.name, phone: lead.phone, origin: "Site")
    expect(result).to have_attributes(id: lead.id, admin_user_id: agent.id, contingency_forwarded_at: nil)
  end
end

RSpec.describe "Encaminhamento concorrente", type: :model do
  self.use_transactional_tests = false

  it "encaminha e consome a fila do destino apenas uma vez" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    target = create(:distribution_rule, tenant: tenant, source_site: false)
    source = create(:distribution_rule, tenant: tenant, source_site: false, contingency_enabled: true,
      contingency_rule: target, contingency_triggers: ["unavailable"])
    create(:distribution_rule_agent, distribution_rule: target, admin_user: broker)
    allow_any_instance_of(Lead).to receive(:route_lead)
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    lead = create(:lead, tenant: tenant, admin_user: nil, distribution_rule: source)
    gate = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          Leads::ContingencyService.try_forward!(Lead.find(lead.id), rule: DistributionRule.find(source.id), reason: "unavailable")
        end
      end
    end
    2.times { gate << true }
    threads.each { |thread| expect(thread.join(15)).to be_present }
    expect(threads.map(&:value).count(true)).to eq(1)
    expect(lead.reload.admin_user_id).to eq(broker.id)
    expect(lead.activities.where(kind: "contingency_forwarded").count).to eq(1)
    expect(lead.activities.where(kind: "distributed").count).to eq(1)
    expect(Leads::NotificationDispatcher).to have_received(:deliver).once
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    lead&.destroy!
    source&.destroy!
    target&.destroy!
    broker&.destroy!
  end
end
