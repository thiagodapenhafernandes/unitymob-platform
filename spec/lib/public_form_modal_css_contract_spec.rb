require "spec_helper"

# O fundo do modal usa `display: grid`, que vence o [hidden] do Tailwind (mesma especificidade, carregado depois).
# Sem uma regra própria para [hidden] o modal aparece aberto ao carregar e o X não fecha.
RSpec.describe "CSS do modal de formulário público" do
  ROOT = File.expand_path("../..", __dir__)

  def rule_body(css, selector)
    css[/#{Regexp.escape(selector)}\s*\{([^}]*)\}/m, 1]
  end

  it "esconde o fundo do modal quando tem o atributo hidden (variante padrão)" do
    css = File.read(File.join(ROOT, "app/assets/stylesheets/components/_public_form_modal.scss"))

    expect(rule_body(css, ".public-form-modal__overlay[hidden]")).to match(/display:\s*none/)
    expect(rule_body(css, ".public-form-modal__overlay")).to match(/display:\s*grid/)
  end

  it "nenhum tema liga o fundo do modal de novo sem respeitar o hidden" do
    Dir[File.join(ROOT, "app/assets/stylesheets/public_site_themes/*.css")].each do |path|
      css = File.read(path)
      # Regra com o seletor completo e mais específica que a do tema não pode reabrir um overlay hidden.
      expect(css).not_to match(/\.public-form-modal__overlay\[hidden\]\s*\{[^}]*display:\s*(grid|flex|block)/), File.basename(path)
    end
  end
end
