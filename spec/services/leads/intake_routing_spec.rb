require "rails_helper"

RSpec.describe "Distribuição de novas consultas no cadastro existente", type: :model do
  include ActiveSupport::Testing::TimeHelpers
  let(:tenant) { Tenant.create!(name: "Reentrada", slug: "reentry-#{SecureRandom.hex(4)}") }
  let(:owner) { create(:admin_user, tenant: tenant) }
  let(:next_owner) { create(:admin_user, tenant: tenant) }
  let(:phone) { "47999990890" }
  let(:original) { create(:lead, tenant: tenant, name: "Cliente", phone: phone, origin: "Meta Ads", admin_user: owner, status: "Em Atendimento") }
  let(:rule) do
    create(:distribution_rule, tenant: tenant, source_site: false, source_portal: true).tap do |record|
      create(:distribution_rule_agent, distribution_rule: record, admin_user: next_owner, position: 1)
    end
  end
  let(:setting) { LeadSetting.instance(tenant: tenant) }

  around { |example| Current.set(tenant: tenant) { example.run } }

  before do
    allow_any_instance_of(Lead).to receive(:route_lead)
    allow(Leads::NotificationDispatcher).to receive(:deliver)
    allow(Leads::NotificationDispatcher).to receive(:notify_complement)
    allow(Leads::NotificationDispatcher).to receive(:notify_shark_tank)
    setting.update!(stickiness_enabled: true, stickiness_match: "phone_or_email",
      stickiness_owner: "any_assignment", stickiness_fallback: "active_in_rule", stickiness_window_days: 30)
  end

  def receive_inquiry(event_id = "nova-consulta", **attributes)
    original
    Leads::Intake.create!(tenant: tenant, name: "Cliente", phone: phone, origin: "grupo_zap",
      other_information: { "portal_lead_id" => event_id }, **attributes)
  end

  def include_previous_owner
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: owner, position: 2)
  end

  it "preserva atendimento elegível sem consumir outra vez no rodízio" do
    include_previous_owner
    original
    before_queue = rule.distribution_rule_agents.order(:position).pluck(:admin_user_id)
    expect { receive_inquiry }.not_to change { tenant.leads.count }
    expect(original.reload).to have_attributes(admin_user_id: owner.id, status: "Em Atendimento")
    expect(rule.distribution_rule_agents.order(:position).pluck(:admin_user_id)).to eq(before_queue)
    expect(Leads::NotificationDispatcher).to have_received(:notify_complement)
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end

  it "usa a origem da consulta nova para escolher a regra, preservando a origem original" do
    wrong_rule = create(:distribution_rule, tenant: tenant, source_site: false, source_meta: true)
    create(:distribution_rule_agent, distribution_rule: wrong_rule, admin_user: owner)
    rule
    result = receive_inquiry
    expect(result.id).to eq(original.id)
    expect(result).to have_attributes(admin_user_id: next_owner.id, distribution_rule_id: rule.id,
      origin: "Meta Ads", status: "Aguardando Aceite")
    expect(Leads::NotificationDispatcher).to have_received(:deliver).with(result, sticky: false)
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_complement)
  end

  it "transfere pendências para o novo responsável e preserva atividades concluídas" do
    rule
    pending = create(:task, tenant: tenant, lead: original, admin_user: owner, status: "pendente")
    done = create(:task, tenant: tenant, lead: original, admin_user: owner, status: "concluida")
    receive_inquiry
    expect(pending.reload.admin_user_id).to eq(next_owner.id)
    expect(done.reload.admin_user_id).to eq(owner.id)
  end

  it "seleciona a regra pelas tags novas mesmo quando o cadastro tem tags antigas" do
    original.update!(other_information: { "webhook_tags" => ["antiga"] })
    old_rule = create(:distribution_rule, tenant: tenant, source_site: false, source_webhook: true, webhook_tags: ["antiga"])
    create(:distribution_rule_agent, distribution_rule: old_rule, admin_user: owner)
    new_rule = create(:distribution_rule, tenant: tenant, source_site: false, source_webhook: true, webhook_tags: ["nova"])
    create(:distribution_rule_agent, distribution_rule: new_rule, admin_user: next_owner)
    setting.update!(stickiness_enabled: false)
    Leads::Intake.create!(tenant: tenant, name: "Cliente", phone: phone, origin: "webhook",
      other_information: { "webhook_tags" => ["nova"] })
    expect(original.reload.distribution_rule_id).to eq(new_rule.id)
    expect(original.admin_user_id).to eq(next_owner.id)
  end

  it "não renova a janela antes de avaliar a fidelização" do
    include_previous_owner
    original.update_columns(created_at: 90.days.ago, updated_at: 90.days.ago)
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "não prolonga a fidelização por uma sincronização recente" do
    include_previous_owner
    original.update_columns(created_at: 90.days.ago, updated_at: Time.current)
    original.activities.create!(kind: "distributed", created_at: 90.days.ago, metadata: { admin_user_id: owner.id })
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "considera aceite recente mesmo quando o cadastro é antigo" do
    include_previous_owner
    original.update_columns(created_at: 90.days.ago, updated_at: 90.days.ago)
    original.activities.create!(kind: "accepted", created_at: 1.day.ago, metadata: { admin_user_id: owner.id })
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(owner.id)
  end

  it "renova a fidelização quando o responsável atualiza o lead" do
    include_previous_owner
    original.update_columns(created_at: 90.days.ago, updated_at: 90.days.ago)
    Current.set(admin_user: owner) { original.update!(notes: "Novo atendimento") }
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(owner.id)
  end

  it "renova a fidelização pelo registro de contato do responsável" do
    include_previous_owner
    original.update_columns(created_at: 90.days.ago, updated_at: 90.days.ago)
    original.activities.create!(kind: "note", metadata: { admin_user_id: owner.id, contact_kind: "ligacao" })
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(owner.id)
  end

  it "usa a última edição do responsável mesmo após o prazo anterior vencer" do
    include_previous_owner
    original.update_columns(created_at: 90.days.ago, updated_at: 90.days.ago)
    travel_to(40.days.ago) do
      Current.set(admin_user: owner) { original.update!(notes: "Primeiro atendimento") }
    end
    Current.set(admin_user: owner) { original.update!(notes: "Atendimento atualizado") }
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(owner.id)
  end

  it "conta o prazo desde a última alteração do corretor e não da sincronização" do
    include_previous_owner
    original.update_columns(created_at: 90.days.ago, updated_at: 90.days.ago)
    travel_to(31.days.ago) do
      Current.set(admin_user: owner) { original.update!(notes: "Atendimento antigo") }
    end
    Current.set(admin_user: nil) { original.update!(notes: "Sincronização recente") }
    original.activities.create!(kind: "external_lead_synced", metadata: { admin_user_id: owner.id })
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "não renova o prazo do responsável pela edição de outro usuário" do
    include_previous_owner
    original.update_columns(created_at: 90.days.ago, updated_at: 90.days.ago)
    Current.set(admin_user: next_owner) { original.update!(notes: "Edição de outro usuário") }
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "respeita a escolha de só fidelizar quem atendeu" do
    include_previous_owner
    setting.update!(stickiness_owner: "attended")
    original.update!(status: "Aguardando Aceite")
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "respeita a escolha de fidelizar qualquer atribuição" do
    include_previous_owner
    original.update!(status: "Aguardando Aceite")
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(owner.id)
  end

  it "mantém dono ativo fora da regra apenas quando a configuração permite" do
    rule
    setting.update!(stickiness_fallback: "active_any")
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(owner.id)
  end

  it "não fideliza corretor inativo mesmo com active_any" do
    rule
    setting.update!(stickiness_fallback: "active_any")
    original
    owner.update!(active: false)
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "redistribui etapas de exceção, reativa o cadastro e guarda o estado anterior" do
    include_previous_owner
    archived_stage = original.lead_pipeline.stages.find_by!(stage_type: "archived")
    original.update!(status: archived_stage.name, lead_pipeline_stage: archived_stage)
    original.update_columns(archived_at: 1.day.ago, archive_note: "Arquivo anterior")
    setting.update!(stickiness_non_fidelizing_stage_ids: [archived_stage.id])
    receive_inquiry
    expect(original.reload).to have_attributes(admin_user_id: next_owner.id, status: "Aguardando Aceite", archived_at: nil)
    history = original.activities.find_by!(kind: "inquiry_complemented").metadata["previous_assignment"]
    expect(history).to include("status" => archived_stage.name, "admin_user_id" => owner.id, "archive_note" => "Arquivo anterior")
  end

  it "redistribui com fidelização desligada fora do pocket" do
    include_previous_owner
    setting.update!(stickiness_enabled: false)
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "mantém a atribuição vigente dentro do pocket com fidelização desligada" do
    rule.update!(pocket_active: true, pocket_time: 20)
    original.update!(distribution_rule: rule, status: "Aguardando Aceite")
    setting.update!(stickiness_enabled: false)
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(owner.id)
    expect(original.activities.where(kind: "distributed")).to be_empty
  end

  it "não deixa o pocket contornar as exceções da fidelização" do
    include_previous_owner
    rule.update!(pocket_active: true, pocket_time: 20)
    original.update!(distribution_rule: rule)
    setting.update!(stickiness_non_fidelizing_stage_ids: [original.lead_pipeline_stage_id])
    receive_inquiry
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "reabre lead encerrado para o mesmo corretor elegível sem consumir rodízio" do
    include_previous_owner
    original.update!(status: "Concluido")
    receive_inquiry
    expect(original.reload).to have_attributes(admin_user_id: owner.id, status: "Em Atendimento", closed_at: nil)
    expect(original.activities.find_by!(kind: "distributed").metadata["sticky"]).to eq(true)
  end

  it "coloca o mesmo cadastro no bolsão quando essa é a regra" do
    rule.update!(distribution_mode: :shark_tank)
    setting.update!(stickiness_enabled: false)
    result = receive_inquiry
    expect(result).to have_attributes(admin_user_id: nil, distribution_rule_id: rule.id, status: "Aguardando Aceite")
    expect(result.activities.where(kind: "shark_tank_ready").count).to eq(1)
  end

  it "respeita o represamento de horários na nova consulta" do
    rule.update!(represamento_active: true)
    allow_any_instance_of(DistributionRule).to receive(:outside_represamento_hours?).and_return(true)
    setting.update!(stickiness_enabled: false)
    receive_inquiry
    expect(original.reload).to have_attributes(admin_user_id: nil, status: "Represado", distribution_rule_id: rule.id)
  end

  it "represa sem elegíveis com check-in, mesmo se o dono estiver ativo" do
    include_previous_owner
    setting.update!(stickiness_fallback: "active_any")
    rule.update!(require_active_checkin: true)
    receive_inquiry
    expect(original.reload).to have_attributes(admin_user_id: nil, status: "Represado", distribution_rule_id: rule.id)
  end

  it "deixa consulta de lead encerrado sem regra visível para triagem" do
    original.update!(status: "Descartado")
    original.update_columns(archived_at: Time.current)
    receive_inquiry
    expect(original.reload.admin_user_id).to be_nil
    expect(original.archived_at).to be_nil
    expect(original.status).to eq(Lead.default_status(tenant: tenant, pipeline: original.lead_pipeline))
    expect(original.activities.find_by!(kind: "distribution_failed").metadata["reason"]).to eq("no_matching_rule")
  end

  it "não reabre nem notifica durante uma importação histórica" do
    rule
    original.update!(status: "Descartado")
    inquiry = tenant.leads.new(name: "Cliente", phone: phone, origin: "grupo_zap")
    inquiry.skip_automatic_routing = true
    Leads::Intake.receive!(inquiry)
    expect(original.reload.status).to eq("Descartado")
    expect(Leads::NotificationDispatcher).not_to have_received(:notify_complement)
    expect(Leads::NotificationDispatcher).not_to have_received(:deliver)
  end

  it "não redistribui uma reentrega nem repete automações" do
    rule
    allow(Automation::Dispatcher).to receive(:dispatch)
    receive_inquiry
    before_events = original.activities.count
    before_queue = rule.distribution_rule_agents.pluck(:last_lead_received_at)
    receive_inquiry
    expect(original.activities.count).to eq(before_events)
    expect(rule.distribution_rule_agents.pluck(:last_lead_received_at)).to eq(before_queue)
    expect(Automation::Dispatcher).to have_received(:dispatch).with(:lead_assigned, anything, anything).once
    expect(Automation::Dispatcher).to have_received(:dispatch).with(:lead_stage_changed, anything,
      hash_including(payload: { from: "Em Atendimento", to: "Aguardando Aceite" })).once
  end

  it "dispara a automação de atribuição novamente em outro ciclo do mesmo cadastro" do
    include_previous_owner
    original.update!(status: "Concluido")
    keys = []
    allow(Automation::Dispatcher).to receive(:dispatch) do |event, _lead, **options|
      keys << options[:idempotency_key] if event == :lead_assigned
    end
    receive_inquiry("primeiro-ciclo")
    original.reload.update!(status: "Concluido")
    receive_inquiry("segundo-ciclo")
    expect(keys.length).to eq(2)
    expect(keys.uniq.length).to eq(2)
    expect(tenant.leads.count).to eq(1)
  end

  it "não aplica regra de outra conta nem consome o evento inválido" do
    original
    other = Tenant.create!(name: "Outra conta", slug: "reentry-other-#{SecureRandom.hex(4)}")
    foreign_rule = create(:distribution_rule, tenant: other)
    inquiry = tenant.leads.new(name: "Cliente", phone: phone, origin: "grupo_zap")
    expect { Leads::Intake.receive!(inquiry, distribution_rule: foreign_rule) }.to raise_error(ArgumentError, /outro tenant/)
    expect(original.reload.admin_user_id).to eq(owner.id)
    expect(original.activities.where(kind: "inquiry_complemented")).to be_empty
  end

  it "usa o contexto da conta correta e restaura o contexto de quem chamou" do
    rule
    other = Tenant.create!(name: "Outro contexto", slug: "reentry-context-#{SecureRandom.hex(4)}")
    allow(Leads::NotificationDispatcher).to receive(:deliver) { expect(Current.tenant).to eq(tenant) }
    Current.set(tenant: other) do
      receive_inquiry
      expect(Current.tenant).to eq(other)
    end
    expect(original.reload.admin_user_id).to eq(next_owner.id)
  end

  it "permite reprocessar quando a consulta das regras falha" do
    rule
    original
    allow_any_instance_of(Leads::DistributorService).to receive(:matches_filters?).and_raise("Consulta indisponível")
    expect { receive_inquiry }.to raise_error("Consulta indisponível")
    expect(original.activities.where(kind: "inquiry_complemented")).to be_empty
    expect(original.reload.admin_user_id).to eq(owner.id)
  end

  it "não consome o evento quando a distribuição falha e permite reprocessar" do
    rule
    allow_any_instance_of(DistributionRule).to receive(:next_available_agent).and_raise("Falha temporária")
    expect { receive_inquiry }.to raise_error("Falha temporária")
    expect(original.reload.admin_user_id).to eq(owner.id)
    expect(original.activities.where(kind: "inquiry_complemented")).to be_empty
    expect(Leads::Intake.find_received_event(tenant: tenant, reference: "olx:nova-consulta")).to be_nil
  end
end
