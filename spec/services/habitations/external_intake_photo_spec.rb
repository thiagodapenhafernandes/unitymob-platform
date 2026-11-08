require "rails_helper"

RSpec.describe Habitations::ExternalIntakePhoto do
  def serve(bytes)
    allow(Automation::WebhookUrlPolicy).to receive(:resolve).with("midia.example.com")
      .and_return([IPAddr.new("93.184.215.14")])
    http = Net::HTTP.new("midia.example.com", 443, nil)
    allow(Net::HTTP).to receive(:new).with("midia.example.com", 443, nil).and_return(http)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:read_body).and_yield(bytes)
    allow(http).to receive(:request).and_yield(response)
  end

  it "aceita PDF apenas no fluxo de documentos e identifica o conteúdo" do
    serve("%PDF-1.4\nDocumento")
    upload = described_class.download("https://midia.example.com/autorizacao.pdf", document: true)
    expect(upload.content_type).to eq("application/pdf")
    expect(upload.read).to start_with("%PDF")
    expect { described_class.download("https://midia.example.com/autorizacao.pdf") }
      .to raise_error(Habitations::ExternalIntake::Invalid, /JPEG/)
  ensure
    upload&.tempfile&.close!
  end

  it "rejeita rede privada e conteúdo não permitido" do
    expect { described_class.download("https://127.0.0.1/autorizacao.pdf", document: true) }
      .to raise_error(Habitations::ExternalIntake::Invalid)
    serve("<html>Não é PDF</html>")
    expect { described_class.download("https://midia.example.com/autorizacao.pdf", document: true) }
      .to raise_error(Habitations::ExternalIntake::Invalid, /PDF/)
  end

  it "rejeita arquivo maior que 8 MB" do
    serve("x" * (8.megabytes + 1))
    expect { described_class.download("https://midia.example.com/autorizacao.pdf", document: true) }
      .to raise_error(Habitations::ExternalIntake::Invalid, /8 MB/)
  end
end
