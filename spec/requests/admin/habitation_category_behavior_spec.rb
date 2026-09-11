require "rails_helper"

RSpec.describe "Cadastro por categoria", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
    allow_any_instance_of(Habitations::FieldLockPolicy).to receive(:unrestricted?).and_return(true)
  end

  it "renderiza todos os cenários com os componentes atuais e sem inputs duplicados" do
    Habitation::REGISTRATION_PROFILES.each do |group, config|
      config[:categories].each do |category|
        get new_admin_habitation_path(habitation: { registration_profile: group, categoria: category })
        expect(response).to have_http_status(:ok), category
        if ENV["CATEGORY_FORM_SNAPSHOTS"]
          FileUtils.mkdir_p(ENV["CATEGORY_FORM_SNAPSHOTS"])
          File.write(File.join(ENV["CATEGORY_FORM_SNAPSHOTS"], "#{category.parameterize}.html"), response.body)
        end
        html = Nokogiri::HTML(response.body)
        expect(html.css('[name="habitation[descricao_web]"]').size).to eq(1), category
        expect(html.css('[name="habitation[andares_qtd]"]').size).to eq(1), category
        expect(html.at_css('[data-habitation-form-detail-fields-value]')).to be_present
        Habitation::CategoryDetails::INTERNAL_EQUIPMENT_OPTIONS.each do |option|
          field = html.at_css("input[name='habitation[caracteristicas][]'][value='#{option}']")
          expect(field.present?).to eq(group.in?(%w[imoveis_residenciais comerciais_industriais])), "#{category}: #{option}"
        end
        charger = html.at_css("input[name='habitation[infra_estrutura][]'][value='#{Habitation::CategoryDetails::EV_CHARGING_OPTION}']")
        expect(charger.present?).to eq(group != "terrenos"), category
        warehouse_type_select = html.at_css('select#habitation_warehouse_type[name="habitation[caracteristicas][]"]')
        expect(warehouse_type_select.present?).to eq(group == "comerciais_industriais"), category
        if warehouse_type_select
          expect(warehouse_type_select.ancestors("[data-category-options]").first.has_attribute?("hidden")).to eq(!%w[Galpão Galpão\ em\ Condomínio].include?(category)), category
          expect(warehouse_type_select.css("option").map(&:text)).to include(*Habitation::CategoryDetails::WAREHOUSE_TYPE_OPTIONS)
          Habitation::CategoryDetails::WAREHOUSE_TYPE_OPTIONS.each do |option|
            expect(html.css("input[type='checkbox'][name='habitation[caracteristicas][]'][value='#{option}']")).to be_empty
          end
        end

        %w[caracteristicas infra_estrutura].each do |name|
          values = html.css("input[type='checkbox'][name='habitation[#{name}][]']").map { |input| input["value"] }
          expect(values).to eq(values.uniq), "#{category}: #{name} sem opções repetidas"
        end
      end
    end
  end

  it "salva os detalhes e audita a retirada confirmada na troca de categoria" do
    property = create(:habitation, tenant: admin.tenant, categoria: "Galpão", docas_qtd: 4)
    patch admin_habitation_path(property), params: { habitation: { categoria: "Loja" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(property.reload.docas_qtd).to eq(4)
    patch admin_habitation_path(property), params: { habitation: { categoria: "Loja", confirm_category_change: "1" } }
    expect(response).to have_http_status(:redirect)
    expect(property.reload.docas_qtd).to be_nil
    expect(property.categoria).to eq("Loja")
    log = HabitationAuditLog.where(habitation_id: property.id).order(:id).last
    expect(log.changeset.to_json).to include('"docas_qtd"', '4')
  end

  it "não salva o imóvel quando a prévia IA é aplicada" do
    property = create(:habitation, tenant: admin.tenant, titulo_anuncio: "Original")
    suggestion = property.ai_property_suggestions.create!(status: "pending", generated_title: "Novo título", generated_description: "Texto sugerido")
    patch apply_ai_suggestion_admin_habitation_path(property), params: { suggestion_id: suggestion.id }, headers: { "Turbo-Frame" => "preview" }
    expect(response).to have_http_status(:ok)
    expect(property.reload.titulo_anuncio).to eq("Original")
    expect(response.body).to include("Aplicar ao formulário")
  end
  it "preserva categoria legada ao editar outro campo" do
    property = create(:habitation, tenant: admin.tenant, categoria: "Casa")
    property.update_column(:categoria, "Dúplex antigo")
    get edit_admin_habitation_path(property)
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('select[name="habitation[categoria]"] option[selected]').text).to eq("Dúplex antigo")
    patch admin_habitation_path(property), params: { habitation: { registration_profile: "imoveis_residenciais", categoria: "Dúplex antigo", observacoes: "Revisado" } }
    expect(response).to have_http_status(:redirect)
    expect(property.reload.categoria).to eq("Dúplex antigo")
  end

  it "mantém no histórico o tipo de vaga retirado de um terreno legado" do
    property = create(:habitation, tenant: admin.tenant, categoria: "Terreno", tipo_vaga: "Privativa")
    patch admin_habitation_path(property), params: { habitation: { categoria: "Área", confirm_category_change: "1" } }
    expect(response).to have_http_status(:redirect)
    expect(property.reload.tipo_vaga).to be_nil
    log = property.habitation_audit_logs.order(:id).last
    expect(log.changeset.dig("tipo_vaga", "before")).to eq("Privativa")
    expect(log.change_summaries.map { |change| change[:field] }).to include("tipo_vaga")
  end

  it "salva as escolhas nos checklists e a área no campo antigo" do
    property = create(:habitation, tenant: admin.tenant, categoria: "Galpão")
    patch admin_habitation_path(property), params: { habitation: {
      caracteristicas: ["Galpão de Estrutura Metálica com Telhas de Zinco", "Classe A+", "Layout automatizado", "Operação industrial"],
      infra_estrutura: ["Energia trifásica", "Subestação"], area_util_m2: "450.50",
      area_total_construida_m2: "999", tipo_galpao: "duplicado"
    } }
    expect(response).to have_http_status(:redirect)
    expect(property.reload.area_util_m2).to eq(450.5)
    expect(property.caracteristicas_imovel).to include("Galpão de Estrutura Metálica com Telhas de Zinco", "Classe a+", "Layout automatizado", "Operação industrial")
    expect(property.caracteristicas_predio).to include("Energia trifásica", "Subestação")
  end

end
