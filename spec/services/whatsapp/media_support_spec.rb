require "rails_helper"

RSpec.describe Whatsapp::MediaSupport do
  describe ".validation_for" do
    it "aceita audio webm pelo nome quando o navegador envia octet-stream" do
      upload = Struct.new(:content_type, :original_filename, :tempfile, :size).new(
        "application/octet-stream",
        "audio-083842.webm",
        StringIO.new("fake-webm-audio"),
        16
      )

      result = described_class.validation_for(upload, allow_convertible: true)

      expect(result).to include(ok: true, type: "audio", content_type: "audio/webm")
      expect(result[:convert]).to eq(true)
    end
  end
end
