require "rails_helper"

RSpec.describe "Admin::LeadSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe a escolha operacional do destino do push" do
    get edit_admin_lead_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ao tocar na notificação")
    expect(response.body).to include("SLA de primeiro contato")
    expect(response.body).to include("lead_setting[first_contact_sla_hours]")
    expect(response.body).to include("lead_setting[stage_automation_sweep_interval_minutes]")
    expect(response.body).to include("lead_setting[lead_whatsapp_conversation_enabled]")
    expect(response.body).to include("Mostrar conversa WhatsApp dentro do lead")
    expect(response.body).to include("Aceita apenas valores entre 5 e 1440 minutos")
    expect(response.body).to include("Detalhes do lead primeiro")
    expect(response.body).to include("WhatsApp do lead direto")
    document = Nokogiri::HTML(response.body)
    expect(document.css("fieldset.ax-radio-group").size).to eq(4)
    expect(document.at_css('fieldset.ax-radio-group input[name="lead_setting[push_lead_click_action]"]')).to be_present
    expect(document.at_css('dl.ax-status-list[aria-label="Resumo das configurações de leads"]')).to be_present
    expect(document.at_css(".ax-form-actions--static")).to be_present
  end

  it "salva o destino operacional do clique no push pela tela de leads" do
    LeadSetting.instance.update!(push_lead_click_action: "whatsapp")

    patch admin_lead_setting_path, params: {
      lead_setting: {
        stickiness_enabled: "0",
        stickiness_match: "phone",
        stickiness_owner: "attended",
        stickiness_fallback: "active_in_rule",
        stickiness_window_days: "",
        first_contact_sla_hours: "6",
        stage_automation_sweep_interval_minutes: "10",
        lead_whatsapp_conversation_enabled: "0",
        secure_links_enabled: "1",
        secure_link_expiry_days: "7",
        secure_link_whatsapp: "1",
        secure_link_email: "1",
        secure_link_push: "1",
        push_lead_click_action: "system",
        notify_on_distribution: "1",
        notify_on_sticky: "1",
        notify_on_redistribution: "1",
        notify_on_shark_tank: "1",
        notify_on_direct_assignment: "1",
        notify_on_reassignment: "1",
        notify_on_lost_turn: "0"
      }
    }

    expect(response).to redirect_to(edit_admin_lead_setting_path)
    setting = LeadSetting.instance(tenant: admin.tenant).reload
    expect(setting.first_contact_sla_hours_value).to eq(6)
    expect(setting.stage_automation_sweep_interval_minutes_value).to eq(10)
    expect(setting).not_to be_lead_whatsapp_conversation_enabled
    expect(LeadSetting.instance(tenant: admin.tenant).reload.push_lead_click_action_value).to eq("system")
  end

  it "salva apenas a configuracao de leads do tenant autenticado" do
    other_tenant = Tenant.create!(name: "Conta leads externa #{SecureRandom.hex(3)}", slug: "leads-externa-#{SecureRandom.hex(4)}")
    other_setting = LeadSetting.create!(tenant: other_tenant, stickiness_enabled: true, push_lead_click_action: "whatsapp")

    patch admin_lead_setting_path, params: {
      lead_setting: {
        stickiness_enabled: "0",
        stickiness_match: "phone",
        stickiness_owner: "attended",
        stickiness_fallback: "active_in_rule",
        stickiness_window_days: "",
        first_contact_sla_hours: "4",
        stage_automation_sweep_interval_minutes: "15",
        secure_links_enabled: "0",
        secure_link_expiry_days: "7",
        push_lead_click_action: "system"
      }
    }

    expect(response).to redirect_to(edit_admin_lead_setting_path)
    expect(other_setting.reload).to be_stickiness_enabled
    expect(LeadSetting.instance(tenant: admin.tenant)).not_to be_stickiness_enabled
    # Regressão do bug: "Ao tocar na notificação" morava numa tabela global
    # (PushSetting) e vazava entre contas — agora é uma coluna por tenant.
    expect(other_setting.reload.push_lead_click_action_value).to eq("whatsapp")
    expect(LeadSetting.instance(tenant: admin.tenant).push_lead_click_action_value).to eq("system")
  end

  it "bloqueia acesso direto sem permissao de gerenciar distribuicao" do
    profile = Profile.create!(
      tenant: admin.tenant,
      name: "Sem distribuição #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 7_500,
      permissions: {}
    )
    viewer = create(:admin_user, tenant: admin.tenant, profile: profile, role: :editor)
    sign_out admin
    sign_in viewer

    get edit_admin_lead_setting_path

    expect(response).to redirect_to(admin_root_path)
  end
  it "salva tempos por conta e recusa configuração inválida" do
    other_tenant = Tenant.create!(name: "Outra conta", slug: "lembretes-outra-#{SecureRandom.hex(4)}")
    other_setting = LeadSetting.instance(tenant: other_tenant)
    LeadSetting.instance(tenant: admin.tenant).update!(stickiness_window_days: 90)
    patch admin_lead_setting_path, params: { lead_setting: {
      reminder_first_minutes: 90, reminder_second_minutes: 45, reminder_third_minutes: 20,
      reminder_overdue_minutes: 180, reminder_retry_minutes: 40, reminder_due_enabled: "0",
      reminder_start_time: "09:30", reminder_end_time: "17:45", tenant_id: other_tenant.id
    } }
    expect(response).to redirect_to(edit_admin_lead_setting_path)
    setting = LeadSetting.instance(tenant: admin.tenant).reload
    expect(setting.reminder_first_minutes).to eq(90)
    expect(setting.stickiness_window_days).to eq(90)
    expect(setting.reminder_due_enabled).to be(false)
    expect(setting.reminder_start_time).to eq("09:30")
    expect(other_setting.reload.reminder_first_minutes).to eq(60)
    patch admin_lead_setting_path, params: { lead_setting: { reminder_retry_minutes: 0 } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(setting.reload.reminder_retry_minutes).to eq(40)
  end

  it "renderiza os tempos padrão em controles nativos dentro do formulário de salvamento" do
    get edit_admin_lead_setting_path
    doc = Nokogiri::HTML(response.body)
    form = doc.at_css('form[action="/admin/lead_setting"]')
    { reminder_first_minutes: "60", reminder_second_minutes: "30", reminder_third_minutes: "15",
      reminder_overdue_minutes: "120", reminder_retry_minutes: "30" }.each do |field, value|
      input = form.at_css("input[name='lead_setting[#{field}]']")
      expect(input["type"]).to eq("number")
      expect(input["value"]).to eq(value)
      expect(input["required"]).not_to be_nil
    end
    expect(form.at_css('input[type="time"][name="lead_setting[reminder_start_time]"]')["value"]).to eq("08:00")
    expect(form.at_css('input[type="time"][name="lead_setting[reminder_end_time]"]')["value"]).to eq("18:00")
    expect(form.at_css('input[type="checkbox"][name="lead_setting[reminder_due_enabled]"]')["checked"]).not_to be_nil
  end

  it "salva o formulário completo sem alterar eventos, privacidade ou fidelização" do
    setting = LeadSetting.instance(tenant: admin.tenant)
    preserved = {
      notify_on_distribution: false, notify_on_sticky: true, notify_on_redistribution: false,
      notify_on_shark_tank: true, notify_on_direct_assignment: false, notify_on_reassignment: true,
      notify_on_lost_turn: false, stickiness_enabled: true, stickiness_window_days: 90,
      secure_links_enabled: true, secure_link_whatsapp: false, secure_link_email: true,
      secure_link_push: false, push_lead_click_action: "whatsapp"
    }
    setting.update!(preserved)
    get edit_admin_lead_setting_path
    form = Nokogiri::HTML(response.body).at_css('form[action="/admin/lead_setting"]')
    # Controles bem-sucedidos do navegador, incluindo os hidden dos checkboxes.
    pairs = form.css('input[name]').filter_map do |input|
      next if input["disabled"] || %w[submit button].include?(input["type"])
      next if %w[checkbox radio].include?(input["type"]) && !input["checked"]
      [input["name"], input["value"].to_s]
    end
    params = Rack::Utils.parse_nested_query(URI.encode_www_form(pairs))
    params.fetch("lead_setting").merge!("reminder_first_minutes" => "90", "reminder_second_minutes" => "45",
      "reminder_third_minutes" => "20", "reminder_due_enabled" => "0", "reminder_start_time" => "09:30",
      "reminder_end_time" => "17:45", "reminder_overdue_minutes" => "180", "reminder_retry_minutes" => "40")
    patch admin_lead_setting_path, params: params
    expect(response).to redirect_to(edit_admin_lead_setting_path)
    expect(setting.reload.attributes.symbolize_keys.slice(*preserved.keys)).to eq(preserved)
    expect(setting.reminder_first_minutes).to eq(90)
    expect(setting.reminder_due_enabled).to be(false)
    follow_redirect!
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('input[name="lead_setting[reminder_start_time]"]')["value"]).to eq("09:30")
    expect(doc.at_css('input[type="checkbox"][name="lead_setting[reminder_due_enabled]"]')["checked"]).to be_nil
    expect(response.body).to include("90, 45 e 20 minutos antes", "180 minutos, entre 09:30 e 17:45")
  end

  it "mantém valores e mostra erros ao rejeitar a ordem dos lembretes" do
    setting = LeadSetting.instance(tenant: admin.tenant)
    original = setting.attributes
    patch admin_lead_setting_path, params: { lead_setting: {
      reminder_first_minutes: 10, reminder_second_minutes: 30, reminder_third_minutes: 15,
      notify_on_shark_tank: "0"
    } }
    expect(response).to have_http_status(:unprocessable_entity)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('input[name="lead_setting[reminder_first_minutes]"]')["value"]).to eq("10")
    expect(doc.at_css('.ax-form-error-summary')).to be_present
    expect(setting.reload.attributes).to eq(original)
  end

end
