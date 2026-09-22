require "rails_helper"

RSpec.describe "Admin::LeadSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "lead-settings-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "organiza as configuracoes em secoes navegaveis e abre so a primeira" do
    get edit_admin_lead_setting_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    tabs = html.css(".ax-studio-nav [data-ax-tabs-target='tab']")
    sections = html.css(".ax-studio__stage > .ax-studio-section")

    expect(tabs.map { |tab| tab["data-ax-tabs-target-param"] }).to eq(
      %w[#lead-tab-stickiness #lead-tab-notify #lead-tab-reminders #lead-tab-sla #lead-tab-privacy #lead-tab-how]
    )
    expect(sections.map { |section| section["id"] }).to eq(tabs.map { |tab| tab["data-ax-tabs-target-param"].delete_prefix("#") })
    expect(sections.reject { |section| section.key?("hidden") }.map { |section| section["id"] }).to eq(["lead-tab-stickiness"])
    expect(html.at_css("form[data-controller~='lead-settings'][data-controller~='ax-dirty-form'] .ax-studio-savebar")).to be_present
  end

  it "mantem os campos, os interruptores e os blocos condicionais" do
    get edit_admin_lead_setting_path

    html = Nokogiri::HTML(response.body)
    %w[stickiness_enabled secure_links_enabled notify_on_distribution lead_whatsapp_conversation_enabled reminder_due_enabled].each do |field|
      expect(html.at_css("input[type='checkbox'][name='lead_setting[#{field}]'].ax-switch__input")).to be_present, "faltou o interruptor #{field}"
    end
    %w[stickiness_window_days reminder_first_minutes stage_automation_sweep_interval_minutes secure_link_expiry_days].each do |field|
      expect(html.at_css("input[type='number'][name='lead_setting[#{field}]']")).to be_present, "faltou o campo #{field}"
    end
    expect(html.at_css("[data-lead-settings-target='stickinessSection']")).to be_present
    expect(html.at_css("[data-lead-settings-target='secureSection']")).to be_present
    expect(html.at_css("select[name='lead_setting[first_contact_sla_duration_unit]'][data-lead-settings-target='slaUnit']")).to be_present
    expect(html.at_css("input[type='radio'][name='lead_setting[push_lead_click_action]']")).to be_present
  end

  it "salva a configuracao do tenant autenticado" do
    patch admin_lead_setting_path, params: { lead_setting: { stickiness_enabled: "1", stickiness_window_days: "45" } }

    expect(response).to redirect_to(edit_admin_lead_setting_path)
    expect(LeadSetting.instance(tenant: admin.tenant)).to have_attributes(stickiness_enabled: true, stickiness_window_days: 45)
  end
end
