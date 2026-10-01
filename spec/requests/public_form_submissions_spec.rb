require "rails_helper"

RSpec.describe "Public form submissions" do
  before { host! "localhost" }

  it "salva submissão e dispara webhook do formulário público" do
    tenant = Tenant.default
    form = PublicForm.ensure_default_announce_property!(tenant: tenant)
    allow(WebhookService).to receive(:send_form_data)

    post public_form_submissions_path(form.slug),
         params: {
           public_form_submission: {
             name: "Maria Cliente",
             phone: "(47) 99999-0000",
             interest: "venda",
             city_state: "Balneário Camboriú/SC",
             property_details: "Apartamento frente mar"
           },
           page_url: "https://saluteimoveis.com.br/"
         },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["success"]).to eq(true)
    submission = form.submissions.last
    expect(submission.normalized_name).to eq("Maria Cliente")
    expect(submission.normalized_phone).to eq("5547999990000")
    expect(WebhookService).to have_received(:send_form_data).with(
      form.webhook_origin,
      hash_including(
        "name" => "Maria Cliente",
        "phone" => "5547999990000",
        public_form_slug: form.slug,
        public_form_category: "property_announcement"
      ),
      hash_including(tenant: tenant, public_form: form)
    )
  end

  it "envia para a URL própria e agenda a distribuição pela regra do formulário" do
    tenant = Tenant.default
    form = PublicForm.ensure_default_announce_property!(tenant: tenant)
    rule = create(:distribution_rule, tenant: tenant)
    form.update!(webhook_url: "https://hooks.example.com/lead", distribution_rule: rule)
    allow(WebhookService).to receive(:send_form_data)

    expect do
      post public_form_submissions_path(form.slug),
           params: {
             public_form_submission: {
               name: "Maria Cliente",
               phone: "(47) 99999-0000",
               interest: "venda",
               city_state: "Balneário Camboriú/SC",
               property_details: "Apartamento frente mar"
             }
           },
           as: :json
    end.to have_enqueued_job(PublicFormLeadRoutingJob)

    expect(response).to have_http_status(:ok)
    expect(WebhookService).to have_received(:send_form_data).with(
      form.webhook_origin, hash_including("name" => "Maria Cliente"),
      hash_including(url: "https://hooks.example.com/lead", tenant: tenant, public_form: form)
    )
  end

  it "não agenda distribuição sem regra configurada" do
    tenant = Tenant.default
    form = PublicForm.ensure_default_announce_property!(tenant: tenant)
    allow(WebhookService).to receive(:send_form_data)

    expect do
      post public_form_submissions_path(form.slug),
           params: {
             public_form_submission: {
               name: "Maria Cliente",
               phone: "(47) 99999-0000",
               interest: "venda",
               city_state: "Balneário Camboriú/SC",
               property_details: "Apartamento frente mar"
             }
           },
           as: :json
    end.not_to have_enqueued_job(PublicFormLeadRoutingJob)

    expect(WebhookService).to have_received(:send_form_data).with(
      form.webhook_origin, anything,
      hash_excluding(:url)
    )
  end

  it "retorna erro quando campo obrigatório não é informado" do
    form = PublicForm.ensure_default_announce_property!(tenant: Tenant.default)

    post public_form_submissions_path(form.slug),
         params: {
           public_form_submission: {
             name: "Maria Cliente",
             interest: "venda"
           }
         },
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["success"]).to eq(false)
    expect(response.parsed_body["errors"].join).to include("WhatsApp / Telefone")
    expect(form.submissions).to be_empty
  end

  describe "campo de anexo" do
    let(:tenant) { Tenant.default }
    let(:form) do
      tenant.public_forms.create!(name: "Currículo", slug: "curriculo-anexo", category: "career", title: "Currículo",
                                  submit_label: "Enviar", success_message: "Ok").tap do |record|
        record.fields.create!(field_type: "text", name: "name", label: "Nome", required: true, position: 10)
        record.fields.create!(field_type: "file", name: "cv", label: "Currículo", required: true, position: 20,
                              config: { "kind" => "documents", "max_mb" => 1 })
      end
    end

    def upload(filename, content = "conteudo", type = "application/pdf")
      Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: filename)
    end

    before { allow(WebhookService).to receive(:send_form_data) }

    it "envia o arquivo para o storage de documentos da conta e anexa ao envio" do
      expect(Storage::Routing.service_name_for(record: PublicFormSubmission.new(tenant: tenant), name: "files"))
        .to eq(StorageIntegrationSetting.current(tenant: tenant).document_service_name)

      post public_form_submissions_path(form.slug),
           params: { public_form_submission: { name: "Ana", cv: upload("curriculo.pdf") } },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok), response.body
      submission = form.submissions.last
      expect(submission.payload["cv"]).to eq(["curriculo.pdf"])
      expect(submission.files.map { |file| file.filename.to_s }).to eq(["curriculo.pdf"])
      expect(submission.files.first.key).to start_with("tenants/#{tenant.id}/public_forms/#{form.slug}/cv/")
      expect(submission.files.first.service_name.to_s).to eq(StorageIntegrationSetting.current(tenant: tenant).document_service_name.to_s)
    end

    it "recusa extensão fora da lista do campo" do
      post public_form_submissions_path(form.slug),
           params: { public_form_submission: { name: "Ana", cv: upload("virus.exe", "MZ", "application/x-msdownload") } },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].join).to include("virus.exe")
      expect(form.submissions).to be_empty
      expect(ActiveStorage::Blob.where(filename: "virus.exe")).to be_empty
    end

    it "recusa arquivo acima do limite e exige o anexo obrigatório" do
      post public_form_submissions_path(form.slug),
           params: { public_form_submission: { name: "Ana", cv: upload("grande.pdf", "x" * 2.megabytes) } },
           headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)

      post public_form_submissions_path(form.slug),
           params: { public_form_submission: { name: "Ana" } },
           headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].join).to include("Currículo é obrigatório")
      expect(form.submissions).to be_empty
    end

    it "não aceita vários arquivos quando o campo não permite" do
      post public_form_submissions_path(form.slug),
           params: { public_form_submission: { name: "Ana", cv: [upload("a.pdf"), upload("b.pdf")] } },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(form.submissions).to be_empty
    end
  end

  it "só recebe envios de formulário publicado (rascunho e inativo respondem 404)" do
    tenant = Tenant.default
    %w[draft inactive].each do |status|
      form = tenant.public_forms.create!(name: "F #{status}", slug: "f-#{status}", category: "custom", title: "T", submit_label: "Enviar", success_message: "Ok", status: status)
      form.fields.create!(field_type: "text", name: "name", label: "Nome", position: 10)

      post public_form_submissions_path(form.slug), params: { public_form_submission: { name: "Ana" } }, as: :json

      expect(response).to have_http_status(:not_found), status
      expect(form.submissions).to be_empty
    end
  end

  describe "campos com máscara" do
    let(:tenant) { Tenant.default }
    let(:form) do
      tenant.public_forms.create!(name: "Com máscara", slug: "com-mascara", category: "career", title: "T", submit_label: "Enviar", success_message: "Ok").tap do |record|
        record.fields.create!(field_type: "text", name: "name", label: "Nome", required: true, position: 10)
        record.fields.create!(field_type: "text", name: "creci", label: "CRECI", position: 20, config: { "mask" => "00000-A" })
        record.fields.create!(field_type: "tel", name: "phone", label: "Telefone", position: 30, config: { "mask" => "(00) 00000-0000" })
        record.fields.create!(field_type: "currency", name: "valor", label: "Valor", position: 40)
      end
    end

    before { allow(WebhookService).to receive(:send_form_data) }

    def enviar(values)
      post public_form_submissions_path(form.slug), params: { public_form_submission: { name: "Ana" }.merge(values) }, as: :json
    end

    it "guarda o valor como o visitante viu (telefone continua normalizado pelo sistema)" do
      enviar(creci: "12345-F", phone: "(47) 99999-0000", valor: "R$ 1.234,56")

      expect(response).to have_http_status(:ok)
      payload = form.submissions.last.payload
      expect(payload).to include("creci" => "12345-F", "valor" => "R$ 1.234,56")
      expect(payload["phone"]).to eq("5547999990000")
    end

    it "recusa valor fora do formato com mensagem e não cria o envio" do
      enviar(creci: "1234", valor: "R$ 12,5")

      expect(response).to have_http_status(:unprocessable_entity)
      errors = response.parsed_body["errors"].join(" ")
      expect(errors).to include("CRECI: use o formato 00000-A", "Valor: use o formato R$ 0,00")
      expect(form.submissions).to be_empty
    end

    it "campo com máscara vazio e opcional passa" do
      enviar(creci: "", phone: "")

      expect(response).to have_http_status(:ok)
    end
  end
end
