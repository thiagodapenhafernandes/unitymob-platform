require "rails_helper"

RSpec.describe Storage::PublicCdnImageUrl do
  before do
    allow(Storage::PublicPropertyPhoto).to receive(:public_base_url).and_return("https://cdn.saluteimoveis.com.br")
  end

  it "não resolve rota interna do Active Storage como URL pública" do
    source = "https://dev.unitymob.com.br/rails/active_storage/blobs/proxy/signed/foto.jpg"

    expect(described_class.resolve(source)).to be_nil
  end

  it "não resolve URL externa fora do CDN configurado" do
    source = "https://cdn.vistahost.com.br/salute/foto.jpg"

    expect(described_class.resolve(source)).to be_nil
  end

  it "não aceita origem direta do Spaces como URL pública quando há CDN configurado" do
    source = "https://imob.sfo3.digitaloceanspaces.com/foto.jpg"

    expect(described_class.resolve(source)).to be_nil
  end

  it "mantém URL já servida pelo CDN configurado" do
    source = "https://cdn.saluteimoveis.com.br/foto.jpg"

    expect(described_class.resolve(source)).to eq(source)
  end

  it "não consulta materialização local para payload que já aponta para o CDN configurado" do
    source = { "url" => "https://cdn.saluteimoveis.com.br/foto.jpg" }

    expect(VistaFileAsset).not_to receive(:where)
    expect(described_class.resolve(source)).to eq(source["url"])
  end

  it "não consulta materialização local para payload externo não-CDN" do
    source = { "url" => "https://cdn.vistahost.com.br/salute/foto.jpg" }

    expect(VistaFileAsset).not_to receive(:where)
    expect(described_class.resolve(source)).to be_nil
  end

  it "resolve blob publicado para URL de CDN" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("image"),
      filename: "foto.jpg",
      content_type: "image/jpeg"
    )
    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_blob).with(blob).and_return("https://cdn.saluteimoveis.com.br/#{blob.key}")

    expect(described_class.resolve(blob)).to eq("https://cdn.saluteimoveis.com.br/#{blob.key}")
  end

  it "resolve anexo publicado para URL de CDN" do
    habitation = create(:habitation, codigo: "CDN-ONLY-1", address_attributes: address_attributes)
    habitation.photos.attach(
      io: StringIO.new("image"),
      filename: "foto.jpg",
      content_type: "image/jpeg"
    )
    attachment = habitation.photos.attachments.first
    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_attachment).with(attachment).and_return("https://cdn.saluteimoveis.com.br/#{attachment.blob.key}")

    expect(described_class.resolve({ "attachment" => attachment })).to eq("https://cdn.saluteimoveis.com.br/#{attachment.blob.key}")
  end

  def address_attributes
    {
      logradouro: "Rua CDN",
      bairro: "Centro",
      cidade: "Itapema",
      uf: "SC"
    }
  end
end
