require "rails_helper"

RSpec.describe Storage::PublicCdnImageUrl do
  before do
    allow(Storage::PublicPropertyPhoto).to receive(:public_base_url).and_return("https://cdn.saluteimoveis.com.br")
  end

  it "não resolve rota interna do Active Storage como URL pública" do
    source = "https://dev.unitymob.com.br/rails/active_storage/blobs/proxy/signed/foto.jpg"

    expect(described_class.resolve(source)).to be_nil
  end

  it "resolve URL externa da Vista como fallback confiável" do
    source = "https://cdn.vistahost.com.br/salute/foto.jpg"

    expect(described_class.resolve(source)).to eq(source)
  end

  it "não aceita origem direta do Spaces como URL pública quando há CDN configurado" do
    source = "https://imob.sfo3.digitaloceanspaces.com/foto.jpg"

    expect(described_class.resolve(source)).to be_nil
  end

  it "mantém URL já servida pelo CDN configurado" do
    source = "https://cdn.saluteimoveis.com.br/foto.jpg"

    expect(described_class.resolve(source)).to eq(source)
  end

  it "normaliza barras duplicadas no início do caminho do CDN" do
    source = "https://dwvimagesv1.b-cdn.net//images/properties/foto.jpg?crop=200,300"

    expect(described_class.resolve(source)).to eq(
      "https://dwvimagesv1.b-cdn.net/images/properties/foto.jpg?crop=200,300"
    )
  end

  it "não consulta materialização local para payload que já aponta para o CDN configurado" do
    source = { "url" => "https://cdn.saluteimoveis.com.br/foto.jpg" }

    expect(VistaFileAsset).not_to receive(:where)
    expect(described_class.resolve(source)).to eq(source["url"])
  end

  it "não consulta materialização local para payload externo não-CDN" do
    source = { "url" => "https://cdn.vistahost.com.br/salute/foto.jpg" }

    expect(VistaFileAsset).not_to receive(:where)
    expect(described_class.resolve(source)).to eq(source["url"])
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

  it "não resolve blob remoto quando o objeto não existe no storage" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "foto-ausente.jpg",
      byte_size: 10,
      checksum: Digest::MD5.base64digest("ausente"),
      content_type: "image/jpeg",
      service_name: ActiveStorage::Blob.service.name
    )
    service = instance_double(ActiveStorage::Service, exist?: false)
    allow(blob).to receive(:service_name).and_return("do_spaces")
    allow(blob).to receive(:service).and_return(service)
    allow(Storage::ActiveStorageRegistry).to receive(:fetch!).with("do_spaces").and_return(service)
    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_blob).with(blob).and_return("https://cdn.saluteimoveis.com.br/#{blob.key}")

    expect(described_class.resolve(blob)).to be_nil
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
    allow(Storage::TransformVariantJob).to receive(:perform_later)

    described_class.resolve(blob, resize_to_fill: [640, 480], saver: { quality: 82 })

    expect(Storage::TransformVariantJob).to have_received(:perform_later).with(blob, resize_to_fill: [640, 480])
  end

  it "inclui formato moderno na transformação solicitada" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("image"),
      filename: "foto.jpg",
      content_type: "image/jpeg"
    )

    allow(blob).to receive(:variable?).and_return(true)
    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_blob).with(blob).and_return("https://cdn.saluteimoveis.com.br/#{blob.key}")
    allow(Rails.cache).to receive(:write).and_return(true)
    allow(Storage::TransformVariantJob).to receive(:perform_later)

    described_class.resolve(blob, resize_to_fill: [640, 480], format: :webp)

    expect(Storage::TransformVariantJob).to have_received(:perform_later).with(blob, resize_to_fill: [640, 480], format: :webp)
  end

  it "retorna rota de representação imediatamente quando force_variant está ativo" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("image"),
      filename: "foto.jpg",
      content_type: "image/jpeg"
    )
    variant = instance_double(
      ActiveStorage::VariantWithRecord,
      blob: instance_double(ActiveStorage::Blob, signed_id: "signed-blob"),
      variation: instance_double(ActiveStorage::Variation, key: "signed-variation"),
      filename: ActiveStorage::Filename.new("foto.webp")
    )

    allow(blob).to receive(:variable?).and_return(true)
    allow(blob).to receive(:variant).with(resize_to_fill: [640, 480], format: :webp).and_return(variant)
    allow(Rails.application.routes.url_helpers)
      .to receive(:rails_blob_representation_proxy_path)
      .with("signed-blob", "signed-variation", ActiveStorage::Filename.new("foto.webp"))
      .and_return("/rails/active_storage/representations/proxy/signed/foto.webp")
    allow(Storage::TransformVariantJob).to receive(:perform_later)

    result = described_class.resolve(
      blob,
      resize_to_fill: [640, 480],
      format: :webp,
      representation_proxy: true,
      force_variant: true
    )

    expect(result).to eq("/rails/active_storage/representations/proxy/signed/foto.webp")
    expect(Storage::TransformVariantJob).not_to have_received(:perform_later)
  end

  it "não reenfileira variante temporariamente bloqueada por falha de integridade" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("image"),
      filename: "foto-corrompida.jpg",
      content_type: "image/jpeg"
    )
    transformations = { resize_to_fill: [640, 480] }
    digest = described_class.transform_digest(transformations)
    blob.update!(metadata: blob.metadata.merge(
      described_class::TRANSFORM_FAILURE_METADATA_KEY => {
        digest => { "error" => "ActiveStorage::IntegrityError" }
      }
    ))

    allow(blob).to receive(:variable?).and_return(true)
    allow(Storage::PublicPropertyPhoto).to receive(:public_url_for_blob).with(blob).and_return("https://cdn.saluteimoveis.com.br/#{blob.key}")
    allow(Storage::TransformVariantJob).to receive(:perform_later)

    expect(described_class.resolve(blob, **transformations)).to eq("https://cdn.saluteimoveis.com.br/#{blob.key}")
    expect(Storage::TransformVariantJob).not_to have_received(:perform_later)
  end

  it "persiste a quarentena no metadata compartilhado do blob" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("image"),
      filename: "foto-integridade.jpg",
      content_type: "image/jpeg"
    )
    transformations = { resize_to_fill: [640, 480] }

    described_class.mark_transform_failed(
      blob: blob,
      transformations: transformations,
      error: ActiveStorage::IntegrityError.new
    )

    digest = described_class.transform_digest(transformations)
    failure = blob.reload.metadata.dig(described_class::TRANSFORM_FAILURE_METADATA_KEY, digest)
    expect(failure).to include("error" => "ActiveStorage::IntegrityError")
    expect(failure.fetch("recorded_at")).to be_present
  end

  it "gera path relativo pelo proxy para representation sem exigir host default" do
    blob = instance_double(ActiveStorage::Blob, signed_id: "signed-blob")
    variation = instance_double(ActiveStorage::Variation, key: "signed-variation")
    filename = ActiveStorage::Filename.new("foto.webp")
    variant = instance_double(ActiveStorage::VariantWithRecord, blob:, variation:, filename:)

    expect(Rails.application.routes.url_helpers)
      .to receive(:rails_blob_representation_proxy_path)
      .with("signed-blob", "signed-variation", filename)
      .and_return("/rails/active_storage/representations/signed/foto.jpg")

    resolver = described_class.new(nil, representation_proxy: true)

    expect(resolver.send(:representation_path, variant)).to eq("/rails/active_storage/representations/signed/foto.jpg")
  end

  it "mantém a rota de redirecionamento quando o proxy é desativado" do
    variant = instance_double(ActiveStorage::VariantWithRecord)

    expect(Rails.application.routes.url_helpers)
      .to receive(:rails_representation_path)
      .with(variant, only_path: true)
      .and_return("/rails/active_storage/representations/redirect/signed/foto.jpg")

    resolver = described_class.new(nil, proxy: false)

    expect(resolver.send(:representation_path, variant)).to eq("/rails/active_storage/representations/redirect/signed/foto.jpg")
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
