require "rails_helper"

RSpec.describe Habitations::CadastroFieldRegistry do
  FORM_TABS_DIR = Rails.root.join("app/views/admin/habitations/form_tabs")

  # Campos que aparecem no formulário via `method: :x` (form.object = habitation
  # ou address_attributes). É a base de completude.
  def form_field_methods
    Dir.glob(FORM_TABS_DIR.join("**/*.erb")).flat_map do |file|
      File.read(file).scan(/method:\s*:([a-z0-9_]+)/).flatten
    end.uniq
  end

  it "não tem chaves duplicadas" do
    keys = described_class.all_keys
    expect(keys).to eq(keys.uniq)
  end

  it "não mapeia dois itens para o mesmo param de topo" do
    tops = described_class.field_items.filter_map { |i| described_class.top_level_param_for(i[:key]) }
    expect(tops).to eq(tops.uniq)
  end

  it "cobre todos os campos do formulário (nenhum campo `method:` fora do registry)" do
    covered = described_class.field_items.flat_map do |i|
      [i[:key], (i[:param_path]&.split(".")&.last)]
    end.compact.uniq
    allowed = covered + described_class::NON_LOCKABLE_FORM_FIELDS

    missing = form_field_methods - allowed
    expect(missing).to be_empty,
      "Campos do formulário sem representação no CadastroFieldRegistry: #{missing.sort.inspect}. " \
      "Adicione-os ao registry (ou a NON_LOCKABLE_FORM_FIELDS se forem estruturais)."
  end
end
