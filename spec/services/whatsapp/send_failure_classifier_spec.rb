require "rails_helper"

RSpec.describe Whatsapp::SendFailureClassifier do
  describe ".service_window_closed?" do
    it "detecta janela fechada pelo código da Meta" do
      expect(
        described_class.service_window_closed?(
          error_message: "Mensagem recusada",
          meta_error: { code: 131047 }
        )
      ).to be(true)
    end

    it "detecta janela fechada pelo título retornado no webhook" do
      expect(
        described_class.service_window_closed?(
          error_message: "#131047 Re-engagement message"
        )
      ).to be(true)
    end

    it "não trata erro operacional como janela fechada" do
      expect(
        described_class.service_window_closed?(
          error_message: "#133010 Account not registered"
        )
      ).to be(false)
    end
  end

  describe ".message_from_status_error" do
    it "preserva código, título, mensagem e detalhes úteis do webhook" do
      message = described_class.message_from_status_error(
        "code" => 131047,
        "title" => "Re-engagement message",
        "message" => "Message failed to send",
        "error_data" => { "details" => "More than 24 hours have passed" }
      )

      expect(message).to include("#131047 Re-engagement message")
      expect(message).to include("Message failed to send")
      expect(message).to include("More than 24 hours have passed")
    end
  end
end
