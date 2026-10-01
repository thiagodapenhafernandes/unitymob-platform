require "rails_helper"

RSpec.describe Banner do
  it "aceita gatilho de modal no link e recusa endereço inválido" do
    banner = described_class.new(link_url: "#modal-anuncie-seu-imovel")
    banner.valid?
    expect(banner.errors[:link_url]).to be_empty

    banner.link_url = "javascript:alert(1)"
    banner.valid?
    expect(banner.errors[:link_url]).to be_present
  end
end
