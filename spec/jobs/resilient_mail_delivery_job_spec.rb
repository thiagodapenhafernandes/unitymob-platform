require "rails_helper"

RSpec.describe ResilientMailDeliveryJob do
  it "é usado como job padrão dos mailers da aplicação" do
    expect(ApplicationMailer.delivery_job).to eq(described_class)
  end

  describe "#report_final_delivery_failure" do
    it "registra falha final de SMTP com contexto do mailer e tenant" do
      tenant = Tenant.create!(name: "Tenant mail retry #{SecureRandom.hex(3)}", slug: "tenant-mail-retry-#{SecureRandom.hex(3)}")
      lead = create(:lead, tenant: tenant)
      corretor = create(:admin_user, tenant: tenant)
      job = described_class.new(
        "LeadMailer",
        "lead_assigned",
        "deliver_now",
        args: [],
        kwargs: nil,
        params: { lead: lead, corretor: corretor }
      )
      error = Net::ReadTimeout.new("Net::ReadTimeout with #<TCPSocket:(closed)>")

      allow(Rails.error).to receive(:report)

      job.report_final_delivery_failure(error)

      expect(Rails.error).to have_received(:report).with(
        error,
        handled: false,
        severity: :error,
        source: ErrorTracking::ACTIVE_JOB_SOURCE,
        context: hash_including(
          job_class: "ResilientMailDeliveryJob",
          queue: "mailers",
          mailer: "LeadMailer",
          mail_method: "lead_assigned",
          delivery_method: "deliver_now",
          tenant_id: tenant.id,
          lead_id: lead.id,
          admin_user_id: corretor.id
        )
      )
    end
  end
end
