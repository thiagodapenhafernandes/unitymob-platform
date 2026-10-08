require "rails_helper"

RSpec.describe PublicFormLeadRoutingJob do
  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = Tenant.default
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  def build_form(tenant, **attrs)
    tenant.public_forms.create!(
      { name: "Captação", slug: "captacao-#{SecureRandom.hex(3)}", category: "custom",
        title: "Captação", submit_label: "Enviar", success_message: "Ok" }.merge(attrs)
    )
  end

  def build_submission(form, payload = { "name" => "Maria Cliente", "email" => "maria@example.com", "phone" => "5547999990000" })
    form.submissions.create!(payload: payload, source: { "page_url" => "https://site.example.com/" })
  end

  it "cria o lead e distribui pela regra do formulário uma única vez" do
    tenant = Tenant.default
    agent = create(:admin_user, :field_agent)
    rule = create(:distribution_rule, tenant: tenant, require_active_checkin: false)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
    form = build_form(tenant, distribution_rule: rule)
    submission = build_submission(form)

    expect { described_class.perform_now(submission.id) }.to change { tenant.leads.count }.by(1)

    lead = tenant.leads.order(:created_at).last
    expect(lead.origin).to eq("public_form:#{form.slug}")
    expect(lead.admin_user_id).to eq(agent.id)
    expect(submission.reload.lead_id).to eq(lead.id)

    expect { described_class.perform_now(submission.id) }.not_to(change { tenant.leads.count })
  end

  it "cria o lead sem distribuir quando a regra está inativa" do
    tenant = Tenant.default
    rule = create(:distribution_rule, tenant: tenant, active: false)
    form = build_form(tenant, distribution_rule: rule)
    submission = build_submission(form)

    described_class.perform_now(submission.id)

    lead = tenant.leads.order(:created_at).last
    expect(lead).to be_present
    expect(lead.admin_user_id).to be_nil
    expect(submission.reload.lead_id).to eq(lead.id)
  end

  it "reutiliza o cadastro e aplica a regra específica do formulário na nova consulta" do
    tenant = Tenant.default
    LeadSetting.instance(tenant: tenant).update!(stickiness_enabled: false)
    previous_owner = create(:admin_user, tenant: tenant)
    agent = create(:admin_user, tenant: tenant)
    original = create(:lead, tenant: tenant, phone: "5547999990000", origin: "Meta Ads",
      admin_user: previous_owner, status: "Descartado", skip_automatic_routing: true)
    original.update_columns(archived_at: Time.current)
    rule = create(:distribution_rule, tenant: tenant, source_site: false, source_webhook: true)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
    form = build_form(tenant, distribution_rule: rule)
    submission = build_submission(form)
    expect { described_class.perform_now(submission.id) }.not_to change { tenant.leads.count }
    expect(submission.reload.lead_id).to eq(original.id)
    expect(original.reload).to have_attributes(admin_user_id: agent.id, distribution_rule_id: rule.id,
      archived_at: nil, status: "Aguardando Aceite", origin: "Meta Ads")
    expect { described_class.perform_now(submission.id) }.not_to change { original.activities.count }
  end

  it "não substitui regra inativa do formulário por outra ativa ao reutilizar um cadastro" do
    tenant = Tenant.default
    original = create(:lead, tenant: tenant, phone: "5547999990000", status: "Descartado", skip_automatic_routing: true)
    create(:distribution_rule, tenant: tenant)
    rule = create(:distribution_rule, tenant: tenant, active: false)
    form = build_form(tenant, distribution_rule: rule)
    submission = build_submission(form)
    described_class.perform_now(submission.id)
    expect(submission.reload.lead_id).to eq(original.id)
    expect(original.reload.admin_user_id).to be_nil
    expect(original.distribution_rule_id).to be_nil
    expect(original.activities.find_by!(kind: "distribution_failed").metadata["rule_id"]).to eq(rule.id)
  end

  it "ignora submissão sem regra ou inexistente" do
    tenant = Tenant.default
    form = build_form(tenant)
    submission = build_submission(form)

    expect { described_class.perform_now(submission.id) }.not_to(change { tenant.leads.count })
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "não cria lead sem telefone (exigido pelo modelo)" do
    tenant = Tenant.default
    rule = create(:distribution_rule, tenant: tenant)
    form = build_form(tenant, distribution_rule: rule)
    submission = build_submission(form, { "name" => "Sem Fone", "email" => "semfone@example.com" })

    expect { described_class.perform_now(submission.id) }.not_to(change { tenant.leads.count })
    expect(submission.reload.lead_id).to be_nil
  end
end
