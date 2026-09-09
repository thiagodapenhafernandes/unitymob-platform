require "rails_helper"
require "active_storage/service/development_read_only_s3_service"

RSpec.describe ActiveStorage::Service::DevelopmentReadOnlyS3Service do
  subject(:service) do
    described_class.new(bucket: "production", region: "us-east-1", access_key_id: "test", secret_access_key: "test", stub_responses: true)
  end

  it "permite leitura mas não escreve, exclui nem gera autorização de upload" do
    service.download("photo")
    expect(service.client.client.api_requests.map { |r| r[:operation_name] }).to eq([:get_object])
    expect { service.upload("photo", StringIO.new("new")) }.to raise_error(IOError)
    expect { service.url_for_direct_upload("photo", expires_in: 60) }.to raise_error(IOError)
    expect { service.compose(["photo"], "copy") }.to raise_error(IOError)
    service.delete("photo")
    service.delete_prefixed("variants/")
    expect(service.client.client.api_requests.map { |r| r[:operation_name] }).to eq([:get_object])
  end
end
