require "rails_helper"

RSpec.describe "Browser extension API", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { Tenant.default }
  let(:user) do
    profile = tenant.profiles.create!(name: "Extension test broker", key: "extension_test", axis: "vertical",
      permissions: Profile.default_permissions_for("Corretor"))
    create(:admin_user, tenant: tenant, profile: profile)
  end
  let(:extension_id) { "a" * 32 }
  let(:verifier) { SecureRandom.urlsafe_base64(32) }
  let(:grant) do
    BrowserExtensionGrant.create!(tenant: tenant, admin_user: user, extension_id: extension_id,
      terms_accepted_at: Time.current, terms_version: BrowserExtensionGrant::TERMS_VERSION, terms_digest: BrowserExtensionGrant.digest(BrowserExtensionGrant::TERMS_TEXT),
      challenge_digest: BrowserExtensionGrant.digest(verifier), challenge_expires_at: 5.minutes.from_now, expires_at: 8.hours.from_now)
  end
  let(:token) { grant.exchange! }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  around do |example|
    keys = %w[BROWSER_EXTENSION_TENANT_IDS BROWSER_EXTENSION_ALLOWED_IDS]
    previous = ENV.slice(*keys)
    ENV["BROWSER_EXTENSION_TENANT_IDS"] = tenant.id.to_s
    ENV["BROWSER_EXTENSION_ALLOWED_IDS"] = extension_id
    example.run
  ensure
    keys.each { |key| previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key) }
  end

  before { host! "localhost" }

  def make_lead(owner: user, account: tenant, phone: "+5511999999999")
    create(:lead, tenant: account, admin_user: owner, phone: phone, skip_automatic_routing: true)
  end

  it "exchanges once and never stores the raw credential" do
    grant
    expect do
      post "/api/v1/browser_extension/session", params: { verifier: verifier, login_token: grant.signed_id(purpose: :browser_extension_pairing, expires_in: 5.minutes), extension_id: extension_id }, as: :json
    end.not_to change(BrowserExtensionGrant, :count)
    expect(response).to have_http_status(:ok)
    issued = response.parsed_body.fetch("token")
    expect(grant.reload.token_digest).to eq(BrowserExtensionGrant.digest(issued))
    post "/api/v1/browser_extension/session", params: { verifier: verifier, login_token: grant.signed_id(purpose: :browser_extension_pairing, expires_in: 5.minutes), extension_id: extension_id }, as: :json
    expect(response).to have_http_status(:gone)
  end

  it "rejects discovery exchanges for a different tenant or user before issuing a credential" do
    attrs = { verifier: verifier, login_token: grant.signed_id(purpose: :browser_extension_pairing, expires_in: 5.minutes), extension_id: extension_id,
      expected_tenant_id: (tenant.id + 1).to_s, expected_email: user.email, expected_instance_id: "test", issuer: "http://localhost" }
    post "/api/v1/browser_extension/session", params: attrs, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.fetch("error")).to eq("account_mismatch")
    expect(grant.reload.exchanged_at).to be_nil
  end

  it "does not authenticate from admin session cookies or a mobile JWT" do
    sign_in user
    get "/api/v1/browser_extension/session"
    expect(response).to have_http_status(:unauthorized)
    jwt, = Warden::JWTAuth::UserEncoder.new.call(user, :admin_user, nil)
    get "/api/v1/browser_extension/session", headers: { "Authorization" => "Bearer #{jwt}" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "resolves only accessible leads without writing activities, assignments or interests" do
    mine = make_lead
    other_user = create(:admin_user, tenant: tenant)
    make_lead(owner: other_user)
    other_tenant = Tenant.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}")
    other = create(:admin_user, tenant: other_tenant)
    make_lead(owner: other, account: other_tenant)
    token
    expect do
      post "/api/v1/browser_extension/leads/resolve", params: { contact_phone: "+55 (11) 99999-9999" }, headers: headers, as: :json
    end.not_to change(LeadActivity, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("leads").map { |row| row.fetch("id") }).to eq([mine.id])
    expect(mine.reload.admin_user_id).to eq(user.id)
  end

  it "returns multiple opportunities instead of silently choosing one" do
    first = make_lead
    second = make_lead
    post "/api/v1/browser_extension/leads/resolve", params: { contact_phone: "+5511999999999" }, headers: headers, as: :json
    expect(response.parsed_body.fetch("leads").map { |row| row.fetch("id") }).to contain_exactly(first.id, second.id)
  end

  it "refuses another owner's lead and cuts access when the owner changes" do
    lead = make_lead
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response).to have_http_status(:ok)
    lead.update!(admin_user: create(:admin_user, tenant: tenant))
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "returns a minimal payload and filters tasks by their own resource permissions" do
    lead = make_lead
    property = create(:habitation, tenant: tenant)
    lead.update!(property_id: property.id)
    lead.update!(notes: "internal note not serialized")
    Task.create!(tenant: tenant, lead: lead, admin_user: user, title: "Retornar", kind: "follow_up", status: "pendente")
    Task.create!(tenant: tenant, lead: lead, admin_user: create(:admin_user, tenant: tenant), title: "Outra equipe", kind: "follow_up", status: "pendente")
    Appointment.create!(tenant: tenant, lead: lead, admin_user: user, title: "Visita autorizada", kind: "visita", status: "agendado", starts_at: 1.day.from_now)
    Appointment.create!(tenant: tenant, lead: lead, admin_user: create(:admin_user, tenant: tenant), title: "Agenda de outra equipe", kind: "visita", status: "agendado", starts_at: 1.day.from_now)
    Proposal.create!(lead: lead, admin_user: user, status: "rascunho", valor_cents: 0, entrada_cents: 0)
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("appointments").map { |row| row.fetch("title") }).to eq(["Visita autorizada"])
    expect(response.parsed_body.fetch("proposals").map { |row| row.fetch("status") }).to eq(["Rascunho"])
    expect(response.body).not_to include("Agenda de outra equipe", "public_token")
    expect(response.parsed_body.fetch("tasks_count")).to eq(1)
    expect(response.parsed_body.fetch("lead").keys).to contain_exactly("id", "name", "status", "stage_id", "owner_name", "origin", "created_at")
    expect(response.parsed_body.fetch("properties").map { |row| row.fetch("id") }).to eq([property.id])
    expect(response.parsed_body.fetch("tasks").map { |row| row.fetch("title") }).to eq(["Retornar"])
    expect(response.body).not_to include("internal note not serialized", "Outra equipe")
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  it "returns saved notes newest first without exposing other leads, tenants or arbitrary metadata" do
    lead = make_lead
    old = lead.activities.create!(tenant: tenant, kind: "note", created_at: 1.day.ago,
      metadata: { body: "Nota antiga", by: "Corretor", contact_kind: "nota", secret: "private metadata" })
    other = make_lead
    other.activities.create!(tenant: tenant, kind: "note", metadata: { body: "Outro atendimento" })
    attrs = operation_params(note: { body: "Nota nova" })
    post "/api/v1/browser_extension/leads/#{lead.id}/notes", params: attrs, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response).to have_http_status(:ok)
    notes = response.parsed_body.fetch("notes")
    expect(notes.map { |note| note.fetch("body") }).to eq(["Nota nova", "Nota antiga"])
    expect(notes.first).to include("author" => user.name, "kind" => "Anotação interna")
    expect(notes.last.fetch("id")).to eq(old.id)
    expect(response.parsed_body.fetch("notes_count")).to eq(2)
    expect(response.body).not_to include("Outro atendimento", "private metadata")
    other_tenant = Tenant.create!(name: "Other notes", slug: "notes-#{SecureRandom.hex(4)}")
    foreign = make_lead(owner: create(:admin_user, tenant: other_tenant), account: other_tenant)
    foreign.activities.create!(tenant: other_tenant, kind: "note", metadata: { body: "Nota de outra conta" })
    get "/api/v1/browser_extension/leads/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Nota de outra conta")
  end

  it "revokes only the current grant, without changing mobile jti" do
    jti = user.jti
    delete "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(user.reload.jti).to eq(jti)
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects disabled accounts, expired grants and disabled pilot configuration" do
    token
    user.update!(active: false)
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:unauthorized)
    user.update!(active: true)
    travel 9.hours do
      get "/api/v1/browser_extension/session", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
    ENV["BROWSER_EXTENSION_TENANT_IDS"] = ""
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "rechecks a trusted device and IP policy on each request" do
    device = TrustedDevice.create!(tenant: tenant, admin_user: user, fingerprint: "extension-test", status: "trusted")
    user.update!(require_trusted_device: true)
    grant.update!(trusted_device: device)
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:ok)
    device.update!(status: "blocked")
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:forbidden)
    device.update!(status: "trusted")
    create(:access_control_rule, tenant: tenant, rule_type: "block_ip", scope_type: "global", ip_value: "127.0.0.1")
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it "does not let a wrong verifier or another extension exchange the grant" do
    grant
    post "/api/v1/browser_extension/session", params: { verifier: SecureRandom.urlsafe_base64(32), extension_id: extension_id }, as: :json
    expect(response).to have_http_status(:accepted)
    post "/api/v1/browser_extension/session", params: { verifier: verifier, extension_id: "b" * 32 }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(grant.reload.exchanged_at).to be_nil
  end

  it "keeps extension authorization out of an already large CRM session" do
    sign_in user
    allow_any_instance_of(Admin::BrowserExtensionConnectionsController).to receive(:remember_extension_login!).and_wrap_original do |original, *args|
      original.receiver.session[:existing_filters] = "x" * 1850
      original.call(*args)
    end
    get "/admin/browser_extension_connections/new", params: { challenge: BrowserExtensionGrant.digest(verifier), extension_id: extension_id }
    expect(response).to have_http_status(:ok)
    expect(request.session[:existing_filters]).to eq("x" * 1850)
    expect(request.session[:browser_extension_pairing]).to be_nil
    expect(cookies[:browser_extension_pairing]).to be_present
  end

  it "requires an authenticated browser approval before exchange" do
    params = { challenge: BrowserExtensionGrant.digest(verifier), extension_id: extension_id }
    expect { post "/admin/browser_extension_connections", params: params }.not_to change(BrowserExtensionGrant, :count)
    expect(response).to have_http_status(:redirect)
    sign_in user
    get "/admin/browser_extension_connections/new", params: params
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Continuar no WhatsApp", tenant.name)
    expect(request.session[:browser_extension_pairing]).to be_nil
    expect(request.session[:browser_extension_login_return]).to be_nil
    expect(cookies[:browser_extension_pairing]).to be_present
    expect { post "/admin/browser_extension_connections", params: params }.to change(BrowserExtensionGrant, :count).by(1)
    callback = URI.parse(response.location)
    expect(callback.host).to eq("#{extension_id}.chromiumapp.org")
    code = Rack::Utils.parse_query(callback.query).fetch("login_token")
    expect(BrowserExtensionGrant.find_signed!(code, purpose: :browser_extension_pairing).terms_accepted?).to be(false)
    expect { post "/admin/browser_extension_connections", params: params }.not_to change(BrowserExtensionGrant, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "does not bypass the real TOTP login challenge" do
    user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    post "/admin/sign_in", params: { admin_user: { email: user.email, password: "password123" } }
    expect(response).to redirect_to("/admin/two_factor")
    get "/admin/browser_extension_connections/new", params: { challenge: BrowserExtensionGrant.digest(verifier), extension_id: extension_id }
    expect(response).to have_http_status(:forbidden)
    expect do
      post "/admin/browser_extension_connections", params: { challenge: BrowserExtensionGrant.digest(verifier), extension_id: extension_id }
    end.not_to change(BrowserExtensionGrant, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects a direct ID from another tenant even for a user with access to all leads" do
    user.profile.update!(permissions: { "leads" => { "view" => true, "scope" => "all" } })
    other_tenant = Tenant.create!(name: "External", slug: "external-#{SecureRandom.hex(4)}")
    owner = create(:admin_user, tenant: other_tenant)
    other_lead = make_lead(owner: owner, account: other_tenant)
    get "/api/v1/browser_extension/leads/#{other_lead.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "rechecks removal of the user's lead permission" do
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:ok)
    user.profile.update!(permissions: {})
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a trusted device from another user" do
    other = create(:admin_user, tenant: tenant)
    device = TrustedDevice.create!(tenant: tenant, admin_user: other, fingerprint: "other-device", status: "trusted")
    grant.trusted_device = device
    expect(grant).not_to be_valid
    expect(grant.errors[:trusted_device]).to be_present
  end

  it "includes the manager's team but excludes peers" do
    position = (1...10_000).find { |value| !tenant.profiles.where(position: value).exists? }
    user.profile.update!(position: position, permissions: { "leads" => { "view" => true, "scope" => "team" } })
    subordinate = create(:admin_user, tenant: tenant, manager: user)
    own_lead = make_lead
    team_lead = make_lead(owner: subordinate)
    make_lead(owner: create(:admin_user, tenant: tenant))
    post "/api/v1/browser_extension/leads/resolve", params: { contact_phone: "+5511999999999" }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("leads").pluck("id")).to contain_exactly(own_lead.id, team_lead.id)
  end

  it "rechecks a mirror membership and its primary identity" do
    home = Tenant.create!(name: "Home", slug: "home-#{SecureRandom.hex(4)}")
    primary = create(:admin_user, tenant: home)
    user.update!(primary_admin_user: primary)
    membership = AccountMembership.create!(tenant: tenant, primary_admin_user: primary, member_admin_user: user,
      profile: user.profile, invited_by: create(:admin_user, :admin, tenant: tenant),
      invited_email: "invite-#{SecureRandom.hex(4)}@example.test", status: :active)
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:ok)
    primary.update!(active: false)
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:unauthorized)
    primary.update!(active: true)
    membership.update!(status: :revoked)
    get "/api/v1/browser_extension/session", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "requires CSRF protection on the browser approval" do
    sign_in user
    params = { challenge: BrowserExtensionGrant.digest(verifier), extension_id: extension_id }
    get "/admin/browser_extension_connections/new", params: params
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    expect { post "/admin/browser_extension_connections", params: params }.not_to change(BrowserExtensionGrant, :count)
    expect(response).to redirect_to(new_admin_user_session_path)
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
  it "blocks commercial reads until the current terms are explicitly accepted" do
    grant.update!(terms_accepted_at: nil, terms_version: nil, terms_digest: nil)
    get "/api/v1/browser_extension/session", headers: headers
    expect(response.parsed_body.dig("capabilities", "read_leads")).to be(false)
    terms = response.parsed_body.fetch("terms")
    post "/api/v1/browser_extension/leads/resolve", params: { contact_phone: "+5511999999999" }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.fetch("error")).to eq("terms_required")
    post "/api/v1/browser_extension/session/terms", params: { accepted: false, version: terms["version"], digest: terms["digest"] }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "/api/v1/browser_extension/session/terms", params: { accepted: true, version: "obsolete", digest: terms["digest"] }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "/api/v1/browser_extension/session/terms", params: { accepted: true, version: terms["version"], digest: terms["digest"] }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(grant.reload).to be_terms_accepted
    accepted_at = grant.terms_accepted_at
    post "/api/v1/browser_extension/session/terms", params: { accepted: true, version: terms["version"], digest: terms["digest"] }, headers: headers, as: :json
    expect(grant.reload.terms_accepted_at).to eq(accepted_at)
    post "/api/v1/browser_extension/leads/resolve", params: { contact_phone: "+5511999999999" }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "does not exchange a verifier stolen from a login link without the signed callback code" do
    grant
    post "/api/v1/browser_extension/session", params: { verifier: verifier, extension_id: extension_id }, as: :json
    expect(response).to have_http_status(:accepted)
    expect(grant.reload.exchanged_at).to be_nil
  end

  it "returns to extension login after real password and TOTP, leaving ordinary logins unchanged" do
    user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    query = { challenge: BrowserExtensionGrant.digest(verifier), extension_id: extension_id }
    get "/admin/browser_extension_connections/new", params: query
    expect(response).to redirect_to(new_admin_user_session_path)
    post "/admin/sign_in", params: { admin_user: { email: user.email, password: "password123" } }
    expect(response).to redirect_to("/admin/two_factor")
    post "/admin/two_factor", params: { otp_code: ROTP::TOTP.new(user.otp_secret).now }
    expect(response).to redirect_to(new_admin_browser_extension_connection_path(query))
  end

  def operation_params(attributes = {})
    { request_key: SecureRandom.uuid, confirmed: true, contact_phone: "+5511999999999" }.merge(attributes)
  end

  it "creates a manual lead once with the current owner and default pipeline, ignoring injected attributes" do
    token
    attrs = operation_params(lead: { name: "Contato extensão", email: "contato@example.test", admin_user_id: 999, tenant_id: 999, status: "Concluido" })
    expect(Leads::RoutingService).to receive(:route!).once
    expect(Automation::Dispatcher).to receive(:dispatch).with(:lead_created, an_instance_of(Lead), source: "lead", idempotency_key: anything).once
    expect { 2.times { post "/api/v1/browser_extension/leads", params: attrs, headers: headers, as: :json } }.to change(Lead, :count).by(1)
    expect(response).to have_http_status(:ok)
    lead = tenant.leads.find(response.parsed_body.fetch("lead_id"))
    expect(lead.admin_user).to eq(user)
    expect(lead.origin).to eq("Cadastro manual")
    expect(lead.phone).to eq("5511999999999")
    expect(lead.lead_pipeline).to eq(LeadPipeline.default_for(tenant: tenant))
    expect(lead.status).not_to eq("Concluido")
  end

  it "records an internal note once without claiming a contact attempt or changing its lead" do
    lead = make_lead
    attrs = operation_params(note: { body: "  Preferência por varanda  ", contact_kind: "whatsapp" })
    expect { 2.times { post "/api/v1/browser_extension/leads/#{lead.id}/notes", params: attrs, headers: headers, as: :json } }.to change(LeadActivity, :count).by(1)
    expect(response).to have_http_status(:ok)
    note = lead.activities.find(response.parsed_body.fetch("note_id"))
    expect(note.metadata).to include("contact_kind" => "nota", "body" => "Preferência por varanda", "admin_user_id" => user.id)
    expect(lead.activities.contact_attempts).to be_empty
    expect(lead.reload.admin_user).to eq(user)
    attrs[:note][:body] = "Outro texto"
    expect { post "/api/v1/browser_extension/leads/#{lead.id}/notes", params: attrs, headers: headers, as: :json }.not_to change(LeadActivity, :count)
    expect(response).to have_http_status(:conflict)
  end

  it "records each contact kind with CRM results, counts attempts and returns the complete history" do
    lead = make_lead
    LeadActivity::CONTACT_ATTEMPT_KINDS.zip(LeadActivity::CONTACT_RESULT_LABELS.keys).each do |kind, result|
      attrs = operation_params(contact: {body: "  Conversa registrada  ", contact_kind: kind, contact_result: result})
      expect { 2.times { post "/api/v1/browser_extension/leads/#{lead.id}/contacts", params: attrs, headers: headers, as: :json } }.to change(LeadActivity, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(lead.activities.find(response.parsed_body.fetch("note_id")).metadata).to include(
        "contact_kind" => kind, "contact_result" => result, "body" => "Conversa registrada", "admin_user_id" => user.id)
    end
    expect(lead.unsuccessful_attempt_count).to eq(2)
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response.parsed_body.fetch("notes").map { |note| note.fetch("result") }).to match_array(LeadActivity::CONTACT_RESULT_LABELS.values)
    expect(response.parsed_body.dig("contact_options", "kinds").keys).to eq(%w[ligacao whatsapp email visita nota])
    expect(response.parsed_body.dig("contact_options", "results")).to eq(LeadActivity::CONTACT_RESULT_LABELS)
    expect(lead.reload.admin_user).to eq(user)
  end

  it "keeps internal contact notes outside attempt counts and rejects missing or forged contact choices" do
    lead = make_lead
    attrs = operation_params(contact: {body: "Preferência", contact_kind: "nota", contact_result: "nao_respondeu"})
    post "/api/v1/browser_extension/leads/#{lead.id}/contacts", params: attrs, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(lead.activities.last.meta("contact_result")).to be_nil
    expect(lead.unsuccessful_attempt_count).to eq(0)
    [{contact_kind: "ligacao"}, {contact_kind: "whatsapp", contact_result: "inventado"},
     {contact_kind: "inventado", contact_result: "nao_respondeu"}, {contact_kind: "nota", body: ""}].each do |fields|
      expect {
        post "/api/v1/browser_extension/leads/#{lead.id}/contacts", params: operation_params(contact: {body: "Resumo"}.merge(fields)), headers: headers, as: :json
      }.not_to change(LeadActivity, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "creates one task and its timeline event with timezone and current owner, including late retries" do
    lead = make_lead
    due = 1.hour.from_now.change(usec: 0)
    attrs = operation_params(task: { title: "Ligar amanhã", kind: "ligacao", priority: "alta", due_at: due.iso8601, admin_user_id: 999, lead_id: 999 })
    expect { post "/api/v1/browser_extension/leads/#{lead.id}/tasks", params: attrs, headers: headers, as: :json }.to change(Task, :count).by(1)
    expect(response).to have_http_status(:ok)
    task = tenant.tasks.find(response.parsed_body.fetch("task_id"))
    expect(task).to have_attributes(admin_user_id: user.id, created_by_id: user.id, lead_id: lead.id, source: "manual", due_at: due)
    travel 2.hours do
      expect { post "/api/v1/browser_extension/leads/#{lead.id}/tasks", params: attrs, headers: headers, as: :json }.not_to change(Task, :count)
      expect(response).to have_http_status(:ok)
    end
    expect(lead.activities.where(kind: "task_created").count).to eq(1)
  end

  it "rejects invalid, unconfirmed and mismatched contacts without writing" do
    lead = make_lead
    [operation_params(note: { body: "" }), operation_params(note: { body: "Nota" }, confirmed: false),
     operation_params(note: { body: "Nota" }, contact_phone: "+5511888888888"),
     operation_params(note: { body: "Nota" }, request_key: "invalid")].each do |attrs|
      expect { post "/api/v1/browser_extension/leads/#{lead.id}/notes", params: attrs, headers: headers, as: :json }.not_to change(LeadActivity, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
    attrs = operation_params(task: { title: "Retornar", kind: "follow_up", priority: "normal", due_at: 1.hour.ago.iso8601 })
    expect { post "/api/v1/browser_extension/leads/#{lead.id}/tasks", params: attrs, headers: headers, as: :json }.not_to change(Task, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(grant.operations).to be_empty
  end

  it "enforces write permissions independently from read access and requires renewed terms" do
    lead = make_lead
    user.profile.update!(permissions: { "leads" => { "view" => true, "scope" => "own" } })
    [ ["leads", { lead: { name: "Novo" } }], ["leads/#{lead.id}/notes", { note: { body: "Nota" } }],
      ["leads/#{lead.id}/contacts", { contact: {body: "Resumo", contact_kind: "nota"} }],
      ["leads/#{lead.id}/tasks", { task: { title: "Tarefa" } }] ].each do |path, attrs|
      post "/api/v1/browser_extension/#{path}", params: operation_params(attrs), headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
    grant.update!(terms_version: "2026-09-06.v1")
    get "/api/v1/browser_extension/session", headers: headers
    expect(response.parsed_body.fetch("capabilities").values).to all(eq(false))
    post "/api/v1/browser_extension/leads", params: operation_params(lead: { name: "Novo" }), headers: headers, as: :json
    expect(response.parsed_body.fetch("error")).to eq("terms_required")
    expect(grant.operations).to be_empty
  end

  it "refuses notes and tasks on other owners or tenants even with forged lead ids" do
    other_tenant = Tenant.create!(name: "External write", slug: "write-#{SecureRandom.hex(4)}")
    other_owner = create(:admin_user, tenant: other_tenant)
    [make_lead(owner: create(:admin_user, tenant: tenant)), make_lead(owner: other_owner, account: other_tenant)].each do |lead|
      %w[notes tasks contacts].each do |action|
        post "/api/v1/browser_extension/leads/#{lead.id}/#{action}", params: operation_params(note: { body: "Nota" }, task: { title: "Tarefa" }), headers: headers, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
    expect(grant.operations).to be_empty
  end

  it "rolls back a task when its audit event cannot persist and allows a safe retry" do
    lead = make_lead
    attrs = operation_params(task: { title: "Retornar", kind: "follow_up", priority: "normal", due_at: 1.hour.from_now.iso8601 })
    allow_any_instance_of(LeadActivity).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(LeadActivity.new))
    expect { post "/api/v1/browser_extension/leads/#{lead.id}/tasks", params: attrs, headers: headers, as: :json }.not_to change(Task, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(grant.operations).to be_empty
  end

  it "keeps identical contact phones isolated even when the connected user can view the whole account" do
    user.profile.update!(permissions: { "leads" => { "view" => true, "scope" => "all" } })
    own = make_lead(owner: create(:admin_user, tenant: tenant))
    own.update!(name: "Mesmo contato", origin: "C2S")
    other_tenant = Tenant.create!(name: "Outra imobiliária", slug: "other-phone-#{SecureRandom.hex(4)}")
    foreign = make_lead(owner: create(:admin_user, tenant: other_tenant), account: other_tenant)
    foreign.update!(name: "Mesmo contato")
    post "/api/v1/browser_extension/leads/resolve", params: { contact_phone: "+5511999999999" }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.fetch("leads")
    expect(rows.pluck("id")).to eq([own.id])
    expect(rows.first).to include("owner_name" => own.admin_user.name, "origin" => "C2S", "created_at" => own.created_at.iso8601)
    get "/api/v1/browser_extension/leads/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "creates an agenda appointment once with trusted ownership and an audit event" do
    lead = make_lead
    attrs = operation_params(appointment: {title: "Visitar imóvel", kind: "visita", starts_at: 1.hour.from_now.iso8601,
      ends_at: 2.hours.from_now.iso8601, location: "Recepção", admin_user_id: 999, tenant_id: 999})
    expect { post "/api/v1/browser_extension/leads/#{lead.id}/appointments", params: attrs, headers: headers, as: :json }.to change(Appointment, :count).by(1)
    expect(response).to have_http_status(:ok)
    appointment = Appointment.find(response.parsed_body.fetch("appointment_id"))
    expect(appointment).to have_attributes(admin_user_id: user.id, tenant_id: tenant.id, lead_id: lead.id, status: "agendado")
    travel 3.hours do
      expect { post "/api/v1/browser_extension/leads/#{lead.id}/appointments", params: attrs, headers: headers, as: :json }.not_to change(Appointment, :count)
      expect(response).to have_http_status(:ok)
    end
    expect(lead.activities.where(kind: "appointment_created").count).to eq(1)
  end

  it "rejects invalid agenda times, missing confirmation, unauthorized leads and permissions" do
    lead = make_lead
    attrs = operation_params(appointment: {title: "Visita", kind: "visita", starts_at: 2.hours.from_now.iso8601, ends_at: 1.hour.from_now.iso8601})
    post "/api/v1/browser_extension/leads/#{lead.id}/appointments", params: attrs, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    attrs[:appointment][:ends_at] = 3.hours.from_now.iso8601
    post "/api/v1/browser_extension/leads/#{lead.id}/appointments", params: attrs.merge(confirmed: false), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    other = make_lead(owner: create(:admin_user, tenant: tenant))
    post "/api/v1/browser_extension/leads/#{other.id}/appointments", params: attrs, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    allow_any_instance_of(AdminUser).to receive(:can?).and_call_original
    allow_any_instance_of(AdminUser).to receive(:can?).with(:manage, :comercial).and_return(false)
    post "/api/v1/browser_extension/leads/#{lead.id}/appointments", params: attrs, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "returns the private label catalog with colors and applies only the user's labels idempotently" do
    lead = make_lead
    own = user.lead_labels.create!(tenant: tenant, name: "Quente", color: "#123456")
    colleague = create(:admin_user, tenant: tenant)
    private_label = colleague.lead_labels.create!(tenant: tenant, name: "Privada", color: "purple")
    lead.lead_labelings.create!(tenant: tenant, lead_label: private_label)
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response.parsed_body.fetch("label_catalog")).to eq([{ "id" => own.id, "name" => "Quente", "color" => "#123456" }])
    expect(response.parsed_body.fetch("labels")).to eq([])
    attrs = operation_params(labels: {ids: own.id.to_s})
    2.times { post "/api/v1/browser_extension/leads/#{lead.id}/labels", params: attrs, headers: headers, as: :json; expect(response).to have_http_status(:ok) }
    expect(lead.lead_labelings.pluck(:lead_label_id)).to contain_exactly(own.id, private_label.id)
    post "/api/v1/browser_extension/leads/#{lead.id}/labels", params: operation_params(labels: {ids: ""}), headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(lead.lead_labelings.pluck(:lead_label_id)).to eq([private_label.id])
    post "/api/v1/browser_extension/leads/#{lead.id}/labels", params: operation_params(labels: {ids: private_label.id.to_s}), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "searches sale and rental properties within the tenant and excludes unavailable listings" do
    lead = make_lead
    sale = create(:habitation, tenant: tenant, status: "Venda", valor_venda_cents: 50000000)
    rental = create(:habitation, tenant: tenant, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 250000)
    unavailable = create(:habitation, tenant: tenant)
    unavailable.update_columns(status: "Vendido terceiros")
    foreign = create(:habitation, tenant: Tenant.create!(name: "Outra imobiliária", slug: "other-#{SecureRandom.hex(4)}"))
    post "/api/v1/browser_extension/leads/#{lead.id}/properties/search", params: {q: "", purpose: "venda"}, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("properties").map { |p| p["id"] }).to include(sale.id)
    expect(response.parsed_body.fetch("properties").map { |p| p["id"] }).not_to include(rental.id, unavailable.id, foreign.id)
    post "/api/v1/browser_extension/leads/#{lead.id}/properties/search", params: {q: rental.codigo, purpose: "locacao"}, headers: headers, as: :json
    expect(response.parsed_body.fetch("properties").map { |p| p["id"] }).to eq([rental.id])
    expect(response.parsed_body.fetch("properties").first).to include(
      "bedrooms" => rental.dormitorios_qtd, "suites" => rental.suites_qtd, "parking" => rental.vagas_qtd,
      "condo_cents" => rental.valor_condominio_cents, "iptu_cents" => rental.valor_iptu_cents,
      "rental" => true, "city" => rental.cidade, "neighborhood" => rental.bairro)
    expect(response.parsed_body.fetch("properties").first).to have_key("area")
    expect(response.parsed_body.fetch("properties").first.fetch("card_title")).to be_present

    lead.property_interests.create!(habitation: sale, tenant: tenant)
    lead.update!(property_id: rental.id)
    post "/api/v1/browser_extension/leads/#{lead.id}/properties/search", params: {q: sale.codigo, purpose: "venda"}, headers: headers, as: :json
    expect(response.parsed_body.fetch("properties")).to be_empty
    post "/api/v1/browser_extension/leads/#{lead.id}/properties/search", params: {q: rental.codigo, purpose: "locacao"}, headers: headers, as: :json
    expect(response.parsed_body.fetch("properties")).to be_empty
    other_lead = make_lead(owner: create(:admin_user, tenant: tenant))
    post "/api/v1/browser_extension/leads/#{other_lead.id}/properties/search", params: {q: "", purpose: "venda"}, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "links selected properties once without replacing the primary property and rejects foreign IDs atomically" do
    lead = make_lead
    first = create(:habitation, tenant: tenant)
    second = create(:habitation, tenant: tenant)
    foreign = create(:habitation, tenant: Tenant.create!(name: "Outra imobiliária", slug: "other-#{SecureRandom.hex(4)}"))
    lead.update!(property_id: first.id)
    attrs = operation_params(properties: {ids: "#{first.id},#{second.id}"})
    2.times do
      post "/api/v1/browser_extension/leads/#{lead.id}/properties", params: attrs, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(lead.property_interests.pluck(:habitation_id)).to contain_exactly(first.id, second.id)
    expect(lead.reload.property_id).to eq(first.id)
    post "/api/v1/browser_extension/leads/#{lead.id}/properties", params: operation_params(properties: {ids: "#{first.id},#{foreign.id}"}), headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(lead.property_interests.count).to eq(2)
    post "/api/v1/browser_extension/leads/#{lead.id}/properties", params: operation_params(properties: {ids: ""}), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "changes the lead stage with an audit trail once and keeps retries idempotent" do
    lead = make_lead
    stage = lead.lead_pipeline.stages.create!(tenant: tenant, name: "Contato confirmado", active: true)
    lead.lead_pipeline_stage.transitions.destroy_all
    lead.lead_pipeline_stage.transitions.create!(tenant: tenant, next_stage: stage)
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response.parsed_body.fetch("status_options").map { |row| row["id"] }).to eq([stage.id])
    attrs = operation_params(status: {stage_id: stage.id.to_s, expected_stage_id: lead.lead_pipeline_stage_id.to_s})
    previous = lead.status
    2.times do
      post "/api/v1/browser_extension/leads/#{lead.id}/status", params: attrs, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(lead.reload).to have_attributes(status: stage.name, lead_pipeline_stage_id: stage.id)
    expect(lead.activities.where(kind: "status_change").count).to eq(1)
    expect(lead.activities.find_by(kind: "status_change").metadata).to include("from" => previous, "to" => stage.name)
  end

  it "rejects stale stages and stages outside the permitted transitions, pipeline and tenant" do
    lead = make_lead
    stage = lead.lead_pipeline.stages.create!(tenant: tenant, name: "Próximo contato", active: true)
    unavailable = lead.lead_pipeline.stages.create!(tenant: tenant, name: "Não permitido", active: true)
    lead.lead_pipeline_stage.transitions.create!(tenant: tenant, next_stage: stage)
    attrs = operation_params(status: {stage_id: stage.id.to_s, expected_stage_id: "99999999"})
    post "/api/v1/browser_extension/leads/#{lead.id}/status", params: attrs, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["error"]).to eq("lead_changed")
    other = tenant.lead_pipelines.create!(name: "Outro funil", kind: "sale")
    other_stage = other.stages.create!(tenant: tenant, name: "Nova etapa", active: true)
    foreign_tenant = Tenant.create!(name: "Status externo", slug: "status-#{SecureRandom.hex(4)}")
    foreign_pipeline = foreign_tenant.lead_pipelines.create!(name: "Funil externo", kind: "sale")
    foreign = foreign_pipeline.stages.create!(tenant: foreign_tenant, name: "Etapa externa", active: true)
    [unavailable, other_stage, foreign].each do |target|
      post "/api/v1/browser_extension/leads/#{lead.id}/status", params: operation_params(status: {stage_id: target.id.to_s, expected_stage_id: lead.lead_pipeline_stage_id.to_s}), headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(lead.activities.where(kind: "status_change").count).to eq(0)
  end

  it "hides role-restricted stages and refuses status changes without edit permission" do
    lead = make_lead
    stage = lead.lead_pipeline.stages.create!(tenant: tenant, name: "Só administrativo", active: true)
    stage.create_policy!(tenant: tenant, visible_to_roles: ["administrative"])
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response.parsed_body.fetch("status_options").map { |row| row["id"] }).not_to include(stage.id)
    attrs = operation_params(status: {stage_id: stage.id.to_s, expected_stage_id: lead.lead_pipeline_stage_id.to_s})
    post "/api/v1/browser_extension/leads/#{lead.id}/status", params: attrs, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    allow_any_instance_of(AdminUser).to receive(:can?).and_call_original
    allow_any_instance_of(AdminUser).to receive(:can?).with(:edit, :leads).and_return(false)
    post "/api/v1/browser_extension/leads/#{lead.id}/status", params: attrs, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "filters property autocomplete by code, price range and minimum rooms" do
    lead = make_lead
    matching = create(:habitation, tenant: tenant, codigo: "8334", status: "Venda", valor_venda_cents: 80000000, suites_qtd: 3, dormitorios_qtd: 4, vagas_qtd: 2)
    create(:habitation, tenant: tenant, codigo: "7777", descricao_web: "Código mencionado 8334", status: "Venda", valor_venda_cents: 80000000)
    endpoint = "/api/v1/browser_extension/leads/#{lead.id}/properties/search"
    post endpoint, params: {q: "8334", purpose: "venda", min_price: "700000", max_price: "900000", suites: "3", bedrooms: "4", parking: "2"}, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("properties").map { |p| p["id"] }).to eq([matching.id])
    post endpoint, params: {q: "8334", purpose: "venda", suites: "4"}, headers: headers, as: :json
    expect(response.parsed_body.fetch("properties")).to eq([])
    post endpoint, params: {q: "8334", purpose: "venda", min_price: "900000", max_price: "700000"}, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post endpoint, params: {q: "8334", purpose: "venda", min_price: "1 OR 1=1"}, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "removes an interest idempotently without removing the primary property" do
    lead = make_lead
    property = create(:habitation, tenant: tenant, exibir_no_site_flag: true, status: "Venda")
    lead.property_interests.create!(tenant: tenant, habitation: property)
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response.parsed_body.fetch("properties").first).to include("public_path" => "/imovel/#{property.codigo}", "removable" => true)
    expect(response.parsed_body.fetch("public_origin")).to be_present
    attrs = operation_params(property: {id: property.id.to_s})
    2.times do
      post "/api/v1/browser_extension/leads/#{lead.id}/properties/remove", params: attrs, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(lead.property_interests.count).to eq(0)
    lead.update!(property_id: property.id)
    post "/api/v1/browser_extension/leads/#{lead.id}/properties/remove", params: operation_params(property: {id: property.id.to_s}), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.property_id).to eq(property.id)
  end

  it "combines category and desktop quick filters inside the tenant catalog" do
    lead = make_lead
    property = create(:habitation, tenant: tenant, categoria: "Apartamento", status: "Venda", valor_venda_cents: 50000000, destaque_web_flag: true)
    create(:habitation, tenant: tenant, categoria: "Casa", status: "Venda", valor_venda_cents: 50000000, destaque_web_flag: true)
    endpoint = "/api/v1/browser_extension/leads/#{lead.id}/properties/search"
    post endpoint, params: {q: "", purpose: "venda", category: "Apartamento", quick: "destaque_web"}, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("properties").map { |p| p["id"] }).to eq([property.id])
    post endpoint, params: {q: "", purpose: "venda", quick: "destroy_all"}, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response.parsed_body.fetch("property_categories")).to include("Apartamento", "Casa")
    expect(response.parsed_body.fetch("property_quick_filters")).to include("frente_mar" => "Frente Mar")
  end

  it "returns compact card data and a factual fallback when the building name is absent" do
    lead = make_lead
    property = create(:habitation, tenant: tenant, nome_empreendimento: nil, categoria: "Apartamento", bairro: "Centro", dormitorios_qtd: 3, suites_qtd: 2, vagas_qtd: 1, area_privativa_m2: 143, valor_venda_cents: 350200000, valor_condominio_cents: 0, valor_iptu_cents: nil)
    lead.property_interests.create!(tenant: tenant, habitation: property)
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    card = response.parsed_body.fetch("properties").first
    expect(card).to include("card_title" => "Apartamento em Centro", "bedrooms" => 3, "suites" => 2, "parking" => 1, "price_cents" => 350200000, "condo_cents" => 0, "iptu_cents" => nil)
    property.update!(nome_empreendimento: "Residencial Teste")
    get "/api/v1/browser_extension/leads/#{lead.id}", headers: headers
    expect(response.parsed_body.fetch("properties").first["card_title"]).to eq("Residencial Teste")
  end

end
