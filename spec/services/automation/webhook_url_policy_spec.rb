require "rails_helper"

RSpec.describe Automation::WebhookUrlPolicy do
  describe ".blocked?" do
    it "blocks loopback destinations" do
      expect(described_class.blocked?("http://127.0.0.1:3000/")).to be true
      expect(described_class.blocked?("http://[::1]/hook")).to be true
    end

    it "blocks private network destinations" do
      expect(described_class.blocked?("http://10.0.0.5/hook")).to be true
      expect(described_class.blocked?("http://192.168.1.1/hook")).to be true
      expect(described_class.blocked?("http://172.16.0.1/hook")).to be true
      expect(described_class.blocked?("http://[fc00::1]/hook")).to be true
    end

    it "blocks link-local, reserved and multicast destinations" do
      expect(described_class.blocked?("http://169.254.169.254/latest/meta-data/")).to be true
      expect(described_class.blocked?("http://[fe80::1]/hook")).to be true
      expect(described_class.blocked?("http://0.0.0.0/hook")).to be true
      expect(described_class.blocked?("http://224.0.0.1/hook")).to be true
    end

    it "blocks URLs with embedded credentials" do
      expect(described_class.blocked?("http://user:pass@example.com/hook")).to be true
      expect(described_class.blocked?("https://example.com@evil.example/hook")).to be true
    end

    it "blocks non-http(s) schemes, blank and malformed URLs" do
      expect(described_class.blocked?("ftp://example.com/hook")).to be true
      expect(described_class.blocked?("file:///etc/passwd")).to be true
      expect(described_class.blocked?("example.com/hook")).to be true
      expect(described_class.blocked?("not-a-url")).to be true
      expect(described_class.blocked?("")).to be true
      expect(described_class.blocked?(nil)).to be true
    end

    it "blocks hostnames that resolve to a non-public address" do
      allow(Resolv).to receive(:getaddresses).with("internal.example").and_return(["10.1.2.3"])

      expect(described_class.blocked?("https://internal.example/hook")).to be true
    end

    it "blocks hostnames when any resolved address is non-public" do
      allow(Resolv).to receive(:getaddresses).with("mixed.example").and_return(["93.184.216.34", "127.0.0.1"])

      expect(described_class.blocked?("https://mixed.example/hook")).to be true
    end

    it "allows public IP literals" do
      expect(described_class.blocked?("http://93.184.216.34/hook")).to be false
      expect(described_class.blocked?("https://8.8.8.8/hook")).to be false
    end

    it "allows hostnames that resolve only to public addresses" do
      allow(Resolv).to receive(:getaddresses).with("hooks.example").and_return(["93.184.216.34"])

      expect(described_class.blocked?("https://hooks.example/hook")).to be false
    end

    it "allows hosts that do not resolve, since no request can be routed to them" do
      allow(Resolv).to receive(:getaddresses).with("missing.example").and_return([])

      expect(described_class.blocked?("https://missing.example/hook")).to be false
    end
  end

  describe "AutomationWebhookDelivery validation" do
    it "rejects internal destinations" do
      delivery = AutomationWebhookDelivery.new(url: "http://127.0.0.1:3000/hook", http_method: "post")

      expect(delivery).not_to be_valid
      expect(delivery.errors[:url]).to be_present
    end

    it "accepts public destinations" do
      delivery = AutomationWebhookDelivery.new(url: "https://hooks.example/hook", http_method: "post")
      allow(Resolv).to receive(:getaddresses).with("hooks.example").and_return(["93.184.216.34"])

      expect(delivery).to be_valid
    end
  end

  describe "Automation::WorkflowDefinition validation" do
    def definition_for(url)
      {
        "nodes" => [
          { "id" => "entry_1", "type" => "entry", "config" => { "trigger" => "lead_created", "entry_policy" => "future" } },
          { "id" => "action_1", "type" => "action", "config" => { "action_type" => "send_webhook", "url" => url } }
        ],
        "edges" => []
      }
    end

    it "flags internal webhook URLs on publish" do
      errors = Automation::WorkflowDefinition.validate(definition_for("http://169.254.169.254/x"), mode: :publish)

      expect(errors).to include("tem acao de webhook com URL invalida")
    end

    it "accepts public webhook URLs on publish" do
      errors = Automation::WorkflowDefinition.validate(definition_for("https://hooks.example/hook"), mode: :publish)

      expect(errors).not_to include("tem acao de webhook com URL invalida")
      expect(errors).not_to include("tem acao de webhook sem URL")
    end
  end

  describe "Automation::WebhookTestDelivery" do
    it "raises before creating a delivery for internal destinations" do
      expect {
        Automation::WebhookTestDelivery.call(url: "http://127.0.0.1:3000/", http_method: "post", headers: nil)
      }.to raise_error(ArgumentError, "Blocked webhook destination")

      expect(AutomationWebhookDelivery.count).to eq(0)
    end
  end
end
