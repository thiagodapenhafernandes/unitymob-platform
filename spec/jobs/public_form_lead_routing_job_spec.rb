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

  it "vincula formulário originado no Direct ao contato original mesmo sem regra própria" do
    tenant = Tenant.default
    allow_any_instance_of(Tenant).to receive(:public_base_url).and_return("https://site.example.com")
    original = create(:lead, tenant: tenant, name: "@edna", phone: nil, email: nil,
      instagram_account_id: "12345", instagram_scoped_id: "98765", skip_automatic_routing: true)
    property = create(:habitation, tenant: tenant)
    form = build_form(tenant)
    submission = build_submission(form)
    submission.update!(source: {"instagram_reference" => Instagram::PropertyJourney.reference(original),
      "page_url" => "https://site.example.com/imoveis/#{property.slug}"})
    expect { described_class.perform_now(submission.id) }.not_to change(Lead, :count)
    expect(submission.reload.lead_id).to eq(original.id)
    expect(original.reload.client_name).to eq("Maria Cliente")
    expect(original.property_interests.pluck(:habitation_id)).to eq([property.id])
    expect { described_class.perform_now(submission.id) }.not_to change { original.activities.count }
  end

  it "cria o lead e distribui pela regra do formulário uma única vez" do
    tenant = Tenant.default
    agent = create(:admin_user, :field_agent)
    rule = create(:distribution_rule, tenant: tenant, require_active_checkin: false)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: agent)
    form = build_form(tenant, distribution_rule: rule)
    submission = build_submission(form)
    submission.update!(source: submission.source.merge("tracking_uid" => "Form_UID"))

    expect { described_class.perform_now(submission.id) }.to change { tenant.leads.count }.by(1)

    lead = tenant.leads.order(:created_at).last
    expect(lead.origin).to eq("public_form:#{form.slug}")
    expect(lead.attribution_data).to include("tracking_uid" => "Form_UID", "tracking_uids" => ["Form_UID"])
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

  it "transporta o snapshot da captura sem recalcular consentimento ou origem no job" do
    tenant = Tenant.default
    rule = create(:distribution_rule, tenant: tenant, active: false)
    form = build_form(tenant, distribution_rule: rule)
    submission = build_submission(form)
    data = { "channel" => "google_ads", "source" => "google", "gclid" => "click-original",
      "analytics_consent" => "granted", "analytics_consent_captured_at" => 1.day.ago.iso8601,
      "client_id" => "123.456", "first_touch" => { "ttclid" => "first-click" },
      "conversion_touch" => { "gclid" => "click-original" }, "tracking_uid" => "Form_UID" }
    submission.update!(source: submission.source.merge("attribution_data" => data,
      "attribution_channel" => "google_ads", "attribution_source" => "google"))
    session = PublicNavigationSession.create!(tenant: tenant, token: SecureRandom.uuid)
    navigation = session.events.create!(tenant: tenant, name: "page_view")
    submission.update!(source: submission.source.merge("navigation_token" => session.token))
    delivery = Tracking::Correlation.record(Tracking::Correlation.submission(submission),
      transport: "webhook", event_id: "submission-webhook", destination: "https://hooks.example.test/form")

    described_class.perform_now(submission.id)
    lead = submission.reload.lead
    expect(lead).to have_attributes(tenant_id: tenant.id, origin: form.webhook_origin,
      source_url: submission.source["page_url"], attribution_channel: "google_ads", attribution_source: "google")
    expect(lead.attribution_data).to include(data)
    expect(session.reload.lead_id).to eq(lead.id)
    expect(navigation.reload.lead_id).to eq(lead.id)
    expect(delivery.reload.lead_id).to eq(lead.id)
    expect(delivery.occurrence_key).to eq("public_form_submission:#{submission.id}")
    expect { described_class.perform_now(submission.id) }.not_to change(Lead, :count)
    expect(lead.reload.attribution_data).to include(data)
  end

  it "não vincula navegação de outra conta ao lead do formulário" do
    tenant = Tenant.default
    other = Tenant.create!(name: "Navegação externa", slug: "other-navigation-#{SecureRandom.hex(4)}")
    session = PublicNavigationSession.create!(tenant: other, token: SecureRandom.uuid)
    rule = create(:distribution_rule, tenant: tenant, active: false)
    submission = build_submission(build_form(tenant, distribution_rule: rule))
    submission.update!(source: submission.source.merge("navigation_token" => session.token))

    described_class.perform_now(submission.id)
    expect(submission.reload.lead.tenant_id).to eq(tenant.id)
    expect(session.reload.lead_id).to be_nil
    expect(session.tenant_id).to eq(other.id)
  end

  it "não leva URL inválida nem parâmetros privados da página para o link de origem do lead" do
    tenant = Tenant.default
    rule = create(:distribution_rule, tenant: tenant, active: false)
    form = build_form(tenant, distribution_rule: rule)
    submission = build_submission(form)
    submission.update!(source: { "page_url" => "https://site.example/formulario?email=private@example.test#fragment" })
    described_class.perform_now(submission.id)
    expect(submission.reload.lead.source_url).to eq("https://site.example/formulario")

    invalid = build_submission(form, { "name" => "Outro contato", "phone" => "5547999990001" })
    invalid.update!(source: { "page_url" => "javascript:alert(1)" })
    described_class.perform_now(invalid.id)
    expect(invalid.reload.lead.source_url).to be_nil
  end

  it "preserva a aquisição original ao agregar uma nova consulta atribuída" do
    tenant = Tenant.default
    original = create(:lead, tenant: tenant, phone: "5547999990000", origin: "Meta Ads",
      attribution_channel: "meta_ads", attribution_source: "meta", attribution_data: { "campaign_id" => "original" },
      skip_automatic_routing: true)
    rule = create(:distribution_rule, tenant: tenant, active: false)
    submission = build_submission(build_form(tenant, distribution_rule: rule))
    submission.update!(source: submission.source.merge("attribution_channel" => "google_ads", "attribution_source" => "google",
      "attribution_data" => { "gclid" => "new-click", "channel" => "google_ads" }))

    expect { described_class.perform_now(submission.id) }.not_to change(Lead, :count)
    expect(submission.reload.lead_id).to eq(original.id)
    expect(original.reload).to have_attributes(origin: "Meta Ads", attribution_channel: "meta_ads")
    expect(original.attribution_data["campaign_id"]).to eq("original")
    inquiry = original.activities.where(kind: "inquiry_complemented").last
    expect(inquiry.metadata.dig("inquiry_attribution", "gclid")).to eq("new-click")
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
