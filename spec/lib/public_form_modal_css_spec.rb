require "rails_helper"

# O wrapper .public-form-modal só guarda o gatilho e o overlay. Se um tema o transformar em camada fixa de tela cheia,
# o modal (mesmo fechado) escurece o site inteiro. Quem cobre a tela é sempre o __overlay.
RSpec.describe "CSS do modal de formulário nos temas" do
  Dir[Rails.root.join("app/assets/stylesheets/public_site_themes/*.css")].each do |path|
    it "#{File.basename(path)}: o wrapper .public-form-modal não vira camada fixa" do
      css = File.read(path)
      wrapper_rules = css.scan(/(?:^|\})\s*\.public-form-modal\s*\{([^}]*)\}/).flatten

      expect(wrapper_rules.grep(/position:\s*fixed/)).to be_empty
    end
  end

  # As colunas dos campos ficam no __grid; colunas também no <form> jogam o grid inteiro na primeira metade da tela.
  Dir[Rails.root.join("app/assets/stylesheets/public_site_themes/*.css")].each do |path|
    it "#{File.basename(path)}: o <form> do modal não define colunas próprias" do
      css = File.read(path)
      form_rules = css.scan(/(?:^|\})\s*\.public-form-modal__form\s*\{([^}]*)\}/).flatten

      expect(form_rules.grep(/grid-template-columns/)).to be_empty
    end
  end
end
