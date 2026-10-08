require "rails_helper"

RSpec.describe "Cadastro manual de leads: telefone ou e-mail duplicado", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:phone) { "+55 (47) 99999-0890" }

  before do
    host! "localhost"
    LeadSetting.instance(tenant: admin.tenant).update!(stickiness_match: "phone_or_email")
    sign_in admin
  end

  def submit_lead
    post admin_leads_path, params: { lead: { name: "Novo cadastro", phone: phone, notes: "Preservar observação" } }
  end

  it "bloqueia número formatado e oferece o cadastro existente sem alterá-lo" do
    existing = create(:lead, tenant: admin.tenant, admin_user: admin, phone: "47999990890", name: "Original")
    expect { submit_lead }.not_to change(Lead, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("já está cadastrado nesta conta", "Preservar observação")
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{admin_lead_path(existing)}']")).to be_present
    expect(existing.reload.name).to eq("Original")
  end

  it "encontra números antigos formatados no campo client_phone, inclusive arquivados" do
    existing = create(:lead, tenant: admin.tenant, admin_user: admin, status: "Descartado")
    existing.update_columns(client_phone: "(47) 99999-0890")
    expect { submit_lead }.not_to change(Lead, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "não revela nome ou link quando o cadastro está fora do escopo de acesso" do
    existing = create(:lead, tenant: admin.tenant, phone: phone, name: "Contato sigiloso")
    allow_any_instance_of(Admin::LeadsController).to receive(:accessible_lead_scope_for_current_user).and_return(Lead.none)
    expect { submit_lead }.not_to change(Lead, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include("Contato sigiloso", admin_lead_path(existing), "Abrir cadastro existente")
  end

  it "permite o mesmo telefone em outra conta e impede reenvio do cadastro manual" do
    other = Tenant.create!(name: "Outra conta", slug: "manual-duplicate-#{SecureRandom.hex(4)}")
    create(:lead, tenant: other, phone: phone)
    expect { submit_lead }.to change { admin.tenant.leads.count }.by(1)
    expect(response).to have_http_status(:redirect)
    expect { submit_lead }.not_to change(Lead, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "preserva o recebimento fora do cadastro manual" do
    create(:lead, tenant: admin.tenant, phone: phone)
    expect { create(:lead, tenant: admin.tenant, phone: phone, origin: "Meta Ads") }.to change(Lead, :count).by(1)
  end

  it "bloqueia e-mail igual com maiúsculas e espaços mesmo com outro telefone" do
    existing = create(:lead, tenant: admin.tenant, admin_user: admin, email: "fabio.cliente@example.com", phone: "47988881234")
    expect {
      post admin_leads_path, params: { lead: { name: "Novo cadastro", phone: phone, email: "  FABIO.CLIENTE@example.com  " } }
    }.not_to change(Lead, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("telefone ou e-mail informado já está cadastrado")
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{admin_lead_path(existing)}']")).to be_present
  end

  it "verifica também client_email e não revela cadastro sem acesso" do
    create(:lead, tenant: admin.tenant, client_email: "cliente@example.com", phone: "47988881234", name: "Contato protegido")
    allow_any_instance_of(Admin::LeadsController).to receive(:accessible_lead_scope_for_current_user).and_return(Lead.none)
    expect {
      post admin_leads_path, params: { lead: { name: "Novo cadastro", phone: phone, email: "CLIENTE@example.com" } }
    }.not_to change(Lead, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include("Contato protegido", "Abrir cadastro existente")
  end

  it "permite e-mail de outra conta e e-mail vazio sem coincidência de telefone" do
    other = Tenant.create!(name: "Outra conta", slug: "manual-email-#{SecureRandom.hex(4)}")
    create(:lead, tenant: other, email: "cliente@example.com", phone: "47988881234")
    expect {
      post admin_leads_path, params: { lead: { name: "Novo cadastro", phone: phone, email: "cliente@example.com" } }
    }.to change { admin.tenant.leads.count }.by(1)
    expect(response).to have_http_status(:redirect)
    create(:lead, tenant: admin.tenant, email: nil, phone: "47977771234")
    expect {
      post admin_leads_path, params: { lead: { name: "Sem e-mail", phone: "47966661234", email: "" } }
    }.to change { admin.tenant.leads.count }.by(1)
    expect(response).to have_http_status(:redirect)
  end

  it "mantém a validação de telefone obrigatório" do
    post admin_leads_path, params: { lead: { name: "Sem telefone", phone: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(admin.tenant.leads.where(name: "Sem telefone")).to be_empty
  end
end
