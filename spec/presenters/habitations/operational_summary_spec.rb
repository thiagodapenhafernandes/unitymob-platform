require "rails_helper"

RSpec.describe Habitations::OperationalSummary do
  it "aponta contradições sem alterar o imóvel" do
    habitation = create(:habitation,
      codigo: "SUMMARY-#{SecureRandom.hex(6)}",
      titulo_anuncio: nil,
      endereco: nil,
      admin_user: nil,
      pictures: [],
      exibir_no_site_flag: true,
      publicar_imovelweb: true,
      valor_venda_cents: 0,
      valor_locacao_cents: 0)
    habitation.update_column(:endereco, nil)

    summary = described_class.new(habitation)

    expect(summary.site_label).to eq("Marcado, mas indisponível")
    expect(summary.issues.map(&:code)).to include(:missing_title, :missing_responsible, :missing_photos, :missing_price, :site_state_conflict, :portal_state_conflict)
    expect { summary.issues }.not_to change { habitation.reload.attributes }
  end

  it "resume os canais locais sem consultar dados de outro tenant" do
    tenant = Tenant.create!(name: "Resumo operacional", slug: "resumo-#{SecureRandom.hex(3)}")
    habitation = create(:habitation, tenant: tenant, codigo: "SUMMARY-TENANT-#{SecureRandom.hex(6)}", publicar_imovelweb: true, publicar_viva_real_vrsync: false)

    channels = described_class.new(habitation).portal_channels

    expect(channels.find { |channel| channel.key == "imovelweb" }).to be_active
    expect(channels.find { |channel| channel.key == "vivareal_vrsync" }).not_to be_active
  end

  it "considera somente anexos locais ao avaliar a mídia operacional" do
    habitation = create(:habitation, codigo: "SUMMARY-LOCAL-#{SecureRandom.hex(6)}", pictures: [{ "url" => "https://legacy.example.test/foto.jpg" }])

    summary = described_class.new(habitation)

    expect(summary.photo_count).to eq(0)
    expect(summary.issues.map(&:code)).to include(:missing_photos)
  end

  it "considera a mídia remota do DWV como disponível" do
    habitation = create(:habitation, codigo: "SUMMARY-DWV-#{SecureRandom.hex(6)}", imovel_dwv: "Sim", pictures: [{ "url" => "https://cdn.dwv.test/foto.jpg" }])

    summary = described_class.new(habitation)

    expect(summary.issues.map(&:code)).not_to include(:missing_photos)
  end
end
