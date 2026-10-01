require "rails_helper"

RSpec.describe PublicForm do
  it "cria o formulário padrão de anuncie seu imóvel com campos essenciais" do
    tenant = Tenant.create!(name: "Conta Form #{SecureRandom.hex(3)}", slug: "conta-form-#{SecureRandom.hex(3)}")

    form = described_class.ensure_default_announce_property!(tenant: tenant)

    expect(form).to be_persisted
    expect(form.slug).to eq("anuncie-seu-imovel")
    expect(form.category).to eq("property_announcement")
    expect(form.fields.pluck(:name)).to include("name", "phone", "interest", "property_details")
    expect(form.fields.find_by!(name: "interest").normalized_options.map { |option| option["value"] }).to contain_exactly("venda", "locacao")
    expect(form.modal_config.to_json).not_to include("Salute")
  end

  it "cria os formulários públicos padrão que entram no builder" do
    tenant = Tenant.create!(name: "Conta Defaults #{SecureRandom.hex(3)}", slug: "conta-defaults-#{SecureRandom.hex(3)}")

    forms = described_class.ensure_default_site_forms!(tenant: tenant)

    expect(forms.map(&:slug)).to contain_exactly("anuncie-seu-imovel", "corretor-parceiro", "trabalhe-conosco")
    expect(tenant.public_forms.find_by!(slug: "corretor-parceiro").category).to eq("partnership")
    expect(tenant.public_forms.find_by!(slug: "trabalhe-conosco").category).to eq("career")
  end

  it "valida a saída dos dados do formulário" do
    tenant = Tenant.create!(name: "Conta Saída #{SecureRandom.hex(3)}", slug: "conta-saida-#{SecureRandom.hex(3)}")
    rule = create(:distribution_rule, tenant: tenant)
    other_rule = create(:distribution_rule)
    form = tenant.public_forms.new(
      name: "Contato", slug: "contato", category: "custom",
      title: "Contato", submit_label: "Enviar", success_message: "Ok"
    )

    form.webhook_url = "nota-url"
    expect(form).not_to be_valid
    expect(form.errors[:webhook_url]).to be_present

    form.webhook_url = "https://hooks.example.com/lead"
    form.distribution_rule = other_rule
    expect(form).not_to be_valid
    expect(form.errors[:distribution_rule]).to be_present

    form.distribution_rule = rule
    expect(form).to be_valid
    expect(form.routes_to_distribution?).to be(true)
  end

  it "usa Premium extra-grande como apresentação padrão do modal" do
    tenant = Tenant.create!(name: "Conta Modal #{SecureRandom.hex(3)}", slug: "conta-modal-#{SecureRandom.hex(3)}")
    form = tenant.public_forms.create!(
      name: "Contato", slug: "contato", category: "custom",
      title: "Contato", submit_label: "Enviar", success_message: "Ok"
    )

    expect(form.modal_layout).to eq("premium")
    expect(form.modal_size).to eq("xl")

    form.modal_layout = "avancado"
    expect(form).not_to be_valid
    form.modal_layout = "basic"

    form.modal_size = "gigante"
    expect(form).not_to be_valid
  end

  it "bloqueia tipos de campo não permitidos" do
    tenant = Tenant.create!(name: "Conta Campo #{SecureRandom.hex(3)}", slug: "conta-campo-#{SecureRandom.hex(3)}")
    form = tenant.public_forms.create!(
      name: "Captação",
      slug: "captacao",
      category: "custom",
      title: "Captação",
      submit_label: "Enviar",
      success_message: "Ok"
    )

    field = form.fields.build(field_type: "script", name: "payload", label: "Payload")

    expect(field).not_to be_valid
    expect(field.errors[:field_type]).to be_present
  end

  it "permite redirecionar apenas para caminho interno ou domínio ativo da conta" do
    tenant = Tenant.create!(name: "Conta Redirect #{SecureRandom.hex(3)}", slug: "conta-redirect-#{SecureRandom.hex(3)}")
    tenant.tenant_domains.create!(hostname: "salute.example.com", active: true, primary_domain: true)
    form = tenant.public_forms.new(
      name: "Contato",
      slug: "contato",
      category: "custom",
      title: "Contato",
      submit_label: "Enviar",
      success_message: "Ok"
    )

    form.redirect_url = "/obrigado"
    expect(form).to be_valid

    form.redirect_url = "https://www.salute.example.com/obrigado"
    expect(form).to be_valid

    form.redirect_url = "https://evil.example/phishing"
    expect(form).not_to be_valid
    expect(form.errors[:redirect_url]).to be_present
  end

  describe "status e active" do
    let(:attrs) { { tenant: Tenant.default, name: "Status", slug: "status-model", category: "custom", title: "T", submit_label: "Enviar", success_message: "Ok" } }

    it "só publicado fica no ar (active derivado do status)" do
      expect(PublicForm.create!(attrs.merge(slug: "s-pub", status: "published"))).to have_attributes(active: true, status: "published")
      expect(PublicForm.create!(attrs.merge(slug: "s-draft", status: "draft"))).to have_attributes(active: false, status: "draft")
      expect(PublicForm.create!(attrs.merge(slug: "s-off", status: "inactive"))).to have_attributes(active: false, status: "inactive")
      expect(PublicForm.active.where(slug: %w[s-pub s-draft s-off]).pluck(:slug)).to eq(["s-pub"])
    end

    it "código antigo que só grava active continua funcionando" do
      form = PublicForm.create!(attrs.merge(active: false))
      expect(form.status).to eq("inactive")

      form.update!(active: true)
      expect(form.reload).to have_attributes(status: "published", active: true)
    end

    it "sem status informado nasce publicado, como antes" do
      expect(PublicForm.create!(attrs)).to have_attributes(status: "published", active: true)
    end

    it "recusa status desconhecido" do
      expect(PublicForm.new(attrs.merge(status: "arquivado"))).not_to be_valid
    end
  end

  describe "benefícios (texto + ícone)" do
    it "aceita JSON do editor, texto antigo por linhas, listas salvas e ignora ícone fora da lista" do
      expect(PublicForm.normalize_benefits("Um\n\n  Dois  ")).to eq(%w[Um Dois])
      expect(PublicForm.normalize_benefits(%w[A B])).to eq(%w[A B])
      expect(PublicForm.normalize_benefits('[{"icon":"bi-star-fill","text":"X"},{"icon":"bi-nope","text":"Y"}]'))
        .to eq([{ "text" => "X", "icon" => "bi-star-fill" }, "Y"])
      expect(PublicForm.normalize_benefits("123")).to eq(%w[123])
      expect(PublicForm.normalize_benefits(nil)).to eq([])
    end

    it "benefit_items devolve sempre texto e ícone seguros para a view" do
      form = PublicForm.new(modal_config: { "benefits" => ["Simples", { "text" => "Com ícone", "icon" => "bi-key-fill" }, { "text" => "Hack", "icon" => "x onclick=1" }] })

      expect(form.benefit_items).to eq([
        { text: "Simples", icon: "bi-check-circle-fill" },
        { text: "Com ícone", icon: "bi-key-fill" },
        { text: "Hack", icon: "bi-check-circle-fill" }
      ])
    end

    it "normaliza ao salvar e continua compatível com os formulários padrão do site" do
      tenant = Tenant.default
      form = PublicForm.ensure_default_announce_property!(tenant: tenant)
      expect(form.reload.modal_config["benefits"]).to eq(["Visibilidade privilegiada", "Consultoria especializada", "Fotos profissionais"])
      expect(form.benefit_items.map { |item| item[:icon] }.uniq).to eq(["bi-check-circle-fill"])
    end
  end

  describe ".modal_link_problem" do
    let(:tenant) { Tenant.default }
    let(:attrs) { { name: "Fale conosco", slug: "fale-conosco", category: "custom", title: "T", submit_label: "Enviar", success_message: "Ok" } }

    it "avisa quando o formulário do #modal-ID está em rascunho ou inativo" do
      tenant.public_forms.create!(attrs.merge(status: "draft"))
      expect(PublicForm.modal_link_problem(tenant: tenant, url: "#modal-fale-conosco")).to include("Fale conosco", "Rascunho", "publique")

      tenant.public_forms.find_by!(slug: "fale-conosco").update!(status: "inactive")
      expect(PublicForm.modal_link_problem(tenant: tenant, url: "#modal-fale-conosco")).to include("Inativo")
    end

    it "avisa quando o formulário não existe ou está fora do modal" do
      expect(PublicForm.modal_link_problem(tenant: tenant, url: "#modal-nao-existe")).to include("nao-existe")

      tenant.public_forms.create!(attrs.merge(status: "published", modal_enabled: false))
      expect(PublicForm.modal_link_problem(tenant: tenant, url: "#modal-fale-conosco")).to include("Disponível para modal")
    end

    it "não avisa quando está tudo certo, nem para destinos que não são modal" do
      tenant.public_forms.create!(attrs.merge(status: "published", modal_enabled: true))

      expect(PublicForm.modal_link_problem(tenant: tenant, url: "#modal-fale-conosco")).to be_nil
      expect(PublicForm.modal_link_problem(tenant: tenant, url: "/contato")).to be_nil
      expect(PublicForm.modal_link_problem(tenant: tenant, url: nil)).to be_nil
    end

    it "só enxerga formulários da própria conta" do
      other = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(3)}")
      other.public_forms.create!(attrs.merge(status: "published"))

      expect(PublicForm.modal_link_problem(tenant: tenant, url: "#modal-fale-conosco")).to include("Nenhum formulário")
    end
  end
end
