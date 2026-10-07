require "rails_helper"

RSpec.describe Admin::LeadOriginHelper, type: :helper do
  before do
    helper.extend Admin::ComercialHelper
    helper.extend Admin::LeadTableHelper
    helper.extend Admin::UiHelper
  end
  let(:lead) do
    build(:lead, origin: "LinkedIn Ads", attribution_source: "linkedin", attribution_channel: "linkedin_ads",
      attribution_data: { "version" => 2, "campaign_name" => "Campanha teste" },
      other_information: { "linkedin_form_id" => "789", "linkedin_form_name" => "Form teste", "linkedin_account_id" => "123", "linkedin_answers" => { "Interesse" => "<script>alert(1)</script>" } })
  end

  it "apresenta identidade LinkedIn, campanha e formulário pela camada compartilhada" do
    origin = helper.lead_origin_column(lead, tenant: lead.tenant)
    expect(origin).to include(brand: "linkedin", label: "LinkedIn Ads")
    expect(origin[:complements]).to include("Formulário: Form teste", "Campanha: Campanha teste")
    html = helper.render("admin/shared/ui/lead_origin", origin: origin)
    expect(html).to include('data-brand="linkedin"', "linkedin")
    conversion = helper.lead_conversion_summary(lead)
    expect(conversion).to include(icon: "bi-linkedin", channel_label: "LinkedIn Ads")
    expect(helper.lead_table_conversion(lead, conversion)[:label]).to eq("Formulário: Form teste")
  end

  it "mostra as respostas escapadas no painel compartilhado de desktop e mobile" do
    html = helper.render("admin/shared/ui/lead_form_responses", lead: lead)
    expect(html).to include("Respostas do formulário LinkedIn", "Interesse", "&lt;script&gt;")
    expect(html).not_to include("<script>alert")
  end
end
