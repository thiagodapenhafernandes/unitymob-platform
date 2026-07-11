require "rails_helper"

RSpec.describe Storage::SafePurgeJob do
  it "não falha quando o blob já foi removido" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "não remove blob que voltou a ter anexos" do
    blob = instance_double(ActiveStorage::Blob)
    attachments = double("attachments", exists?: true)

    allow(ActiveStorage::Blob).to receive(:find_by).with(id: 123).and_return(blob)
    allow(blob).to receive(:attachments).and_return(attachments)
    expect(blob).not_to receive(:purge)

    described_class.perform_now(123)
  end
end
