module Whatsapp
  # Watchdog do pipeline de campanhas (recorrente, a cada 5 min via recurring.yml).
  # Cobre crash/deploy no meio do disparo — o SolidQueue marca claimed executions
  # de processo morto como failed, sem re-executar:
  #   1. mensagens presas em 'queued' sem aceite da Meta voltam para 'pending';
  #   2. corrente do BulkSendJob morta é re-enfileirada (uma só — checa a fila
  #      do SolidQueue para não multiplicar a corrente/send_rate);
  #   3. campanha 'processing' sem pendências é reconciliada para completed.
  # Idempotente; cada campanha roda sob Current.set(tenant:).
  class CampaignStuckSweepJob < ApplicationJob
    queue_as :campaigns

    # Acima disso, 'queued' sem external_message_id é considerado órfão.
    # Reencaminhar tem risco raro de dupla entrega (crash entre o aceite da
    # Meta e a persistência do external_message_id) — at-least-once aceito.
    STUCK_QUEUED_AFTER = 15.minutes

    def perform
      WhatsappCampaign.where(status: "processing").find_each do |campaign|
        next if campaign.tenant.blank?

        Current.set(tenant: campaign.tenant) { sweep_campaign(campaign) }
      rescue => e
        Rails.logger.error("[whatsapp campaign sweep] campaign=#{campaign.id} #{e.class}: #{e.message}")
      end
    end

    private

    def sweep_campaign(campaign)
      # Campanha recém-iniciada: o processor pode nem ter criado as mensagens
      # ainda — não mexer para não completar/reviver prematuramente.
      return if campaign.started_at.present? && campaign.started_at > STUCK_QUEUED_AFTER.ago

      requeued = requeue_stuck_queued_messages(campaign)
      Rails.logger.info("[whatsapp campaign sweep] campaign=#{campaign.id} requeued=#{requeued}") if requeued.positive?

      campaign.refresh_counters!

      if campaign.campaign_messages.where(status: "pending").exists?
        revive_bulk_chain(campaign) unless bulk_chain_alive?(campaign)
      elsif campaign.campaign_messages.exists?
        campaign.complete_if_finished!
      end
    end

    # Dispatch morreu entre o queue! e o envio: sem external_message_id a Meta
    # não confirmou nada — volta para 'pending' e a corrente reprocessa.
    def requeue_stuck_queued_messages(campaign)
      campaign.campaign_messages
        .where(status: "queued", external_message_id: nil)
        .where("queued_at IS NOT NULL AND queued_at <= ?", STUCK_QUEUED_AFTER.ago)
        .update_all(status: "pending", queued_at: nil, updated_at: Time.current)
    end

    def revive_bulk_chain(campaign)
      Rails.logger.info("[whatsapp campaign sweep] revivendo BulkSendJob campaign=#{campaign.id}")
      Whatsapp::BulkSendJob.perform_later(campaign.id, tenant_id: campaign.tenant_id)
    end

    def bulk_chain_alive?(campaign)
      ids = alive_bulk_campaign_ids
      return true if ids.nil? # checagem indisponível: não arrisca duplicar a corrente

      ids.include?(campaign.id)
    end

    # Campanhas com BulkSendJob vivo no SolidQueue (ready/scheduled/claimed).
    # Jobs com failed_execution são corrente morta — elegíveis para revive.
    def alive_bulk_campaign_ids
      return @alive_bulk_campaign_ids if defined?(@alive_bulk_campaign_ids)

      @alive_bulk_campaign_ids = begin
        jobs = SolidQueue::Job.where(class_name: "Whatsapp::BulkSendJob", finished_at: nil)
        jobs = jobs.where.not(id: SolidQueue::FailedExecution.select(:job_id))
        jobs.filter_map { |job| job.arguments.to_h["arguments"]&.first }.to_set
      rescue => e
        Rails.logger.warn("[whatsapp campaign sweep] checagem da corrente indisponível: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
