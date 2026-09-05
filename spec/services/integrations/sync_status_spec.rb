require "rails_helper"

RSpec.describe Integrations::SyncStatus do
  include ActiveSupport::Testing::TimeHelpers

  [Dwv::SyncStatusService, Loft::SyncStatusService].each do |service_class|
    context service_class.name do
      let(:tenant) { Tenant.create!(name: "Sync status", slug: "sync-status-#{SecureRandom.hex(4)}") }
      let(:service) { service_class.new(tenant: tenant) }
      let(:prefix) { service_class::PREFIX }

      def value(suffix)
        Setting.tenant_get("#{prefix}_#{suffix}", tenant: tenant)
      end

      it "preserva progresso, mensagem, horários e formato do histórico em todas as transições" do
        freeze_time do
          service.mark_processing!(message: "Início", mode: "full", progress: -10)
          expect(value("sync_status")).to eq("processing")
          expect(value("sync_progress")).to eq("0")
          expect(value("last_sync_at")).to be_nil
          service.update_progress!(progress: 140, message: "")
          expect(value("sync_progress")).to eq("100")
          expect(value("last_sync_message")).to eq("Início")
          service.update_progress!(progress: 43, message: "Página 2")
          service.mark_failed!(message: "Falhou", mode: "full")
          expect(value("sync_progress")).to eq("43")
          expect(value("last_sync_at")).to eq(Time.current.iso8601)
          service.mark_skipped!(message: "Ignorado")
          expect(value("sync_status")).to eq("skipped")
          expect(value("sync_progress")).to eq("43")
          service.mark_completed!(message: "Fim")
          expect(value("sync_status")).to eq("completed")
          expect(value("sync_progress")).to eq("100")
          entry = { "at" => Time.current.iso8601, "status" => "completed", "mode" => nil, "message" => "Fim" }
          entry["stats"] = {} if service_class == Loft::SyncStatusService
          expect(service.history.first).to eq(entry)
          expect(Setting.find_by!(tenant: tenant, key: "#{prefix}_sync_progress").description).to eq(service_class::PROGRESS_DESCRIPTION)
        end
      end

      it "limita o histórico a cinco entradas e não lê dados globais ou de outra conta" do
        Setting.set("#{prefix}_sync_history", '[{"message":"global"}]', tenant: nil)
        other = Tenant.create!(name: "Outro status", slug: "other-status-#{SecureRandom.hex(4)}")
        service_class.new(tenant: other).mark_completed!(message: "Outra conta")
        expect(service.history).to eq([])
        7.times { |i| service.mark_completed!(message: i.to_s) }
        expect(service.history.map { |entry| entry["message"] }).to eq(%w[6 5 4 3 2])
        expect(service.history(limit: 2).size).to eq(2)
        expect(service_class.new(tenant: other).history.first["message"]).to eq("Outra conta")
      end

      it "recupera histórico inválido e trata progresso nil como zero ao iniciar" do
        ["invalid", "{}"].each do |raw|
          Setting.set("#{prefix}_sync_history", raw, tenant: tenant)
          expect(service.history).to eq([])
          service.mark_processing!(message: nil, progress: nil)
          expect(value("sync_progress")).to eq("0")
          expect(service.history.first["message"]).to eq("")
        end
      end

      if service_class == Loft::SyncStatusService
        it "mantém estatísticas com chaves string inclusive na falha" do
          service.mark_completed!(message: "Fim", stats: { processed: 2 })
          service.mark_failed!(message: "Erro", stats: { errors: 1 })
          expect(service.history.map { |entry| entry["stats"] }).to eq([{ "errors" => 1 }, { "processed" => 2 }])
        end
      end
    end
  end
end
