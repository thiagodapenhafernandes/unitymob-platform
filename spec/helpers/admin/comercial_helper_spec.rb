require "rails_helper"

RSpec.describe Admin::ComercialHelper, type: :helper do

  it "mantém eventos práticos e oculta telemetria; o detalhado mostra também a confirmação do gateway" do
    [true, false].each do |detailed|
      %w[automation_event pocket_pool_ready secure_link_accessed unknown_event].each do |kind|
        expect(helper.lead_timeline_event_visible?(LeadActivity.new(kind: kind), detailed: detailed)).to eq(false)
      end
      %w[received distributed pocket_expired accepted notification_sent notification_failed].each do |kind|
        expect(helper.lead_timeline_event_visible?(LeadActivity.new(kind: kind), detailed: detailed)).to eq(true)
      end
      # "Envio da notificação confirmado" só aparece na linha do tempo detalhada.
      expect(helper.lead_timeline_event_visible?(PushDeliveryEvent.new(event_type: "provider_accepted"), detailed: detailed)).to eq(detailed)
      expect(helper.lead_timeline_event_visible?(PushDeliveryEvent.new(event_type: "device_received"), detailed: detailed)).to eq(true)
    end
    expect(helper.lead_timeline_event_visible?(LeadActivity.new(kind: "task_completed"))).to eq(true)
  end
  it "separa avisos por canal e preserva os marcos comuns nas duas trajetórias" do
    common = %w[received distributed pocket_expired accepted].map { |kind| LeadActivity.new(kind: kind, metadata: { channel: "whatsapp" }) }
    whatsapp = LeadActivity.new(kind: "notification_sent", metadata: { channel: "whatsapp" })
    push = LeadActivity.new(kind: "notification_failed", metadata: { channel: "push" })
    device = PushDeliveryEvent.new(event_type: "device_received")
    email = LeadActivity.new(kind: "notification_sent", metadata: { channel: "email" })
    entries = [whatsapp, push, device, email, *common]
    expect(helper.lead_timeline_for_channel(entries, channel: "whatsapp")).to eq([whatsapp, email, *common])
    expect(helper.lead_timeline_for_channel(entries, channel: "push")).to eq([push, device, email, *common])
  end

  it "agrupa recebimentos do aparelho pelo corretor e envio, mantendo segundos no detalhe" do
    helper.extend Admin::UiHelper
    at = Time.zone.local(2026, 9, 13, 11, 0, 13)
    send = LeadActivity.new(lead_id: 1, kind: "notification_sent", created_at: at, metadata: { channel: "push", admin_user_id: 7, notification_context: "pool" })
    previous = LeadActivity.new(lead_id: 1, kind: "notification_sent", created_at: at - 10.minutes, metadata: send.metadata)
    receipt = PushDeliveryEvent.new(lead_id: 1, admin_user_id: 7, event_type: "device_received", created_at: at + 4.seconds)
    other = PushDeliveryEvent.new(lead_id: 1, admin_user_id: 8, event_type: "device_received", created_at: at + 4.seconds)
    orphan = PushDeliveryEvent.new(lead_id: 2, admin_user_id: 7, event_type: "device_received", created_at: at + 4.seconds)
    groups = helper.lead_timeline_push_receipts([previous, send, receipt, other, orphan])
    expect(groups).to eq(send => [receipt])
    allow(helper).to receive(:push_delivery_timeline_detail).and_return("Aplicativo")
    html = helper.render(partial: "admin/leads/timeline_entries", locals: { entries: [send], push_receipts: groups })
    document = Nokogiri::HTML.fragment(html)
    expect(document.at_css("details[open]")).to be_nil
    expect(document.at_css("details").text).to include("Notificação recebida no aparelho", "13/09/2026 11:00:17")
    expect(html).not_to include("13/09/2026 11:00:13")
  end

  describe "avisos na linha do tempo" do
    it "identifica o canal e o contexto registrado sem inferir a regra atual do lead" do
      [
        ["pool", nil, "whatsapp", "Bolsão", :info, "bi-whatsapp", "green"],
        ["shark_tank", 22, "push", "Bolsão", :info, "bi-bell-fill", "purple"],
        ["distribution", 22, "email", "Rodízio", :success, "bi-envelope-fill", "cyan"],
        ["distribution", nil, "push", nil, nil, "bi-bell-fill", "purple"],
        [nil, 22, "whatsapp", nil, nil, "bi-whatsapp", "green"]
      ].each do |context, rule_id, channel, label, tone, icon, color|
        activity = LeadActivity.new(kind: "notification_sent", metadata: {
          notification_context: context, rule_id: rule_id, channel: channel
        })
        [true, false].each do |detailed|
          entry = helper.timeline_entry(activity, detailed: detailed)
          expect(entry[:label]).to eq("Aviso enviado ao corretor")
          expect(entry[:notification_mode]).to eq(label ? { label: label, tone: tone } : nil)
          expect(entry.values_at(:icon, :color)).to eq([icon, color])
        end
      end
    end

    it "omite segundos no aviso inicial e preserva segundos nos status do WhatsApp" do
      helper.extend Admin::UiHelper
      activity = LeadActivity.new(kind: "notification_sent", created_at: Time.zone.local(2026, 9, 13, 11, 0, 37))
      allow(helper).to receive(:timeline_entry).with(activity, detailed: true).and_return(
        icon: "bi-whatsapp", color: "green", label: "Aviso enviado ao corretor",
        notification_mode: { label: "Bolsão", tone: :info }, detail: "WhatsApp",
        whatsapp_status_events: [["Lido no WhatsApp", activity.created_at + 5.seconds, nil, :green]]
      )
      html = helper.render(partial: "admin/leads/timeline_entries", locals: { entries: [activity] })
      expect(html).not_to include("13/09/2026 11:00:37")
      expect(html).to include("13/09/2026 11:00", "13/09/2026 11:00:42", "ax-badge--info", "Bolsão", 'data-brand="whatsapp"', 'aria-hidden="true"')
    end
  end

  describe "fidelização na linha do tempo" do
    it "explica a fidelização nos modos resumido e detalhado usando o nome registrado no evento" do
      activity = LeadActivity.new(kind: "distributed", created_at: Time.current, metadata: {
        "sticky" => true, "admin_user_name" => "Renata Santos Cardoso", "rule_name" => "Equipe vendas"
      })
      [true, false].each do |detailed|
        entry = helper.timeline_entry(activity, detailed: detailed)
        expect(entry[:label]).to eq("Encaminhado por fidelização")
        expect(entry[:detail]).to include("Renata Santos Cardoso", "Cliente já atendido", "Sem consumir a vez no rodízio", "Equipe vendas")
        expect(entry[:detail]).not_to include("pela fila")
      end
    end

    it "preserva a apresentação da distribuição normal, sem inferir fidelização" do
      [nil, false, "false"].each do |sticky|
        activity = LeadActivity.new(kind: "distributed", metadata: { "sticky" => sticky, "admin_user_name" => "Levi", "rule_name" => "Equipe vendas" })
        expect(helper.timeline_entry(activity, detailed: false)[:label]).to eq("Lead enviado para corretor")
        expect(helper.timeline_entry(activity, detailed: false)[:detail]).to eq("Para Levi · pela fila Equipe vendas")
        expect(helper.timeline_entry(activity)[:label]).to eq("Distribuído")
      end
    end
  end

  describe "#lead_conversion_summary" do
    it "prefere a origem original do C2S em leads migrados" do
      lead = build_stubbed(
        :lead,
        origin: ExternalLeadIntegration::LEAD_ORIGIN,
        lead_type: "webhook",
        attribution_source: "Portal parceiro",
        attribution_channel: "Landing Page",
        attribution_data: {
          "provider" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
          "lead_source" => { "name" => "Portal parceiro" },
          "channel" => { "name" => "Landing Page" }
        },
        other_information: {
          "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:origin]).to eq("Portal parceiro")
      expect(summary[:channel_label]).to eq("Landing Page")
      expect(summary[:channel_label]).not_to eq("Webhook")
    end

    it "mantem a origem do lead quando nao veio da migracao externa" do
      lead = build_stubbed(:lead, origin: "Facebook Leads", lead_type: nil)

      expect(helper.lead_conversion_summary(lead)[:origin]).to eq("Facebook Leads")
    end

    it "usa fonte e canal comerciais em leads recebidos por webhook nativo" do
      lead = build_stubbed(
        :lead,
        origin: "webhook",
        lead_type: "webhook",
        product: "Apartamento no Centro",
        other_information: {
          "source" => "Instagram Leads",
          "channel" => "social",
          "webhook_payload" => {
            "utm_source" => "instagram",
            "utm_medium" => "social"
          }
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:origin]).to eq("Instagram Leads")
      expect(summary[:channel_label]).to eq("Rede Social")
      expect(helper.lead_card_interest_line(lead, summary)).to eq("Rede Social - Apartamento no Centro")
    end

    it "separa origem direta da conversao feita pelo site" do
      lead = build_stubbed(
        :lead,
        origin: "Site",
        lead_type: "whatsapp_modal",
        source_url: "https://conexaobc.com/imoveis/apartamento-centro-2431",
        attribution_channel: "direct",
        attribution_data: {
          "captured_at" => "2026-09-03T15:54:25-03:00",
          "landing_url" => "https://conexaobc.com/imoveis/apartamento-centro-2431"
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:channel]).to eq(:direct)
      expect(summary[:lead_origin_label]).to eq("Direto / origem desconhecida")
      expect(summary[:conversion_origin_label]).to eq("Site")
      expect(summary[:headline]).to eq("Criado por um formulário do site")
      expect(helper.lead_conversion_summary_label(summary)).to eq("Origem: Direto / origem desconhecida · Conversão: Site")
    end

    it "mantem origem de midia separada da conversao pelo site" do
      lead = build_stubbed(
        :lead,
        origin: "Site",
        lead_type: "whatsapp_modal",
        source_url: "https://conexaobc.com/imoveis/apartamento-centro-2431",
        attribution_source: "google",
        attribution_channel: "google_ads",
        attribution_data: {
          "utm_source" => "google",
          "utm_medium" => "cpc",
          "landing_url" => "https://conexaobc.com/imoveis/apartamento-centro-2431"
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:lead_origin_label]).to eq("Google Ads")
      expect(summary[:conversion_origin_label]).to eq("Site")
      expect(helper.lead_conversion_origin_badge_label(summary)).to eq("Conversão: Site")
      expect(helper.lead_tracking_origin_text(summary)).to eq("Origem: Google Ads")
    end

    it "aproveita utm_source quando o canal veio como direto" do
      lead = build_stubbed(
        :lead,
        origin: "Site",
        lead_type: "whatsapp_modal",
        source_url: "https://conexaobc.com/imoveis/apartamento-centro-2431",
        attribution_channel: "direct",
        attribution_data: {
          "utm_source" => "google",
          "landing_url" => "https://conexaobc.com/imoveis/apartamento-centro-2431"
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:channel_label]).to eq("Direto / origem desconhecida")
      expect(summary[:lead_origin_label]).to eq("Google")
      expect(summary[:conversion_origin_label]).to eq("Site")
    end
  end

  describe "#lead_card_interest_line" do
    it "troca webhook tecnico por canal comercial em leads C2S" do
      lead = build_stubbed(
        :lead,
        origin: ExternalLeadIntegration::LEAD_ORIGIN,
        lead_type: "webhook",
        product: "[3937] Form Varekai",
        attribution_data: {
          "provider" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY,
          "channel" => { "name" => "Landing Page" }
        },
        other_information: {
          "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY
        }
      )

      expect(helper.lead_card_interest_line(lead)).to eq("Landing Page - [3937] Form Varekai")
    end

    it "usa origem e canal do payload legado C2S" do
      lead = build_stubbed(
        :lead,
        origin: "C2S",
        lead_type: "webhook",
        other_information: {
          "source" => "c2s",
          "attributes" => {
            "lead_source" => { "name" => "Instagram Leads" },
            "channel" => { "name" => "Internet" }
          }
        }
      )

      summary = helper.lead_conversion_summary(lead)

      expect(summary[:origin]).to eq("Instagram Leads")
      expect(summary[:lead_origin_label]).to eq("Instagram Leads")
      expect(summary[:channel_label]).to eq("Internet")
    end
  end

  it "mantém o canal importado como fallback quando não há origem específica" do
    lead = build_stubbed(:lead, origin: "Migração externa", attribution_channel: "Internet",
      attribution_data: { "provider" => "external_lead_migration", "channel" => { "name" => "Internet" } })
    expect(helper.lead_conversion_summary(lead)[:lead_origin_label]).to eq("Internet")
  end

  describe "#lead_card_business_label" do
    it "identifica venda pelo produto importado do C2S" do
      lead = build_stubbed(
        :lead,
        product: "[7991] | Venda | Residencial Ecoville",
        other_information: { "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY }
      )

      expect(helper.lead_card_business_label(lead)).to eq("Venda")
    end

    it "identifica locacao pela negociacao do payload C2S" do
      lead = build_stubbed(
        :lead,
        product: "Apartamento no Centro",
        attribution_data: {
          "product" => {
            "real_estate_detail" => {
              "negotiation_name" => "Locação anual"
            }
          }
        },
        other_information: { "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY }
      )

      expect(helper.lead_card_business_label(lead)).to eq("Locação")
    end

    it "identifica captacao quando o lead veio para captar imovel" do
      lead = build_stubbed(:lead, product: "Captar apto", lead_type: "webhook")

      expect(helper.lead_card_business_label(lead)).to eq("Captação")
    end
  end

  describe "#lead_card_note_line" do
    it "traduz rotulos tecnicos em ingles para texto comum" do
      lead = build_stubbed(
        :lead,
        notes: "Full name: Sara franca Phone number: 5541996607000 Message: Quero atendimento",
        origin: ExternalLeadIntegration::LEAD_ORIGIN,
        attribution_data: { "provider" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY },
        other_information: { "source" => ExternalLeadMigration::LeadMapper::PROVIDER_KEY }
      )

      expect(helper.lead_card_note_line(lead)).to eq(
        "Nome completo: Sara franca Telefone: 5541996607000 Mensagem: Quero atendimento"
      )
    end

    it "nao exibe payload tecnico serializado no card do lead" do
      lead = build_stubbed(
        :lead,
        notes: '{"id"=>"4e42462f78f54164142a48ca83e2b75f", "sender_id"=>"7c123"}',
        origin: "Facebook",
        lead_type: "WhatsApp"
      )

      expect(helper.lead_card_note_line(lead)).to eq("Facebook")
    end
  end
end

RSpec.describe Admin::ComercialHelper, type: :helper do
  it "explicita Google orgânico para registros legados e novos" do
    [ {}, {"version" => 2} ].each do |data|
      lead = build(:lead, origin: "Site", attribution_channel: "organic_search", attribution_source: "google", attribution_data: data)
      expect(helper.lead_conversion_summary(lead)[:lead_origin_label]).to eq("Google orgânico")
    end
  end

  it "mostra TikTok Ads e não confunde clique Meta com anúncio" do
    lead = build(:lead, origin: "Site")
    Leads::Attribution.apply!(lead, raw: {ttclid: "click"})
    expect(helper.lead_conversion_summary(lead)).to include(lead_origin_label: "TikTok Ads", icon: "bi-tiktok")
    other = build(:lead, origin: "Site")
    Leads::Attribution.apply!(other, raw: {fbclid: "click"})
    expect(helper.lead_conversion_summary(other)).to include(lead_origin_label: "Meta", channel: :social)
  end
end

RSpec.describe Admin::ComercialHelper, type: :helper do
  it "mantém nome e ícone da mesma rede em atribuições sociais legadas" do
    {"meta" => ["Meta", "bi-meta"], "instagram" => ["Instagram", "bi-instagram"], "facebook" => ["Facebook", "bi-facebook"]}.each do |source, (label, icon)|
      lead = build(:lead, origin: "Site", attribution_channel: "organic_social", attribution_source: source, attribution_data: {})
      expect(helper.lead_conversion_summary(lead)).to include(lead_origin_label: label, icon: icon)
    end
  end
end
