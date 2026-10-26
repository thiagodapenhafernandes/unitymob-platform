require "rails_helper"

RSpec.describe "Agenda vencida na ficha do lead", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  def appointment(**attrs)
    create(:appointment, tenant: admin.tenant, admin_user: admin, lead: lead, **attrs)
  end

  it "mostra e conta todos os vencidos pendentes no desktop e mobile, sem truncar a agenda" do
    records = 21.times.map { |i| appointment(title: "Visita #{i}", starts_at: (i + 1).days.ago) }
    future = appointment(starts_at: 2.days.from_now)
    done = appointment(status: "realizado", starts_at: 3.days.ago)
    canceled = appointment(status: "cancelado", starts_at: 2.days.ago)
    selected = records.last

    get admin_lead_path(lead), params: { appointment_id: selected.id }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    %w[lead-desktop lead-pwa].each do |prefix|
      section = document.at_css("##{prefix}-agenda")
      expect(section).to be_present
      expect(section.css(".lead-operational-section__actions > .ax-badge").first.text.strip).to eq("22")
      (records + [future]).each { |record| expect(section.at_css("##{prefix}-appointment-#{record.id}")).to be_present }
      [done, canceled].each { |record| expect(section.at_css("##{prefix}-appointment-#{record.id}")).to be_nil }
      row = section.at_css("##{prefix}-appointment-#{selected.id}")
      expect(row.text).to include("Vencido · pendente", "Compromisso do alerta")
      expect(row["data-controller"]).to eq("ax-scroll-into-view")
      expect(row.at_css("select[name='appointment[status]']").css("option").map { |o| o["value"] }).to include("realizado", "cancelado")
    end
  end

  it "não inclui compromisso de outro lead ou conta apontado pela URL" do
    other_admin = create(:admin_user, :admin, tenant: Tenant.create!(name: "Outra", slug: "outra-agenda-#{SecureRandom.hex(3)}"))
    foreign_lead = create(:lead, tenant: other_admin.tenant, admin_user: other_admin)
    foreign = create(:appointment, tenant: other_admin.tenant, admin_user: other_admin, lead: foreign_lead, starts_at: 3.days.ago)
    other_lead = create(:lead, tenant: admin.tenant, admin_user: admin)
    unrelated = create(:appointment, tenant: admin.tenant, admin_user: admin, lead: other_lead, starts_at: 3.days.ago)

    [foreign, unrelated].each do |record|
      get admin_lead_path(lead), params: { appointment_id: record.id }
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("#lead-desktop-appointment-#{record.id}")).to be_nil
      expect(document.at_css("#lead-pwa-appointment-#{record.id}")).to be_nil
    end
  end

  it "preserva a resolução pelo formulário e permite consultar alerta antigo já resolvido" do
    record = appointment(starts_at: 3.days.ago)
    patch admin_appointment_path(record), params: { appointment: { status: "realizado" } }
    expect(record.reload.status).to eq("realizado")

    get admin_lead_path(lead)
    expect(Nokogiri::HTML(response.body).at_css("#lead-desktop-appointment-#{record.id}")).to be_nil

    get admin_lead_path(lead), params: { appointment_id: record.id }
    row = Nokogiri::HTML(response.body).at_css("#lead-desktop-appointment-#{record.id}")
    expect(row.text).to include("Realizado", "Compromisso do alerta")
    expect(row.text).not_to include("Vencido · pendente")
  end
end
