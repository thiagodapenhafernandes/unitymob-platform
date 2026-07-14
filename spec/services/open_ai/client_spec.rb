require "rails_helper"

RSpec.describe OpenAi::Client do
  describe "#multipart_body" do
    it "monta corpo binário mesmo com prompt acentuado e áudio binário" do
      client = described_class.new(api_key: "test")
      audio = Struct.new(:original_filename, :content_type) do
        def read = "\xFF\xFB\x90binary".b
        def rewind = nil
      end.new("busca.webm", "audio/webm")

      body = client.send(
        :multipart_body,
        boundary: "----UnitymobTest",
        fields: { model: "gpt-4o-mini-transcribe", language: "pt", prompt: "Vocabulário: Itapema, Perequê, Balneário Camboriú." },
        file: audio
      )

      expect(body.encoding).to eq(Encoding::ASCII_8BIT)
      expect(body).to include("Vocabulário: Itapema".b)
      expect(body).to include("\xFF\xFB\x90binary".b)
    end
  end
end
