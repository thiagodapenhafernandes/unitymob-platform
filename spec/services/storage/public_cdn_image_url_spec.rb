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

  it "resolve anexo privado fora de fotos públicas pelo proxy do Active Storage" do
    setting = HomeSetting.instance
    setting.hero_background_desktop.attach(
      io: StringIO.new("image"),
      filename: "hero.jpg",
      content_type: "image/jpeg"
    )
    attachment = setting.hero_background_desktop.attachment

    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_attachment).with(attachment).and_return(nil)

    result = described_class.resolve(setting.hero_background_desktop)

    expect(result).to include("/rails/active_storage/blobs/proxy/")
    expect(result).to end_with("/hero.jpg")
  end

  it "não enfileira saver como transformação do Active Storage" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("image"),
      filename: "foto.jpg",
      content_type: "image/jpeg"
    )

    allow(blob).to receive(:variable?).and_return(true)
    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_blob).with(blob).and_return("https://cdn.saluteimoveis.com.br/#{blob.key}")
    allow(Rails.cache).to receive(:write).and_return(true)
    allow(ActiveStorage::TransformJob).to receive(:perform_later)

    described_class.resolve(blob, resize_to_fill: [640, 480], saver: { quality: 82 })

    expect(ActiveStorage::TransformJob).to have_received(:perform_later).with(blob, resize_to_fill: [640, 480])
  end

  it "gera path relativo para representation sem exigir host default" do
    variant = instance_double(ActiveStorage::VariantWithRecord)

    expect(Rails.application.routes.url_helpers)
      .to receive(:rails_representation_path)
      .with(variant, only_path: true)
      .and_return("/rails/active_storage/representations/signed/foto.jpg")

    resolver = described_class.new(nil)

    expect(resolver.send(:representation_path, variant)).to eq("/rails/active_storage/representations/signed/foto.jpg")
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
