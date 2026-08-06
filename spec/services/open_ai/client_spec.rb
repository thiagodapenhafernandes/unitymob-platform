require "rails_helper"

RSpec.describe OpenAi::Client do
  describe "#create_response" do
    it "tenta fallback quando a OpenAI recusa o modelo configurado" do
      client = described_class.new(api_key: "test")
      bad_response = http_response(
        success: false,
        code: "404",
        body: { error: { message: "The model gpt-old does not exist.", code: "model_not_found" } }.to_json
      )
      ok_response = http_response(success: true, code: "200", body: { output_text: "ok" }.to_json)
      requests = stub_http_requests(bad_response, ok_response)

      result = client.create_response({ model: "gpt-old", input: "teste" }, fallback_model: "gpt-4.1-mini")

      expect(result).to eq("output_text" => "ok")
      expect(JSON.parse(requests.first.body)).to include("model" => "gpt-old")
      expect(JSON.parse(requests.second.body)).to include("model" => "gpt-4.1-mini")
    end

    it "não troca modelo quando o erro não é de disponibilidade do modelo" do
      client = described_class.new(api_key: "test")
      bad_response = http_response(
        success: false,
        code: "429",
        message: "Too Many Requests",
        body: { error: { message: "Rate limit reached." } }.to_json
      )
      requests = stub_http_requests(bad_response)

      expect do
        client.create_response({ model: "gpt-old", input: "teste" }, fallback_model: "gpt-4.1-mini")
      end.to raise_error(RuntimeError, /OpenAI retornou erro 429/)

      expect(requests.size).to eq(1)
    end
  end

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

  def http_response(success:, code:, body:, message: success ? "OK" : "Erro")
    response = double("http_response", body:, code:, message:)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(success)
    response
  end

  def stub_http_requests(*responses)
    http = instance_double(Net::HTTP)
    remaining = responses.dup
    requests = []
    allow(http).to receive(:request) do |request|
      requests << request
      remaining.shift
    end
    allow(Net::HTTP).to receive(:start).and_yield(http)
    requests
  end
end
