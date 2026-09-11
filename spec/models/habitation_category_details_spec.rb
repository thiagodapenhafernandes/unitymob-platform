require "rails_helper"

RSpec.describe Habitation::CategoryDetails do
  it "oferece quatro grupos e inclui apartamento, cobertura, loft e diferenciado nos residenciais" do
    expect(Habitation::REGISTRATION_PROFILES.keys).to match_array(%w[imoveis_residenciais comerciais_industriais terrenos empreendimento])
    expect(Habitation::REGISTRATION_PROFILES.dig("imoveis_residenciais", :categories)).to include("Apartamento", "Cobertura", "Loft", "Diferenciado")
    expect(Habitation::CATEGORIES).to include("Diferenciado")
    expect(PropertyReviewPolicy.registration_type_for_category("Diferenciado")).to eq("imoveis_residenciais")
    expect(PropertyReviewPolicy.registration_type_for_category("Apartamento")).to eq("apartamentos")
  end

  it "interpreta o grupo antigo sem reescrever o registro nem perder dados" do
    property = create(:habitation, categoria: "Apartamento", dormitorios_qtd: 3)
    property.update_column(:registration_profile, "apartamentos")
    property.reload
    expect(property.registration_group).to eq("imoveis_residenciais")
    expect(property).to be_valid
    property.update!(salas_qtd: 2)
    expect(property.reload.registration_profile).to eq("apartamentos")
    expect(property.dormitorios_qtd).to eq(3)
    expect(property.update(registration_profile: "terrenos")).to be(false)
  end

  it "normaliza o alias somente na criação e aceita sua equivalência na edição" do
    property = create(:habitation, categoria: "Apartamento", registration_profile: "apartamentos")
    expect(property.registration_profile).to eq("imoveis_residenciais")
    property.update_column(:registration_profile, "apartamentos")
    expect(property.reload.update(registration_profile: "imoveis_residenciais")).to be(true)
  end

  it "mantém todos os detalhes opcionais em imóveis antigos e não infere números dos checklists" do
    property = create(:habitation, categoria: "Galpão", caracteristicas: ["Pé-direito livre", "Área de armazenagem"], infra_estrutura: ["Docas"])
    expect(property.pe_direito_livre_m).to be_nil
    expect(property.area_armazenagem_m2).to be_nil
    expect(property.docas_qtd).to be_nil
    expect(property.reload).to be_valid
  end

  it "valida medidas, capacidades e contagens sem confundir vazio com zero" do
    property = build(:habitation, categoria: "Galpão", pe_direito_livre_m: 12.5, capacidade_eletrica_kva: 500, docas_qtd: 0)
    expect(property).to be_valid
    property.docas_qtd = 1.5
    property.pe_direito_livre_m = 0
    expect(property).not_to be_valid
    expect(property.errors[:docas_qtd]).to be_present
    expect(property.errors[:pe_direito_livre_m]).to be_present
    property.docas_qtd = nil
    property.pe_direito_livre_m = nil
    expect(property).to be_valid
  end

  it "normaliza seleções múltiplas e exige complemento de Outros" do
    property = build(:habitation, categoria: "Galpão em Condomínio", caracteristicas: ["", " Operação industrial ", "Operação industrial", "Outra operação"])
    expect(property).not_to be_valid
    expect(property.caracteristicas_imovel).to eq(["Operação industrial", "Outra operação"])
    expect(property.errors[:outra_operacao_galpao]).to be_present
    property.outra_operacao_galpao = " Montagem "
    expect(property).to be_valid
    expect(property.outra_operacao_galpao).to eq("Montagem")
  end

  it "trata tipo de galpão legado como a opção completa do mapa" do
    property = build(:habitation, categoria: "Galpão", caracteristicas: ["Galpão de estrutura metálica"])
    expect(property.selected_warehouse_type).to eq("Galpão de Estrutura Metálica com Telhas de Zinco")
  end

  it "rejeita seleções únicas contraditórias sem apagar escolhas" do
    property = build(:habitation, categoria: "Galpão", caracteristicas: ["Classe A+", "Classe A"], infra_estrutura: ["Energia trifásica", "Energia bifásica"])
    expect(property).not_to be_valid
    expect(property.errors[:caracteristicas]).to be_present
    expect(property.errors[:infra_estrutura]).to be_present
    expect(property.caracteristicas_imovel).to include("Classe a+", "Classe a")
  end

  it "rejeita campos técnicos incompatíveis também fora do formulário" do
    property = build(:habitation, categoria: "Sala Comercial", docas_qtd: 2)
    expect(property).not_to be_valid
    expect(property.errors[:docas_qtd]).to include("não se aplica à categoria selecionada")
  end

  it "reutiliza frente e mantém as demais medidas do terreno" do
    property = build(:habitation, categoria: "Terreno", frente_terreno_m: 15, fundo_terreno_m: 15, lateral_1_terreno_m: 30, lateral_2_terreno_m: 30, setor_terreno: "07A")
    expect(property).to be_valid
    property.categoria = "Terreno em Condomínio"
    expect(property).to be_valid
  end

  it "protege medidas negativas no banco mesmo com validações Rails ignoradas" do
    property = create(:habitation, categoria: "Galpão")
    expect do
      Habitation.transaction(requires_new: true) { property.update_columns(docas_qtd: -1) }
    end.to raise_error(ActiveRecord::StatementInvalid, /habitations_docas_qtd_nonnegative/)
  end
  it "confirma a troca, retira dados incompatíveis e mantém os compatíveis" do
    property = create(:habitation, categoria: "Galpão", docas_qtd: 4, banheiros_qtd: 2, caracteristicas: ["CFTV"])
    property.categoria = "Sala Comercial"
    expect(property.save).to be(false)
    expect(property.reload.docas_qtd).to eq(4)
    property.assign_attributes(categoria: "Sala Comercial", confirm_category_change: "1")
    expect(property.save).to be(true)
    expect(property.reload.docas_qtd).to be_nil
    expect(property.banheiros_qtd).to eq(2)
    expect(property.caracteristicas).not_to include("CFTV")
    property.update!(categoria: "Loja")
    expect(property.banheiros_qtd).to eq(2)
  end

  it "não retira campos bloqueados mesmo com confirmação" do
    property = create(:habitation, categoria: "Galpão", docas_qtd: 2)
    property.assign_attributes(categoria: "Loja", confirm_category_change: "1")
    property.category_transition_locked_fields = ["docas_qtd"]
    expect(property.save).to be(false)
    expect(property.reload.docas_qtd).to eq(2)
  end

  it "preserva medidas na troca entre galpões e exclui somente o complemento de Outros desmarcado" do
    property = create(:habitation, categoria: "Galpão", docas_qtd: 2, caracteristicas: ["Outra operação"], outra_operacao_galpao: "Montagem")
    property.update!(categoria: "Galpão em Condomínio")
    expect(property.docas_qtd).to eq(2)
    property.update!(caracteristicas: ["Operação industrial"])
    expect(property.reload.outra_operacao_galpao).to be_nil
  end

  it "não aceita mobília contraditória e não bloqueia dados antigos em edição sem relação" do
    property = build(:habitation, categoria: "Loja", caracteristicas: ["Mobiliado", "Sem Mobília"])
    expect(property).not_to be_valid
    expect(property.errors[:caracteristicas]).to be_present
  end

  it "restaura dados na memória quando outro campo impede salvar a troca" do
    property = create(:habitation, categoria: "Galpão", docas_qtd: 3)
    property.assign_attributes(categoria: "Loja", confirm_category_change: "1", captador_commission_percentage: 101)
    expect(property.save).to be(false)
    expect(property.docas_qtd).to eq(3)
    expect(property.reload.docas_qtd).to eq(3)
  end

  it "valida quantidades e áreas alteradas no formulário, preservando valores legados sem edição" do
    property = create(:habitation, categoria: "Sala Comercial", salas_qtd: -1)
    property.category_form_submission = true
    property.observacoes = "Revisado"
    expect(property).to be_valid
    property.salas_qtd = 1.5
    property.area_total_m2 = 0
    expect(property).not_to be_valid
    expect(property.errors[:salas_qtd]).to be_present
    expect(property.errors[:area_total_m2]).to be_present
  end

  it "mantém apenas dez novas colunas e reutiliza os campos antigos" do
    expect(described_class::DETAIL_FIELDS.size).to eq(10)
    expect(Habitation.column_names).to include("area_util_m2", "frente_terreno_m", "caracteristicas", "infra_estrutura", "dimensoes_terreno")
    expect(Habitation.column_names & %w[area_total_construida_m2 testada_terreno_m rua_interna_condominio tipo_galpao operacoes_galpao layouts_galpao classificacao_galpao tipo_piso_galpao zoneamentos_galpao alimentacao_eletrica instalacoes_eletricas]).to be_empty
  end

  it "preserva seleções legadas conflitantes quando o grupo não foi editado" do
    property = create(:habitation, categoria: "Galpão")
    property.update_columns(caracteristicas: { "Classe a" => "Classe a", "Classe aaa" => "Classe aaa" })
    property.reload.update!(observacoes: "Revisado")
    property.update!(caracteristicas: property.caracteristicas_imovel + ["Mezanino"])
    expect(property.reload.caracteristicas_imovel).to include("Classe a", "Classe aaa", "Mezanino")
  end

  it "preserva área útil construída antiga na troca de categoria" do
    property = create(:habitation, categoria: "Galpão", area_util_m2: 120)
    property.update!(categoria: "Loja", confirm_category_change: "1")
    expect(property.reload.area_util_m2).to eq(120)
  end

  it "preserva opções antigas e não cria repetições entre características e infraestrutura" do
    Habitation::REGISTRATION_PROFILES.each do |group, config|
      next if group == "empreendimento"
      config[:categories].each do |category|
        property = Habitation.new(registration_profile: group, categoria: category)
        features = property.category_checklist_options("feature")
        infra = property.category_checklist_options("infrastructure")
        next unless features && infra
        normalizer = AttributeOptions::HabitationFeatureNormalizer
        old_features = normalizer.normalize_list(property.standard_feature_options)
        old_infra = normalizer.normalize_list(property.standard_infrastructure_options, category: "infrastructure")
        expect(old_features - features).to be_empty, category
        expect(old_infra - infra).to be_empty, category
        expect((features & infra) - (old_features & old_infra)).to be_empty, category
      end
    end
  end

  it "mantém a trava de grupo sem a conversão interna da captação" do
    property = create(:habitation, :broker_intake, tipo: "Empreendimento", categoria: "Empreendimento")
    expect(property.update(tipo: "Unitário", categoria: "Apartamento", registration_profile: "imoveis_residenciais")).to be(false)
    expect(property.errors[:registration_profile]).to be_present
  end

  it "preserva a recarga herdada pelo terreno sem criar uma opção própria" do
    charger = described_class::EV_CHARGING_OPTION
    development = create(:habitation, tipo: "Empreendimento", categoria: "Empreendimento", infra_estrutura: [charger])
    land = create(:habitation, categoria: "Terreno em Condomínio", codigo_empreendimento: development.codigo)
    expect(land.standard_infrastructure_options).not_to include(charger)
    expect(land.caracteristicas_predio).to include(charger)
  end

end
