require "rails_helper"

RSpec.describe LandingPage do
  let(:tenant) { Tenant.default }

  def page(attrs = {})
    tenant.landing_pages.new({ title: "Página #{SecureRandom.hex(3)}" }.merge(attrs))
  end

  it "gera o endereço do título quando o campo vem em branco (string vazia do formulário)" do
    saved = page(title: "Casas à beira-mar", slug: "").tap(&:save!)

    expect(saved.slug).to eq("casas-a-beira-mar")
  end

  describe "status (Inativo, Rascunho, Publicado)" do
    it "só publicada está no ar: active é derivado do status" do
      expect(page(status: "published").tap(&:save!)).to have_attributes(active: true)
      expect(page(status: "draft").tap(&:save!)).to have_attributes(active: false)
      expect(page(status: "inactive").tap(&:save!)).to have_attributes(active: false)
      expect(LandingPage.active.where(tenant: tenant).count).to eq(1)
    end

    it "código antigo que só grava active continua funcionando e a página nasce publicada" do
      expect(page.tap(&:save!)).to have_attributes(status: "published", active: true)
      expect(page(active: false).tap(&:save!)).to have_attributes(status: "inactive", active: false)
    end

    it "recusa status desconhecido" do
      expect(page(status: "arquivada")).not_to be_valid
    end
  end

  describe "blocos" do
    it "vêm ordenados por posição e a página sabe se foi montada por blocos" do
      record = page(status: "draft").tap(&:save!)
      expect(record.blocks?).to eq(false)

      record.blocks.create!(block_type: "button", position: 2, data: { "label" => "B", "url" => "/b" })
      record.blocks.create!(block_type: "cover", position: 1)
      record.blocks.create!(block_type: "text", position: 3, visible: false, data: { "heading" => "Oculto" })

      expect(record.reload.blocks.map(&:block_type)).to eq(%w[cover button text])
      expect(record.visible_blocks.map(&:block_type)).to eq(%w[cover button])
      expect(record.blocks?).to eq(true)
    end

    it "apaga os blocos junto com a página" do
      record = page(status: "draft").tap(&:save!)
      record.blocks.create!(block_type: "cover", position: 1)

      expect { record.destroy }.to change(LandingPageBlock, :count).by(-1)
    end

    it "aceita criar blocos junto com a página (nested attributes) e remover pelo _destroy" do
      record = page(status: "draft", blocks_attributes: { "0" => { block_type: "cover", position: "1" }, "1" => { block_type: "text", position: "2", data: { heading: "Oi" } } })
      expect(record.save).to eq(true)
      expect(record.blocks.count).to eq(2)

      text = record.blocks.find_by!(block_type: "text")
      record.update!(blocks_attributes: { "0" => { id: text.id, _destroy: "1" } })
      expect(record.reload.blocks.pluck(:block_type)).to eq(["cover"])
    end

    it "só uma vitrine pode ter filtros do visitante e paginação" do
      record = page(status: "draft", blocks_attributes: {
        "0" => { block_type: "property_showcase", position: "1", data: { visitor_filters: "1" } },
        "1" => { block_type: "property_showcase", position: "2", data: { visitor_filters: "1" } }
      })
      expect(record).not_to be_valid
      expect(record.errors.full_messages.join).to include("Só uma vitrine")

      second = record.blocks.last
      second.data = second.data.merge("visitor_filters" => false)
      expect(record).to be_valid
    end
  end
  it "ocultar uma seção oculta seus filhos até a próxima seção" do
    record = page(status: "draft").tap(&:save!)
    record.blocks.create!(block_type: "section", position: 0, visible: false)
    record.blocks.create!(block_type: "text", position: 1, data: { heading: "Oculto" })
    record.blocks.create!(block_type: "section", position: 2)
    record.blocks.create!(block_type: "text", position: 3, data: { heading: "Visível" })
    expect(record.reload.visible_blocks.map(&:position)).to eq([2, 3])
  end

end
