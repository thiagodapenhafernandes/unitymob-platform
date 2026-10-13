require "rails_helper"

RSpec.describe MetaAi::Client do
  describe "#create_response" do
    it "tenta fallback quando a Meta recusa o modelo configurado" do
      client = described_class.new(api_key: "test")
      bad_response = http_response(
        success: false,
        code: "404",
        body: { error: { message: "The model muse-old does not exist.", code: "model_not_found" } }.to_json
      )
      ok_response = http_response(success: true, code: "200", body: { output_text: "ok" }.to_json)
      requests = stub_http_requests(bad_response, ok_response)

      result = client.create_response({ model: "muse-old", input: "teste" }, fallback_model: "muse-spark-1.3")

      expect(result).to eq("output_text" => "ok")
      expect(JSON.parse(requests.first.body)).to include("model" => "muse-old")
      expect(JSON.parse(requests.second.body)).to include("model" => "muse-spark-1.3")
      expect(requests.first.path).to eq("/v1/responses")
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
        client.create_response({ model: "muse-spark-1.3", input: "teste" }, fallback_model: "muse-spark-1.2")
      end.to raise_error(RuntimeError, /Meta Muse retornou erro 429/)

      expect(requests.size).to eq(1)
    end
  end

  describe "#transcribe" do
    let!(:wav_file) do
      Tempfile.new(["stt", ".wav"]).tap { |f| f.binmode.write("RIFFdata".b); f.flush }
    end
    let(:wav_path) { wav_file.path }
    let(:audio) do
      Struct.new(:original_filename, :content_type, :path).new("busca.webm", "audio/webm", "/tmp/busca.webm")
    end

    it "converte para WAV e extrai o transcript do ASR" do
      client = described_class.new(api_key: "test")
      allow(client).to receive(:convert_to_wav!).with(audio).and_return(wav_path)
      ok_response = http_response(success: true, code: "200", body: { transcript: "apartamento na Barra Sul" }.to_json)
      requests = stub_http_requests(ok_response)

      result = client.transcribe(file: audio, language: "pt-BR", model: "muse-voice-transcribe-1.0", keywords: %w[Itapema])

      expect(result).to eq("apartamento na Barra Sul")
      expect(requests.first.path).to match(%r{\A/v1/asr/transcribe\?sessionId=.+\z})
      expect(requests.first.body).to include("muse-voice-transcribe-1.0")
      expect(requests.first.body).to include("Portuguese")
      expect(requests.first.body).to include("Itapema")
      expect(requests.first["Authorization"]).to eq("Bearer test")
    end

    it "falha com mensagem clara sem ffmpeg" do
      client = described_class.new(api_key: "test")
      allow(Whatsapp::MediaConverter).to receive(:available?).and_return(false)

      expect do
        client.transcribe(file: audio, language: "pt-BR", model: "muse-voice-transcribe-1.0")
      end.to raise_error(RuntimeError, /ffmpeg não está disponível/)
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
