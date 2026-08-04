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
end
