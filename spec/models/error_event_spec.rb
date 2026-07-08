require "rails_helper"

RSpec.describe ErrorEvent, type: :model do
  before { described_class.reset_storage_check! }
  after { described_class.reset_storage_check! }

  def build_exception(message, backtrace: default_backtrace)
    error = RuntimeError.new(message)
    error.set_backtrace(backtrace)
    error
  end

  def default_backtrace
    [
      "#{Rails.root}/app/services/leads/distributor_service.rb:42:in `call'",
      "#{Rails.root}/app/controllers/admin/leads_controller.rb:10:in `create'",
      "/usr/local/gems/actionpack-7.1.6/lib/action_controller/metal.rb:5:in `dispatch'"
    ]
  end

  describe ".fingerprint_for" do
    it "é estável quando a mensagem varia só por números longos, hex e uuids" do
      a = build_exception("Lead 12345 não encontrado (uuid 123e4567-e89b-12d3-a456-426614174000, ref 0xdeadbeef)")
      b = build_exception("Lead 99887 não encontrado (uuid 00000000-0000-0000-0000-000000000000, ref 0xcafebabe)")

      expect(described_class.fingerprint_for(a)).to eq(described_class.fingerprint_for(b))
    end

    it "muda quando os frames do app mudam" do
      a = build_exception("boom")
      b = build_exception("boom", backtrace: ["#{Rails.root}/app/models/lead.rb:7:in `save'"])

      expect(described_class.fingerprint_for(a)).not_to eq(described_class.fingerprint_for(b))
    end

    it "ignora frames de gems fora do app" do
      a = build_exception("boom")
      b = build_exception("boom", backtrace: default_backtrace + ["/outra/gems/foo-1.0/lib/foo.rb:1:in `x'"])

      expect(described_class.fingerprint_for(a)).to eq(described_class.fingerprint_for(b))
    end
  end

  describe ".record!" do
    it "cria na primeira ocorrência e só incrementa nas seguintes (dedupe por fingerprint)" do
      exception = build_exception("PG::UndefinedColumn: coluna 123456 não existe")

      event = described_class.record!(exception, source: "request", context: { path: "/admin/leads" })

      expect(event).to be_persisted
      expect(event.occurrences_count).to eq(1)
      expect(event.source).to eq("request")
      expect(event.first_seen_at).to be_present

      again = described_class.record!(exception, source: "request", context: { path: "/admin/leads/9" })

      expect(again.id).to eq(event.id)
      expect(described_class.where(fingerprint: event.fingerprint).count).to eq(1)

      event.reload
      expect(event.occurrences_count).to eq(2)
      expect(event.context["path"]).to eq("/admin/leads/9")
    end

    it "reabre evento resolvido quando o erro reincide" do
      exception = build_exception("boom")
      event = described_class.record!(exception, source: "job")
      event.resolve!

      described_class.record!(exception, source: "job")

      expect(event.reload).not_to be_resolved
    end

    it "nunca levanta exceção quando a persistência falha" do
      allow(described_class).to receive(:find_by).and_raise(StandardError, "banco fora do ar")

      result = nil
      expect {
        result = described_class.record!(build_exception("boom"), source: "manual")
      }.not_to raise_error
      expect(result).to be_nil
    end

    it "não grava quando a tabela ainda não existe" do
      allow(described_class).to receive(:storage_ready?).and_return(false)

      expect {
        expect(described_class.record!(build_exception("boom"), source: "manual")).to be_nil
      }.not_to change(described_class, :count)
    end
  end
end
