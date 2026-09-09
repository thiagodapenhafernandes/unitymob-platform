require "rails_helper"

RSpec.describe Activities::ReminderDelivery do
  include ActiveSupport::Testing::TimeHelpers

  [[:task, :due_at, Tasks::DueReminderJob], [:appointment, :starts_at, Appointments::DueReminderJob]].each do |factory, schedule_field, job|
    context factory.to_s do
      let(:tenant) { Tenant.create!(name: "Lembretes", slug: "lembretes-#{SecureRandom.hex(4)}") }
      let(:owner) { create(:admin_user, tenant: tenant) }
      let(:setting) { LeadSetting.instance(tenant: tenant) }
      let(:activity) { create(factory, tenant: tenant, admin_user: owner, lead: nil, schedule_field => 5.minutes.ago) }
      let(:deliveries) { [] }

      around { |example| travel_to(Time.zone.local(2026, 9, 8, 10, 59)) { example.run } }

      before do
        allow(Tenant).to receive(:find_each).and_yield(tenant)
        allow(Notifications::PushDispatcher).to receive(:deliver) { |**args| deliveries << args; 1 }
      end

      def notify_activity(record = activity)
        described_class.new(record, setting: setting.reload, now: Time.current).call do |phase, tag|
          deliveries << { phase: phase, tag: tag }
          1
        end
      end

      it "aguarda o intervalo real mesmo atravessando o bloco do relógio" do
        activity.update!(schedule_field => 3.hours.ago)
        notify_activity
        travel 1.minute
        notify_activity
        expect(deliveries.size).to eq(1)
        travel 119.minutes
        notify_activity
        expect(deliveries.size).to eq(2)
      end

      it "reinicia lembretes ao reagendar, inclusive voltando ao horário original" do
        original_time = activity[schedule_field]
        notify_activity
        activity.update!(schedule_field => 1.day.from_now)
        travel 1.day
        notify_activity
        activity.update!(schedule_field => original_time)
        notify_activity
        expect(deliveries.size).to eq(3)
      end

      it "mantém fases entregues quando a configuração muda" do
        activity.update!(schedule_field => 45.minutes.from_now)
        notify_activity
        setting.update!(reminder_first_minutes: 90)
        notify_activity
        expect(deliveries.size).to eq(1)
      end

      it "usa antecedência e texto personalizados nos dois jobs" do
        setting.update!(reminder_first_minutes: 90, reminder_second_minutes: 45, reminder_third_minutes: 20)
        activity.update!(schedule_field => 80.minutes.from_now)
        job.perform_now
        expect(deliveries.one?).to be(true)
        expect(deliveries.first[:body]).to include("90 minutos")
      end

      it "respeita horário com minutos e a desativação do aviso no vencimento" do
        setting.update!(reminder_due_enabled: false, reminder_overdue_minutes: 60,
                        reminder_start_time: "11:30", reminder_end_time: "12:30")
        notify_activity
        travel 1.hour
        notify_activity
        expect(deliveries.size).to eq(1)
        travel 1.hour
        notify_activity
        expect(deliveries.size).to eq(1)
      end

      it "persiste falhas e libera uma nova fase sem confundi-la com retry" do
        activity.update!(schedule_field => 16.minutes.from_now)
        2.times do
          described_class.new(activity, setting: setting, now: Time.current).call { |phase, _| deliveries << phase; 0 }
        end
        expect(deliveries).to eq(["30_minutes_before"])
        travel 1.minute
        notify_activity
        expect(deliveries.size).to eq(2)
      end

      it "respeita retry ao passar de vencimento para atraso" do
        setting.update!(reminder_overdue_minutes: 10, reminder_retry_minutes: 30)
        described_class.new(activity, setting: setting, now: Time.current).call { 0 }
        travel 10.minutes
        notify_activity
        expect(deliveries).to be_empty
        travel 20.minutes
        notify_activity
        expect(deliveries.size).to eq(1)
      end

      it "não aplica o intervalo de falha a um envio bem-sucedido" do
        setting.update!(reminder_overdue_minutes: 60, reminder_retry_minutes: 180)
        activity.update!(schedule_field => 3.hours.ago)
        notify_activity
        travel 60.minutes
        notify_activity
        expect(deliveries.size).to eq(2)
      end

      it "mantém cooldown mesmo se o dispatcher lançar uma exceção" do
        allow(Rails.error).to receive(:report)
        described_class.new(activity, setting: setting, now: Time.current).call { raise IOError, "indisponível" }
        notify_activity
        expect(deliveries).to be_empty
        expect(Rails.error).to have_received(:report)
      end

      it "não usa o histórico de outro responsável" do
        notify_activity
        activity.update!(admin_user: create(:admin_user, tenant: tenant))
        notify_activity
        expect(deliveries.size).to eq(2)
      end

      it "revalida responsável inativo antes do envio" do
        activity
        owner.update!(active: false)
        notify_activity
        expect(deliveries).to be_empty
      end

      it "processa além de 200 atividades mesmo com antigas já notificadas" do
        activity
        attrs = activity.attributes.except("id").merge("reminder_state" => {})
        activity.class.insert_all!(Array.new(201) { attrs })
        job.perform_now
        expect(deliveries.size).to eq(202)
        deliveries.clear
        job.perform_now
        expect(deliveries).to be_empty
      end
    end
  end
end
