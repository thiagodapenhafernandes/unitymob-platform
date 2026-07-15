require "rails_helper"

RSpec.describe Habitations::CadastroFieldRegistry do
  FORM_TABS_DIR = Rails.root.join("app/views/admin/habitations/form_tabs")

  # Campos que aparecem no formulário via `method: :x` (form.object = habitation
  # ou address_attributes). É a base de completude.
  def form_field_methods
    Dir.glob(FORM_TABS_DIR.join("**/*.erb")).flat_map do |file|
      source = File.read(file)
      source.scan(/method:\s*:([a-z0-9_]+)/).flatten +
        source.scan(/ax_toggle_chip\(\s*f,\s*:([a-z0-9_]+)/m).flatten +
        source.scan(/(?:f|address_form)\.(?:text_field|select|check_box|radio_button|file_field|hidden_field|rich_text_area)\s*:([a-z0-9_]+)/).flatten +
        source.scan(/name=["']habitation\[([a-z0-9_]+)/).flatten +
        source.scan(/input_name:\s*["']habitation\[([a-z0-9_]+)/).flatten +
        source.scan(/(?:hidden|check|file)_field_tag\s+["']habitation\[([a-z0-9_]+)/).flatten
    end.uniq
  end

  def covered_form_fields
    described_class.all_items.flat_map do |item|
      [
        (item[:key] unless item[:kind] == :action),
        item[:param_path]&.split(".")&.last,
        *item[:extra_params]
      ]
    end.compact.uniq
  end

  it "não tem chaves duplicadas" do
    keys = described_class.all_keys
    expect(keys).to eq(keys.uniq)
  end

  it "agrupa os sinalizadores exatamente como aparecem na visão geral" do
    group = described_class.groups.find do |entry|
      entry[:tab] == "Visão geral" && entry[:section] == "Identificação e sinalizadores"
    end

    expect(group.fetch(:items).map { |item| [item[:key], item[:label], item[:kind]] }).to eq([
      ["exibir_no_site_flag", "Site", :flag],
      ["destaque_web_flag", "Destaque", :flag],
      ["festival_salute_flag", "Super destaque", :flag],
      ["lancamento_flag", "Lançamento", :flag],
      ["tem_placa_flag", "Placa", :flag],
      ["exclusivo_flag", "Exclusivo", :flag],
      ["imovel_dwv", "Imóvel DWV", :flag]
    ])
  end

  it "não mapeia dois itens para o mesmo param de topo" do
    tops = described_class.field_items.filter_map { |i| described_class.top_level_param_for(i[:key]) }
    expect(tops).to eq(tops.uniq)
  end

  it "cobre todos os campos do formulário (nenhum campo `method:` fora do registry)" do
    allowed = covered_form_fields + described_class::NON_LOCKABLE_FORM_FIELDS

    missing = form_field_methods - allowed
    expect(missing).to be_empty,
      "Campos do formulário sem representação no CadastroFieldRegistry: #{missing.sort.inspect}. " \
      "Adicione-os ao registry (ou a NON_LOCKABLE_FORM_FIELDS se forem estruturais)."
  end


  it "cobre as ações operacionais configuráveis do cadastro" do
    sources = Dir.glob(Rails.root.join("app/views/admin/habitations/**/*.erb")).to_h do |file|
      [file.delete_prefix("#{Rails.root}/"), File.read(file)]
    end
    expected_actions = {
      "acao:buscar_cep" => "cep-search#search",
      "acao:gerenciar_imediacoes" => "field_lock_action: \"acao:gerenciar_imediacoes\"",
      "acao:vincular_empreendimento" => "field_lock_action: \"acao:vincular_empreendimento\"",
      "acao:gerar_ia" => "action_locked?(\"acao:gerar_ia\")",
      "acao:gerenciar_destaques" => "data-field-lock-action=\"acao:gerenciar_destaques\"",
      "acao:gerenciar_caracteristicas" => "data-field-lock-action=\"acao:gerenciar_caracteristicas\"",
      "acao:gerenciar_infraestrutura" => "data-field-lock-action=\"acao:gerenciar_infraestrutura\"",
      "acao:cadastrar_proprietario" => "field_lock_action: \"acao:cadastrar_proprietario\"",
      "acao:gerenciar_responsaveis" => "action_locked?(\"acao:gerenciar_responsaveis\")",
      "acao:abrir_organizador_midia" => "data-field-lock-action=\"acao:abrir_organizador_midia\"",
      "acao:organizar_fotos" => "acao:organizar_fotos",
      "acao:enviar_fotos" => "acao:enviar_fotos",
      "acao:alterar_visibilidade_fotos" => "acao:alterar_visibilidade_fotos",
      "acao:gerenciar_ordem_fotos" => "acao:gerenciar_ordem_fotos",
      "acao:configurar_ambiente_foto" => "acao:configurar_ambiente_foto",
      "acao:remover_foto" => "acao:remover_foto",
      "acao:remover_fichas_cadastro" => "acao:remover_fichas_cadastro",
      "acao:remover_autorizacoes_venda" => "acao:remover_autorizacoes_venda"
    }
    combined_source = sources.values.join("\n")

    expect(expected_actions.keys - described_class.all_keys).to be_empty
    expected_actions.each_value do |marker|
      expect(combined_source).to include(marker), "Ação sem marcador/enforcement no cadastro: #{marker}"
    end
  end
end
