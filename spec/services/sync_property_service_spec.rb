require "rails_helper"

RSpec.describe SyncPropertyService do
  describe "publication flag preservation" do
    it "preserva exibir_no_site_flag de imóvel existente mesmo sem preservar outros campos manuais" do
      service = described_class.new("9001", preserve_manual_fields: false)

      attrs = service.send(
        :filtered_habitation_attrs,
        {
          titulo_anuncio: "Atualizado pela API",
          exibir_no_site_flag: true,
          destaque_web_flag: true
        },
        existing_record: true
      )

      expect(attrs).to include(titulo_anuncio: "Atualizado pela API", destaque_web_flag: true)
      expect(attrs).not_to have_key(:exibir_no_site_flag)
    end

    it "mantém exibir_no_site_flag da API para imóvel novo" do
      service = described_class.new("9001")

      attrs = service.send(
        :filtered_habitation_attrs,
        { exibir_no_site_flag: true },
        existing_record: false
      )

      expect(attrs).to include(exibir_no_site_flag: true)
    end
  end
end
