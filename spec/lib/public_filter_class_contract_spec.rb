require "rails_helper"

# Contrato v2 (docs/public-theme-contract.md): o filtro global usa as MESMAS
# classes em todos os temas e o CSS de tema só usa seletor plano por classe.
RSpec.describe "Contrato de classes do filtro global" do
  let(:views) do
    %w[
      app/views/public_theme/components/_filter_drawer.html.erb
      app/views/public_theme/components/_filter_trigger.html.erb
    ].map { |path| Rails.root.join(path).read }
  end
  let(:stylesheets) do
    {
      "salute_luxury.css" => Rails.root.join("app/assets/stylesheets/public_site_themes/salute_luxury.css").read,
      "_public_global_search_drawer.scss" => Rails.root.join("app/assets/stylesheets/components/_public_global_search_drawer.scss").read
    }
  end

  it "emite só classes do contrato no HTML do filtro" do
    classes = views.flat_map do |source|
      source.scan(/class(?:="|: ")([^"]+)"/).flatten.flat_map { |value| value.gsub(/<%=.*?%>/, "").split }
    end

    unexpected = classes.uniq.reject do |name|
      name.start_with?("public-theme-filter-drawer", "public-theme-filter-fab", "public-theme-combobox") ||
        %w[bi hidden].include?(name) || name.start_with?("bi-") || name.end_with?("--")
    end

    expect(unexpected).to be_empty, "classes fora do contrato: #{unexpected.join(', ')}"
  end

  it "não usa >, +, ~ nem nth-child nos seletores do filtro" do
    stylesheets.each do |file, css|
      selectors = css.scan(/^[^{}\n]*public-theme-(?:filter-drawer|filter-fab|combobox)[^{}\n]*(?:\{|,)$/)
      offending = selectors.select { |selector| selector.match?(/\s[>+~]\s|:nth-/) }

      expect(selectors.size).to be > 20, "#{file}: nenhum seletor do filtro encontrado"

      expect(offending).to be_empty, "#{file}: #{offending.join(' | ')}"
    end
  end
end
