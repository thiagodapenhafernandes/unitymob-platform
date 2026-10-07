require "rails_helper"

RSpec.describe Linkedin::ReceiveLead do
  let(:integration) { create(:linkedin_integration) }
  let(:client) { instance_double(Linkedin::Client) }
  let(:response_data) do
    { "id" => "response-1", "leadType" => "SPONSORED", "testLead" => false,
      "owner" => { "sponsoredAccount" => "urn:li:sponsoredAccount:123" },
      "versionedLeadGenFormUrn" => "urn:li:versionedLeadGenForm:(urn:li:leadGenForm:789,1)",
      "leadMetadata" => { "sponsoredLeadMetadata" => { "campaign" => "urn:li:sponsoredCampaign:456" } },
      "submittedAt" => (Time.current.to_f * 1000).to_i,
      "formResponse" => { "answers" => [
        { "questionId" => 1, "answerDetails" => { "textQuestionAnswer" => { "answer" => "Ana" } } },
        { "questionId" => 2, "answerDetails" => { "textQuestionAnswer" => { "answer" => "ana@example.com" } } }
      ], "consentResponses" => [{ "accepted" => true, "consentId" => 1 }] } }
  end
  let(:form) do
    { "id" => 789, "name" => "Formulário LinkedIn", "owner" => { "sponsoredAccount" => "urn:li:sponsoredAccount:123" },
      "content" => { "questions" => [
        { "questionId" => 1, "predefinedField" => "FIRST_NAME", "question" => { "localized" => { "pt_BR" => "Nome" } } },
        { "questionId" => 2, "predefinedField" => "EMAIL", "question" => { "localized" => { "pt_BR" => "E-mail" } } }
      ] } }
  end
  before { allow(client).to receive(:form).with("789").and_return(form) }

  def ingest(data = response_data)
    described_class.call(integration, data, client: client)
  end

  it "recebe e-mail sem telefone, preserva atribuição e respostas, e não duplica" do
    ingest
    lead = integration.tenant.leads.find_by!(origin: "LinkedIn Ads")
    expect(lead).to have_attributes(name: "Ana", email: "ana@example.com", phone: nil, admin_user_id: nil, attribution_channel: "linkedin_ads")
    expect(lead.attribution_data["campaign_name"]).to eq("Campanha LinkedIn")
    expect(lead.other_information["linkedin_answers"]).to eq("Nome" => "Ana", "E-mail" => "ana@example.com")
    expect { ingest }.not_to change(Lead, :count)
    expect(LinkedinLeadReceipt.where(tenant: integration.tenant).count).to eq(1)
  end

  it "encaminha o lead pelo roteamento existente e pela regra LinkedIn" do
    rule = create(:distribution_rule, tenant: integration.tenant, source_site: false, source_linkedin: true,
      linkedin_campaign_ids: ["456"], linkedin_form_ids: ["789"], distribution_mode: :shark_tank)
    ingest
    lead = integration.tenant.leads.find_by!(origin: "LinkedIn Ads")
    expect(lead.distribution_rule_id).to eq(rule.id)
    expect(lead.activities.where(kind: "shark_tank_ready")).to exist
  end

  it "mantém a idempotência mesmo depois que o lead é removido ou complementado" do
    ingest
    LinkedinLeadReceipt.find_by!(tenant: integration.tenant).lead.destroy!
    expect { ingest }.not_to change(Lead, :count)
  end

  it "rejeita uma conta não selecionada e não grava recibo" do
    response_data["owner"]["sponsoredAccount"] = "urn:li:sponsoredAccount:999"
    expect { ingest }.to raise_error(Linkedin::Client::Error)
    expect(LinkedinLeadReceipt.where(tenant: integration.tenant)).to be_empty
  end

  it "não aceita o formulário de outra conta" do
    form["owner"]["sponsoredAccount"] = "urn:li:sponsoredAccount:999"
    expect { ingest }.to raise_error(Linkedin::Client::Error)
  end

  it "ignora leads de teste" do
    expect { ingest(response_data.merge("testLead" => true)) }.not_to change(Lead, :count)
  end

  it "uma resposta sem contato falha sem consumir o recibo" do
    form["content"]["questions"].last["predefinedField"] = "COMPANY_NAME"
    expect { ingest }.to raise_error(Linkedin::Client::Error, /telefone nem e-mail/)
    expect(LinkedinLeadReceipt.where(tenant: integration.tenant)).to be_empty
  end

  it "não libera a ausência de telefone em leads comuns" do
    lead = build(:lead, tenant: integration.tenant, phone: nil, email: "ana@example.com")
    expect(lead).not_to be_valid
    expect(lead.errors[:phone]).to be_present
  end

  it "o mesmo ID de resposta pode chegar a tenants distintos" do
    ingest
    other = create(:linkedin_integration, admin_user: create(:admin_user, :admin, tenant: Tenant.create!(name: "Outra conta", slug: "linkedin-other")))
    expect { described_class.call(other, response_data, client: client) }.to change(Lead, :count).by(1)
  end
end
