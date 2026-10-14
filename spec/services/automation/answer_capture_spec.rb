require "rails_helper"

RSpec.describe Automation::AnswerCapture do
  let(:tenant) { Tenant.default }
  let(:lead) { create(:lead, tenant: tenant, name: "Contato", email: "antigo@exemplo.com", phone: "5547999994321") }

  def capture(config, body)
    described_class.call(lead: lead, config: config, response_body: body)
  end

  describe ".validation_messages" do
    it "exige o nome da variavel e valida tipo e destino" do
      expect(described_class.validation_messages({})).to include(a_string_matching(/sem nome da variavel/))
      expect(described_class.validation_messages({ variable: "x", answer_type: "foo" })).to include(a_string_matching(/tipo invalido/))
      expect(described_class.validation_messages({ variable: "x", lead_target: "custom" })).to include(a_string_matching(/campo personalizado sem nome/))
      expect(described_class.validation_messages({ variable: "x", answer_type: "text", lead_target: "email" })).to include(a_string_matching(/nao e e-mail/))
      expect(described_class.validation_messages({ variable: "x", answer_type: "email", lead_target: "email" })).to be_empty
    end
  end

  it "guarda so a variavel quando nao ha destino no lead" do
    result = capture({ variable: "Nome Completo", answer_type: "text" }, "  Maria   Silva ")

    expect(result).to have_attributes(variable: "nome_completo", value: "Maria Silva", lead_written: false)
    expect(lead.reload.name).to eq("Contato")
  end

  it "grava o e-mail no lead normalizado e registra a mudanca na linha do tempo" do
    result = capture({ variable: "email", answer_type: "email", lead_target: "email" }, "MARIA@Exemplo.com")

    expect(result.lead_written).to be(true)
    expect(lead.reload.email).to eq("maria@exemplo.com")
    activity = LeadActivity.where(lead: lead, kind: "automation").last
    expect(activity.metadata).to include("field" => "email", "previous" => "antigo@exemplo.com", "value" => "maria@exemplo.com")
  end

  it "grava o nome no lead" do
    capture({ variable: "nome", answer_type: "text", lead_target: "name" }, "Maria Silva")

    expect(lead.reload.name).to eq("Maria Silva")
  end

  it "usa custom_answers (a lista dos formularios) sem apagar as outras respostas e atualiza a mesma chave" do
    lead.update!(custom_answers: [{ "key" => "orcamento", "answer" => "500 mil" }])
    config = { variable: "bairro", answer_type: "text", lead_target: "custom", custom_key: "Bairro de interesse", custom_label: "Bairro" }

    capture(config, "Centro")
    capture(config, "Itaim")

    answers = lead.reload.custom_answers
    expect(answers.size).to eq(2)
    expect(answers.find { |item| item["key"] == "orcamento" }["answer"]).to eq("500 mil")
    expect(answers.find { |item| item["key"] == "bairro_de_interesse" }).to include("answer" => "Itaim", "label" => "Bairro", "source" => "automation")
  end

  it "nao sobrescreve nada com resposta vazia" do
    result = capture({ variable: "email", answer_type: "email", lead_target: "email" }, "   ")

    expect(result).to have_attributes(lead_written: false, note: "resposta vazia")
    expect(lead.reload.email).to eq("antigo@exemplo.com")
  end

  it "normaliza telefone e numero" do
    expect(capture({ variable: "tel", answer_type: "phone" }, "(47) 99999-1234").value).to eq("5547999991234")
    expect(capture({ variable: "valor", answer_type: "number" }, "1500,50").value).to eq("1500.50")
  end

  describe "validacao do fluxo ao publicar" do
    def messages(config)
      definition = {
        "schema_version" => 1,
        "nodes" => [
          { "id" => "entry_1", "type" => "entry", "config" => { "trigger" => "lead_created", "entry_policy" => "future" } },
          { "id" => "capture", "type" => "action", "label" => "Guardar", "config" => { "action_type" => "capture_answer" }.merge(config) }
        ],
        "edges" => [{ "from" => "entry_1", "to" => "capture" }]
      }
      Automation::WorkflowDefinition.validate(definition, mode: :publish)
    end

    it "aceita a captura bem configurada e recusa a sem variavel" do
      expect(messages({ "variable" => "email", "answer_type" => "email", "lead_target" => "email" }).join(" ")).not_to include("guardar resposta")
      expect(messages({}).join(" ")).to include("guardar resposta sem nome da variavel")
    end
  end
end
