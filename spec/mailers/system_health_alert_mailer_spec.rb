require "rails_helper"

RSpec.describe SystemHealthAlertMailer, type: :mailer do
  describe "#degraded" do
    it "mostra origem, release, snapshot e erro real no corpo" do
      mail = described_class.with(
        recipients: ["operacao@example.com"],
        status: "critical",
        findings: [
          { code: "application_errors", severity: "critical", message: "557 erros funcionais abertos" }
        ],
        diagnostic: {
          environment: "production",
          app_host: "https://saluteimoveis.com.br",
          server_hostname: "salute-prod-01",
          rails_root: "/home/salute/deploy/current",
          collected_at: "2026-08-27T18:55:00-03:00",
          release: { identifier: "release 509", revision: "abc123", schema_version: "20260827010101", migrations_pending: false },
          runtime: { http_status: 200, http_ms: 123, puma: "active", solid_queue: "active", nginx: "active", database: "ok", cache: "ok", memory_available_percent: 31.2, disk_percent: 63.4, swap_used_mb: 0 },
          platform_errors: { application_open: 557, unassigned_open: 286, affected_tenants: 3 },
          top_error_events: [
            { id: 42, exception_class: "RuntimeError", message: "Falha ao carregar catálogo", source: "request", severity: "error", tenant_id: 7, occurrences_count: 4, last_seen_at: "2026-08-27T18:54:00-03:00", request_id: "req-123", method: "GET", path: "/admin/habitations" }
          ],
          degraded_tenants: [
            { id: 7, name: "Conexão", status: "attention", open_errors: 12, integration_failures: 1 }
          ]
        }
      ).degraded

      text = mail.text_part.body.decoded

      expect(mail.subject).to eq("[UNITYMOB] Saúde da plataforma critical: https://saluteimoveis.com.br")
      expect(text).to include("Domínio/app: https://saluteimoveis.com.br")
      expect(text).to include("Servidor: salute-prod-01")
      expect(text).to include("Release: release 509 (rev abc123)")
      expect(text).to include("Erros funcionais abertos: 557")
      expect(text).to include("#42 RuntimeError: Falha ao carregar catálogo")
      expect(text).to include("Request ID: req-123")
      expect(text).to include("Detalhes: https://saluteimoveis.com.br/admin/system/error_events/42")
      expect(text).to include("Conexão (#7): status=attention, erros=12, integrações=1")
    end
  end
end
