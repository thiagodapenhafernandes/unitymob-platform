require "rails_helper"

RSpec.describe ActiveStorage::Service::DigitalOceanSpacesService do
  subject(:service) do
    described_class.new(
      bucket: "bucket-test",
      access_key_id: "access-key",
      secret_access_key: "secret-key",
      region: "sfo3",
      endpoint: "https://sfo3.digitaloceanspaces.com",
      stub_responses: true
    )
  end

  it "faz upload sem enviar Content-MD5 para compatibilidade com Spaces" do
    service.upload("photos/file.jpg", StringIO.new("image"), checksum: Digest::MD5.base64digest("image"), content_type: "image/jpeg")

    request = service.client.client.api_requests.last

    expect(request[:operation_name]).to eq(:put_object)
    expect(request[:params]).not_to have_key(:content_md5)
    expect(request[:params]).to include(bucket: "bucket-test", key: "photos/file.jpg", content_type: "image/jpeg")
  end

  it "rejeita bytes divergentes antes de sobrescrever um objeto no Spaces" do
    expect {
      service.upload("photos/existing.jpg", StringIO.new("changed"), checksum: Digest::MD5.base64digest("original"))
    }.to raise_error(ActiveStorage::IntegrityError)

    expect(service.client.client.api_requests).to be_empty
  end

  it "envia todos os bytes depois de validar o checksum em blocos" do
    body = "a" * (5.megabytes + 1)
    io = StringIO.new(body)
    service.upload("photos/file.jpg", io, checksum: Digest::MD5.base64digest(body))

    request = service.client.client.api_requests.last
    expect(request[:params][:body].read).to eq(body)
  end

  it "nao exige Content-MD5 no upload direto" do
    headers = service.headers_for_direct_upload(
      "photos/file.jpg",
      content_type: "image/jpeg",
      checksum: Digest::MD5.base64digest("image"),
      filename: ActiveStorage::Filename.new("file.jpg")
    )

    expect(headers).not_to have_key("Content-MD5")
    expect(headers["Content-Type"]).to eq("image/jpeg")
  end
end
